import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

/// SQLite substrate for Tranche 2 offline queue and draft persistence.
///
/// Three tables are created on first run:
///
///   pending_pickups  — queue of pickup submissions awaiting network delivery.
///                      webhook_url is stored as a separate column (NOT inside
///                      payload_json) so the flush path reads it directly.
///
///   pickup_drafts    — auto-saved form state keyed on route_customer_id.
///                      One draft per customer at a time; overwritten on re-save.
///
///   schedule_cache   — forward-compat table for Tranche 3 (Today/Week views).
///                      No consumer in Tranche 2; schema lands now.
///
/// Usage:
///   final db = await AppDatabase.instance.database;
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  Database? _db;

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'fieldworker.db');
    return openDatabase(
      path,
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // v2: add UNIQUE index on schedule_cache.route_id for upsert support
      await db.execute(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_schedule_cache_route_id ON schedule_cache(route_id)');
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    // ── pending_pickups ────────────────────────────────────────────────────────
    // E1: webhook_url is a separate column so flush reads it without parsing JSON.
    await db.execute('''
      CREATE TABLE pending_pickups (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        route_id      INTEGER NOT NULL,
        customer_id   INTEGER NOT NULL,
        customer_name TEXT    NOT NULL DEFAULT '',
        lot_code      TEXT    NOT NULL DEFAULT '',
        webhook_url   TEXT    NOT NULL,
        payload_json  TEXT    NOT NULL,
        before_photo  TEXT    NOT NULL,
        after_photo   TEXT    NOT NULL,
        status        TEXT    NOT NULL DEFAULT 'pending'
                                CHECK(status IN ('pending','failed')),
        attempts      INTEGER NOT NULL DEFAULT 0,
        last_error    TEXT,
        enqueued_at   INTEGER NOT NULL
      )
    ''');

    // ── pickup_drafts ──────────────────────────────────────────────────────────
    // Keyed on route_customer_id — one draft per customer, overwritten on re-save.
    await db.execute('''
      CREATE TABLE pickup_drafts (
        route_customer_id INTEGER PRIMARY KEY,
        route_id          INTEGER NOT NULL,
        customer_id       INTEGER NOT NULL,
        form_state_json   TEXT    NOT NULL,
        before_photo_path TEXT,
        after_photo_path  TEXT,
        saved_at          INTEGER NOT NULL
      )
    ''');

    // ── schedule_cache ─────────────────────────────────────────────────────────
    // Forward-compat for Tranche 3 (Today/Week views). No consumer in Tranche 2.
    await db.execute('''
      CREATE TABLE schedule_cache (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        worker_id     INTEGER NOT NULL,
        schedule_id   INTEGER,
        route_date    TEXT    NOT NULL,
        route_id      INTEGER,
        payload_json  TEXT    NOT NULL,
        cached_at     INTEGER NOT NULL
      )
    ''');
    // v2: UNIQUE index on route_id to support ON CONFLICT upsert in upsertRouteCache.
    await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_schedule_cache_route_id ON schedule_cache(route_id)');
  }

  // ── pending_pickups helpers ──────────────────────────────────────────────────

  Future<int> insertPendingPickup(Map<String, dynamic> row) async {
    final db = await database;
    return db.insert('pending_pickups', row);
  }

  Future<List<Map<String, dynamic>>> getPendingPickups() async {
    final db = await database;
    return db.query(
      'pending_pickups',
      where: "status = 'pending'",
      orderBy: 'enqueued_at ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getFailedPickups() async {
    final db = await database;
    return db.query(
      'pending_pickups',
      where: "status = 'failed'",
      orderBy: 'enqueued_at ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getAllQueuedPickups() async {
    final db = await database;
    return db.query('pending_pickups', orderBy: 'enqueued_at ASC');
  }

  Future<void> updatePickupStatus(int id,
      {required String status,
      required int attempts,
      String? lastError}) async {
    final db = await database;
    await db.update(
      'pending_pickups',
      {
        'status': status,
        'attempts': attempts,
        if (lastError != null) 'last_error': lastError,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deletePickup(int id) async {
    final db = await database;
    await db.delete('pending_pickups', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> countPending() async {
    final db = await database;
    final result = await db.rawQuery(
        "SELECT COUNT(*) as c FROM pending_pickups WHERE status = 'pending'");
    return (result.first['c'] as int?) ?? 0;
  }

  Future<int> countFailed() async {
    final db = await database;
    final result = await db.rawQuery(
        "SELECT COUNT(*) as c FROM pending_pickups WHERE status = 'failed'");
    return (result.first['c'] as int?) ?? 0;
  }

  // ── pickup_drafts helpers ────────────────────────────────────────────────────

  Future<void> upsertDraft(Map<String, dynamic> row) async {
    final db = await database;
    await db.insert(
      'pickup_drafts',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getDraft(int routeCustomerId) async {
    final db = await database;
    final rows = await db.query(
      'pickup_drafts',
      where: 'route_customer_id = ?',
      whereArgs: [routeCustomerId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> deleteDraft(int routeCustomerId) async {
    final db = await database;
    await db.delete('pickup_drafts',
        where: 'route_customer_id = ?', whereArgs: [routeCustomerId]);
  }

  // ── schedule_cache helpers ───────────────────────────────────────────────────
  // Used by route_detail_screen for offline-first route data.
  // Keyed on route_id. One row per route; upserted on every successful online fetch.

  /// Persist route + customers JSON for a given routeId.
  Future<void> upsertRouteCache({
    required int routeId,
    required int workerId,
    required String routeDate,
    required Map<String, dynamic> routePayload,
    required List<dynamic> customersPayload,
  }) async {
    final db = await database;
    final payload = jsonEncode({
      'route': routePayload,
      'customers': customersPayload,
    });
    await db.execute(
      '''
      INSERT INTO schedule_cache (worker_id, route_date, route_id, payload_json, cached_at)
      VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(route_id) DO UPDATE SET
        worker_id   = excluded.worker_id,
        route_date  = excluded.route_date,
        payload_json = excluded.payload_json,
        cached_at   = excluded.cached_at
      ''',
      [workerId, routeDate, routeId, payload, DateTime.now().millisecondsSinceEpoch],
    );
  }

  /// Retrieve cached route + customers for a given routeId.
  /// Returns null if no cache entry exists.
  Future<({Map<String, dynamic> route, List<dynamic> customers})?> getCachedRoute(
      int routeId) async {
    final db = await database;
    final rows = await db.query(
      'schedule_cache',
      where: 'route_id = ?',
      whereArgs: [routeId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    try {
      final decoded = jsonDecode(rows.first['payload_json'] as String)
          as Map<String, dynamic>;
      return (
        route: Map<String, dynamic>.from(decoded['route'] as Map),
        customers: decoded['customers'] as List<dynamic>,
      );
    } catch (_) {
      return null;
    }
  }
}

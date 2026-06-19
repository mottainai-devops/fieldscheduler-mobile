import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'api_service.dart';
import 'database.dart';
import 'photo_store.dart';

/// Thrown by [PickupQueue.enqueue] when the pending queue is at capacity.
class QueueFullException implements Exception {
  final String message;
  const QueueFullException([this.message = 'Queue is full (max 20 pending pickups)']);
  @override
  String toString() => message;
}

/// Singleton queue engine for offline pickup submissions.
///
/// Sub-area 3 (§5.3):
///   - enqueue()        — writes a pending_pickups row; throws QueueFullException
///                        if pending count >= MAX_PENDING (20).
///   - flush()          — walks pending rows in enqueued_at order, submits each
///                        to its resolved webhook_url via MultipartRequest.
///   - resetForRetry()  — resets status='pending', attempts=0, last_error=null
///                        (C5 fix: both status AND attempts reset, not just status).
///
/// Re-entrancy: flush() is guarded by a boolean lock. A second call while a
/// flush is in progress is a no-op (returns immediately).
///
/// 401 handling: on 401, the ApiService interceptor clears the token and
/// redirects to /supervisor-login. flush() breaks out of the loop on 401
/// (no point continuing with no auth); attempts are NOT incremented.
///
/// Network error mid-flush: if connectivity is offline, the loop stops without
/// incrementing attempts. If a real HTTP error, attempts are bumped.
///
/// State machine per row:
///   pending  →  (2xx)   → deleted (+ photo files deleted)
///   pending  →  (401)   → status unchanged, attempts unchanged, loop breaks
///   pending  →  (4xx/5xx or real error) → attempts++; if attempts >= MAX_RETRIES → failed
///   failed   →  resetForRetry() → pending, attempts=0
final pickupQueue = PickupQueue._();

class PickupQueue extends ChangeNotifier {
  PickupQueue._();

  static const int _maxPending = 20;
  static const int _maxRetries = 5;
  static const _secureStorage = FlutterSecureStorage();

  bool _flushing = false;

  // ── Public counts (reactive) ─────────────────────────────────────────────────

  int _pendingCount = 0;
  int _failedCount = 0;

  int get pendingCount => _pendingCount;
  int get failedCount => _failedCount;

  /// Called once from main() before runApp() to seed initial counts.
  Future<void> init() async => refreshCounts();

  /// Refresh counts from DB and notify listeners.
  Future<void> refreshCounts() async {
    _pendingCount = await AppDatabase.instance.countPending();
    _failedCount = await AppDatabase.instance.countFailed();
    notifyListeners();
  }

  // ── enqueue ──────────────────────────────────────────────────────────────────

  /// Enqueue a pickup for later submission.
  ///
  /// [payload] is the field bag (Map<String,dynamic>) — photos are NOT included
  /// here; they are stored as file paths in [beforePath] / [afterPath].
  /// [webhookUrl] is stored as a separate column, not inside payload_json.
  ///
  /// Throws [QueueFullException] if pending count >= 20.
  Future<int> enqueue({
    required int routeId,
    required int customerId,
    required String customerName,
    required String lotCode,
    required Map<String, dynamic> payload,
    required String beforePath,
    required String afterPath,
    required String webhookUrl,
  }) async {
    final pending = await AppDatabase.instance.countPending();
    if (pending >= _maxPending) {
      throw const QueueFullException();
    }

    final id = await AppDatabase.instance.insertPendingPickup({
      'route_id': routeId,
      'customer_id': customerId,
      'customer_name': customerName,
      'lot_code': lotCode,
      'webhook_url': webhookUrl,
      'payload_json': jsonEncode(payload),
      'before_photo': beforePath,
      'after_photo': afterPath,
      'status': 'pending',
      'attempts': 0,
      'enqueued_at': DateTime.now().millisecondsSinceEpoch,
    });

    await refreshCounts();
    return id;
  }

  // ── flush ────────────────────────────────────────────────────────────────────

  /// Attempt to submit all pending pickups.
  ///
  /// Re-entrant guard: if already flushing, returns immediately.
  /// Connectivity check: if offline at start, returns immediately.
  Future<void> flush() async {
    if (_flushing) return;
    _flushing = true;

    try {
      // Quick connectivity check before starting the loop
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity == ConnectivityResult.none) return;

      final rows = await AppDatabase.instance.getPendingPickups();
      for (final row in rows) {
        final id = row['id'] as int;
        final webhookUrl = row['webhook_url'] as String;
        final payloadJson = row['payload_json'] as String;
        final beforePath = row['before_photo'] as String;
        final afterPath = row['after_photo'] as String;
        final attempts = (row['attempts'] as int?) ?? 0;
        final routeId = row['route_id'] as int;
        final customerId = row['customer_id'] as int;

        // E3: Read token LIVE from secure storage at each attempt (C4 fix)
        final token = await _secureStorage.read(key: 'workerSurveyToken');

        try {
          final payload = jsonDecode(payloadJson) as Map<String, dynamic>;
          final uri = Uri.parse(webhookUrl);
          final req = http.MultipartRequest('POST', uri);

          // Attach Bearer header if token present
          if (token != null && token.isNotEmpty) {
            req.headers['Authorization'] = 'Bearer $token';
          }

          // Add payload fields with null-omission
          payload.forEach((key, value) {
            if (value != null) {
              final s = value.toString().trim();
              if (s.isNotEmpty && s != 'null' && s != 'undefined') {
                req.fields[key] = s;
              }
            }
          });

          // Attach photos from file paths
          req.files.add(await http.MultipartFile.fromPath('beforePhoto', beforePath));
          req.files.add(await http.MultipartFile.fromPath('afterPhoto', afterPath));

          final streamed = await req.send();
          final response = await http.Response.fromStream(streamed);

          if (response.statusCode == 401) {
            // B6: delegate to ApiService interceptor (clears token, redirects)
            await ApiService.handle401FromQueue();
            // Break — no auth, no point continuing
            break;
          }

          if (response.statusCode >= 200 && response.statusCode < 300) {
            // Happy path: mark customer picked server-side, then clean up
            try {
              await ApiService.markCustomerPicked(routeId, customerId);
            } catch (_) {
              // Non-fatal: route progress update failed, but pickup was recorded
            }
            await AppDatabase.instance.deletePickup(id);
            await PhotoStore.deletePhoto(beforePath);
            await PhotoStore.deletePhoto(afterPath);
          } else {
            // Non-200 (4xx/5xx): bump attempts, transition to failed if maxed
            final newAttempts = attempts + 1;
            final newStatus = newAttempts >= _maxRetries ? 'failed' : 'pending';
            await AppDatabase.instance.updatePickupStatus(
              id,
              status: newStatus,
              attempts: newAttempts,
              lastError: 'HTTP ${response.statusCode}: ${response.body.substring(0, response.body.length.clamp(0, 200))}',
            );
          }
        } catch (e) {
          // Network error or file-not-found: check connectivity
          final conn = await Connectivity().checkConnectivity();
          if (conn == ConnectivityResult.none) {
            // Offline mid-flush — stop without incrementing
            break;
          }
          // Real error — bump attempts
          final newAttempts = attempts + 1;
          final newStatus = newAttempts >= _maxRetries ? 'failed' : 'pending';
          await AppDatabase.instance.updatePickupStatus(
            id,
            status: newStatus,
            attempts: newAttempts,
            lastError: e.toString().substring(0, e.toString().length.clamp(0, 200)),
          );
        }
      }
    } finally {
      _flushing = false;
      await refreshCounts();
    }
  }

  // ── resetForRetry ────────────────────────────────────────────────────────────

  /// Reset a failed item for retry.
  ///
  /// C5 fix: resets BOTH status='pending' AND attempts=0 AND clears last_error.
  /// Resetting status alone (the C5 gap in the web app) is insufficient.
  /// After reset, triggers flush immediately.
  Future<void> resetForRetry(int id) async {
    await AppDatabase.instance.updatePickupStatus(
      id,
      status: 'pending',
      attempts: 0,
      lastError: null,
    );
    await refreshCounts();
    flush(); // fire and forget
  }

  // ── discard ──────────────────────────────────────────────────────────────────

  /// Discard a queued item (pending or failed).
  /// Deletes the row and its photo files.
  /// [reason] is logged to console (discard_log table deferred to v2).
  Future<void> discard(int id,
      {required String beforePath,
      required String afterPath,
      String reason = ''}) async {
    debugPrint('[PickupQueue] Discard id=$id reason="$reason"');
    await AppDatabase.instance.deletePickup(id);
    await PhotoStore.deletePhoto(beforePath);
    await PhotoStore.deletePhoto(afterPath);
    await refreshCounts();
  }
}

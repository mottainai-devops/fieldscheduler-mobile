import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';

/// Thrown when a lot cannot be resolved from the local cache.
/// C3: This is an authorisation problem, not a degradation — do NOT fall
/// back to any admin-dashboard call on cache miss.
class NoAccessibleLotException implements Exception {
  final String message;
  const NoAccessibleLotException(this.message);
  @override
  String toString() => message;
}

/// Local lot cache for supervisor sessions.
///
/// Implements [WidgetsBindingObserver] so it can react to
/// [AppLifecycleState.resumed] and refresh stale data.
///
/// C2 (30-min freshness gate): Webhook URLs change rarely — they are admin
/// configuration, not per-pickup data. Refreshing on every foreground event
/// would add latency for no practical benefit. Cache staleness is bounded to
/// 30 minutes; a full re-login always resets the cache. This mirrors the
/// identical rationale documented in WorkerMobile.tsx (Tranche 0 follow-up 4).
class LotCache with WidgetsBindingObserver {
  static const _lotsKey = 'assignedLots';
  static const _cachedAtKey = 'lotCachedAt';
  static const _refreshThresholdMs = 30 * 60 * 1000; // 30 minutes

  static const _secureStorage = FlutterSecureStorage();

  List<Map<String, dynamic>> _lots = [];
  int _cachedAt = 0;

  List<Map<String, dynamic>> get lots => List.unmodifiable(_lots);

  // ─── Lifecycle ───────────────────────────────────────────────────────────────

  /// Register this observer with [WidgetsBinding].
  /// Call once from the app shell (e.g. main.dart or the root widget).
  void register() {
    WidgetsBinding.instance.addObserver(this);
  }

  /// Unregister — call from the root widget's dispose().
  void unregister() {
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _maybeRefresh();
    }
  }

  // ─── Initialisation ──────────────────────────────────────────────────────────

  /// Populate the cache from the [assignedLots] field of the supervisorLogin
  /// response. Called immediately after a successful supervisor login.
  Future<void> seedFromLogin(List<dynamic> rawLots) async {
    _lots = rawLots.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    _cachedAt = DateTime.now().millisecondsSinceEpoch;
    await _persist();
  }

  /// Load the cache from SharedPreferences on app start (e.g. after a cold
  /// launch where the supervisor was already logged in).
  Future<void> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lotsKey);
    _cachedAt = prefs.getInt(_cachedAtKey) ?? 0;
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as List<dynamic>;
        _lots = decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } catch (_) {
        _lots = [];
      }
    }
  }

  // ─── Refresh ─────────────────────────────────────────────────────────────────

  /// Conditionally refresh the cache if it is older than 30 minutes.
  Future<void> _maybeRefresh() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _cachedAt < _refreshThresholdMs) return;

    final token = await _secureStorage.read(key: 'workerSurveyToken');
    if (token == null || token.isEmpty) return; // not a supervisor session

    try {
      final freshLots = await ApiService.getAssignedLots(token);
      _lots = freshLots.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      _cachedAt = DateTime.now().millisecondsSinceEpoch;
      await _persist();
    } catch (_) {
      // Refresh failure is non-fatal — keep the stale cache.
    }
  }

  /// Force a refresh regardless of cache age (e.g. after a successful pickup).
  Future<void> forceRefresh() async {
    _cachedAt = 0;
    await _maybeRefresh();
  }

  // ─── Lot resolution ──────────────────────────────────────────────────────────

  /// Resolve the lot for a customer at submit time.
  ///
  /// Algorithm (§3):
  ///   1. Parse the trailing digits from [mafCode] (e.g. "MAF-042" → 42).
  ///   2. Match against cached lots by lotNumber (int comparison).
  ///   3. On miss, throw [NoAccessibleLotException] — no fallback.
  ///
  /// Returns the full lot map so the caller can read paytWebhook /
  /// monthlyWebhook / lotCode / lotName / lotId / lotNumber.
  Map<String, dynamic> resolveByMafCode(String mafCode) {
    // Extract trailing digits from the MAF code
    final digits = RegExp(r'\d+$').firstMatch(mafCode)?.group(0);
    if (digits == null || digits.isEmpty) {
      throw NoAccessibleLotException(
          'Cannot resolve lot: MAF code "$mafCode" contains no trailing digits.');
    }
    final lotNum = int.tryParse(digits);
    if (lotNum == null) {
      throw NoAccessibleLotException(
          'Cannot resolve lot: trailing digits "$digits" in "$mafCode" are not a valid integer.');
    }

    for (final lot in _lots) {
      final cachedLotNumber = lot['lotNumber'];
      if (cachedLotNumber != null) {
        final cached = int.tryParse(cachedLotNumber.toString());
        if (cached == lotNum) return lot;
      }
      // Fallback: compare against lotCode string (strip leading zeros)
      final lotCode = lot['lotCode']?.toString() ?? '';
      if (int.tryParse(lotCode) == lotNum) return lot;
    }

    throw NoAccessibleLotException(
        'Lot not found in cache for MAF code "$mafCode" (lotNumber=$lotNum). '
        'This is an authorisation problem — the supervisor may not have access '
        'to this lot. Do not fall back to the admin dashboard.');
  }

  // ─── Persistence ─────────────────────────────────────────────────────────────

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lotsKey, jsonEncode(_lots));
    await prefs.setInt(_cachedAtKey, _cachedAt);
  }
}

/// Singleton accessor — register once in main(), use anywhere.
final lotCache = LotCache();

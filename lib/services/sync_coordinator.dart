import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';

import 'lot_cache.dart';
import 'pickup_queue.dart';

/// Sync coordinator for Tranche 2 offline queue.
///
/// Sub-area 4 (§5.4): Registered as a WidgetsBindingObserver in main().
/// Three triggers:
///
///   1. Connectivity event: Connectivity().onConnectivityChanged
///      When the new state is anything other than ConnectivityResult.none,
///      call queue.flush().
///
  ///   2. Lifecycle resume: didChangeAppLifecycleState → AppLifecycleState.resumed
  ///      Calls queue.flush() AND lotCache.forceRefresh() (resets _cachedAt=0 then
  ///      calls _maybeRefresh, which re-checks the 30-min gate — effectively a
  ///      conditional refresh without requiring a public maybeRefresh() surface).
///
///   3. Periodic: Timer.periodic(60s) — calls queue.flush().
///      Timer is cancelled on dispose().
///
/// Background sync via workmanager is OUT of scope for this tranche.
/// TODO(v2): Add workmanager for true background sync when app is suspended.
class SyncCoordinator extends WidgetsBindingObserver {
  final PickupQueue _queue;
  final LotCache _lotCache;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _periodicTimer;

  SyncCoordinator({
    required PickupQueue queue,
    required LotCache lotCache,
  })  : _queue = queue,
        _lotCache = lotCache;

  /// Call once from main() after WidgetsBinding is initialized.
  void init() {
    // Trigger 1: connectivity events
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final isOnline = results.any((r) => r != ConnectivityResult.none);
      if (isOnline) {
        _queue.flush();
      }
    });

    // Trigger 3: periodic 60-second timer
    _periodicTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _queue.flush();
    });
  }

  /// Cancel all subscriptions and timers. Call from dispose() or app shutdown.
  void dispose() {
    _connectivitySub?.cancel();
    _periodicTimer?.cancel();
  }

  // Trigger 2: lifecycle resume
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _queue.flush();
      // forceRefresh() resets _cachedAt to 0 then calls the internal
      // _maybeRefresh() gate — the 30-min check still applies on the
      // next call, so this is not unconditionally expensive.
      _lotCache.forceRefresh();
    }
  }
}

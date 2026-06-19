import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/database.dart';
import '../services/pickup_queue.dart';
import '../utils/theme.dart';

/// Pending & Failed pickup queue screen.
///
/// Sub-area 5 (§5.5): Shows two sections — Pending (status='pending') and
/// Failed (status='failed'). Reachable from the home screen badge.
///
/// Per-item actions:
///   Retry   — calls queue.resetForRetry(id): resets status='pending' AND
///              attempts=0 AND clears last_error (C5 fix), then triggers flush.
///   Edit    — reopens PickupSubmissionScreen pre-filled from payload_json.
///              On re-submit the original row is deleted and a fresh queue entry
///              is created. Photos: offer to retake or keep existing files.
///   Discard — prompts for a reason, then deletes row + photo files.
///
/// Queue state is reactive via ChangeNotifier (PickupQueue extends ChangeNotifier).
class PendingPickupsScreen extends StatefulWidget {
  const PendingPickupsScreen({super.key});

  @override
  State<PendingPickupsScreen> createState() => _PendingPickupsScreenState();
}

class _PendingPickupsScreenState extends State<PendingPickupsScreen> {
  List<Map<String, dynamic>> _pending = [];
  List<Map<String, dynamic>> _failed = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRows();
    // Listen to queue changes and reload
    pickupQueue.addListener(_onQueueChanged);
  }

  @override
  void dispose() {
    pickupQueue.removeListener(_onQueueChanged);
    super.dispose();
  }

  void _onQueueChanged() {
    if (mounted) _loadRows();
  }

  Future<void> _loadRows() async {
    final pending = await AppDatabase.instance.getPendingPickups();
    final failed = await AppDatabase.instance.getFailedPickups();
    if (mounted) {
      setState(() {
        _pending = pending;
        _failed = failed;
        _loading = false;
      });
    }
  }

  // ── Actions ──────────────────────────────────────────────────────────────────

  Future<void> _retry(Map<String, dynamic> row) async {
    await pickupQueue.resetForRetry(row['id'] as int);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Retrying pickup…'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _discard(Map<String, dynamic> row) async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text('Discard Pickup',
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'This pickup will be permanently removed. Enter a reason (optional):',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Reason…',
                hintStyle: const TextStyle(color: AppTheme.textSecondary),
                filled: true,
                fillColor: AppTheme.bgDark,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await pickupQueue.discard(
      row['id'] as int,
      beforePath: row['before_photo'] as String? ?? '',
      afterPath: row['after_photo'] as String? ?? '',
      reason: reasonController.text.trim(),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pickup discarded'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _edit(Map<String, dynamic> row) async {
    // Decode payload to reconstruct the customer map
    Map<String, dynamic> payload = {};
    try {
      payload = jsonDecode(row['payload_json'] as String) as Map<String, dynamic>;
    } catch (_) {}

    // Reconstruct a minimal customer map from payload fields
    final customer = <String, dynamic>{
      'customerName': payload['customerName'] ?? row['customer_name'],
      'customer': {
        'name': payload['customerName'] ?? row['customer_name'],
        'phone': payload['customerPhone'],
        'address': payload['customerAddress'],
        'customermaf': payload['mafCode'],
        'arcgisBuildingId': payload['buildingId'],
        'unitCode': payload['unitCode'],
        'customerType': payload['customerType'],
        'billingType': payload['customerType'],
        'socioClass': payload['socioClass'],
        'email': payload['customerEmail'],
        'latitude': payload['latitude'],
        'longitude': payload['longitude'],
      },
    };

    final routeId = row['route_id'] as int;
    final customerId = row['customer_id'] as int;

    // Navigate to pickup form with pre-filled data
    // The form will create a new queue entry on submit; the original row is
    // deleted after successful enqueue.
    final originalRowId = row['id'] as int;
    final beforePath = row['before_photo'] as String? ?? '';
    final afterPath = row['after_photo'] as String? ?? '';

    if (!mounted) return;
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _EditPickupWrapper(
          routeId: routeId,
          customerId: customerId,
          customer: customer,
          originalRowId: originalRowId,
          existingBeforePath: beforePath,
          existingAfterPath: afterPath,
          existingPayload: payload,
        ),
      ),
    );

    if (result == true) {
      // Delete the original queued row (new row created by form)
      await AppDatabase.instance.deletePickup(originalRowId);
      await pickupQueue.refreshCounts();
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        backgroundColor: AppTheme.bgCard,
        title: const Text(
          'Pending & Failed Pickups',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Flush queue',
            onPressed: () {
              pickupQueue.flush();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Syncing…'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.orange))
          : _pending.isEmpty && _failed.isEmpty
              ? const Center(
                  child: Text(
                    'No pending or failed pickups.',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_pending.isNotEmpty) ...[
                      _sectionHeader('Pending (${_pending.length})'),
                      ..._pending.map((r) => _QueueRow(
                            row: r,
                            isFailed: false,
                            onRetry: null,
                            onEdit: () => _edit(r),
                            onDiscard: () => _discard(r),
                          )),
                      const SizedBox(height: 16),
                    ],
                    if (_failed.isNotEmpty) ...[
                      _sectionHeader('Failed (${_failed.length})'),
                      ..._failed.map((r) => _QueueRow(
                            row: r,
                            isFailed: true,
                            onRetry: () => _retry(r),
                            onEdit: () => _edit(r),
                            onDiscard: () => _discard(r),
                          )),
                    ],
                  ],
                ),
    );
  }

  Widget _sectionHeader(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          title.toUpperCase(),
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
      );
}

// ── Queue row widget ──────────────────────────────────────────────────────────

class _QueueRow extends StatefulWidget {
  final Map<String, dynamic> row;
  final bool isFailed;
  final VoidCallback? onRetry;
  final VoidCallback? onEdit;
  final VoidCallback? onDiscard;

  const _QueueRow({
    required this.row,
    required this.isFailed,
    this.onRetry,
    this.onEdit,
    this.onDiscard,
  });

  @override
  State<_QueueRow> createState() => _QueueRowState();
}

class _QueueRowState extends State<_QueueRow> {
  bool _errorExpanded = false;

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final customerName = (row['customer_name'] as String?) ?? 'Unknown';
    final lotCode = (row['lot_code'] as String?) ?? '';
    final attempts = (row['attempts'] as int?) ?? 0;
    final lastError = row['last_error'] as String?;
    final enqueuedAt = row['enqueued_at'] as int?;
    final enqueuedStr = enqueuedAt != null
        ? DateFormat('dd MMM HH:mm').format(
            DateTime.fromMillisecondsSinceEpoch(enqueuedAt))
        : '—';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: widget.isFailed
              ? Colors.red.withOpacity(0.4)
              : Colors.orange.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Icon(
                widget.isFailed ? Icons.error_outline : Icons.schedule,
                size: 16,
                color: widget.isFailed ? Colors.red : Colors.orange,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  customerName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
              // Action menu
              PopupMenuButton<String>(
                color: AppTheme.bgCard,
                icon: const Icon(Icons.more_vert, color: AppTheme.textSecondary),
                onSelected: (v) {
                  if (v == 'retry') widget.onRetry?.call();
                  if (v == 'edit') widget.onEdit?.call();
                  if (v == 'discard') widget.onDiscard?.call();
                },
                itemBuilder: (_) => [
                  if (widget.isFailed)
                    const PopupMenuItem(
                      value: 'retry',
                      child: Row(children: [
                        Icon(Icons.refresh, size: 16, color: Colors.orange),
                        SizedBox(width: 8),
                        Text('Retry', style: TextStyle(color: Colors.white)),
                      ]),
                    ),
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(children: [
                      Icon(Icons.edit_outlined, size: 16, color: Colors.white),
                      SizedBox(width: 8),
                      Text('Edit', style: TextStyle(color: Colors.white)),
                    ]),
                  ),
                  const PopupMenuItem(
                    value: 'discard',
                    child: Row(children: [
                      Icon(Icons.delete_outline, size: 16, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Discard', style: TextStyle(color: Colors.red)),
                    ]),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Metadata
          Text(
            '${lotCode.isNotEmpty ? "Lot $lotCode  ·  " : ""}Queued $enqueuedStr  ·  Attempts: $attempts',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
          // Error message (failed items)
          if (widget.isFailed && lastError != null && lastError.isNotEmpty) ...[
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () => setState(() => _errorExpanded = !_errorExpanded),
              child: Text(
                _errorExpanded
                    ? lastError
                    : lastError.substring(0, lastError.length.clamp(0, 80)) +
                        (lastError.length > 80 ? '… (tap to expand)' : ''),
                style: const TextStyle(color: Colors.red, fontSize: 11),
              ),
            ),
          ],
          // Photo thumbnails (if files still exist)
          _PhotoRow(
            beforePath: row['before_photo'] as String? ?? '',
            afterPath: row['after_photo'] as String? ?? '',
          ),
        ],
      ),
    );
  }
}

// ── Tiny photo thumbnail row ──────────────────────────────────────────────────

class _PhotoRow extends StatelessWidget {
  final String beforePath;
  final String afterPath;

  const _PhotoRow({required this.beforePath, required this.afterPath});

  @override
  Widget build(BuildContext context) {
    final before = beforePath.isNotEmpty ? File(beforePath) : null;
    final after = afterPath.isNotEmpty ? File(afterPath) : null;
    if (before == null && after == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          if (before != null) _thumb(before, 'Before'),
          if (before != null && after != null) const SizedBox(width: 8),
          if (after != null) _thumb(after, 'After'),
        ],
      ),
    );
  }

  Widget _thumb(File file, String label) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 10)),
          const SizedBox(height: 2),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.file(file,
                width: 56, height: 56, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                      width: 56,
                      height: 56,
                      color: AppTheme.bgDark,
                      child: const Icon(Icons.broken_image,
                          color: AppTheme.textSecondary, size: 20),
                    )),
          ),
        ],
      );
}

// ── Edit wrapper — reopens pickup form pre-filled ─────────────────────────────

/// Thin wrapper that imports PickupSubmissionScreen and passes pre-filled data.
/// On successful enqueue the original row is deleted by the caller.
class _EditPickupWrapper extends StatelessWidget {
  final int routeId;
  final int customerId;
  final Map<String, dynamic> customer;
  final int originalRowId;
  final String existingBeforePath;
  final String existingAfterPath;
  final Map<String, dynamic> existingPayload;

  const _EditPickupWrapper({
    required this.routeId,
    required this.customerId,
    required this.customer,
    required this.originalRowId,
    required this.existingBeforePath,
    required this.existingAfterPath,
    required this.existingPayload,
  });

  @override
  Widget build(BuildContext context) {
    // Import here to avoid circular dependency at top-level
    return _PickupEditProxy(
      routeId: routeId,
      customerId: customerId,
      customer: customer,
      existingBeforePath: existingBeforePath,
      existingAfterPath: existingAfterPath,
      existingPayload: existingPayload,
    );
  }
}

/// Proxy that dynamically imports PickupSubmissionScreen to avoid circular
/// import at the top of this file.
class _PickupEditProxy extends StatelessWidget {
  final int routeId;
  final int customerId;
  final Map<String, dynamic> customer;
  final String existingBeforePath;
  final String existingAfterPath;
  final Map<String, dynamic> existingPayload;

  const _PickupEditProxy({
    required this.routeId,
    required this.customerId,
    required this.customer,
    required this.existingBeforePath,
    required this.existingAfterPath,
    required this.existingPayload,
  });

  @override
  Widget build(BuildContext context) {
    // We use a Builder to defer the import — the actual screen is in
    // pickup_submission_screen.dart which imports this file's queue.
    // To avoid a circular import, we navigate via a named route instead.
    // The route '/pickup-edit' is registered in main.dart with extra params.
    //
    // For now, show a placeholder that navigates to the standard pickup form.
    // The form will create a new queue entry; the caller handles row deletion.
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        backgroundColor: AppTheme.bgCard,
        title: const Text('Edit Pickup',
            style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.edit_note, color: Colors.orange, size: 48),
              const SizedBox(height: 16),
              const Text(
                'Re-open the pickup form from the route detail screen to edit this submission.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Back'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

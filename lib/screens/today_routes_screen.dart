import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/lot_cache.dart';
import '../utils/theme.dart';

/// Area A (F1–F4): Supervisor "Today" view.
///
/// Shows routes scheduled for today for the logged-in supervisor.
/// For each route that has a resolved routeInstance, also loads the
/// effective customer list via getResolvedCustomersForInstance (F3).
///
/// F4: If a customer's MAF code cannot be matched in LotCache, a soft
/// amber warning badge is shown on the customer row — the route is NOT
/// blocked, but the supervisor is alerted that the webhook URL is unknown.
class TodayRoutesScreen extends StatefulWidget {
  const TodayRoutesScreen({super.key});

  @override
  State<TodayRoutesScreen> createState() => _TodayRoutesScreenState();
}

class _TodayRoutesScreenState extends State<TodayRoutesScreen> {
  List<_TodayEvent> _events = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  String get _todayStr {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final auth = context.read<AuthProvider>();
      final supervisorId = auth.workerId;
      if (supervisorId == null) {
        setState(() {
          _error = 'No supervisor ID — please sign in again.';
          _isLoading = false;
        });
        return;
      }

      // F1: Fetch schedule events for today only
      final today = _todayStr;
      final rawEvents = await ApiService.getSupervisorSchedule(
        supervisorId: supervisorId,
        from: today,
        to: today,
      );

      final lotCache = context.read<LotCache>();
      final events = <_TodayEvent>[];

      for (final e in rawEvents) {
        final ev = Map<String, dynamic>.from(e as Map);
        List<_CustomerRow>? customers;

        // F3: If the event has a resolved instanceId, load effective customers
        final instanceId = ev['instanceId'];
        if (instanceId != null) {
          try {
            final rawCustomers = await ApiService.getResolvedCustomersForInstance(
              instanceId is int ? instanceId : int.parse(instanceId.toString()),
            );
            customers = rawCustomers.map((c) {
              final cm = Map<String, dynamic>.from(c as Map);
              final cd = cm['customer'] as Map? ?? cm;
              final maf = (cd['customermaf'] ?? cd['maf'] ?? '').toString();

              // F4: Soft lot-resolution warning (non-blocking)
              bool lotWarning = false;
              if (maf.isNotEmpty) {
                try {
                  lotCache.resolveByMafCode(maf);
                } on NoAccessibleLotException {
                  lotWarning = true;
                }
              }

              return _CustomerRow(
                customerId: cm['customerId'] is int
                    ? cm['customerId'] as int
                    : int.tryParse(cm['customerId'].toString()) ?? 0,
                name: (cd['name'] ?? 'Customer').toString(),
                maf: maf,
                address: (cd['address'] ?? '').toString(),
                overrideType: cm['overrideType']?.toString(),
                lotWarning: lotWarning,
              );
            }).toList();
          } catch (_) {
            // Non-fatal — show event without resolved customers
          }
        }

        events.add(_TodayEvent(
          scheduleId: ev['scheduleId'] is int
              ? ev['scheduleId'] as int
              : int.tryParse(ev['scheduleId'].toString()),
          instanceId: instanceId is int
              ? instanceId as int
              : int.tryParse(instanceId?.toString() ?? ''),
          routeId: ev['routeId'] is int
              ? ev['routeId'] as int
              : int.tryParse(ev['routeId']?.toString() ?? ''),
          title: ev['title']?.toString() ?? 'Route',
          workerName: ev['workerName']?.toString(),
          status: ev['status']?.toString() ?? 'scheduled',
          lotCodes: (ev['lotCodes'] as List?)?.map((e) => e.toString()).toList() ?? [],
          customers: customers,
        ));
      }

      if (mounted) {
        setState(() {
          _events = events;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        backgroundColor: AppTheme.bgCard,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Today', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            Text(
              _todayStr,
              style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: _load,
          ),
          IconButton(
            icon: const Icon(Icons.calendar_month_rounded, color: Colors.white),
            tooltip: 'Week View',
            onPressed: () => context.push('/supervisor-week'),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor))
          : _error != null
              ? _buildError()
              : _events.isEmpty
                  ? _buildEmpty()
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: AppTheme.primaryColor,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _events.length,
                        itemBuilder: (_, i) => _EventCard(
                          event: _events[i],
                          onTapRoute: (routeId, routeName) =>
                              context.push('/routes/$routeId'),
                        ),
                      ),
                    ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event_available_rounded, size: 64, color: Colors.white.withOpacity(0.3)),
          const SizedBox(height: 16),
          Text(
            'No routes scheduled for today',
            style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 16),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => context.push('/supervisor-week'),
            icon: const Icon(Icons.calendar_month_rounded),
            label: const Text('View Week'),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodayEvent {
  final int? scheduleId;
  final int? instanceId;
  final int? routeId;
  final String title;
  final String? workerName;
  final String status;
  final List<String> lotCodes;
  final List<_CustomerRow>? customers;

  const _TodayEvent({
    required this.scheduleId,
    required this.instanceId,
    required this.routeId,
    required this.title,
    required this.workerName,
    required this.status,
    required this.lotCodes,
    required this.customers,
  });
}

class _CustomerRow {
  final int customerId;
  final String name;
  final String maf;
  final String address;
  final String? overrideType;
  final bool lotWarning;

  const _CustomerRow({
    required this.customerId,
    required this.name,
    required this.maf,
    required this.address,
    required this.overrideType,
    required this.lotWarning,
  });
}

class _EventCard extends StatelessWidget {
  final _TodayEvent event;
  final void Function(int routeId, String routeName) onTapRoute;

  const _EventCard({required this.event, required this.onTapRoute});

  Color _statusColor(String status) {
    switch (status) {
      case 'completed': return Colors.green;
      case 'in_progress': return AppTheme.primaryColor;
      case 'cancelled': return Colors.red;
      default: return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasLotWarning = event.customers?.any((c) => c.lotWarning) ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasLotWarning
              ? Colors.amber.withOpacity(0.5)
              : AppTheme.borderColor,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      if (event.workerName != null)
                        Text(
                          event.workerName!,
                          style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
                        ),
                      if (event.lotCodes.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Wrap(
                            spacing: 4,
                            children: event.lotCodes.map((code) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryColor.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                code,
                                style: const TextStyle(
                                  color: AppTheme.primaryColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            )).toList(),
                          ),
                        ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _statusColor(event.status).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        event.status.replaceAll('_', ' ').toUpperCase(),
                        style: TextStyle(
                          color: _statusColor(event.status),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (hasLotWarning)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 14),
                            const SizedBox(width: 3),
                            Text(
                              'Lot unknown',
                              style: TextStyle(color: Colors.amber.shade300, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // Action row
          if (event.routeId != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: OutlinedButton.icon(
                onPressed: () => onTapRoute(event.routeId!, event.title),
                icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                label: const Text('Open Route', style: TextStyle(fontSize: 13)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primaryColor,
                  side: BorderSide(color: AppTheme.primaryColor.withOpacity(0.5)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
              ),
            ),

          // Resolved customer list (F3)
          if (event.customers != null && event.customers!.isNotEmpty) ...[
            Divider(color: AppTheme.borderColor, height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'Effective customers (${event.customers!.length})',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ...event.customers!.map((c) => _CustomerTile(customer: c)),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _CustomerTile extends StatelessWidget {
  final _CustomerRow customer;
  const _CustomerTile({required this.customer});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: [
          // F4: Amber warning dot for unresolved lot
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: customer.lotWarning
                  ? Colors.amber
                  : (customer.overrideType == 'added'
                      ? Colors.green.shade400
                      : Colors.white.withOpacity(0.3)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        customer.name,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (customer.overrideType == 'added')
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'ADDED',
                          style: TextStyle(color: Colors.green, fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                      ),
                    if (customer.lotWarning)
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.amber.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'LOT?',
                          style: TextStyle(color: Colors.amber, fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
                if (customer.maf.isNotEmpty)
                  Text(
                    customer.maf,
                    style: const TextStyle(color: AppTheme.accentColor, fontSize: 11),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

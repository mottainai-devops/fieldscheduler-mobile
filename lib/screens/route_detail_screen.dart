import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/database.dart';
import '../utils/theme.dart';
import 'customer_detail_screen.dart';
import 'optimized_route_screen.dart';
import 'report_violation_screen.dart';
import 'pickup_submission_screen.dart';

class RouteDetailScreen extends StatefulWidget {
  final int routeId;
  final String routeName;

  const RouteDetailScreen({
    super.key,
    required this.routeId,
    required this.routeName,
  });

  @override
  State<RouteDetailScreen> createState() => _RouteDetailScreenState();
}

class _RouteDetailScreenState extends State<RouteDetailScreen> {
  List<dynamic> _customers = [];
  Map<String, dynamic>? _route;
  bool _isLoading = true;
  String? _error;
  String _searchQuery = '';
  bool _isOnline = true;
  final Set<int> _completedCustomerIds = {};
  final Set<int> _pickedCustomerIds = {};
  final Set<int> _skippedCustomerIds = {};
  bool _isCompletingRoute = false;
  bool _servedFromCache = false; // Bug C: true when route data came from local SQLite cache

  // Area D: Handoff request state — button is disabled once submitted.
  bool _handoffSubmitted = false;
  bool _isRequestingHandoff = false;

  // Area C: scheduleId resolved once on route entry via getScheduleIdForRoute.
  // null = non-recurring route (skipCustomer will use the no-schedule path).
  int? _scheduleId;
  bool _scheduleIdResolved = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    _checkConnectivity();
    Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (mounted) setState(() => _isOnline = online);
    });
  }

  Future<void> _checkConnectivity() async {
    final results = await Connectivity().checkConnectivity();
    if (mounted) {
      setState(() => _isOnline = results.any((r) => r != ConnectivityResult.none));
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        ApiService.getRouteById(widget.routeId),
        ApiService.getRouteCustomers(widget.routeId),
      ]);
      final route = results[0] as Map<String, dynamic>;
      final customers = results[1] as List<dynamic>;

      // Pre-populate completedCustomerIds, pickedCustomerIds, skippedCustomerIds from server data
      final completed = <int>{};
      final picked = <int>{};
      final skipped = <int>{};
      for (final c in customers) {
        final raw = c['customerId'] ?? c['id'];
        if (raw != null) {
          final id = raw is int ? raw : int.tryParse(raw.toString()) ?? 0;
          if (id > 0) {
            if (c['completedAt'] != null) completed.add(id);
            if (c['pickedAt'] != null) picked.add(id);
            // completionType='skipped' set by Tranche 0 Item 3
            if (c['completionType'] == 'skipped') skipped.add(id);
          }
        }
      }

      if (mounted) {
        setState(() {
          _route = route;
          _customers = customers;
          _completedCustomerIds.addAll(completed);
          _pickedCustomerIds.addAll(picked);
          _skippedCustomerIds.addAll(skipped);
          _isLoading = false;
        });
      }

      // Area C: Resolve scheduleId once after route data is loaded.
      // Fire-and-forget — does not block the UI.
      if (!_scheduleIdResolved) {
        _resolveScheduleId();
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

  /// Area C (H1): Resolve the active scheduleId for this route.
  /// Runs once after _loadData completes. Result is stored in _scheduleId.
  Future<void> _resolveScheduleId() async {
    try {
      final id = await ApiService.getScheduleIdForRoute(widget.routeId);
      if (mounted) {
        setState(() {
          _scheduleId = id;
          _scheduleIdResolved = true;
        });
      }
    } catch (_) {
      // Non-fatal — skip will use the no-schedule path
      if (mounted) setState(() => _scheduleIdResolved = true);
    }
  }  // ─── Area D: Request Handoff ──────────────────────────────────────────────

  static const _handoffReasons = [
    ('illness',           'Illness / medical'),
    ('vehicle_breakdown', 'Vehicle breakdown'),
    ('overloaded',        'Route overloaded'),
    ('emergency',         'Personal emergency'),
    ('route_conflict',    'Route conflict / overlap'),
    ('other',             'Other'),
  ];

  Future<void> _requestHandoff() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => _HandoffReasonDialog(reasons: _handoffReasons),
    );
    if (reason == null || !mounted) return;

    final auth = context.read<AuthProvider>();
    final supervisorId = auth.workerId ?? 0;

    setState(() => _isRequestingHandoff = true);
    try {
      // B3 fix: pass routeId so server can resolve scheduleId for non-recurring routes
      await ApiService.requestHandoff(
        scheduleId: _scheduleId,
        routeId: widget.routeId,
        supervisorId: supervisorId,
        reason: reason,
      );
      if (mounted) {
        setState(() {
          _handoffSubmitted = true;
          _isRequestingHandoff = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Handoff request submitted'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isRequestingHandoff = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Handoff failed: ${e.toString().replaceFirst("Exception: ", "")}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ─── Area C: Skip customer ──────────────────────────────────────────────────

  static const _skipReasons = [
    ('no_access',            'Gate locked / no access'),
    ('customer_not_present', 'Customer not present'),
    ('customer_request',     'Customer opt-out'),
    ('bin_not_out',          'Bins not out'),
    ('safety_concern',       'Safety / weather concern'),
    ('permanent_moved',      'Permanent — customer moved out'),
    ('permanent_closed',     'Permanent — business closed'),
    ('other',                'Other (add note below)'),
  ];

  Future<void> _skipCustomer(Map<String, dynamic> customer) async {
    if (!_isOnline) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('You\'re offline — skipping a customer requires a network connection.'),
        backgroundColor: Colors.orange,
      ));
      return;
    }
    final id = _extractCustomerId(customer);
    if (id == 0) return;
    final cd = customer['customer'] ?? customer;
    final name = (cd['name'] ?? customer['customerName'] ?? 'Customer').toString();

    // Show closed-picklist skip dialog
    final result = await showDialog<({String reason, String? note})>(
      context: context,
      builder: (ctx) => _SkipDialog(customerName: name, reasons: _skipReasons),
    );
    if (result == null || !mounted) return;

    final auth = context.read<AuthProvider>();
    final workerId = auth.workerId ?? 0;

    try {
      await ApiService.skipCustomer(
        scheduleId: _scheduleId,   // null → server uses no-schedule path
        routeId: widget.routeId,
        customerId: id,
        skipReason: result.reason,
        skipNote: result.note,
        workerId: workerId,
      );
      if (mounted) {
        setState(() {
          _skippedCustomerIds.add(id);
          _completedCustomerIds.add(id); // mark stop as visited
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Customer skipped'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Skip failed: ${e.toString().replaceFirst("Exception: ", "")}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  List<dynamic> get _filteredCustomers {
    if (_searchQuery.isEmpty) return _customers;
    final q = _searchQuery.toLowerCase();
    return _customers.where((c) {
      final cd = c['customer'] ?? c;
      final name = (cd['name'] ?? c['customerName'] ?? '').toString().toLowerCase();
      final id = (c['customerId'] ?? cd['id'] ?? '').toString().toLowerCase();
      final address = (cd['address'] ?? '').toString().toLowerCase();
      return name.contains(q) || id.contains(q) || address.contains(q);
    }).toList();
  }

  int get _completedCount => _completedCustomerIds.length;
  int get _totalCount => _customers.length;

  String get _routeStatus => (_route?['status'] ?? 'assigned').toString();

  double? get _routeDistance {
    final d = _route?['totalDistance'] ?? _route?['distance'];
    if (d == null) return null;
    return double.tryParse(d.toString());
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return Colors.green;
      case 'in_progress':
        return AppTheme.primaryColor;
      case 'assigned':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  String _statusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'in_progress':
        return 'In Progress';
      case 'completed':
        return 'Completed';
      case 'assigned':
        return 'Assigned';
      default:
        return status;
    }
  }

  int _extractCustomerId(Map<String, dynamic> c) {
    final cd = c['customer'] ?? c;
    final raw = c['customerId'] ?? cd['id'];
    if (raw == null) return 0;
    return raw is int ? raw : int.tryParse(raw.toString()) ?? 0;
  }

  Future<void> _toggleCustomerComplete(int customerId) async {
    if (!_isOnline) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('You\'re offline — marking stops requires a network connection.'),
        backgroundColor: Colors.orange,
      ));
      return;
    }
    final wasCompleted = _completedCustomerIds.contains(customerId);
    setState(() {
      if (wasCompleted) {
        _completedCustomerIds.remove(customerId);
      } else {
        _completedCustomerIds.add(customerId);
      }
    });
    try {
      if (wasCompleted) {
        await ApiService.markCustomerIncomplete(widget.routeId, customerId);
      } else {
        await ApiService.markCustomerComplete(widget.routeId, customerId);
        if (_routeStatus == 'assigned' && _completedCustomerIds.length == 1) {
          await ApiService.startRoute(widget.routeId);
          await _loadData();
        }
      }
    } catch (e) {
      setState(() {
        if (wasCompleted) {
          _completedCustomerIds.add(customerId);
        } else {
          _completedCustomerIds.remove(customerId);
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _completeRoute() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text('Complete Route', style: TextStyle(color: Colors.white)),
        content: Text(
          'Mark this entire route as completed?\n\n$_completedCount of $_totalCount stops visited.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Complete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isCompletingRoute = true);
    try {
      await ApiService.completeRoute(widget.routeId);
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Route completed!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isCompletingRoute = false);
    }
  }

  Future<void> _navigateToCustomer(Map<String, dynamic> customer) async {
    final cd = customer['customer'] ?? customer;
    final lat = cd['latitude'] ?? cd['lat'] ?? customer['latitude'];
    final lng = cd['longitude'] ?? cd['lng'] ?? cd['lon'] ?? customer['longitude'];
    if (lat == null || lng == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No GPS coordinates for this customer')),
        );
      }
      return;
    }
    final geoUri = Uri.parse('geo:$lat,$lng?q=$lat,$lng');
    final mapsUri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving',
    );
    try {
      if (await canLaunchUrl(geoUri)) {
        await launchUrl(geoUri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(mapsUri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      try {
        await launchUrl(mapsUri, mode: LaunchMode.externalApplication);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not open maps: $e')),
          );
        }
      }
    }
  }

  void _openOptimizedRoute() {
    if (_customers.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OptimizedRouteScreen(
          route: _route ?? {'id': widget.routeId, 'name': widget.routeName},
          customers: _customers.map((c) => Map<String, dynamic>.from(c as Map)).toList(),
        ),
      ),
    );
  }

  void _openReportViolation(Map<String, dynamic> customer) {
    final id = _extractCustomerId(customer);
    if (id == 0) return;
    final cd = customer['customer'] ?? customer;
    final name = (cd['name'] ?? customer['customerName'] ?? 'Customer').toString();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReportViolationScreen(
          customerId: id,
          routeId: widget.routeId,
          customerName: name,
        ),
      ),
    );
  }

  Future<void> _openPickupSubmission(Map<String, dynamic> customer) async {
    final id = _extractCustomerId(customer);
    if (id == 0) return;
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PickupSubmissionScreen(
          routeId: widget.routeId,
          customerId: id,
          customer: customer,
        ),
      ),
    );
    if (result == true && mounted) {
      setState(() => _pickedCustomerIds.add(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _routeStatus;
    final isCompleted = status == 'completed';

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/home');
        }
      },
      child: Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        backgroundColor: AppTheme.bgCard,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.routeName,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            if (_routeDistance != null)
              Text(
                '${_routeDistance!.toStringAsFixed(1)} km',
                style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
              ),
          ],
        ),
        actions: [
          // Online/Offline indicator
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Chip(
              avatar: Icon(
                _isOnline ? Icons.wifi : Icons.wifi_off,
                size: 13,
                color: Colors.white,
              ),
              label: Text(
                _isOnline ? 'Online' : 'Offline',
                style: const TextStyle(color: Colors.white, fontSize: 10),
              ),
              backgroundColor: _isOnline ? Colors.green.shade700 : Colors.red.shade700,
              padding: EdgeInsets.zero,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          // Bug C: show "Cached" badge when route data came from local SQLite cache
          if (_servedFromCache)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Chip(
                avatar: const Icon(Icons.offline_bolt, size: 13, color: Colors.white),
                label: const Text(
                  'Cached',
                  style: TextStyle(color: Colors.white, fontSize: 10),
                ),
                backgroundColor: Colors.orange.shade700,
                padding: EdgeInsets.zero,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          // Status badge
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Chip(
              label: Text(
                _statusLabel(status),
                style: const TextStyle(color: Colors.white, fontSize: 10),
              ),
              backgroundColor: _statusColor(status),
              padding: EdgeInsets.zero,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          if (_customers.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.alt_route_rounded, color: Colors.white),
              tooltip: 'Optimize Route',
              onPressed: _openOptimizedRoute,
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: _loadData,
          ),
          // Area D (I1): Request Handoff button — supervisor only, disabled after submit
          Builder(builder: (ctx) {
            // B2 fix: use isSupervisor (covers user/cherry_picker/field_supervisor/supervisor)
            final isSup = ctx.watch<AuthProvider>().isSupervisor;
            if (!isSup) return const SizedBox.shrink();
            return IconButton(
              icon: _isRequestingHandoff
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : Icon(
                      Icons.swap_horiz_rounded,
                      color: _handoffSubmitted ? Colors.grey : Colors.amber,
                    ),
              tooltip: _handoffSubmitted ? 'Handoff requested' : 'Request Handoff',
              onPressed: (_handoffSubmitted || _isRequestingHandoff) ? null : _requestHandoff,
            );
          }),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor))
          : _error != null
              ? _buildError()
              : Column(
                  children: [
                    _buildProgressBar(),
                    _buildSearchBar(),
                    Expanded(child: _buildCustomerList()),
                  ],
                ),
      floatingActionButton: (!_isLoading && !isCompleted && _customers.isNotEmpty)
          ? FloatingActionButton.extended(
              onPressed: _isCompletingRoute ? null : _completeRoute,
              backgroundColor: Colors.green,
              icon: _isCompletingRoute
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.check_circle_outline),
              label: const Text('Complete Route'),
            )
          : null,
    ),
    );
  }

  Widget _buildProgressBar() {
    final progress = _totalCount > 0 ? _completedCount / _totalCount : 0.0;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      color: AppTheme.bgCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Progress', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13)),
              Text(
                '$_completedCount of $_totalCount completed',
                style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white.withOpacity(0.15),
              valueColor: AlwaysStoppedAnimation<Color>(
                progress >= 1.0 ? Colors.green : AppTheme.primaryColor,
              ),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: TextField(
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Search customers...',
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
          prefixIcon: Icon(Icons.search_rounded, color: Colors.white.withOpacity(0.5)),
          filled: true,
          fillColor: AppTheme.bgCard,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
        onChanged: (v) => setState(() => _searchQuery = v),
      ),
    );
  }

  Widget _buildCustomerList() {
    final customers = _filteredCustomers;
    if (customers.isEmpty) {
      return Center(
        child: Text(
          _searchQuery.isEmpty ? 'No customers on this route' : 'No results for "$_searchQuery"',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      color: AppTheme.primaryColor,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
        itemCount: customers.length,
        itemBuilder: (context, index) {
          final customer = customers[index] as Map<String, dynamic>;
          final cd = customer['customer'] ?? customer;
          final id = _extractCustomerId(customer);
          final isCompleted = _completedCustomerIds.contains(id);
          final isSkipped = _skippedCustomerIds.contains(id);
          final name = (cd['name'] ?? customer['customerName'] ?? 'Customer').toString();
          final maf = (cd['customermaf'] ?? cd['maf'] ?? '').toString();
          final address = (cd['address'] ?? customer['buildingAddress'] ?? '').toString();
          final hasGps = cd['latitude'] != null || cd['lat'] != null ||
              customer['latitude'] != null;

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: isSkipped
                  ? Colors.orange.withOpacity(0.08)
                  : isCompleted
                      ? Colors.green.withOpacity(0.12)
                      : AppTheme.bgCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSkipped
                    ? Colors.orange.withOpacity(0.4)
                    : isCompleted
                        ? Colors.green.withOpacity(0.4)
                        : AppTheme.borderColor,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => _toggleCustomerComplete(id),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isCompleted ? Colors.green : AppTheme.primaryColor,
                          ),
                          child: Center(
                            child: isCompleted
                                ? const Icon(Icons.check, color: Colors.white, size: 18)
                                : Text(
                                    '${index + 1}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: TextStyle(
                          color: isSkipped
                              ? Colors.orange.shade300
                              : isCompleted
                                  ? Colors.green.shade300
                                  : Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            decoration: isSkipped || isCompleted ? TextDecoration.lineThrough : null,
                              ),
                            ),
                            if (maf.isNotEmpty)
                              Text(
                                maf,
                                style: const TextStyle(color: AppTheme.accentColor, fontSize: 12),
                              ),
                            if (address.isNotEmpty)
                              Text(
                                address,
                                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Action buttons
                Builder(
                  builder: (context) {
                    // B2 fix: use isSupervisor (covers all four Survey App supervisor roles)
                    final isSupervisor = context.watch<AuthProvider>().isSupervisor;
                    final isPicked = _pickedCustomerIds.contains(id);
                    final isAlreadySkipped = _skippedCustomerIds.contains(id);
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => CustomerDetailScreen(
                                    customerId: id,
                                    customerName: name,
                                    routeId: widget.routeId,
                                    cachedCustomer: customer,
                                  ),
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: BorderSide(color: Colors.white.withOpacity(0.3)),
                                padding: const EdgeInsets.symmetric(vertical: 8),
                              ),
                              child: const Text('View Details', style: TextStyle(fontSize: 12)),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: hasGps ? () => _navigateToCustomer(customer) : null,
                              icon: const Icon(Icons.navigation, size: 14),
                              label: const Text('Navigate', style: TextStyle(fontSize: 12)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: hasGps ? AppTheme.primaryColor : Colors.grey,
                                side: BorderSide(
                                  color: hasGps
                                      ? AppTheme.primaryColor.withOpacity(0.6)
                                      : Colors.grey.withOpacity(0.3),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 8),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          if (!isSupervisor)
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _openReportViolation(customer),
                                icon: const Icon(Icons.warning_amber, size: 14),
                                label: const Text('Report', style: TextStyle(fontSize: 12)),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.orange,
                                  side: BorderSide(color: Colors.orange.withOpacity(0.5)),
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                ),
                              ),
                            )
                          else ...[  // supervisor path
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: (isPicked || isAlreadySkipped) ? null : () => _openPickupSubmission(customer),
                                icon: Icon(
                                  isPicked ? Icons.check_circle : Icons.local_shipping,
                                  size: 14,
                                ),
                                label: Text(
                                  isPicked ? 'Picked' : 'Pickup',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: isPicked ? Colors.green : Colors.orange,
                                  side: BorderSide(
                                    color: isPicked
                                        ? Colors.green.withOpacity(0.5)
                                        : Colors.orange.withOpacity(0.5),
                                  ),
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            // Area C (H4): Skip button with closed picklist dialog
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: (isAlreadySkipped || isPicked)
                                    ? null
                                    : () => _skipCustomer(customer),
                                icon: Icon(
                                  isAlreadySkipped ? Icons.block : Icons.skip_next_rounded,
                                  size: 14,
                                ),
                                label: Text(
                                  isAlreadySkipped ? 'Skipped' : 'Skip',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: isAlreadySkipped ? Colors.grey : Colors.red.shade300,
                                  side: BorderSide(
                                    color: isAlreadySkipped
                                        ? Colors.grey.withOpacity(0.3)
                                        : Colors.red.withOpacity(0.4),
                                  ),
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          );
        },
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
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Area C (H4): Skip reason dialog with closed picklist.
///
/// Presents the fixed list of skip reasons. The user must select one before
/// confirming. An optional free-text note field is shown for all reasons but
/// is mandatory only when reason == 'other'.
class _SkipDialog extends StatefulWidget {
  final String customerName;
  final List<(String, String)> reasons;

  const _SkipDialog({required this.customerName, required this.reasons});

  @override
  State<_SkipDialog> createState() => _SkipDialogState();
}

class _SkipDialogState extends State<_SkipDialog> {
  String? _selectedReason;
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  bool get _canConfirm {
    if (_selectedReason == null) return false;
    if (_selectedReason == 'other' && _noteController.text.trim().isEmpty) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E2530),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Skip Customer',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            widget.customerName,
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Reason',
              style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ...widget.reasons.map(((String, String) r) {
              final (code, label) = r;
              return RadioListTile<String>(
                value: code,
                groupValue: _selectedReason,
                onChanged: (v) => setState(() => _selectedReason = v),
                title: Text(label, style: const TextStyle(color: Colors.white, fontSize: 13)),
                activeColor: const Color(0xFF4CAF50),
                contentPadding: EdgeInsets.zero,
                dense: true,
              );
            }),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              style: const TextStyle(color: Colors.white),
              maxLines: 2,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: _selectedReason == 'other'
                    ? 'Note (required for Other)'
                    : 'Note (optional)',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
        ),
        ElevatedButton(
          onPressed: _canConfirm
              ? () => Navigator.pop(
                    context,
                    (reason: _selectedReason!, note: _noteController.text.trim().isEmpty
                        ? null
                        : _noteController.text.trim()),
                  )
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red.shade700,
            disabledBackgroundColor: Colors.red.withOpacity(0.3),
          ),
          child: const Text('Skip', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}

/// Area D (I1): Handoff reason selection dialog.
///
/// Simple single-select picklist. Confirm is disabled until a reason is chosen.
class _HandoffReasonDialog extends StatefulWidget {
  final List<(String, String)> reasons;
  const _HandoffReasonDialog({required this.reasons});

  @override
  State<_HandoffReasonDialog> createState() => _HandoffReasonDialogState();
}

class _HandoffReasonDialogState extends State<_HandoffReasonDialog> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E2530),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        'Request Handoff',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Select a reason for the handoff request:',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 12),
            ...widget.reasons.map(((String, String) r) {
              final (code, label) = r;
              return RadioListTile<String>(
                value: code,
                groupValue: _selected,
                onChanged: (v) => setState(() => _selected = v),
                title: Text(label, style: const TextStyle(color: Colors.white, fontSize: 13)),
                activeColor: Colors.amber,
                contentPadding: EdgeInsets.zero,
                dense: true,
              );
            }),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
        ),
        ElevatedButton(
          onPressed: _selected != null
              ? () => Navigator.pop(context, _selected)
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.amber.shade700,
            disabledBackgroundColor: Colors.amber.withOpacity(0.3),
          ),
          child: const Text('Submit', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}

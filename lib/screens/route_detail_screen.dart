import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/api_service.dart';
import '../utils/theme.dart';
import 'customer_detail_screen.dart';
import 'optimized_route_screen.dart';
import 'report_violation_screen.dart';

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
  bool _isCompletingRoute = false;

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

      // Pre-populate completedCustomerIds from server data
      final completed = <int>{};
      for (final c in customers) {
        if (c['completedAt'] != null) {
          final raw = c['customerId'] ?? c['id'];
          if (raw != null) {
            final id = raw is int ? raw : int.tryParse(raw.toString()) ?? 0;
            if (id > 0) completed.add(id);
          }
        }
      }

      if (mounted) {
        setState(() {
          _route = route;
          _customers = customers;
          _completedCustomerIds.addAll(completed);
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

  @override
  Widget build(BuildContext context) {
    final status = _routeStatus;
    final isCompleted = status == 'completed';

    return Scaffold(
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
          final name = (cd['name'] ?? customer['customerName'] ?? 'Customer').toString();
          final maf = (cd['customermaf'] ?? cd['maf'] ?? '').toString();
          final address = (cd['address'] ?? customer['buildingAddress'] ?? '').toString();
          final hasGps = cd['latitude'] != null || cd['lat'] != null ||
              customer['latitude'] != null;

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: isCompleted ? Colors.green.withOpacity(0.12) : AppTheme.bgCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isCompleted
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
                                color: isCompleted ? Colors.green.shade300 : Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                                decoration: isCompleted ? TextDecoration.lineThrough : null,
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
                Padding(
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
                      ),
                    ],
                  ),
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

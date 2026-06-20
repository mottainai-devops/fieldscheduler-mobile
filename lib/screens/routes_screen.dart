import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../providers/route_provider.dart';

// ─── Filter state ────────────────────────────────────────────────────────────

enum _StatusFilter { all, assigned, inProgress, completed, incomplete }

extension _StatusFilterLabel on _StatusFilter {
  String get label {
    switch (this) {
      case _StatusFilter.all: return 'All';
      case _StatusFilter.assigned: return 'Assigned';
      case _StatusFilter.inProgress: return 'In Progress';
      case _StatusFilter.completed: return 'Completed';
      case _StatusFilter.incomplete: return 'Inactive (7d+)';
    }
  }
}

// ─── Screen ──────────────────────────────────────────────────────────────────

class RoutesScreen extends StatefulWidget {
  const RoutesScreen({super.key});
  @override
  State<RoutesScreen> createState() => _RoutesScreenState();
}

class _RoutesScreenState extends State<RoutesScreen> {
  // Filters
  _StatusFilter _statusFilter = _StatusFilter.all;
  DateTime? _dateFilter;
  final _managerController = TextEditingController();
  String _managerQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      if (auth.workerId != null) {
        context.read<RouteProvider>().loadRoutes(auth.workerId!);
      }
    });
  }

  @override
  void dispose() {
    _managerController.dispose();
    super.dispose();
  }

  // ─── Filtering logic ───────────────────────────────────────────────────────

  List<Map<String, dynamic>> _applyFilters(List<dynamic> raw) {
    final now = DateTime.now();
    return raw
        .cast<Map<String, dynamic>>()
        .where((route) {
          final status = (route['status'] as String? ?? '').toLowerCase();
          final date = route['scheduledDate'] as String?;
          final updatedAt = route['updatedAt'] as String?;
          final workerName = (route['workerName'] ?? route['fieldManagerName'] ?? '').toString().toLowerCase();

          // Status filter
          switch (_statusFilter) {
            case _StatusFilter.all:
              break;
            case _StatusFilter.assigned:
              if (status != 'assigned') return false;
              break;
            case _StatusFilter.inProgress:
              if (status != 'in_progress') return false;
              break;
            case _StatusFilter.completed:
              if (status != 'completed') return false;
              break;
            case _StatusFilter.incomplete:
              // Incomplete = not completed AND last update > 7 days ago
              if (status == 'completed') return false;
              if (updatedAt != null) {
                try {
                  final updated = DateTime.parse(updatedAt);
                  if (now.difference(updated).inDays < 7) return false;
                } catch (_) {}
              } else if (date != null) {
                // Fall back to scheduledDate if updatedAt not present
                try {
                  final scheduled = DateTime.parse(date);
                  if (now.difference(scheduled).inDays < 7) return false;
                } catch (_) {}
              } else {
                return false; // can't determine — exclude
              }
              break;
          }

          // Date filter
          if (_dateFilter != null && date != null) {
            try {
              final d = DateTime.parse(date);
              if (d.year != _dateFilter!.year ||
                  d.month != _dateFilter!.month ||
                  d.day != _dateFilter!.day) return false;
            } catch (_) {
              return false;
            }
          }

          // Field manager filter
          if (_managerQuery.isNotEmpty) {
            if (!workerName.contains(_managerQuery.toLowerCase())) return false;
          }

          return true;
        })
        .toList();
  }

  // ─── Date picker ───────────────────────────────────────────────────────────

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateFilter ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _dateFilter = picked);
    }
  }

  void _clearDate() => setState(() => _dateFilter = null);

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final routeProvider = context.watch<RouteProvider>();
    final filtered = routeProvider.routes.isEmpty ? <Map<String, dynamic>>[] : _applyFilters(routeProvider.routes);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Routes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              final auth = context.read<AuthProvider>();
              if (auth.workerId != null) {
                context.read<RouteProvider>().loadRoutes(auth.workerId!);
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterBar(),
          Expanded(
            child: routeProvider.isLoading
                ? const Center(child: CircularProgressIndicator())
                : routeProvider.error != null
                    ? _buildError(routeProvider)
                    : filtered.isEmpty
                        ? _buildEmpty(routeProvider.routes.isEmpty)
                        : RefreshIndicator(
                            onRefresh: () async {
                              final auth = context.read<AuthProvider>();
                              if (auth.workerId != null) {
                                await context.read<RouteProvider>().loadRoutes(auth.workerId!);
                              }
                            },
                            child: ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                return _RouteCard(route: filtered[index]);
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    final hasActiveFilter = _statusFilter != _StatusFilter.all ||
        _dateFilter != null ||
        _managerQuery.isNotEmpty;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status chips
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: _StatusFilter.values.map((f) {
                final selected = _statusFilter == f;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(f.label, style: const TextStyle(fontSize: 12)),
                    selected: selected,
                    onSelected: (_) => setState(() => _statusFilter = f),
                    selectedColor: Colors.blue.shade700,
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : Colors.black87,
                      fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
          // Date + field manager row
          Row(
            children: [
              // Date picker button
              Expanded(
                child: InkWell(
                  onTap: _pickDate,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today, size: 14, color: Colors.grey.shade600),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _dateFilter != null
                                ? '${_dateFilter!.day}/${_dateFilter!.month}/${_dateFilter!.year}'
                                : 'Filter by date',
                            style: TextStyle(
                              fontSize: 12,
                              color: _dateFilter != null ? Colors.black87 : Colors.grey.shade500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (_dateFilter != null)
                          GestureDetector(
                            onTap: _clearDate,
                            child: Icon(Icons.close, size: 14, color: Colors.grey.shade600),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Field manager search
              Expanded(
                child: TextField(
                  controller: _managerController,
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    hintText: 'Field manager...',
                    hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                    prefixIcon: Icon(Icons.person_search, size: 16, color: Colors.grey.shade600),
                    suffixIcon: _managerQuery.isNotEmpty
                        ? GestureDetector(
                            onTap: () {
                              _managerController.clear();
                              setState(() => _managerQuery = '');
                            },
                            child: Icon(Icons.close, size: 14, color: Colors.grey.shade600),
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _managerQuery = v.trim()),
                ),
              ),
              // Clear all filters
              if (hasActiveFilter) ...[
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(Icons.filter_alt_off, size: 18),
                  tooltip: 'Clear all filters',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () {
                    _managerController.clear();
                    setState(() {
                      _statusFilter = _StatusFilter.all;
                      _dateFilter = null;
                      _managerQuery = '';
                    });
                  },
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildError(RouteProvider routeProvider) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 16),
          Text(routeProvider.error!, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              final auth = context.read<AuthProvider>();
              if (auth.workerId != null) {
                context.read<RouteProvider>().loadRoutes(auth.workerId!);
              }
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(bool noRoutesAtAll) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.route, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            noRoutesAtAll ? 'No routes assigned' : 'No routes match your filters',
            style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          Text(
            noRoutesAtAll
                ? 'Contact your admin to get routes assigned'
                : 'Try adjusting the filters above',
            style: TextStyle(color: Colors.grey.shade500),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ─── Route card ──────────────────────────────────────────────────────────────

class _RouteCard extends StatelessWidget {
  final Map<String, dynamic> route;
  const _RouteCard({required this.route});

  @override
  Widget build(BuildContext context) {
    final id = route['id'];
    final name = route['name'] as String? ?? 'Route #$id';
    final status = route['status'] as String? ?? 'pending';
    final customerCount = route['customerCount'] ?? route['customers']?.length ?? 0;
    final date = route['scheduledDate'] as String?;
    final workerName = route['workerName'] ?? route['fieldManagerName'];

    Color statusColor;
    IconData statusIcon;
    switch (status) {
      case 'completed':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case 'in_progress':
        statusColor = Colors.orange;
        statusIcon = Icons.play_circle;
        break;
      default:
        statusColor = Colors.blue;
        statusIcon = Icons.pending;
        break;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/routes/$id?name=${Uri.encodeComponent(name)}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(statusIcon, color: statusColor, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.people_outline, size: 14, color: Colors.grey.shade600),
                        const SizedBox(width: 4),
                        Text('$customerCount customers',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                        if (date != null) ...[
                          const SizedBox(width: 12),
                          Icon(Icons.calendar_today, size: 14, color: Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Text(_formatDate(date),
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                        ],
                      ],
                    ),
                    if (workerName != null && workerName.toString().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.person_outline, size: 13, color: Colors.grey.shade500),
                          const SizedBox(width: 4),
                          Text(workerName.toString(),
                              style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                        ],
                      ),
                    ],
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        status.replaceAll('_', ' ').toUpperCase(),
                        style: TextStyle(
                            color: statusColor,
                            fontSize: 11,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(String dateStr) {
    try {
      final d = DateTime.parse(dateStr);
      return '${d.day}/${d.month}/${d.year}';
    } catch (_) {
      return dateStr;
    }
  }
}

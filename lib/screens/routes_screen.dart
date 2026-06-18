import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../providers/route_provider.dart';

class RoutesScreen extends StatefulWidget {
  const RoutesScreen({super.key});
  @override
  State<RoutesScreen> createState() => _RoutesScreenState();
}

class _RoutesScreenState extends State<RoutesScreen> {
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
  Widget build(BuildContext context) {
    final routeProvider = context.watch<RouteProvider>();
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
      body: routeProvider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : routeProvider.error != null
              ? Center(
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
                )
              : routeProvider.routes.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.route, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text('No routes assigned', style: TextStyle(fontSize: 18, color: Colors.grey)),
                          SizedBox(height: 8),
                          Text('Contact your admin to get routes assigned',
                              style: TextStyle(color: Colors.grey), textAlign: TextAlign.center),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () async {
                        final auth = context.read<AuthProvider>();
                        if (auth.workerId != null) {
                          await context.read<RouteProvider>().loadRoutes(auth.workerId!);
                        }
                      },
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: routeProvider.routes.length,
                        itemBuilder: (context, index) {
                          final route = routeProvider.routes[index] as Map<String, dynamic>;
                          return _RouteCard(route: route);
                        },
                      ),
                    ),
    );
  }
}

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

    Color statusColor;
    IconData statusIcon;
    switch (status) {
      case 'completed': statusColor = Colors.green; statusIcon = Icons.check_circle; break;
      case 'in_progress': statusColor = Colors.orange; statusIcon = Icons.play_circle; break;
      default: statusColor = Colors.blue; statusIcon = Icons.pending; break;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.go('/routes/$id'),
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
                    Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.people_outline, size: 14, color: Colors.grey.shade600),
                        const SizedBox(width: 4),
                        Text('$customerCount customers', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                        if (date != null) ...[
                          const SizedBox(width: 12),
                          Icon(Icons.calendar_today, size: 14, color: Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Text(_formatDate(date), style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(status.replaceAll('_', ' ').toUpperCase(),
                          style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)),
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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';

class WorkerSelectScreen extends StatelessWidget {
  const WorkerSelectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final extra = GoRouterState.of(context).extra as Map<String, dynamic>?;
    final workers = (extra?['workers'] as List<dynamic>?) ?? [];

    return Scaffold(
      backgroundColor: const Color(0xFF1565C0),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.go('/login'),
        ),
        title: const Text('Select Your Profile', style: TextStyle(color: Colors.white)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Text('Who are you?', style: TextStyle(fontSize: 18, color: Colors.white70)),
            ),
            Expanded(
              child: workers.isEmpty
                  ? const Center(child: Text('No workers found.', style: TextStyle(color: Colors.white)))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: workers.length,
                      itemBuilder: (context, index) {
                        final worker = workers[index] as Map<String, dynamic>;
                        final name = worker['name'] as String? ?? 'Worker';
                        final role = worker['role'] as String? ?? 'field_worker';
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            leading: CircleAvatar(
                              backgroundColor: const Color(0xFF1565C0),
                              child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'W',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            ),
                            title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            subtitle: Text(_formatRole(role), style: TextStyle(color: Colors.grey.shade600)),
                            trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Color(0xFF1565C0)),
                            onTap: () async {
                              await context.read<AuthProvider>().selectWorker(worker);
                              if (context.mounted) context.go('/home');
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatRole(String role) {
    switch (role) {
      case 'field_manager': return 'Field Manager';
      case 'field_worker': return 'Field Worker';
      case 'admin': return 'Administrator';
      default: return role.replaceAll('_', ' ').toUpperCase();
    }
  }
}

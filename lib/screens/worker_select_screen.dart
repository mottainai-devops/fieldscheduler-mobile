import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/api_service.dart';

class WorkerSelectScreen extends StatefulWidget {
  const WorkerSelectScreen({super.key});

  @override
  State<WorkerSelectScreen> createState() => _WorkerSelectScreenState();
}

class _WorkerSelectScreenState extends State<WorkerSelectScreen> {
  List<dynamic> _workers = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadWorkers();
  }

  Future<void> _loadWorkers() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final workers = await ApiService.getAllWorkers();
      setState(() { _workers = workers; _isLoading = false; });
    } catch (e) {
      setState(() {
        _error = 'Could not load profiles. Check your connection.';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 40),
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFF1565C0),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.location_on, size: 44, color: Colors.white),
            ),
            const SizedBox(height: 20),
            const Text(
              'Field Worker App',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 8),
            const Text(
              'Select your profile to continue',
              style: TextStyle(fontSize: 15, color: Colors.white60),
            ),
            const SizedBox(height: 32),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Colors.white))
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_error!,
                                  style: const TextStyle(color: Colors.white70),
                                  textAlign: TextAlign.center),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: _loadWorkers,
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _workers.length,
                          itemBuilder: (context, index) {
                            final worker = _workers[index] as Map<String, dynamic>;
                            final name = worker['name'] as String? ?? 'Worker';
                            final phone = worker['phone'] as String? ??
                                worker['phoneNumber'] as String? ?? '';
                            final initials = name.trim().isNotEmpty
                                ? name.trim().split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join().toUpperCase()
                                : 'W';
                            final colors = [
                              const Color(0xFF1565C0),
                              const Color(0xFF00897B),
                              const Color(0xFF6A1B9A),
                              const Color(0xFF2E7D32),
                              const Color(0xFFAD1457),
                            ];
                            final avatarColor = colors[name.codeUnitAt(0) % colors.length];

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1A2A3A),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 10),
                                leading: Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: avatarColor,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    initials,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                subtitle: phone.isNotEmpty
                                    ? Text(phone,
                                        style: const TextStyle(
                                            color: Colors.white54, fontSize: 13))
                                    : null,
                                trailing: const Icon(Icons.chevron_right,
                                    color: Colors.white38),
                                onTap: () {
                                  context.go('/pin', extra: {'worker': worker});
                                },
                              ),
                            );
                          },
                        ),
            ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '© 2025 Field Scheduler',
                style: TextStyle(color: Colors.white30, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

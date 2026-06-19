import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../services/pickup_queue.dart';
import '../utils/theme.dart';
import 'routes_screen.dart';
import 'notifications_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  DateTime? _lastBackPress;

  final List<Widget> _screens = const [
    RoutesScreen(),
    NotificationsScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    // E5: Reactive queue badge — rebuilds when PickupQueue notifies
    final queue = context.watch<PickupQueue>();
    final pendingCount = queue.pendingCount;
    final failedCount = queue.failedCount;
    final totalQueued = pendingCount + failedCount;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        // If not on the Routes tab, go back to Routes tab
        if (_currentIndex != 0) {
          setState(() => _currentIndex = 0);
          return;
        }
        // On Routes tab: require double-tap to exit
        final now = DateTime.now();
        if (_lastBackPress == null ||
            now.difference(_lastBackPress!) > const Duration(seconds: 2)) {
          _lastBackPress = now;
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Press back again to exit'),
                duration: Duration(seconds: 2),
                backgroundColor: AppTheme.bgCard,
              ),
            );
          }
          return;
        }
        // Second back press within 2 seconds — exit
        if (context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: _screens,
        ),
        // E5: Pending queue badge in app bar
        appBar: totalQueued > 0
            ? AppBar(
                backgroundColor: AppTheme.bgCard,
                automaticallyImplyLeading: false,
                title: const SizedBox.shrink(),
                actions: [
                  InkWell(
                    onTap: () => context.push('/pending-pickups'),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      child: Row(children: [
                        if (failedCount > 0) ...
                          [
                            const Icon(Icons.error_outline,
                                color: Colors.red, size: 18),
                            const SizedBox(width: 4),
                            Text('$failedCount failed',
                                style: const TextStyle(
                                    color: Colors.red,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(width: 10),
                          ],
                        if (pendingCount > 0) ...
                          [
                            const Icon(Icons.schedule,
                                color: Colors.orange, size: 18),
                            const SizedBox(width: 4),
                            Text('$pendingCount pending',
                                style: const TextStyle(
                                    color: Colors.orange,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                          ],
                      ]),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              )
            : null,
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppTheme.borderColor, width: 1)),
          ),
          child: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (index) => setState(() => _currentIndex = index),
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.route_outlined),
                activeIcon: Icon(Icons.route_rounded),
                label: 'Routes',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.notifications_outlined),
                activeIcon: Icon(Icons.notifications_rounded),
                label: 'Notifications',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.person_outline_rounded),
                activeIcon: Icon(Icons.person_rounded),
                label: 'Profile',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

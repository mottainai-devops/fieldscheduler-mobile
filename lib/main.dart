import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import 'providers/auth_provider.dart';
import 'providers/route_provider.dart';
import 'providers/notification_provider.dart';
import 'services/lot_cache.dart';

import 'screens/pin_login_screen.dart';
import 'screens/worker_select_screen.dart';
import 'screens/home_screen.dart';
import 'screens/routes_screen.dart';
import 'screens/route_detail_screen.dart';
import 'screens/customer_detail_screen.dart';
import 'screens/customer_notes_screen.dart';
import 'screens/optimized_route_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/report_violation_screen.dart';
import 'screens/supervisor_login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // C2: Register LotCache as a WidgetsBindingObserver so AppLifecycleState.resumed
  // triggers a conditional refresh (30-min gate).
  lotCache.register();
  await lotCache.loadFromPrefs();
  runApp(const FieldWorkerApp());
}

class FieldWorkerApp extends StatelessWidget {
  const FieldWorkerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => RouteProvider()),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
      ],
      child: Consumer<AuthProvider>(
        builder: (context, auth, _) {
          return MaterialApp.router(
            title: 'FieldWorker',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF1565C0),
                brightness: Brightness.light,
              ),
              useMaterial3: true,
              appBarTheme: const AppBarTheme(
                backgroundColor: Color(0xFF1565C0),
                foregroundColor: Colors.white,
                elevation: 0,
              ),
              elevatedButtonTheme: ElevatedButtonThemeData(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1565C0),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            routerConfig: _buildRouter(auth),
          );
        },
      ),
    );
  }

  GoRouter _buildRouter(AuthProvider auth) {
    return GoRouter(
      initialLocation: '/select-worker',
      redirect: (context, state) {
        final isLoggedIn = auth.isLoggedIn;
        final loc = state.matchedLocation;
        final isAuthPage = loc == '/select-worker' || loc == '/pin' || loc == '/supervisor-login';
        if (!isLoggedIn && !isAuthPage) return '/select-worker';
        if (isLoggedIn && isAuthPage) return '/home';
        return null;
      },
      routes: [
        GoRoute(
          path: '/select-worker',
          builder: (context, state) => const WorkerSelectScreen(),
        ),
        GoRoute(
          path: '/pin',
          builder: (context, state) => const PinLoginScreen(),
        ),
        GoRoute(
          path: '/supervisor-login',
          builder: (context, state) => const SupervisorLoginScreen(),
        ),
        GoRoute(
          path: '/home',
          builder: (context, state) => const HomeScreen(),
        ),
        GoRoute(
          path: '/routes',
          builder: (context, state) => const RoutesScreen(),
        ),
        GoRoute(
          path: '/routes/:routeId',
          builder: (context, state) {
            final routeId = int.tryParse(state.pathParameters['routeId'] ?? '0') ?? 0;
            final routeName = state.uri.queryParameters['name'] ?? 'Route #$routeId';
            return RouteDetailScreen(routeId: routeId, routeName: routeName);
          },
        ),
        GoRoute(
          path: '/routes/:routeId/optimize',
          builder: (context, state) {
            final extra = state.extra as Map<String, dynamic>? ?? {};
            final route = extra['route'] as Map<String, dynamic>? ?? {'id': state.pathParameters['routeId']};
            final customers = (extra['customers'] as List?)?.cast<Map<String, dynamic>>() ?? [];
            return OptimizedRouteScreen(route: route, customers: customers);
          },
        ),
        GoRoute(
          path: '/customers/:customerId',
          builder: (context, state) {
            final customerId = int.tryParse(state.pathParameters['customerId'] ?? '0') ?? 0;
            final routeId = int.tryParse(state.uri.queryParameters['routeId'] ?? '0') ?? 0;
            return CustomerDetailScreen(customerId: customerId, routeId: routeId);
          },
        ),
        GoRoute(
          path: '/customers/:customerId/notes',
          builder: (context, state) {
            final customerId = int.tryParse(state.pathParameters['customerId'] ?? '0') ?? 0;
            final customerName = state.uri.queryParameters['name'] ?? 'Customer';
            return CustomerNotesScreen(
              customerId: customerId,
              customerName: customerName,
            );
          },
        ),
        GoRoute(
          path: '/customers/:customerId/report-violation',
          builder: (context, state) {
            final customerId = int.tryParse(state.pathParameters['customerId'] ?? '0') ?? 0;
            final routeId = int.tryParse(state.uri.queryParameters['routeId'] ?? '0') ?? 0;
            return ReportViolationScreen(
              customerId: customerId,
              routeId: routeId,
            );
          },
        ),
        GoRoute(
          path: '/notifications',
          builder: (context, state) => const NotificationsScreen(),
        ),
        GoRoute(
          path: '/profile',
          builder: (context, state) => const ProfileScreen(),
        ),
      ],
    );
  }
}

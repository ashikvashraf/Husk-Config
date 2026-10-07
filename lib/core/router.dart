import 'package:go_router/go_router.dart';

import '../features/dashboard/dashboard_screen.dart';
import '../features/servers/scan_screen.dart';
import '../features/servers/server_form_screen.dart';

GoRouter createRouter() => GoRouter(
      routes: [
        GoRoute(path: '/', builder: (context, state) => const DashboardScreen()),
        GoRoute(
          path: '/servers/new',
          builder: (context, state) => ServerFormScreen(
            initialHost: state.uri.queryParameters['host'],
            initialPort: int.tryParse(state.uri.queryParameters['port'] ?? ''),
          ),
        ),
        GoRoute(path: '/servers/scan', builder: (context, state) => const ScanScreen()),
        GoRoute(
          path: '/servers/:id/edit',
          builder: (context, state) => ServerFormScreen(serverId: state.pathParameters['id']),
        ),
      ],
    );

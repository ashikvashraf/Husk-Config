import 'package:go_router/go_router.dart';

import '../features/dashboard/dashboard_screen.dart';
import '../features/device/device_shell.dart';
import '../features/servers/scan_screen.dart';
import '../features/servers/server_form_screen.dart';
import '../features/settings/settings_screen.dart';

GoRouter createRouter({String initialLocation = '/'}) => GoRouter(
      initialLocation: initialLocation,
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
        GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
        GoRoute(
          path: '/servers/:id/edit',
          builder: (context, state) => ServerFormScreen(serverId: state.pathParameters['id']),
        ),
        GoRoute(
          path: '/device/:id/:tab',
          builder: (context, state) => DeviceShell(
            serverId: state.pathParameters['id']!,
            tab: DeviceShell.parseTab(state.pathParameters['tab']),
          ),
        ),
      ],
    );

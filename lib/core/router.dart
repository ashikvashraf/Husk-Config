import 'package:go_router/go_router.dart';

import '../features/dashboard/dashboard_screen.dart';

GoRouter createRouter() => GoRouter(
      routes: [
        GoRoute(path: '/', builder: (context, state) => const DashboardScreen()),
      ],
    );

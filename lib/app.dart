import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/providers.dart';
import 'core/router.dart';
import 'features/settings/settings_controller.dart';

class HuskConfigApp extends ConsumerStatefulWidget {
  const HuskConfigApp({super.key});

  @override
  ConsumerState<HuskConfigApp> createState() => _HuskConfigAppState();
}

class _HuskConfigAppState extends ConsumerState<HuskConfigApp> {
  late final GoRouter _router = createRouter();
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Polling and streams pause while the app is hidden; `inactive` (desktop
    // window unfocused) still counts as foreground.
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) => ref
          .read(appForegroundProvider.notifier)
          .set(state == AppLifecycleState.resumed || state == AppLifecycleState.inactive),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(settingsProvider.select((s) => s.themeMode));
    return MaterialApp.router(
      title: 'Husk Config',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      routerConfig: _router,
    );
  }
}

ThemeData _theme(Brightness brightness) => ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal, brightness: brightness),
      useMaterial3: true,
    );

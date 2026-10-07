import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:huskconfig/app.dart';
import 'package:huskconfig/core/providers.dart';
import 'package:huskconfig/core/storage/app_settings.dart';
import 'package:huskconfig/core/storage/server_config.dart';

import 'memory_repos.dart';

/// A ProviderScope wired to in-memory repositories with retries disabled.
ProviderScope testScope({
  required Widget child,
  List<ServerConfig> servers = const [],
  AppSettings settings = const AppSettings(),
  List<Override> overrides = const [],
  MemoryServerRepository? serverRepo,
  MemorySettingsRepository? settingsRepo,
}) =>
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        serverRepositoryProvider.overrideWithValue(serverRepo ?? MemoryServerRepository(servers)),
        settingsRepositoryProvider.overrideWithValue(settingsRepo ?? MemorySettingsRepository(settings)),
        ...overrides,
      ],
      child: child,
    );

Widget testApp({
  List<ServerConfig> servers = const [],
  AppSettings settings = const AppSettings(),
  List<Override> overrides = const [],
}) =>
    testScope(servers: servers, settings: settings, overrides: overrides, child: const HuskConfigApp());

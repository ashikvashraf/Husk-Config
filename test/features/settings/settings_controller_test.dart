import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/providers.dart';
import 'package:huskconfig/core/storage/app_settings.dart';
import 'package:huskconfig/features/settings/settings_controller.dart';

import '../../support/memory_repos.dart';

void main() {
  test('update persists and pollIntervalProvider follows settings and foreground', () async {
    final repo = MemorySettingsRepository();
    final c = ProviderContainer(retry: (_, _) => null, overrides: [settingsRepositoryProvider.overrideWithValue(repo)]);
    addTearDown(c.dispose);

    expect(c.read(pollIntervalProvider), const Duration(seconds: 10));
    await c.read(settingsProvider.notifier).update((s) => s.copyWith(themeMode: ThemeMode.dark, pollIntervalSeconds: 0));
    expect(repo.saved.themeMode, ThemeMode.dark);
    expect(c.read(pollIntervalProvider), Duration.zero);

    c.read(appForegroundProvider.notifier).set(false);
    expect(c.read(pollIntervalProvider), isNull);
    expect(c.read(settingsProvider), const AppSettings(themeMode: ThemeMode.dark, pollIntervalSeconds: 0));
  });
}

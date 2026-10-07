// ignore_for_file: file_names, avoid_print
// Device checklist S05 (background pauses polling) and S06 (settings apply and
// persist). Runs the real app on macOS against the real phone. Read-only on the
// phone: only /info is requested (through the counting adapter).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/app.dart';
import 'package:huskconfig/core/providers.dart';
import 'package:huskconfig/core/storage/app_settings.dart';
import 'package:huskconfig/core/storage/settings_repository.dart';
import 'package:huskconfig/features/settings/settings_controller.dart';

import 'support/device_harness.dart';

const String _group = '02_settings_polling_test';

void main() {
  initDeviceHarness();
  final probe = PhoneProbe();

  tearDown(() async {
    // Leave the phone on its home screen (nothing here changes it otherwise).
    try {
      await probe.home();
    } catch (e) {
      print('tearDown: could not press Home: $e');
    }
  });

  testWidgets('S05 App in background pauses polling and resumes on return', (tester) async {
    try {
      final adapter = await pumpHuskApp(
        tester,
        servers: [phoneServer],
        settings: const AppSettings(pollIntervalSeconds: 5),
      );
      // Registered after pumpHuskApp's teardowns, so it runs first: never leave
      // the binding hidden for the next test.
      // Go back through `inactive`: AppLifecycleListener asserts on the
      // hidden -> resumed shortcut, like the real platform never sends it.
      addTearDown(() {
        if (tester.binding.lifecycleState == AppLifecycleState.hidden) {
          tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        }
        if (tester.binding.lifecycleState != AppLifecycleState.resumed) {
          tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        }
      });

      // Foreground: first poll is immediate, then every 5 s, so ~3 in 12 s.
      await pumpFor(tester, const Duration(seconds: 12));
      final foreground = adapter.count('/info');
      final snapPath1 = await snap(tester, _group, 'S05-1');
      expect(foreground, greaterThan(1), reason: 'expected repeated /info polls in 12 s at a 5 s interval');

      // Background, the way the platform reports it: resumed -> inactive ->
      // hidden (AppLifecycleListener rejects resumed -> hidden directly).
      // Frames are disabled while hidden, so wait in real time with runAsync
      // instead of tester.pump (which would wait for a frame).
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      expect(tester.binding.lifecycleState, AppLifecycleState.hidden);
      // Let an in-flight request finish before taking the baseline.
      await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
      final baseline = adapter.count('/info');
      await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 12)));
      final whileHidden = adapter.count('/info') - baseline;
      expect(whileHidden, 0, reason: '/info requests made while the app was hidden');

      // Return to foreground (hidden -> inactive -> resumed): polling resumes
      // (immediate fetch, then every 5 s).
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(tester.binding.lifecycleState, AppLifecycleState.resumed);
      final beforeResume = adapter.count('/info');
      await pumpFor(tester, const Duration(seconds: 12));
      final afterResume = adapter.count('/info') - beforeResume;
      final snapPath2 = await snap(tester, _group, 'S05-2');
      expect(afterResume, greaterThan(1), reason: '/info requests in 12 s after resume');
      expect(adapter.blocked, isEmpty);

      check(
        'S05',
        'PASS',
        'interval 5 s: foreground /info=$foreground in 12 s; hidden /info=$whileHidden in 12 s (baseline $baseline); '
            'after resumed /info=$afterResume in 12 s; $snapPath1 $snapPath2',
      );
    } catch (e) {
      check('S05', 'FAIL', '$e');
      rethrow;
    }
  });

  testWidgets('S06 Settings: theme applies, polling Off stops refresh, screen mode and client name persist', (tester) async {
    try {
      final adapter = await pumpHuskApp(
        tester,
        servers: [phoneServer],
        settings: const AppSettings(themeMode: ThemeMode.light, pollIntervalSeconds: 5),
      );
      ProviderContainer container() => ProviderScope.containerOf(tester.element(find.byType(HuskConfigApp)));
      ThemeMode appThemeMode() => tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode!;
      Brightness uiBrightness() => Theme.of(tester.element(find.byType(Scaffold).first)).brightness;
      Future<void> tapText(String text) async {
        final f = find.text(text);
        await tester.ensureVisible(f);
        await tester.tap(f);
        await pumpFor(tester, const Duration(milliseconds: 500));
      }

      // Dashboard shows the real phone, then open Settings.
      await pumpUntil(tester, find.text('Test phone'));
      await tester.tap(find.byTooltip('Settings'));
      await pumpUntil(tester, find.text('Appearance'));
      expect(appThemeMode(), ThemeMode.light);
      expect(uiBrightness(), Brightness.light);

      // --- Theme: Dark then Light, applied immediately and stored.
      await tapText('Dark');
      final darkMode = appThemeMode();
      final darkBrightness = uiBrightness();
      final darkStored = container().read(settingsProvider).themeMode;
      expect(darkMode, ThemeMode.dark);
      expect(darkBrightness, Brightness.dark);
      expect(darkStored, ThemeMode.dark);
      final snapDark = await snap(tester, _group, 'S06-1');
      await tapText('Light');
      expect(appThemeMode(), ThemeMode.light);
      expect(uiBrightness(), Brightness.light);
      expect(container().read(settingsProvider).themeMode, ThemeMode.light);
      // Leave Dark selected for the persistence check below.
      await tapText('Dark');

      // --- Default screen mode.
      await tapText('H.264');
      expect(container().read(settingsProvider).defaultScreenMode, ScreenMode.h264);

      // --- Client name: valid value saved, invalid value ignored.
      const clientName = 'Husk Test_1.2';
      final nameField = find.byType(TextFormField);
      await tester.ensureVisible(nameField);
      await tester.enterText(nameField, clientName);
      await pumpFor(tester, const Duration(milliseconds: 300));
      expect(container().read(settingsProvider).tokenClientName, clientName);
      await tester.enterText(nameField, 'bad/name!');
      await pumpFor(tester, const Duration(milliseconds: 300));
      expect(container().read(settingsProvider).tokenClientName, clientName, reason: 'invalid client name must not be saved');
      await tester.enterText(nameField, clientName);
      await pumpFor(tester, const Duration(milliseconds: 300));
      final snapSettings = await snap(tester, _group, 'S06-2');

      // --- Read back from the real prefs (what the real repository wrote).
      final prefs = container().read(sharedPreferencesProvider);
      final saved = PrefsSettingsRepository(prefs).load();
      final rawJson = prefs.getString(PrefsSettingsRepository.key);
      expect(saved.themeMode, ThemeMode.dark);
      expect(saved.defaultScreenMode, ScreenMode.h264);
      expect(saved.tokenClientName, clientName);
      expect(saved.pollIntervalSeconds, 5);

      // --- Polling interval Off.
      final dropdown = find.byType(DropdownButton<int>);
      await tester.ensureVisible(dropdown);
      await tester.tap(dropdown);
      await pumpFor(tester, const Duration(milliseconds: 500));
      await tester.tap(find.text('Off').last);
      await pumpFor(tester, const Duration(milliseconds: 500));
      expect(container().read(settingsProvider).pollIntervalSeconds, 0);
      expect(PrefsSettingsRepository(prefs).load().pollIntervalSeconds, 0);

      // Back to the dashboard: it fetches once on return, then must stay quiet.
      await tester.tap(find.byTooltip('Back'));
      await pumpUntil(tester, find.text('Test phone'));
      await pumpFor(tester, const Duration(seconds: 3));
      adapter.reset();
      await pumpFor(tester, const Duration(seconds: 12));
      final autoWhileOff = adapter.count('/info');
      final snapOff = await snap(tester, _group, 'S06-3');
      expect(autoWhileOff, 0, reason: '/info requests in 12 s with polling Off');
      // Manual refresh still works (read-only /info).
      await tester.tap(find.byTooltip('Refresh'));
      await pumpFor(tester, const Duration(seconds: 3));
      final manual = adapter.count('/info');
      expect(manual, greaterThanOrEqualTo(1), reason: 'manual Refresh should still fetch /info');
      expect(adapter.blocked, isEmpty);

      // --- Relaunch the app on the same prefs: settings are restored.
      final relaunchAdapter = CountingAdapter();
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpFor(tester, const Duration(milliseconds: 300));
      await tester.pumpWidget(ProviderScope(
        retry: (_, _) => null,
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          countingApiOverride(relaunchAdapter),
        ],
        child: const HuskConfigApp(),
      ));
      await pumpFor(tester, const Duration(milliseconds: 500));
      final restored = ProviderScope.containerOf(tester.element(find.byType(HuskConfigApp))).read(settingsProvider);
      expect(restored.themeMode, ThemeMode.dark);
      expect(restored.pollIntervalSeconds, 0);
      expect(restored.defaultScreenMode, ScreenMode.h264);
      expect(restored.tokenClientName, clientName);
      expect(appThemeMode(), ThemeMode.dark);

      check(
        'S06',
        'PASS',
        'theme Dark -> MaterialApp.themeMode=$darkMode, UI brightness=$darkBrightness, stored=$darkStored; '
            'interval Off -> $autoWhileOff /info in 12 s (manual Refresh then made $manual); '
            'prefs settings.v1=$rawJson after screen mode H.264 and client name "$clientName" (invalid name rejected); '
            'restored after relaunch=${restored.toJson()}; $snapDark $snapSettings $snapOff',
      );
    } catch (e) {
      check('S06', 'FAIL', '$e');
      rethrow;
    }
  });
}

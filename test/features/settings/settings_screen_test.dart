import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/storage/app_settings.dart';
import 'package:huskconfig/features/settings/settings_screen.dart';

import '../../support/fixtures.dart';
import '../../support/memory_repos.dart';
import '../../support/test_app.dart';

void main() {
  late MemorySettingsRepository repo;

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(testScope(
      servers: [server1],
      settingsRepo: repo,
      overrides: [appVersionProvider.overrideWith((ref) async => '1.0.0 (1)')],
      child: const MaterialApp(home: SettingsScreen()),
    ));
    await tester.pumpAndSettle();
  }

  setUp(() => repo = MemorySettingsRepository());

  testWidgets('theme selection is saved', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(repo.saved.themeMode, ThemeMode.dark);
  });

  testWidgets('polling interval can be turned off', (tester) async {
    await pump(tester);
    await tester.tap(find.text('10 s'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Off').last);
    await tester.pumpAndSettle();
    expect(repo.saved.pollIntervalSeconds, 0);
  });

  testWidgets('default screen mode is saved', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Web control'));
    await tester.pumpAndSettle();
    expect(repo.saved.defaultScreenMode, ScreenMode.webview);
  });

  testWidgets('invalid client names are rejected, valid ones saved', (tester) async {
    await pump(tester);
    final field = find.widgetWithText(TextFormField, 'Token client name');
    await tester.enterText(field, 'bad/name');
    await tester.pumpAndSettle();
    expect(find.text('Use letters, digits, space, dot, underscore or dash (max 32).'), findsOneWidget);
    expect(repo.saved.tokenClientName, 'Husk Config');
    await tester.enterText(field, 'My Mac');
    await tester.pumpAndSettle();
    expect(repo.saved.tokenClientName, 'My Mac');
  });

  testWidgets('lists servers and shows the app version', (tester) async {
    await pump(tester);
    expect(find.text('Kitchen phone'), findsOneWidget);
    expect(find.text('1.0.0 (1)'), findsOneWidget);
  });
}

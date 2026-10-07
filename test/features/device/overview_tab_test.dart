import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/storage/app_settings.dart';
import 'package:huskconfig/features/device/overview_tab.dart';
import 'package:huskconfig/features/servers/api_provider.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/fixtures.dart';
import '../../support/mocks.dart';
import '../../support/overview_stubs.dart';
import '../../support/test_app.dart';

void main() {
  late MockHuskApi api;

  setUp(() {
    api = MockHuskApi();
    stubOverview(api);
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(testScope(
      servers: [server1],
      settings: const AppSettings(pollIntervalSeconds: 0),
      overrides: [apiProvider.overrideWith((ref, id) => api)],
      child: const MaterialApp(home: Scaffold(body: OverviewTab(serverId: 's1'))),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('shows device, battery, connectivity and services', (tester) async {
    await pump(tester);
    expect(find.text('samsung SM-A750F'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('wifi'), findsOneWidget);
    expect(find.text('1080 × 2112'), findsWidgets);
    expect(find.text('Front'), findsOneWidget); // selected camera from /flags
  });

  testWidgets('a plain-text ERR from /location is shown, not a crash', (tester) async {
    await pump(tester);
    expect(find.textContaining('no-fix'), findsOneWidget);
  });

  testWidgets('wake and torch call the phone', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Wake screen'));
    await tester.pumpAndSettle();
    verify(() => api.wake()).called(1);
    expect(find.text('Screen woken for about 2 minutes'), findsOneWidget);
    await tester.tap(find.widgetWithText(SwitchListTile, 'Torch'));
    await tester.pumpAndSettle();
    verify(() => api.torch(on: true)).called(1);
  });
}

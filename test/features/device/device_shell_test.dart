import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/router.dart';
import 'package:huskconfig/core/storage/app_settings.dart';
import 'package:huskconfig/core/api/models/hardware_models.dart';
import 'package:huskconfig/core/api/models/tools_models.dart';
import 'package:huskconfig/core/storage/server_config.dart';
import 'package:huskconfig/features/device/sensors_card.dart';
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

  Future<void> pump(WidgetTester tester, {required double width, String location = '/device/s1/overview'}) async {
    tester.view.physicalSize = Size(width, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(testScope(
      servers: [server1],
      settings: const AppSettings(pollIntervalSeconds: 0),
      overrides: [apiProvider.overrideWith((ref, id) => api)],
      child: MaterialApp.router(routerConfig: createRouter(initialLocation: location)),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('wide layout uses a navigation rail', (tester) async {
    await pump(tester, width: 1200);
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Kitchen phone'), findsWidgets);
  });

  testWidgets('narrow layout uses a bottom navigation bar', (tester) async {
    await pump(tester, width: 400);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('an unknown server id explains itself', (tester) async {
    await pump(tester, width: 800, location: '/device/nope/overview');
    expect(find.text('This server no longer exists.'), findsOneWidget);
  });

  testWidgets('switching server resets card state and stops live polling of the old server', (tester) async {
    final apiB = MockHuskApi();
    stubOverview(apiB);
    when(() => api.mic()).thenAnswer((_) async => const MicLevel(amplitude: 100, max: 1000));
    when(() => apiB.mic()).thenAnswer((_) async => const MicLevel(amplitude: 100, max: 1000));
    final server2 = ServerConfig(
        id: 's2', name: 'Garage phone', host: '192.168.0.107', port: 8090, createdAt: DateTime.utc(2026, 10, 7));
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(testScope(
      servers: [server1, server2],
      settings: const AppSettings(pollIntervalSeconds: 0),
      overrides: [apiProvider.overrideWith((ref, id) => id == 's1' ? api : apiB)],
      child: MaterialApp.router(routerConfig: createRouter(initialLocation: '/device/s1/overview')),
    ));
    await tester.pumpAndSettle();

    final micSwitch = find.descendant(of: find.byType(MicCard), matching: find.byType(Switch));
    await tester.tap(micSwitch);
    await tester.pump(const Duration(seconds: 2));
    verify(() => api.mic()).called(greaterThan(0));
    expect(tester.widget<Switch>(micSwitch).value, isTrue);

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Garage phone').last);
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(micSwitch).value, isFalse);
    clearInteractions(api);
    await tester.pump(const Duration(seconds: 3));
    verifyNever(() => api.mic());
    verifyNever(() => apiB.mic());
  });
  testWidgets('switching server on the Tools tab reloads the tool page for the new server', (tester) async {
    final apiB = MockHuskApi();
    stubOverview(apiB);
    void stubMotion(MockHuskApi a, MotionConfig config) {
      when(() => a.motion()).thenAnswer((_) async => config);
      when(() => a.events()).thenAnswer((_) async => const <MotionEvent>[]);
      when(() => a.setMotion(
            enabled: any(named: 'enabled'),
            topic: any(named: 'topic'),
            server: any(named: 'server'),
            sensitivity: any(named: 'sensitivity'),
          )).thenAnswer((_) async {});
    }

    stubMotion(api, const MotionConfig(enabled: true, ntfyServer: 'https://a.example', ntfyTopic: 'topic-A', sensitivity: 9, lastNtfy: ''));
    stubMotion(apiB, const MotionConfig(enabled: false, ntfyServer: 'https://b.example', ntfyTopic: 'topic-B', sensitivity: 3, lastNtfy: ''));
    final server2 = ServerConfig(
        id: 's2', name: 'Garage phone', host: '192.168.0.107', port: 8090, createdAt: DateTime.utc(2026, 10, 7));
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(testScope(
      servers: [server1, server2],
      settings: const AppSettings(pollIntervalSeconds: 0),
      overrides: [apiProvider.overrideWith((ref, id) => id == 's1' ? api : apiB)],
      child: MaterialApp.router(routerConfig: createRouter(initialLocation: '/device/s1/tools')),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ListTile, 'Motion alarm').first);
    await tester.pumpAndSettle();
    expect(find.text('topic-A'), findsOneWidget);

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Garage phone').last);
    await tester.pumpAndSettle();

    // The tool selection resets with the server; open Motion alarm for phone B.
    await tester.tap(find.widgetWithText(ListTile, 'Motion alarm').first);
    await tester.pumpAndSettle();
    expect(find.text('topic-A'), findsNothing);
    expect(find.text('topic-B'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    verify(() => apiB.setMotion(enabled: false, topic: 'topic-B', server: 'https://b.example', sensitivity: 3)).called(1);
    verifyNever(() => api.setMotion(
          enabled: any(named: 'enabled'),
          topic: any(named: 'topic'),
          server: any(named: 'server'),
          sensitivity: any(named: 'sensitivity'),
        ));
  });
}

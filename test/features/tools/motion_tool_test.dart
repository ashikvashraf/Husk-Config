import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/api/models/tools_models.dart';
import 'package:huskconfig/features/servers/api_provider.dart';
import 'package:huskconfig/features/tools/motion_tool.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/fixtures.dart';
import '../../support/mocks.dart';
import '../../support/test_app.dart';

void main() {
  late MockHuskApi api;

  setUp(() {
    api = MockHuskApi();
    when(() => api.motion()).thenAnswer((_) async =>
        const MotionConfig(enabled: false, ntfyServer: 'https://ntfy.sh', ntfyTopic: '', sensitivity: 5, lastNtfy: ''));
    when(() => api.events()).thenAnswer((_) async => [MotionEvent(time: DateTime(2026, 10, 7, 12), source: 'camera', change: 12.5)]);
    when(() => api.setMotion(
          enabled: any(named: 'enabled'),
          topic: any(named: 'topic'),
          server: any(named: 'server'),
          sensitivity: any(named: 'sensitivity'),
        )).thenAnswer((_) async {});
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(testScope(
      servers: [server1],
      overrides: [apiProvider.overrideWith((ref, id) => api)],
      child: const MaterialApp(home: Scaffold(body: MotionTool(serverId: 's1'))),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('loads config and events, saves changes', (tester) async {
    await pump(tester);
    expect(find.text('12.5 % change'), findsOneWidget);
    await tester.tap(find.widgetWithText(SwitchListTile, 'Motion alarm'));
    await tester.enterText(find.widgetWithText(TextField, 'ntfy topic'), 'my-topic');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    verify(() => api.setMotion(enabled: true, topic: 'my-topic', server: 'https://ntfy.sh', sensitivity: 5)).called(1);
  });

  testWidgets('rejects a non-https ntfy server', (tester) async {
    await pump(tester);
    await tester.enterText(find.widgetWithText(TextField, 'ntfy server'), 'http://ntfy.local');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Only https:// servers are accepted.'), findsOneWidget);
    verifyNever(() => api.setMotion(
          enabled: any(named: 'enabled'),
          topic: any(named: 'topic'),
          server: any(named: 'server'),
          sensitivity: any(named: 'sensitivity'),
        ));
  });

  testWidgets('after saving, the form shows the saved state while the reload is pending', (tester) async {
    var calls = 0;
    when(() => api.motion()).thenAnswer((_) async {
      calls++;
      if (calls == 1) {
        return const MotionConfig(enabled: false, ntfyServer: 'https://ntfy.sh', ntfyTopic: '', sensitivity: 5, lastNtfy: '');
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return const MotionConfig(enabled: true, ntfyServer: 'https://ntfy.sh', ntfyTopic: 'my-topic', sensitivity: 5, lastNtfy: '12:00');
    });
    await pump(tester);
    await tester.tap(find.widgetWithText(SwitchListTile, 'Motion alarm'));
    await tester.enterText(find.widgetWithText(TextField, 'ntfy topic'), 'my-topic');
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Motion alarm')).value, isTrue);
    expect(find.widgetWithText(TextField, 'my-topic'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Motion alarm')).value, isTrue);
    expect(find.widgetWithText(TextField, 'my-topic'), findsOneWidget);
    expect(find.text('12:00'), findsOneWidget);
    expect(calls, 2);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/api/text_result.dart';
import 'package:huskconfig/features/servers/api_provider.dart';
import 'package:huskconfig/features/tools/launch_tool.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/fixtures.dart';
import '../../support/mocks.dart';
import '../../support/test_app.dart';

void main() {
  testWidgets('a preset fills the action and Launch sends it', (tester) async {
    final api = MockHuskApi();
    when(() => api.launch(action: 'android.settings.WIFI_SETTINGS', data: null, package: null, display: 0))
        .thenAnswer((_) async => const TextResult('OK'));
    await tester.pumpWidget(testScope(
      servers: [server1],
      overrides: [apiProvider.overrideWith((ref, id) => api)],
      child: const MaterialApp(home: Scaffold(body: LaunchTool(serverId: 's1'))),
    ));
    await tester.tap(find.text('Wi-Fi settings'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'android.settings.WIFI_SETTINGS'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Launch'));
    await tester.pumpAndSettle();
    verify(() => api.launch(action: 'android.settings.WIFI_SETTINGS', data: null, package: null, display: 0)).called(1);
    expect(find.text('OK'), findsOneWidget);
  });
}

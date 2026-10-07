import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/api/models/tools_models.dart';
import 'package:huskconfig/features/servers/api_provider.dart';
import 'package:huskconfig/features/tools/management_tool.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/fixtures.dart';
import '../../support/mocks.dart';
import '../../support/test_app.dart';

void main() {
  testWidgets('Wireless Debugging needs confirmation and shows the adb command', (tester) async {
    final api = MockHuskApi();
    when(() => api.wd()).thenAnswer((_) async => const WdInfo(ip: '192.168.0.106', port: 37123, ipport: '192.168.0.106:37123'));
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(testScope(
      servers: [server1],
      overrides: [apiProvider.overrideWith((ref, id) => api)],
      child: const MaterialApp(home: Scaffold(body: ManagementTool(serverId: 's1'))),
    ));

    await tester.tap(find.text('Enable Wireless Debugging'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    verifyNever(() => api.wd());

    await tester.tap(find.text('Enable Wireless Debugging'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Enable'));
    await tester.pumpAndSettle();
    verify(() => api.wd()).called(1);
    expect(find.text('adb connect 192.168.0.106:37123'), findsOneWidget);
  });

  testWidgets('a second tap while Wireless Debugging is pending does not call the API twice', (tester) async {
    final api = MockHuskApi();
    final completer = Completer<WdInfo>();
    when(() => api.wd()).thenAnswer((_) => completer.future);
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(testScope(
      servers: [server1],
      overrides: [apiProvider.overrideWith((ref, id) => api)],
      child: const MaterialApp(home: Scaffold(body: ManagementTool(serverId: 's1'))),
    ));

    await tester.tap(find.text('Enable Wireless Debugging'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Enable'));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    await tester.tap(find.text('Enable Wireless Debugging'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.widgetWithText(FilledButton, 'Enable'), findsNothing);
    verify(() => api.wd()).called(1);

    completer.complete(const WdInfo(ip: '192.168.0.106', port: 37123, ipport: '192.168.0.106:37123'));
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('adb connect 192.168.0.106:37123'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/features/servers/api_provider.dart';
import 'package:huskconfig/features/tools/rpc_tool.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/fixtures.dart';
import '../../support/mocks.dart';
import '../../support/test_app.dart';

void main() {
  testWidgets('confirms once per session, then sends directly', (tester) async {
    final api = MockHuskApi();
    when(() => api.rpc(any())).thenAnswer((_) async => 'pong');
    await tester.pumpWidget(testScope(
      servers: [server1],
      overrides: [apiProvider.overrideWith((ref, id) => api)],
      child: const MaterialApp(home: Scaffold(body: RpcTool(serverId: 's1'))),
    ));

    final field = find.widgetWithText(TextField, 'Command');
    await tester.enterText(field, 'ping');
    await tester.tap(find.widgetWithText(FilledButton, 'Send'));
    await tester.pumpAndSettle();
    expect(find.text('Send raw commands?'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('pong'), findsOneWidget);

    await tester.enterText(field, 'ping');
    await tester.tap(find.widgetWithText(FilledButton, 'Send'));
    await tester.pumpAndSettle();
    expect(find.text('Send raw commands?'), findsNothing);
    verify(() => api.rpc('ping')).called(2);
  });
}

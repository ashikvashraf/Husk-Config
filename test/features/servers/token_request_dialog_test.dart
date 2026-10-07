import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/api/husk_exception.dart';
import 'package:huskconfig/core/api/models/tools_models.dart';
import 'package:huskconfig/core/api/token_request_flow.dart';
import 'package:huskconfig/features/servers/token_request_dialog.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/mocks.dart';

void main() {
  late MockHuskApi api;
  String? result;

  setUp(() {
    api = MockHuskApi();
    result = null;
    when(() => api.requestToken(client: any(named: 'client')))
        .thenAnswer((_) async => const TokenRequest(id: 'r', expiresIn: 120));
  });

  Future<void> open(WidgetTester tester, {Delay? delay}) async {
    final flow = TokenRequestFlow(api: api, clientName: 'Husk Config', delay: delay ?? (_) async {});
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await showDialog<String>(context: context, builder: (_) => TokenRequestDialog(flow: flow)),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('returns the token when approved', (tester) async {
    when(() => api.tokenStatus('r')).thenAnswer((_) async => const TokenStatus(state: TokenState.approved, token: 'tok'));
    await open(tester);
    expect(result, 'tok');
    expect(find.byType(TokenRequestDialog), findsNothing);
  });

  testWidgets('shows the approval prompt while pending and cancels cleanly', (tester) async {
    when(() => api.tokenStatus('r')).thenAnswer((_) async => const TokenStatus(state: TokenState.pending));
    await open(tester, delay: (_) => Completer<void>().future); // poll never fires
    expect(find.text('Approve the request on your phone.'), findsOneWidget);
    expect(find.textContaining('Expires in'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.byType(TokenRequestDialog), findsNothing);
  });

  testWidgets('explains a denial', (tester) async {
    when(() => api.tokenStatus('r')).thenAnswer((_) async => const TokenStatus(state: TokenState.denied));
    await open(tester);
    expect(find.text('The request was denied on the phone.'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
  });

  testWidgets('explains disabled notifications (503)', (tester) async {
    when(() => api.requestToken(client: any(named: 'client'))).thenThrow(HttpStatusException(503, ''));
    await open(tester);
    expect(find.textContaining('Notifications are disabled'), findsOneWidget);
  });
}

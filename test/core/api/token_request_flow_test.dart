import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/api/husk_exception.dart';
import 'package:huskconfig/core/api/models/tools_models.dart';
import 'package:huskconfig/core/api/token_request_flow.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/mocks.dart';

const pending = TokenStatus(state: TokenState.pending);

void main() {
  late MockHuskApi api;
  late DateTime clock;

  setUp(() {
    api = MockHuskApi();
    clock = DateTime(2026, 10, 7, 12);
  });

  TokenRequestFlow flow() => TokenRequestFlow(
        api: api,
        clientName: 'Husk Config',
        now: () => clock,
        delay: (d) async => clock = clock.add(d),
      );

  void requestReturns({int expiresIn = 120}) => when(() => api.requestToken(client: 'Husk Config'))
      .thenAnswer((_) async => TokenRequest(id: 'req1', expiresIn: expiresIn));

  void statuses(List<Object> answers) {
    var i = 0;
    when(() => api.tokenStatus('req1')).thenAnswer((_) async {
      final answer = answers[i++];
      if (answer is Exception) throw answer;
      return answer as TokenStatus;
    });
  }

  Future<List<String>> names(TokenRequestFlow f) async => [for (final s in await f.run().toList()) s.toString()];

  test('approved after one pending poll', () async {
    requestReturns();
    statuses([pending, const TokenStatus(state: TokenState.approved, token: 'tok')]);
    final states = await flow().run().toList();
    expect(states.map((s) => s.toString()), ['requesting', 'pending(120)', 'pending(118)', 'approved']);
    expect((states.last as TokenFlowApproved).token, 'tok');
    expect(states.last.isTerminal, isTrue);
  });

  test('denied on the phone', () async {
    requestReturns();
    statuses([const TokenStatus(state: TokenState.denied)]);
    expect(await names(flow()), ['requesting', 'pending(120)', 'denied']);
  });

  test('expired reported by the phone', () async {
    requestReturns();
    statuses([const TokenStatus(state: TokenState.expired)]);
    expect(await names(flow()), ['requesting', 'pending(120)', 'expired']);
  });

  test('local deadline expires while still pending', () async {
    requestReturns(expiresIn: 4);
    statuses([pending, pending, pending, pending]);
    expect(await names(flow()), ['requesting', 'pending(4)', 'pending(2)', 'expired']);
  });

  test('a transient offline poll is tolerated', () async {
    requestReturns();
    statuses([const OfflineException('blip'), const TokenStatus(state: TokenState.approved, token: 'tok')]);
    expect(await names(flow()), ['requesting', 'pending(120)', 'pending(118)', 'approved']);
  });

  test('approved without a token is a failure', () async {
    requestReturns();
    statuses([const TokenStatus(state: TokenState.approved)]);
    final states = await flow().run().toList();
    expect(states.last, isA<TokenFlowFailed>());
  });

  test('429 explains that another request is pending', () async {
    when(() => api.requestToken(client: 'Husk Config')).thenThrow(HttpStatusException(429, ''));
    final states = await flow().run().toList();
    expect(states.last, isA<TokenFlowFailed>().having((s) => s.message, 'message', contains('already waiting')));
  });

  test('503 explains that notifications are disabled', () async {
    when(() => api.requestToken(client: 'Husk Config')).thenThrow(HttpStatusException(503, ''));
    final states = await flow().run().toList();
    expect(states.last, isA<TokenFlowFailed>().having((s) => s.message, 'message', contains('Notifications are disabled')));
  });

  test('offline request fails with the offline message', () async {
    when(() => api.requestToken(client: 'Husk Config')).thenThrow(const OfflineException("Can't reach 10.0.0.5:8090"));
    expect(await names(flow()), ['requesting', "failed: Can't reach 10.0.0.5:8090"]);
  });

  test('cancel stops polling', () async {
    requestReturns();
    statuses([pending, pending, pending]);
    final f = flow();
    final seen = <String>[];
    await for (final s in f.run()) {
      seen.add(s.toString());
      if (s is TokenFlowPending) f.cancel();
    }
    expect(seen, ['requesting', 'pending(120)']);
    verifyNever(() => api.tokenStatus(any()));
  });
}

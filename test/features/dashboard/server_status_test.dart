import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/api/husk_exception.dart';
import 'package:huskconfig/core/storage/app_settings.dart';
import 'package:huskconfig/features/dashboard/dashboard_screen.dart';
import 'package:huskconfig/features/dashboard/server_status.dart';
import 'package:huskconfig/features/servers/api_provider.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/fixtures.dart';
import '../../support/mocks.dart';
import '../../support/test_app.dart';

void main() {
  group('last seen', () {
    late MockHuskApi api;

    setUp(() {
      api = MockHuskApi();
      when(() => api.info()).thenAnswer((_) async => deviceInfoFixture());
    });

    ProviderContainer containerOf() {
      final scope = testScope(
        child: const SizedBox(),
        servers: [server1],
        settings: const AppSettings(pollIntervalSeconds: 0),
        overrides: [apiProvider.overrideWith((ref, id) => api)],
      );
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: scope.overrides,
      );
      addTearDown(container.dispose);
      return container;
    }

    test('survives a provider rebuild (refresh)', () async {
      final container = containerOf();
      final sub = container.listen(serverStatusProvider('s1'), (_, _) {});
      addTearDown(sub.close);
      final online = await container.read(serverStatusProvider('s1').future) as ServerOnline;

      when(() => api.info()).thenThrow(const OfflineException('down'));
      container.invalidate(serverStatusProvider);
      final offline = await container.read(serverStatusProvider('s1').future) as ServerOffline;

      expect(offline.lastSeen, online.checkedAt);
    });

    test('survives autoDispose of the status provider', () async {
      final container = containerOf();
      final first = container.listen(serverStatusProvider('s1'), (_, _) {});
      final online = await container.read(serverStatusProvider('s1').future) as ServerOnline;
      first.close();
      await Future<void>.delayed(Duration.zero);

      when(() => api.info()).thenThrow(const OfflineException('down'));
      final second = container.listen(serverStatusProvider('s1'), (_, _) {});
      addTearDown(second.close);
      final offline = await container.read(serverStatusProvider('s1').future) as ServerOffline;

      expect(offline.lastSeen, online.checkedAt);
    });

    test('is null for a server that was never online', () async {
      when(() => api.info()).thenThrow(const OfflineException('down'));
      final container = containerOf();
      final sub = container.listen(serverStatusProvider('s1'), (_, _) {});
      addTearDown(sub.close);
      final offline = await container.read(serverStatusProvider('s1').future) as ServerOffline;
      expect(offline.lastSeen, isNull);
    });
  });

  testWidgets('polling pauses while a route covers the dashboard and resumes on return', (tester) async {
    final api = MockHuskApi();
    when(() => api.info()).thenAnswer((_) async => deviceInfoFixture());
    await tester.pumpWidget(testScope(
      servers: [server1],
      settings: const AppSettings(pollIntervalSeconds: 1),
      overrides: [apiProvider.overrideWith((ref, id) => api)],
      child: const MaterialApp(home: DashboardScreen()),
    ));
    await tester.pump();
    await tester.pump();
    verify(() => api.info()).called(1);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('covering page'))));
    await tester.pumpAndSettle();
    clearInteractions(api);

    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 5));
    verifyNever(() => api.info());

    navigator.pop();
    await tester.pumpAndSettle();
    verify(() => api.info()).called(greaterThanOrEqualTo(1));

    // Dispose the tree and let the last poll delay elapse.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}

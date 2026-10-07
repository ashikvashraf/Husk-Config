import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/api/husk_exception.dart';
import 'package:huskconfig/core/storage/server_config.dart';
import 'package:huskconfig/features/servers/api_provider.dart';
import 'package:huskconfig/features/tools/token_tool.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/fixtures.dart';
import '../../support/memory_repos.dart';
import '../../support/mocks.dart';
import '../../support/test_app.dart';

class _FailingSaveRepository extends MemoryServerRepository {
  _FailingSaveRepository(super.initial);

  @override
  Future<void> saveAll(List<ServerConfig> servers) async => throw StateError('disk full');
}

void main() {
  late MockHuskApi api;
  late MemoryServerRepository repo;

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(testScope(
      serverRepo: repo,
      overrides: [apiProvider.overrideWith((ref, id) => api)],
      child: const MaterialApp(home: Scaffold(body: TokenTool(serverId: 's1'))),
    ));
  }

  setUp(() {
    api = MockHuskApi();
    repo = MemoryServerRepository([server1.copyWith(token: 'O' * 32)]);
  });

  testWidgets('rejects an invalid new token without calling the phone', (tester) async {
    await pump(tester);
    await tester.enterText(find.widgetWithText(TextField, 'New token'), 'short');
    await tester.tap(find.widgetWithText(FilledButton, 'Change token'));
    await tester.pumpAndSettle();
    expect(find.text('The new token must be 24–128 letters and digits.'), findsOneWidget);
    verifyNever(() => api.setToken(any()));
  });

  testWidgets('a confirmed change updates the phone and the saved token', (tester) async {
    when(() => api.setToken('N' * 32)).thenAnswer((_) async {});
    await pump(tester);
    await tester.enterText(find.widgetWithText(TextField, 'New token'), 'N' * 32);
    await tester.tap(find.widgetWithText(FilledButton, 'Change token'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Change token').last);
    await tester.pumpAndSettle();
    verify(() => api.setToken('N' * 32)).called(1);
    expect(repo.saved.single.token, 'N' * 32);
    expect(find.text('Token changed and saved.'), findsOneWidget);
  });

  testWidgets('409 explains that no token is set', (tester) async {
    when(() => api.setToken(any())).thenThrow(HttpStatusException(409, '{"error":"no token set; use /token/request"}'));
    await pump(tester);
    await tester.enterText(find.widgetWithText(TextField, 'New token'), 'N' * 32);
    await tester.tap(find.widgetWithText(FilledButton, 'Change token'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Change token').last);
    await tester.pumpAndSettle();
    expect(find.text('No token is set on the phone. Use Request token instead.'), findsOneWidget);
    expect(repo.saved.single.token, 'O' * 32);
  });

  testWidgets('a failed local save keeps the new token visible and tells the user', (tester) async {
    repo = _FailingSaveRepository([server1.copyWith(token: 'O' * 32)]);
    when(() => api.setToken('N' * 32)).thenAnswer((_) async {});
    await pump(tester);
    await tester.enterText(find.widgetWithText(TextField, 'New token'), 'N' * 32);
    await tester.tap(find.widgetWithText(FilledButton, 'Change token'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Change token').last);
    await tester.pumpAndSettle();
    verify(() => api.setToken('N' * 32)).called(1);
    expect(find.text('The phone now uses the new token but saving it failed. Copy it before leaving this page.'), findsOneWidget);
    expect(tester.widget<TextField>(find.widgetWithText(TextField, 'New token')).controller!.text, 'N' * 32);
    expect(tester.takeException(), isNull);
  });
}

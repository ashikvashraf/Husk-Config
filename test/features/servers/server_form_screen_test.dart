import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:huskconfig/features/servers/server_form_screen.dart';

import '../../support/fixtures.dart';
import '../../support/memory_repos.dart';
import '../../support/test_app.dart';

void main() {
  late MemoryServerRepository repo;

  Future<void> pumpForm(WidgetTester tester, {String? serverId}) async {
    final router = GoRouter(initialLocation: '/form', routes: [
      GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('home'))),
      GoRoute(path: '/form', builder: (_, _) => ServerFormScreen(serverId: serverId)),
    ]);
    await tester.pumpWidget(testScope(serverRepo: repo, child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  setUp(() => repo = MemoryServerRepository());

  testWidgets('rejects a hostname', (tester) async {
    await pumpForm(tester);
    await tester.enterText(field('IP address'), 'phone.local');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Husk only accepts IP addresses (e.g. 192.168.0.106)'), findsOneWidget);
    expect(repo.saved, isEmpty);
  });

  testWidgets('rejects an invalid port', (tester) async {
    await pumpForm(tester);
    await tester.enterText(field('IP address'), '192.168.0.106');
    await tester.enterText(field('Port'), '70000');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Port must be 1–65535'), findsOneWidget);
  });

  testWidgets('saves a new server with a trimmed host and default port', (tester) async {
    await pumpForm(tester);
    await tester.enterText(field('Name'), 'Kitchen');
    await tester.enterText(field('IP address'), ' 192.168.0.106 ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(repo.saved.single.host, '192.168.0.106');
    expect(repo.saved.single.port, 8090);
    expect(repo.saved.single.name, 'Kitchen');
    expect(repo.saved.single.token, isNull);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('name defaults to the host when left empty', (tester) async {
    await pumpForm(tester);
    await tester.enterText(field('IP address'), '10.0.0.9');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(repo.saved.single.name, '10.0.0.9');
  });

  testWidgets('edit pre-fills the fields and keeps the id', (tester) async {
    repo = MemoryServerRepository([server1]);
    await pumpForm(tester, serverId: server1.id);
    expect(find.text('Edit server'), findsOneWidget);
    expect(find.text('192.168.0.106'), findsOneWidget);
    await tester.enterText(field('Name'), 'Renamed');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(repo.saved.single.id, server1.id);
    expect(repo.saved.single.name, 'Renamed');
  });

  testWidgets('a duplicate address asks before saving', (tester) async {
    repo = MemoryServerRepository([server1]);
    await pumpForm(tester);
    await tester.enterText(field('IP address'), '192.168.0.106');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Duplicate address'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repo.saved, hasLength(1));
  });
}

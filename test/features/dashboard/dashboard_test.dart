import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/features/dashboard/server_status.dart';

import '../../support/fixtures.dart';
import '../../support/test_app.dart';

void main() {
  Future<void> pumpWith(WidgetTester tester, ServerStatus status) async {
    await tester.pumpWidget(testApp(
      servers: [server1],
      overrides: [serverStatusProvider.overrideWith((ref, id) => Stream.value(status))],
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('online card shows model, Android version, battery and services', (tester) async {
    await pumpWith(tester, ServerOnline(deviceInfoFixture(battery: 87), DateTime(2026, 10, 7, 12)));
    expect(find.text('Kitchen phone'), findsOneWidget);
    expect(find.text('192.168.0.106:8090'), findsOneWidget);
    expect(find.textContaining('samsung SM-A750F'), findsOneWidget);
    expect(find.textContaining('Android 10'), findsOneWidget);
    expect(find.text('87%'), findsOneWidget);
    expect(find.text('a11y'), findsOneWidget);
    expect(find.text('Add server'), findsOneWidget); // FAB
  });

  testWidgets('offline card shows the reason', (tester) async {
    await pumpWith(tester, const ServerOffline("Can't reach 192.168.0.106:8090"));
    expect(find.text('Offline'), findsOneWidget);
    expect(find.text("Can't reach 192.168.0.106:8090"), findsOneWidget);
  });

  testWidgets('unauthorized card asks for a token', (tester) async {
    await pumpWith(tester, const ServerUnauthorized());
    expect(find.text('Token required'), findsOneWidget);
  });

  testWidgets('delete asks for confirmation and removes the card', (tester) async {
    await pumpWith(tester, const ServerUnauthorized());
    await tester.tap(find.byTooltip('Server actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete Kitchen phone?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.text('No Husk servers yet'), findsOneWidget);
  });
}

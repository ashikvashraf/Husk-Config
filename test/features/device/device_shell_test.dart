import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/router.dart';
import 'package:huskconfig/core/storage/app_settings.dart';
import 'package:huskconfig/features/servers/api_provider.dart';

import '../../support/fixtures.dart';
import '../../support/mocks.dart';
import '../../support/overview_stubs.dart';
import '../../support/test_app.dart';

void main() {
  late MockHuskApi api;

  setUp(() {
    api = MockHuskApi();
    stubOverview(api);
  });

  Future<void> pump(WidgetTester tester, {required double width, String location = '/device/s1/overview'}) async {
    tester.view.physicalSize = Size(width, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(testScope(
      servers: [server1],
      settings: const AppSettings(pollIntervalSeconds: 0),
      overrides: [apiProvider.overrideWith((ref, id) => api)],
      child: MaterialApp.router(routerConfig: createRouter(initialLocation: location)),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('wide layout uses a navigation rail', (tester) async {
    await pump(tester, width: 1200);
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Kitchen phone'), findsWidgets);
  });

  testWidgets('narrow layout uses a bottom navigation bar', (tester) async {
    await pump(tester, width: 400);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('an unknown server id explains itself', (tester) async {
    await pump(tester, width: 800, location: '/device/nope/overview');
    expect(find.text('This server no longer exists.'), findsOneWidget);
  });
}

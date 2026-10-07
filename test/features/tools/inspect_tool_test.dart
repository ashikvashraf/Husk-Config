import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/api/text_result.dart';
import 'package:huskconfig/features/servers/api_provider.dart';
import 'package:huskconfig/features/tools/inspect_tool.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/fixtures.dart';
import '../../support/mocks.dart';
import '../../support/test_app.dart';

void main() {
  late MockHuskApi api;

  setUp(() => api = MockHuskApi());

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(testScope(
      servers: [server1],
      overrides: [apiProvider.overrideWith((ref, id) => api)],
      child: const MaterialApp(home: Scaffold(body: InspectTool(serverId: 's1'))),
    ));
  }

  testWidgets('asks for a pattern first', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Find'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a regular expression to match text or content descriptions.'), findsOneWidget);
  });

  testWidgets('Find shows the centre and Tap here taps it', (tester) async {
    when(() => api.find('Settings', display: 0)).thenAnswer((_) async => (x: 540, y: 1056));
    when(() => api.tap(540, 1056, display: 0)).thenAnswer((_) async => const TextResult('OK'));
    await pump(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Pattern (regex)'), 'Settings');
    await tester.tap(find.text('Find'));
    await tester.pumpAndSettle();
    expect(find.text('Found at 540, 1056'), findsOneWidget);
    await tester.tap(find.text('Tap here'));
    await tester.pumpAndSettle();
    verify(() => api.tap(540, 1056, display: 0)).called(1);
  });

  testWidgets('Exists reports no match', (tester) async {
    when(() => api.exists('Nope', display: 0)).thenAnswer((_) async => false);
    await pump(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Pattern (regex)'), 'Nope');
    await tester.tap(find.text('Exists'));
    await tester.pumpAndSettle();
    expect(find.text('No matching element'), findsOneWidget);
  });

  testWidgets('Dump shows a filterable tree', (tester) async {
    when(() => api.dump(display: 0)).thenAnswer((_) async => 'Settings [0,0][100,100]\nWi-Fi [0,100][100,200]');
    await pump(tester);
    await tester.tap(find.text('Dump'));
    await tester.pumpAndSettle();
    expect(find.text('Dumped 2 lines'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Filter lines'), 'wi-fi');
    await tester.pumpAndSettle();
    expect(find.text('Wi-Fi [0,100][100,200]'), findsOneWidget);
  });
}

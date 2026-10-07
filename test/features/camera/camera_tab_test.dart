import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/api/husk_exception.dart';
import 'package:huskconfig/core/api/text_result.dart';
import 'package:huskconfig/core/storage/app_settings.dart';
import 'package:huskconfig/features/camera/camera_side_switch.dart';
import 'package:huskconfig/features/camera/camera_tab.dart';
import 'package:huskconfig/features/servers/api_provider.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/fixtures.dart';
import '../../support/mocks.dart';
import '../../support/overview_stubs.dart';
import '../../support/test_app.dart';

void main() {
  late MockHuskApi api;
  // What the phone reports in /flags.front; flagsFixture starts on Front.
  late bool phoneFront;

  setUpAll(() => registerFallbackValue(CancelToken()));

  setUp(() {
    api = MockHuskApi();
    stubOverview(api);
    phoneFront = true;
    when(() => api.flags()).thenAnswer((_) async => flagsFixture(front: phoneFront));
    when(() => api.openMultipart(any(), cancelToken: any(named: 'cancelToken'))).thenAnswer((_) async =>
        (contentType: 'multipart/x-mixed-replace; boundary=rigframe', stream: StreamController<Uint8List>().stream));
  });

  const fastTiming = CameraSideSwitchTiming(
    pollInterval: Duration(milliseconds: 10),
    confirmFor: Duration(milliseconds: 50),
    retryAfter: Duration(milliseconds: 20),
  );

  /// /set?front=X answers OK and the phone applies it.
  void phoneApplies() => when(() => api.setCamera(front: any(named: 'front'))).thenAnswer((inv) async {
        phoneFront = inv.namedArguments[#front] as bool;
        return const TextResult('OK');
      });

  bool? selectedSide(WidgetTester tester) => tester.widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>)).selected.firstOrNull;

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(testScope(
      servers: [server1],
      settings: const AppSettings(pollIntervalSeconds: 0),
      overrides: [apiProvider.overrideWith((ref, id) => api)],
      child: const MaterialApp(home: Scaffold(body: CameraTab(serverId: 's1', sideSwitchTiming: fastTiming))),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('switching side sends /set?front=0 and confirms it on the first /flags poll', (tester) async {
    phoneApplies();
    await pump(tester);
    expect(selectedSide(tester), isTrue);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    verify(() => api.setCamera(front: false)).called(1);
    expect(selectedSide(tester), isFalse);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('the side buttons are disabled and show progress while the switch is confirmed', (tester) async {
    final reply = Completer<TextResult>();
    when(() => api.setCamera(front: false)).thenAnswer((_) => reply.future);
    await pump(tester);
    await tester.tap(find.text('Back'));
    await tester.pump();
    expect(tester.widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>)).onSelectionChanged, isNull);
    expect(find.text('Switching…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // A second press while switching sends nothing.
    await tester.tap(find.text('Front'));
    await tester.pump();
    verify(() => api.setCamera(front: false)).called(1);
    verifyNever(() => api.setCamera(front: true));

    phoneFront = false;
    reply.complete(const TextResult('OK'));
    await tester.pumpAndSettle();
    expect(tester.widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>)).onSelectionChanged, isNotNull);
    expect(find.text('Switching…'), findsNothing);
    expect(selectedSide(tester), isFalse);
  });

  testWidgets('an OK the phone does not apply is retried once and then reported', (tester) async {
    when(() => api.setCamera(front: false)).thenAnswer((_) async => const TextResult('OK'));
    await pump(tester);
    clearInteractions(api);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    verify(() => api.setCamera(front: false)).called(2);
    expect(find.text('The phone did not switch cameras. Wait a few seconds and try again.'), findsOneWidget);
    // The UI keeps showing what /flags reports, and the stream is left alone.
    expect(selectedSide(tester), isTrue);
    verifyNever(() => api.openMultipart(any(), cancelToken: any(named: 'cancelToken')));
  });

  testWidgets('the phone applying the retried /set counts as success', (tester) async {
    var sets = 0;
    when(() => api.setCamera(front: false)).thenAnswer((_) async {
      if (++sets == 2) phoneFront = false;
      return const TextResult('OK');
    });
    await pump(tester);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(sets, 2);
    expect(selectedSide(tester), isFalse);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a 409 explains the camera side does not exist', (tester) async {
    when(() => api.setCamera(front: false)).thenThrow(HttpStatusException(409, 'no such camera'));
    await pump(tester);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('This camera side does not exist on the device.'), findsOneWidget);
    verify(() => api.setCamera(front: false)).called(1);
    expect(selectedSide(tester), isTrue);
  });

  testWidgets('a confirmed switch reconnects the stream once instead of waiting for the phone to drop it', (tester) async {
    phoneApplies();
    await pump(tester);
    verify(() => api.openMultipart('/stream', cancelToken: any(named: 'cancelToken'))).called(1);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    verify(() => api.openMultipart('/stream', cancelToken: any(named: 'cancelToken'))).called(1);
  });

  testWidgets('a failed /set leaves the stream connection alone', (tester) async {
    when(() => api.setCamera(front: false)).thenThrow(HttpStatusException(409, 'no such camera'));
    await pump(tester);
    clearInteractions(api);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    verifyNever(() => api.openMultipart(any(), cancelToken: any(named: 'cancelToken')));
  });
}

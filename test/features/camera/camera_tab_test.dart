import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/api/husk_exception.dart';
import 'package:huskconfig/core/api/text_result.dart';
import 'package:huskconfig/core/storage/app_settings.dart';
import 'package:huskconfig/features/camera/camera_tab.dart';
import 'package:huskconfig/features/servers/api_provider.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/fixtures.dart';
import '../../support/mocks.dart';
import '../../support/overview_stubs.dart';
import '../../support/test_app.dart';

void main() {
  late MockHuskApi api;

  setUpAll(() => registerFallbackValue(CancelToken()));

  setUp(() {
    api = MockHuskApi();
    stubOverview(api);
    when(() => api.openMultipart(any(), cancelToken: any(named: 'cancelToken'))).thenAnswer((_) async =>
        (contentType: 'multipart/x-mixed-replace; boundary=rigframe', stream: StreamController<Uint8List>().stream));
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(testScope(
      servers: [server1],
      settings: const AppSettings(pollIntervalSeconds: 0),
      overrides: [apiProvider.overrideWith((ref, id) => api)],
      child: const MaterialApp(home: Scaffold(body: CameraTab(serverId: 's1'))),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('switching side sends /set?front=0', (tester) async {
    when(() => api.setCamera(front: false)).thenAnswer((_) async => const TextResult('ok'));
    await pump(tester);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    verify(() => api.setCamera(front: false)).called(1);
  });

  testWidgets('a 409 explains the camera side does not exist', (tester) async {
    when(() => api.setCamera(front: false)).thenThrow(HttpStatusException(409, 'no such camera'));
    await pump(tester);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('This camera side does not exist on the device.'), findsOneWidget);
  });
}

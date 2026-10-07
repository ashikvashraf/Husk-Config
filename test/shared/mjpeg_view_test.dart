import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/api/husk_exception.dart';
import 'package:huskconfig/shared/widgets/mjpeg_view.dart';
import 'package:mocktail/mocktail.dart';

import '../support/mocks.dart';

void main() {
  late MockHuskApi api;

  setUpAll(() => registerFallbackValue(CancelToken()));
  setUp(() => api = MockHuskApi());

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(ProviderScope(
        retry: (_, _) => null,
        child: MaterialApp(home: MjpegView(api: api, path: '/stream')),
      ));

  testWidgets('shows Connecting while waiting for the first frame', (tester) async {
    when(() => api.openMultipart('/stream', cancelToken: any(named: 'cancelToken'))).thenAnswer((_) async =>
        (contentType: 'multipart/x-mixed-replace; boundary=rigframe', stream: StreamController<Uint8List>().stream));
    await pump(tester);
    await tester.pump();
    expect(find.text('Connecting…'), findsOneWidget);
  });

  testWidgets('a failed connection schedules a reconnect with backoff', (tester) async {
    when(() => api.openMultipart('/stream', cancelToken: any(named: 'cancelToken')))
        .thenThrow(const OfflineException("Can't reach 10.0.0.5:8090"));
    await pump(tester);
    await tester.pump();
    expect(find.text("Can't reach 10.0.0.5:8090. Reconnecting in 1s…"), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    verify(() => api.openMultipart('/stream', cancelToken: any(named: 'cancelToken'))).called(2);
    expect(find.text("Can't reach 10.0.0.5:8090. Reconnecting in 2s…"), findsOneWidget);
  });
}

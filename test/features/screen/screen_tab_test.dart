import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/api/models/hardware_models.dart';
import 'package:huskconfig/core/api/models/tools_models.dart';
import 'package:huskconfig/core/api/text_result.dart';
import 'package:huskconfig/core/storage/app_settings.dart';
import 'package:huskconfig/features/screen/gesture_layer.dart';
import 'package:huskconfig/features/screen/screen_tab.dart';
import 'package:huskconfig/features/servers/api_provider.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/fixtures.dart';
import '../../support/mocks.dart';
import '../../support/overview_stubs.dart';
import '../../support/test_app.dart';

void main() {
  late MockHuskApi api;

  setUpAll(() => registerFallbackValue(CancelToken()));

  Future<void> pump(
    WidgetTester tester, {
    required bool screenSharing,
    bool secondDisplay = false,
    StreamController<Uint8List>? frames,
  }) async {
    api = MockHuskApi();
    stubOverview(api, screenSharing: screenSharing);
    if (secondDisplay) {
      when(() => api.displays())
          .thenAnswer((_) async => const [DisplayEntry(id: 0, raw: '0:0'), DisplayEntry(id: 1, raw: '1:1')]);
      when(() => api.display(display: 1)).thenAnswer((_) async =>
          DisplayInfo.fromJson({'width': 720, 'height': 1280, 'densityDpi': 240, 'density': 1.5, 'refreshHz': 60.0, 'rotation': '0'}));
    }
    when(() => api.openMultipart(any(), cancelToken: any(named: 'cancelToken'))).thenAnswer((_) async =>
        (contentType: 'multipart/x-mixed-replace; boundary=rigframe', stream: (frames ?? StreamController<Uint8List>()).stream));
    when(() => api.tap(any(), any(), display: any(named: 'display'), ms: any(named: 'ms')))
        .thenAnswer((_) async => const TextResult('OK'));
    when(() => api.key(any())).thenAnswer((_) async => const TextResult('OK'));
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(testScope(
      servers: [server1],
      settings: const AppSettings(pollIntervalSeconds: 0),
      overrides: [apiProvider.overrideWith((ref, id) => api)],
      child: const MaterialApp(home: Scaffold(body: ScreenTab(serverId: 's1'))),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('explains when screen sharing is off', (tester) async {
    await pump(tester, screenSharing: false);
    expect(find.text('Screen sharing is off. Enable it in the Husk app on the phone.'), findsOneWidget);
    expect(find.byType(GestureLayer), findsNothing);
  });

  testWidgets('before the first frame a tap maps onto the /info screen size', (tester) async {
    await pump(tester, screenSharing: true);
    await tester.tap(find.byType(GestureLayer));
    await tester.pumpAndSettle();
    verify(() => api.tap(540, 1110, display: 0)).called(1);
  });

  testWidgets('nav bar Home sends /key?k=home', (tester) async {
    await pump(tester, screenSharing: true);
    await tester.tap(find.byTooltip('Home'));
    await tester.pumpAndSettle();
    verify(() => api.key(NavKey.home)).called(1);
  });

  testWidgets('ERR cancelled suggests waking the screen', (tester) async {
    await pump(tester, screenSharing: true);
    when(() => api.key(NavKey.back)).thenAnswer((_) async => const TextResult('ERR cancelled'));
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Screen may be off — press Wake.'), findsOneWidget);
  });

  testWidgets('ERR ime-needs-api30 on Send text shows an Android 11 hint', (tester) async {
    await pump(tester, screenSharing: true);
    when(() => api.typeText(any())).thenAnswer((_) async => const TextResult('ERR ime-needs-api30'));
    await tester.enterText(find.byType(TextField), 'hello');
    await tester.tap(find.byTooltip('Send text'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Typing needs Android 11 or newer on the phone.'), findsOneWidget);
  });

  testWidgets('picking a display streams it and maps taps with its size', (tester) async {
    await pump(tester, screenSharing: true, secondDisplay: true);
    verify(() => api.openMultipart('/screen', cancelToken: any(named: 'cancelToken'))).called(1);

    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Display 1').last);
    await tester.pumpAndSettle();

    verify(() => api.openMultipart('/screen?d=1', cancelToken: any(named: 'cancelToken'))).called(1);
    verify(() => api.display(display: 1)).called(1);

    await tester.tap(find.byType(GestureLayer));
    await tester.pumpAndSettle();
    verify(() => api.tap(360, 640, display: 1)).called(1);
  });

  testWidgets('H.264 is offered for display 0 only, other displays fall back to MJPEG', (tester) async {
    await pump(tester, screenSharing: true, secondDisplay: true);
    expect(find.text('H.264'), findsOneWidget);

    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Display 1').last);
    await tester.pumpAndSettle();

    expect(find.text('H.264'), findsNothing);
  });

  /// Sends one solid PNG frame of [width] x [height] down the MJPEG stream and
  /// waits until the view has decoded it.
  Future<void> sendFrame(WidgetTester tester, StreamController<Uint8List> frames, int width, int height) async {
    final png = (await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawRect(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), Paint());
      final image = await recorder.endRecording().toImage(width, height);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data!.buffer.asUint8List();
    }))!;
    frames.add(Uint8List.fromList([
      ...ascii.encode('--rigframe\r\nContent-Type: image/png\r\nContent-Length: ${png.length}\r\n\r\n'),
      ...png,
      ...ascii.encode('\r\n--rigframe\r\n'),
    ]));
    // Let the parser deliver the frame and the engine decode it (real async work).
    for (var i = 0; i < 5; i++) {
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    }
    await tester.pumpAndSettle();
  }

  /// Where a [frame]-sized image is drawn (BoxFit.contain) inside the gesture layer.
  Rect drawnFrame(WidgetTester tester, Size frame) {
    final layer = tester.getRect(find.byType(GestureLayer));
    final fitted = applyBoxFit(BoxFit.contain, frame, layer.size).destination;
    return Alignment.center.inscribe(fitted, layer);
  }

  testWidgets('taps map onto the full-screen frame being drawn, not the /display size', (tester) async {
    // Real phone: /display 1080x2112 leaves out the nav bar; /info and the frames are the full 1080x2220.
    final frames = StreamController<Uint8List>();
    addTearDown(frames.close);
    await pump(tester, screenSharing: true, frames: frames);
    await sendFrame(tester, frames, 720, 1480);

    final image = drawnFrame(tester, const Size(720, 1480));
    expect(image.width, lessThan(tester.getSize(find.byType(GestureLayer)).width)); // The view does not match the frame.

    await tester.tapAt(image.center);
    await tester.pumpAndSettle();
    verify(() => api.tap(540, 1110, display: 0)).called(1);

    // The nav bar strip at the very bottom is reachable.
    await tester.tapAt(Offset(image.center.dx, image.bottom - 0.25));
    await tester.pumpAndSettle();
    final y = verify(() => api.tap(540, captureAny(), display: 0)).captured.single as int;
    expect(y, closeTo(2219, 1));
  });

  testWidgets('a rotated frame maps taps onto the rotated full screen', (tester) async {
    final frames = StreamController<Uint8List>();
    addTearDown(frames.close);
    await pump(tester, screenSharing: true, frames: frames);
    var reads = 0;
    when(() => api.display()).thenAnswer((_) async {
      reads++;
      return DisplayInfo.fromJson({'width': 2112, 'height': 1080, 'densityDpi': 360, 'density': 2.25, 'refreshHz': 60.0, 'rotation': '1'});
    });

    // The phone turned to landscape: the next MJPEG frame is wider than tall.
    await sendFrame(tester, frames, 148, 72);

    // The frame alone gives the rotated geometry, so /display is not re-read.
    expect(reads, 0);
    await tester.tapAt(drawnFrame(tester, const Size(148, 72)).center);
    await tester.pumpAndSettle();
    verify(() => api.tap(1110, 540, display: 0)).called(1);
  });
}

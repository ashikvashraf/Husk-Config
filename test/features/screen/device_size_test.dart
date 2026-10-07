import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/features/screen/device_size.dart';

void main() {
  // Real SM-A750F values: /display leaves out the 108 px nav bar, /info and the
  // streamed frames cover the whole screen.
  const display = Size(1080, 2112);
  const screen = Size(1080, 2220);

  group('gestureDeviceSize', () {
    test('scales a portrait frame up to the full /info screen', () {
      expect(gestureDeviceSize(display: display, screen: screen, frame: const Size(720, 1480)), const Size(1080, 2220));
    });

    test('scales a landscape frame up to the rotated full screen', () {
      expect(gestureDeviceSize(display: display, screen: screen, frame: const Size(1480, 720)), const Size(2220, 1080));
      expect(
        gestureDeviceSize(display: const Size(2112, 1080), screen: screen, frame: const Size(1480, 720)),
        const Size(2220, 1080),
      );
    });

    test('keeps the frame aspect, so the mapping matches where the frame is drawn', () {
      final size = gestureDeviceSize(display: display, screen: screen, frame: const Size(500, 1000));
      expect(size, const Size(1110, 2220));
    });

    test('before the first frame uses the /info screen turned to the /display orientation', () {
      expect(gestureDeviceSize(display: display, screen: screen), const Size(1080, 2220));
      expect(gestureDeviceSize(display: const Size(2112, 1080), screen: screen), const Size(2220, 1080));
      expect(gestureDeviceSize(display: const Size(2112, 1080), screen: const Size(2220, 1080)), const Size(2220, 1080));
      expect(gestureDeviceSize(display: display, screen: const Size(2220, 1080)), const Size(1080, 2220));
    });

    test('without an /info screen size a frame is scaled by the /display short side, never its height', () {
      expect(gestureDeviceSize(display: display, frame: const Size(720, 1480)), const Size(1080, 2220));
      expect(gestureDeviceSize(display: display, screen: Size.zero, frame: const Size(720, 1480)), const Size(1080, 2220));
      expect(gestureDeviceSize(display: const Size(2112, 1080), frame: const Size(1480, 720)), const Size(2220, 1080));
    });

    test('with neither a frame nor an /info screen size falls back to /display', () {
      expect(gestureDeviceSize(display: display), display);
      expect(gestureDeviceSize(display: const Size(720, 1280), screen: Size.zero), const Size(720, 1280));
    });
  });
}

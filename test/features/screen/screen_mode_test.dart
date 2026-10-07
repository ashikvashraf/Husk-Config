import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/storage/app_settings.dart';
import 'package:huskconfig/features/screen/screen_mode.dart';

void main() {
  test('session choice wins over the default when available', () {
    expect(
      effectiveScreenMode(session: ScreenMode.webview, defaultMode: ScreenMode.mjpeg, available: {ScreenMode.mjpeg, ScreenMode.webview}),
      ScreenMode.webview,
    );
  });

  test('falls back to the default, then to MJPEG when unavailable', () {
    expect(effectiveScreenMode(session: null, defaultMode: ScreenMode.webview, available: {ScreenMode.mjpeg, ScreenMode.webview}), ScreenMode.webview);
    expect(effectiveScreenMode(session: ScreenMode.h264, defaultMode: ScreenMode.h264, available: {ScreenMode.mjpeg}), ScreenMode.mjpeg);
  });

  test('availableScreenModes hides H.264 when unsupported or after a failure', () {
    expect(availableScreenModes(h264Supported: true, h264Failed: false), {ScreenMode.mjpeg, ScreenMode.h264, ScreenMode.webview});
    expect(availableScreenModes(h264Supported: false, h264Failed: false), {ScreenMode.mjpeg, ScreenMode.webview});
    expect(availableScreenModes(h264Supported: true, h264Failed: true), {ScreenMode.mjpeg, ScreenMode.webview});
  });
}

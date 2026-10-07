import 'package:flutter/foundation.dart';
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

  // Values from docs/superpowers/spikes/2026-10-07-h264-media-kit.md.
  test('H.264 platforms match the spike findings (H264_PLATFORMS: macos,android)', () {
    expect(h264Platforms, {TargetPlatform.macOS, TargetPlatform.android});
  });

  test('catch-up seek is off (CATCH_UP_SEEK: off): with cache=no mpv reads at most ~1 s ahead, so a >2 s gap never occurs', () {
    expect(h264CatchUpSeek, isFalse);
  });
}

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/app_settings.dart';

/// Mode picked in the Screen tab during this app session (null = settings default).
class SessionScreenMode extends Notifier<ScreenMode?> {
  @override
  ScreenMode? build() => null;

  void set(ScreenMode mode) => state = mode;
}

final sessionScreenModeProvider = NotifierProvider<SessionScreenMode, ScreenMode?>(SessionScreenMode.new);

/// Platforms that get the H.264 /screen.mp4 mode
/// (docs/superpowers/spikes/2026-10-07-h264-media-kit.md, H264_PLATFORMS).
/// macOS passed the local libmpv probe; Android is included untested, as the
/// spike's rule allows once macOS passes. A player error falls back to MJPEG.
const Set<TargetPlatform> h264Platforms = {TargetPlatform.macOS, TargetPlatform.android};

/// Whether H264View seeks to the live edge when it falls >2 s behind (spike: CATCH_UP_SEEK: off).
/// With cache=no mpv reads at most demuxer-readahead-secs (1 s) ahead, so the
/// buffer never leads the position by 2 s and the seek could never fire.
const bool h264CatchUpSeek = false;

Set<ScreenMode> availableScreenModes({required bool h264Supported, required bool h264Failed}) => {
      ScreenMode.mjpeg,
      if (h264Supported && !h264Failed) ScreenMode.h264,
      ScreenMode.webview,
    };

ScreenMode effectiveScreenMode({
  required ScreenMode? session,
  required ScreenMode defaultMode,
  required Set<ScreenMode> available,
}) {
  final mode = session ?? defaultMode;
  return available.contains(mode) ? mode : ScreenMode.mjpeg;
}

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

/// Platforms where H.264 /screen.mp4 plays. Provisional until the Task 2
/// spike is run (it was deferred); then replace with the spike's H264_PLATFORMS.
const Set<TargetPlatform> h264Platforms = {TargetPlatform.macOS, TargetPlatform.android};

/// Whether H264View seeks to the live edge when it falls >2 s behind.
/// Provisional until the Task 2 spike is run (spike: CATCH_UP_SEEK).
const bool h264CatchUpSeek = true;

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

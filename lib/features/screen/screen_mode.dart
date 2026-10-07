import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/app_settings.dart';

/// Mode picked in the Screen tab during this app session (null = settings default).
class SessionScreenMode extends Notifier<ScreenMode?> {
  @override
  ScreenMode? build() => null;

  void set(ScreenMode mode) => state = mode;
}

final sessionScreenModeProvider = NotifierProvider<SessionScreenMode, ScreenMode?>(SessionScreenMode.new);

/// Modes this build can show. H.264 and Web control are added in Task 20.
Set<ScreenMode> availableScreenModes() => {ScreenMode.mjpeg};

ScreenMode effectiveScreenMode({
  required ScreenMode? session,
  required ScreenMode defaultMode,
  required Set<ScreenMode> available,
}) {
  final mode = session ?? defaultMode;
  return available.contains(mode) ? mode : ScreenMode.mjpeg;
}

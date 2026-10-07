import 'dart:ui';

/// The phone-pixel size the gesture layer maps the drawn frame onto (spec 5.9).
///
/// /tap and /swipe take real screen pixels. On the test phone /display
/// (1080x2112) leaves out the 108 px nav bar while /info's screen size and
/// the /screen and /screen.mp4 frames cover the full 1080x2220 screen, so the
/// mapping follows the frame actually drawn:
/// - [frame] (the decoded size of the latest frame) is scaled so its long side
///   matches the long side of [screen] (/info's screen size), keeping the
///   frame's aspect and orientation: 720x1480 -> 1080x2220, 1480x720 -> 2220x1080.
/// - Without a usable [screen], the frame is scaled by [display]'s short side,
///   which is a full screen edge; /display's long side may miss the nav bar.
/// - Before the first frame, [screen] turned to [display]'s orientation is
///   used, and only with neither does [display] itself apply.
Size gestureDeviceSize({required Size display, Size? screen, Size? frame}) {
  final full = screen == null || screen.isEmpty ? null : _oriented(screen, landscape: display.width > display.height);
  if (frame != null && !frame.isEmpty) {
    final scale = full != null ? full.longestSide / frame.longestSide : display.shortestSide / frame.shortestSide;
    return Size((frame.width * scale).roundToDouble(), (frame.height * scale).roundToDouble());
  }
  return full ?? display;
}

Size _oriented(Size size, {required bool landscape}) => (size.width > size.height) == landscape ? size : size.flipped;

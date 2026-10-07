import 'dart:math' as math;
import 'dart:ui';

/// Maps pointer positions on a letterboxed (BoxFit.contain) view of the
/// phone screen to the phone's real pixel coordinates used by /tap and /swipe.
class CoordinateMapper {
  const CoordinateMapper({required this.viewSize, required this.deviceSize});

  final Size viewSize;
  final Size deviceSize;

  /// Where the phone image is drawn inside the view.
  Rect get contentRect {
    if (viewSize.isEmpty || deviceSize.isEmpty) return Rect.zero;
    final scale = math.min(viewSize.width / deviceSize.width, viewSize.height / deviceSize.height);
    final width = deviceSize.width * scale;
    final height = deviceSize.height * scale;
    return Rect.fromLTWH((viewSize.width - width) / 2, (viewSize.height - height) / 2, width, height);
  }

  /// Device pixel under [local], or null when [local] is in the letterbox bars.
  ({int x, int y})? toDevice(Offset local) {
    final rect = contentRect;
    if (rect.isEmpty) return null;
    if (local.dx < rect.left || local.dx > rect.right || local.dy < rect.top || local.dy > rect.bottom) return null;
    return _map(local, rect);
  }

  /// Like [toDevice] but clamps points outside the image onto its edge
  /// (drag end points may leave the image).
  ({int x, int y})? toDeviceClamped(Offset local) {
    final rect = contentRect;
    if (rect.isEmpty) return null;
    return _map(Offset(local.dx.clamp(rect.left, rect.right), local.dy.clamp(rect.top, rect.bottom)), rect);
  }

  ({int x, int y}) _map(Offset point, Rect rect) => (
        x: ((point.dx - rect.left) / rect.width * deviceSize.width).round().clamp(0, deviceSize.width.toInt() - 1),
        y: ((point.dy - rect.top) / rect.height * deviceSize.height).round().clamp(0, deviceSize.height.toInt() - 1),
      );
}

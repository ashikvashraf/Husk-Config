import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/models/tools_models.dart';
import 'coordinate_mapper.dart';

typedef DevicePoint = ({int x, int y});

/// Turns taps, long presses, drags, wheel scrolls and Esc/Enter on top of a
/// letterboxed phone image into device-pixel input events.
class GestureLayer extends StatefulWidget {
  const GestureLayer({
    super.key,
    required this.deviceSize,
    required this.child,
    required this.onTap,
    required this.onLongPress,
    required this.onSwipe,
    required this.onScroll,
    required this.onKey,
  });

  final Size deviceSize;
  final Widget child;
  final void Function(DevicePoint point) onTap;
  final void Function(DevicePoint point) onLongPress;
  final void Function(DevicePoint from, DevicePoint to, Duration duration) onSwipe;
  final void Function(bool forward) onScroll;
  final void Function(NavKey key) onKey;

  @override
  State<GestureLayer> createState() => _GestureLayerState();
}

class _GestureLayerState extends State<GestureLayer> {
  final _focus = FocusNode(debugLabel: 'phone screen');
  Offset? _panStart;
  Offset? _panLast;
  DateTime? _panStartedAt;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onKey(NavKey.back);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      widget.onKey(NavKey.enter);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
        final mapper = CoordinateMapper(viewSize: constraints.biggest, deviceSize: widget.deviceSize);
        return Focus(
          focusNode: _focus,
          onKeyEvent: _onKey,
          child: Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) widget.onScroll(event.scrollDelta.dy > 0);
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => _focus.requestFocus(),
              onTapUp: (details) {
                final point = mapper.toDevice(details.localPosition);
                if (point != null) widget.onTap(point);
              },
              onLongPressStart: (details) {
                final point = mapper.toDevice(details.localPosition);
                if (point != null) widget.onLongPress(point);
              },
              // The pointer-down position, not the one after the touch slop, is where the swipe starts.
              onPanDown: (details) {
                _panStart = details.localPosition;
                _panLast = details.localPosition;
                _panStartedAt = DateTime.now();
              },
              onPanUpdate: (details) => _panLast = details.localPosition,
              onPanEnd: (_) {
                final start = _panStart, end = _panLast, startedAt = _panStartedAt;
                _panStart = null;
                if (start == null || end == null || startedAt == null) return;
                final from = mapper.toDevice(start);
                final to = mapper.toDeviceClamped(end);
                if (from == null || to == null) return;
                final ms = DateTime.now().difference(startedAt).inMilliseconds.clamp(100, 2000);
                widget.onSwipe(from, to, Duration(milliseconds: ms));
              },
              child: widget.child,
            ),
          ),
        );
      });
}

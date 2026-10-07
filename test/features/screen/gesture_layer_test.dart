import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/api/models/tools_models.dart';
import 'package:huskconfig/features/screen/gesture_layer.dart';

void main() {
  final taps = <DevicePoint>[];
  final longPresses = <DevicePoint>[];
  final swipes = <(DevicePoint, DevicePoint, Duration)>[];
  final keys = <NavKey>[];

  setUp(() {
    taps.clear();
    longPresses.clear();
    swipes.clear();
    keys.clear();
  });

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(MaterialApp(
        home: Center(
          child: SizedBox(
            width: 400,
            height: 400,
            child: GestureLayer(
              deviceSize: const Size(1080, 2112),
              onTap: taps.add,
              onLongPress: longPresses.add,
              onSwipe: (a, b, d) => swipes.add((a, b, d)),
              onScroll: (_) {},
              onKey: keys.add,
              child: const ColoredBox(color: Colors.black),
            ),
          ),
        ),
      ));

  testWidgets('tap in the centre maps to the device centre', (tester) async {
    await pump(tester);
    await tester.tap(find.byType(GestureLayer));
    await tester.pumpAndSettle();
    expect(taps, [(x: 540, y: 1056)]);
  });

  testWidgets('taps in the letterbox bars are ignored', (tester) async {
    await pump(tester);
    final topLeft = tester.getTopLeft(find.byType(GestureLayer));
    await tester.tapAt(topLeft + const Offset(10, 200));
    await tester.pumpAndSettle();
    expect(taps, isEmpty);
  });

  testWidgets('long press maps to a long tap', (tester) async {
    await pump(tester);
    await tester.longPress(find.byType(GestureLayer));
    await tester.pumpAndSettle();
    expect(longPresses, [(x: 540, y: 1056)]);
  });

  testWidgets('a drag becomes a swipe from the start point', (tester) async {
    await pump(tester);
    await tester.drag(find.byType(GestureLayer), const Offset(0, -100));
    await tester.pumpAndSettle();
    expect(swipes, hasLength(1));
    final (from, to, duration) = swipes.single;
    expect(from, (x: 540, y: 1056));
    expect(to.x, 540);
    expect(to.y, lessThan(1056));
    expect(duration.inMilliseconds, inInclusiveRange(100, 2000));
  });

  testWidgets('Escape maps to Back once the view has focus', (tester) async {
    await pump(tester);
    await tester.tap(find.byType(GestureLayer));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(keys, [NavKey.back]);
  });
}

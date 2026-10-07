import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/features/screen/coordinate_mapper.dart';

void main() {
  const tallPhone = Size(1080, 2112);

  group('portrait phone in a square view (bars left/right)', () {
    const mapper = CoordinateMapper(viewSize: Size(400, 400), deviceSize: tallPhone);

    test('content rect is centred horizontally', () {
      final r = mapper.contentRect;
      expect(r.top, 0);
      expect(r.height, 400);
      expect(r.width, closeTo(204.545, 0.01));
      expect(r.left, closeTo(97.727, 0.01));
    });

    test('centre maps to device centre', () {
      expect(mapper.toDevice(const Offset(200, 200)), (x: 540, y: 1056));
    });

    test('points in the bars are rejected', () {
      expect(mapper.toDevice(const Offset(50, 200)), isNull);
      expect(mapper.toDevice(const Offset(390, 10)), isNull);
    });

    test('corners clamp to the last pixel', () {
      final r = mapper.contentRect;
      expect(mapper.toDevice(r.topLeft), (x: 0, y: 0));
      expect(mapper.toDevice(r.bottomRight), (x: 1079, y: 2111));
    });

    test('toDeviceClamped pulls bar points onto the edge', () {
      expect(mapper.toDeviceClamped(const Offset(0, 200)), (x: 0, y: 1056));
    });
  });

  test('landscape device in a tall view (bars top/bottom)', () {
    const mapper = CoordinateMapper(viewSize: Size(400, 800), deviceSize: Size(2112, 1080));
    expect(mapper.toDevice(const Offset(200, 100)), isNull);
    expect(mapper.toDevice(const Offset(200, 400)), (x: 1056, y: 540));
  });

  test('empty sizes map to null', () {
    expect(const CoordinateMapper(viewSize: Size(400, 400), deviceSize: Size.zero).toDevice(const Offset(1, 1)), isNull);
    expect(const CoordinateMapper(viewSize: Size.zero, deviceSize: tallPhone).toDeviceClamped(Offset.zero), isNull);
  });
}

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/api/husk_exception.dart';
import 'package:huskconfig/features/camera/snapshot.dart';

void main() {
  final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]);

  test('retries once after a 503 while the lazy camera wakes up', () async {
    var calls = 0;
    final bytes = await fetchWithWarmup(() async {
      if (++calls == 1) throw HttpStatusException(503, 'no frame yet');
      return jpeg;
    }, wait: Duration.zero);
    expect(bytes, jpeg);
    expect(calls, 2);
  });

  test('does not retry other errors', () async {
    var calls = 0;
    await expectLater(
      fetchWithWarmup(() async {
        calls++;
        throw HttpStatusException(500, 'boom');
      }, wait: Duration.zero),
      throwsA(isA<HttpStatusException>()),
    );
    expect(calls, 1);
  });

  test('gives up after the second 503', () async {
    await expectLater(
      fetchWithWarmup(() async => throw HttpStatusException(503, ''), wait: Duration.zero),
      throwsA(isA<HttpStatusException>().having((e) => e.statusCode, 'statusCode', 503)),
    );
  });
}

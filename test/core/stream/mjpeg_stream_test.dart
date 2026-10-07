import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/stream/mjpeg_stream.dart';

Uint8List jpeg(int seed, [int size = 32]) =>
    Uint8List.fromList([0xFF, 0xD8, for (var i = 0; i < size; i++) (seed + i) % 256, 0xFF, 0xD9]);

List<int> part(Uint8List frame, {bool withLength = true, String boundary = 'rigframe'}) => [
      ...ascii.encode('--$boundary\r\nContent-Type: image/jpeg\r\n'
          '${withLength ? 'Content-Length: ${frame.length}\r\n' : ''}\r\n'),
      ...frame,
      ...ascii.encode('\r\n'),
    ];

Future<List<Uint8List>> parse(List<List<int>> chunks, {String boundary = 'rigframe', int maxBufferBytes = 16 << 20}) =>
    Stream.fromIterable(chunks.map(Uint8List.fromList))
        .transform(MjpegParser(boundary, maxBufferBytes: maxBufferBytes))
        .toList();

void main() {
  final a = jpeg(1), b = jpeg(2, 500), c = jpeg(3);

  group('boundaryFrom', () {
    test('plain, quoted and missing', () {
      expect(MjpegParser.boundaryFrom('multipart/x-mixed-replace; boundary=rigframe'), 'rigframe');
      expect(MjpegParser.boundaryFrom('multipart/x-mixed-replace;boundary="abc def"'), 'abc def');
      expect(MjpegParser.boundaryFrom('image/jpeg'), isNull);
    });
  });

  test('two frames in one chunk', () async {
    expect(await parse([[...part(a), ...part(b)]]), [a, b]);
  });

  test('frames split byte by byte', () async {
    final bytes = [...part(a), ...part(b), ...part(c)];
    expect(await parse([for (final byte in bytes) [byte]]), [a, b, c]);
  });

  test('frames without Content-Length are cut at the next boundary', () async {
    expect(
      await parse([[...part(a, withLength: false), ...part(b, withLength: false), ...ascii.encode('--rigframe')]]),
      [a, b],
    );
  });

  test('garbage before the first boundary is ignored', () async {
    expect(await parse([ascii.encode('HTTP junk\r\n'), part(a)]), [a]);
  });

  test('an oversized part is discarded and the parser recovers on the next part', () async {
    final frames = await parse(
      [
        ascii.encode('--rigframe\r\nContent-Type: image/jpeg\r\nContent-Length: 100000\r\n\r\n'),
        List.filled(300, 0),
        part(c),
      ],
      maxBufferBytes: 200,
    );
    expect(frames, [c]);
  });

  group('a Content-Length larger than the part', () {
    // Declares 5000 bytes but the part is ~40 bytes; three valid frames follow.
    List<int> bogus() => [
          ...ascii.encode('--rigframe\r\nContent-Type: image/jpeg\r\nContent-Length: 5000\r\n\r\n'),
          ...a,
          ...ascii.encode('\r\n'),
        ];

    test('is not trusted: the part is cut at the next boundary and later frames survive', () async {
      expect(await parse([[...bogus(), ...part(a), ...part(b), ...part(c)]]), [a, a, b, c]);
    });

    test('recovers when the bytes arrive one at a time', () async {
      final bytes = [...bogus(), ...part(a), ...part(b), ...part(c)];
      expect(await parse([for (final byte in bytes) [byte]]), [a, a, b, c]);
    });
  });
}

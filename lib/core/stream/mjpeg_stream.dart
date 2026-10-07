import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// Splits a `multipart/x-mixed-replace` body (Husk /stream and /screen) into
/// JPEG frames. Uses Content-Length when present, otherwise cuts at the next
/// boundary. If more than [maxBufferBytes] pile up without a complete frame,
/// the buffer is dropped so a broken stream cannot grow memory without bound.
class MjpegParser extends StreamTransformerBase<Uint8List, Uint8List> {
  MjpegParser(String boundary, {this.maxBufferBytes = 16 * 1024 * 1024}) : _delimiter = utf8.encode('--$boundary');

  final int maxBufferBytes;
  final List<int> _delimiter;

  /// The `boundary` parameter of a Content-Type header value, or null.
  static String? boundaryFrom(String contentType) {
    final match = RegExp(r'boundary="?([^";]+)"?', caseSensitive: false).firstMatch(contentType);
    final value = match?.group(1)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  @override
  Stream<Uint8List> bind(Stream<Uint8List> stream) =>
      Stream<Uint8List>.eventTransformed(stream, (sink) => _MjpegSink(sink, _delimiter, maxBufferBytes));
}

enum _Part { boundary, headers, body }

class _MjpegSink implements EventSink<Uint8List> {
  _MjpegSink(this._out, this._delimiter, this._maxBytes);

  static const _headerEnd = [13, 10, 13, 10];
  static final _contentLength = RegExp(r'content-length:\s*(\d+)', caseSensitive: false);

  final EventSink<Uint8List> _out;
  final List<int> _delimiter;
  final int _maxBytes;
  final _buffer = _ByteBuffer();
  _Part _part = _Part.boundary;
  int _length = -1;
  int _scanFrom = 0;

  @override
  void add(Uint8List chunk) {
    _buffer.add(chunk);
    _drain();
    if (_buffer.length > _maxBytes) {
      _buffer.clear();
      _part = _Part.boundary;
    }
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) => _out.addError(error, stackTrace);

  @override
  void close() => _out.close();

  void _drain() {
    while (true) {
      switch (_part) {
        case _Part.boundary:
          final at = _buffer.indexOf(_delimiter);
          if (at < 0) {
            // Keep a tail that could be the start of a delimiter split across chunks.
            _buffer.skip(math.max(0, _buffer.length - (_delimiter.length - 1)));
            return;
          }
          _buffer.skip(at + _delimiter.length);
          _part = _Part.headers;
        case _Part.headers:
          final at = _buffer.indexOf(_headerEnd);
          if (at < 0) return;
          final headers = latin1.decode(_buffer.peek(at));
          _buffer.skip(at + _headerEnd.length);
          _length = int.tryParse(_contentLength.firstMatch(headers)?.group(1) ?? '') ?? -1;
          _scanFrom = 0;
          _part = _Part.body;
        case _Part.body:
          if (_length >= 0) {
            if (_buffer.length < _length) return;
            _emit(_buffer.take(_length));
          } else {
            final at = _buffer.indexOf(_delimiter, _scanFrom);
            if (at < 0) {
              _scanFrom = math.max(0, _buffer.length - _delimiter.length);
              return;
            }
            var end = at;
            if (end >= 2 && _buffer[end - 2] == 13 && _buffer[end - 1] == 10) end -= 2;
            _emit(_buffer.take(end));
            _buffer.skip(at - end);
          }
          _part = _Part.boundary;
      }
    }
  }

  void _emit(Uint8List frame) {
    if (frame.isNotEmpty) _out.add(frame);
  }
}

/// Growable byte queue with cheap consumption from the front.
class _ByteBuffer {
  Uint8List _data = Uint8List(64 * 1024);
  int _start = 0;
  int _end = 0;

  int get length => _end - _start;

  int operator [](int index) => _data[_start + index];

  void add(Uint8List chunk) {
    final used = length;
    if (_end + chunk.length > _data.length) {
      final target = used + chunk.length > _data.length ? Uint8List(math.max(used + chunk.length, _data.length * 2)) : _data;
      target.setRange(0, used, _data, _start);
      _data = target;
      _start = 0;
      _end = used;
    }
    _data.setRange(_end, _end + chunk.length, chunk);
    _end += chunk.length;
  }

  /// Index of [pattern] relative to the front, searching from [from], or -1.
  int indexOf(List<int> pattern, [int from = 0]) {
    final last = length - pattern.length;
    outer:
    for (var i = from; i <= last; i++) {
      for (var j = 0; j < pattern.length; j++) {
        if (_data[_start + i + j] != pattern[j]) continue outer;
      }
      return i;
    }
    return -1;
  }

  /// A view of the first [count] bytes; valid only until the next mutation.
  Uint8List peek(int count) => Uint8List.sublistView(_data, _start, _start + count);

  /// Copies and removes the first [count] bytes.
  Uint8List take(int count) {
    final out = _data.sublist(_start, _start + count);
    skip(count);
    return out;
  }

  void skip(int count) {
    _start += count;
    if (_start >= _end) clear();
  }

  void clear() {
    _start = 0;
    _end = 0;
  }
}

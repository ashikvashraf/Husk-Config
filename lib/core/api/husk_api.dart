import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'husk_exception.dart';
import 'models/device_models.dart';
import 'models/hardware_models.dart';
import 'models/json_read.dart';
import 'models/tools_models.dart';
import 'text_result.dart';

/// Body of a streaming (MJPEG) response plus its Content-Type header.
typedef MultipartResponse = ({String contentType, Stream<Uint8List> stream});

/// Typed client for one Husk phone. Every endpoint is a GET with query
/// parameters; the token travels as `?token=`.
class HuskApi {
  HuskApi({
    required this.baseUrl,
    this.token,
    HttpClientAdapter? adapter,
    Duration connectTimeout = const Duration(seconds: 3),
    Duration receiveTimeout = const Duration(seconds: 10),
    this.streamIdle = const Duration(seconds: 15),
  }) : _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: connectTimeout,
          receiveTimeout: receiveTimeout,
          responseType: ResponseType.plain,
          validateStatus: (_) => true,
        )) {
    if (adapter != null) _dio.httpClientAdapter = adapter;
  }

  /// For endpoints that drive the phone's UI (dump, rpc, management).
  static const _slow = Duration(seconds: 30);

  /// Idle limit for [openMultipart]. dio's receiveTimeout (dio 5.x IO
  /// adapter) bounds only the wait for the response headers and gives no
  /// per-chunk timer for `ResponseType.stream`. So [openMultipart] wraps the
  /// returned stream in `Stream.timeout(streamIdle)`: when no chunk arrives
  /// for this long, the stream emits [OfflineException], closes, and cancels
  /// the underlying response so consumers can reconnect.
  final Duration streamIdle;

  final String baseUrl;
  final String? token;
  final Dio _dio;

  void close() => _dio.close(force: true);

  /// Absolute URL for [path] with the token attached, for consumers that do
  /// their own HTTP (media_kit, WebView).
  Uri uri(String path, [Map<String, Object?> query = const {}]) {
    final params = _params(query, auth: true);
    return Uri.parse(baseUrl).replace(path: path, queryParameters: params.isEmpty ? null : params);
  }

  // ---------------------------------------------------------------- Status

  Future<bool> healthz() async => (await _text('/healthz', auth: false)).trim() == 'ok';

  Future<DeviceInfo> info() async => DeviceInfo.fromJson(await _map('/info'));

  Future<Flags> flags() async => Flags.fromJson(await _map('/flags'));

  // -------------------------------------------------------------- Hardware

  Future<BatteryInfo> battery() async => BatteryInfo.fromJson(await _map('/battery'));

  Future<ConnectivityInfo> connectivity() async => ConnectivityInfo.fromJson(await _map('/connectivity'));

  /// Size and rotation of [display] (default display 0; `d` is sent only for other displays).
  Future<DisplayInfo> display({int display = 0}) async =>
      DisplayInfo.fromJson(await _map('/display', query: {'d': display == 0 ? null : display}));

  Future<LocationInfo> location() async => LocationInfo.fromJson(await _map('/location'));

  Future<MicLevel> mic() async => MicLevel.fromJson(await _map('/mic'));

  Future<List<SensorInfo>> sensors() async => [for (final e in await _list('/sensors')) SensorInfo.fromJson(readMap(e))];

  Future<SensorReading> sensor(String type) async => SensorReading.fromJson(await _map('/sensor', query: {'type': type}));

  Future<Map<String, VolumeLevel>> volume() async => VolumeLevel.parseAll(await _map('/volume'));

  Future<String> ringerMode() async => readString((await _map('/ringer'))['mode']) ?? 'unknown';

  Future<BrightnessInfo> brightness() async => BrightnessInfo.fromJson(await _map('/brightness'));

  Future<List<DisplayEntry>> displays() async => DisplayEntry.parseList(await _text('/displays'));

  // ---------------------------------------------------------------- Motion

  Future<MotionConfig> motion() async => MotionConfig.fromJson(await _map('/motion'));

  Future<List<MotionEvent>> events() async => [for (final e in await _list('/events')) MotionEvent.fromJson(readMap(e))];

  // ----------------------------------------------------------------- Token

  Future<TokenRequest> requestToken({required String client}) async =>
      TokenRequest.fromJson(await _map('/token/request', query: {'client': client}, auth: false));

  Future<TokenStatus> tokenStatus(String id) async =>
      TokenStatus.fromJson(await _map('/token/status', query: {'id': id}, auth: false));

  // ------------------------------------------------------------ Management

  Future<WdInfo> wd() async => WdInfo.fromJson(await _map('/wd', receiveTimeout: _slow));

  Future<PairInfo> pair() async => PairInfo.fromJson(await _map('/pair', receiveTimeout: _slow));

  // ------------------------------------------------------- Camera & screen

  Future<Uint8List> snapshot() => _bytes('/snapshot');

  Future<Uint8List> screenshot() => _bytes('/screen.jpg');

  Future<MultipartResponse> openMultipart(String path, {CancelToken? cancelToken}) async {
    final response = await _get<ResponseBody>(
      path,
      responseType: ResponseType.stream,
      receiveTimeout: streamIdle, // header wait only; chunk silence is handled below
      cancelToken: cancelToken,
    );
    final status = response.statusCode ?? 0;
    final body = response.data;
    if (body == null) throw HttpStatusException(status, '');
    if (status < 200 || status >= 300) {
      final bytes = await body.stream.fold<List<int>>(<int>[], (all, chunk) => all..addAll(chunk));
      _check(status, utf8.decode(bytes, allowMalformed: true));
    }
    // dio gives no per-chunk idle timeout for streams, so a connected but
    // silent stream (Wi-Fi drop, phone asleep) would hang forever. On silence,
    // surface an OfflineException and close so consumers can reconnect.
    final stream = body.stream.timeout(
      streamIdle,
      onTimeout: (sink) {
        sink.addError(const OfflineException('Stream stalled'));
        sink.close();
      },
    );
    return (contentType: response.headers.value(Headers.contentTypeHeader) ?? '', stream: stream);
  }

  Future<TextResult> setCamera({int? rotation, bool? flip, bool? front, int? fps, int? screenQuality, int? screenFps}) =>
      _command('/set', query: {'rot': rotation, 'flip': flip, 'front': front, 'fps': fps, 'sq': screenQuality, 'sfps': screenFps});

  // ----------------------------------------------------------------- Input

  Future<TextResult> wake() => _command('/wake');

  Future<TextResult> tap(int x, int y, {int display = 0, int? ms}) =>
      _command('/tap', query: {'x': x, 'y': y, 'd': display, 'ms': ms});

  Future<TextResult> swipe(int x1, int y1, int x2, int y2, {int display = 0, int? ms}) =>
      _command('/swipe', query: {'x1': x1, 'y1': y1, 'x2': x2, 'y2': y2, 'd': display, 'ms': ms});

  Future<TextResult> key(NavKey key) => _command('/key', query: {'k': key.name});

  Future<TextResult> click(String match, {int display = 0}) => _command('/click', query: {'match': match, 'd': display});

  /// Replaces the focused field's whole content (newlines are stripped by Husk).
  Future<TextResult> typeText(String text) => _command('/text', query: {'t': text});

  // --------------------------------------------------- Inspection & generic

  Future<String> dump({int display = 0}) => _text('/dump', query: {'d': display}, receiveTimeout: _slow);

  Future<String> rpc(String command) => _text('/rpc', query: {'cmd': command}, receiveTimeout: _slow);

  Future<({int x, int y})?> find(String match, {int display = 0}) async {
    final r = await _command('/find', query: {'match': match, 'd': display});
    if (r.isNone) return null;
    if (r.isErr) throw DeviceErrorException(r.text);
    final parts = r.text.split(RegExp(r'\s+'));
    final x = int.tryParse(parts.first);
    final y = parts.length > 1 ? int.tryParse(parts[1]) : null;
    if (x == null || y == null) throw DeviceErrorException('Unexpected response: ${r.text}');
    return (x: x, y: y);
  }

  Future<String?> getText(String match, {int display = 0}) async {
    final r = await _command('/gettext', query: {'match': match, 'd': display});
    if (r.isNone) return null;
    if (r.isErr) throw DeviceErrorException(r.text);
    return r.text;
  }

  Future<bool> exists(String match, {int display = 0}) async {
    final r = await _command('/exists', query: {'match': match, 'd': display});
    if (r.isErr) throw DeviceErrorException(r.text);
    return r.text == '1';
  }

  Future<TextResult> scroll({int display = 0, bool forward = true}) =>
      _command('/scroll', query: {'d': display, 'dir': forward ? 'fwd' : 'back'});

  // ------------------------------------------------------------ Navigation

  Future<TextResult> launch({required String action, String? data, String? package, int display = 0}) =>
      _command('/launch', query: {'action': action, 'data': data, 'pkg': package, 'd': display});

  // ------------------------------------------------------- Token & control

  /// Requires the current token; 409 when no token is set, 400 for an invalid one.
  Future<void> setToken(String newToken) async {
    await _text('/token/set', query: {'new': newToken});
  }

  Future<TextResult> devOptions({bool probe = false}) =>
      _command('/devoptions', query: {'probe': probe ? true : null}, receiveTimeout: _slow);

  // ------------------------------------------------------ Hardware setters

  Future<TextResult> torch({required bool on}) => _command('/torch', query: {'on': on});

  Future<TextResult> vibrate({int? ms}) => _command('/vibrate', query: {'ms': ms});

  Future<TextResult> setVolume(String stream, int level) => _command('/volume', query: {'stream': stream, 'level': level});

  Future<TextResult> setRinger(String mode) => _command('/ringer', query: {'mode': mode});

  Future<TextResult> setBrightness(int level) => _command('/brightness', query: {'level': level});

  /// An empty [topic] is sent as-is: it means "log to /events only, no push".
  Future<void> setMotion({bool? enabled, String? topic, String? server, int? sensitivity}) async {
    final r = await _command('/motion', query: {'on': enabled, 'topic': topic, 'server': server, 'sensitivity': sensitivity});
    if (r.isErr) throw DeviceErrorException(r.text);
  }

  // ------------------------------------------------------------- Plumbing

  Map<String, String> _params(Map<String, Object?> query, {required bool auth}) {
    final params = <String, String>{};
    query.forEach((key, value) {
      if (value == null) return;
      params[key] = value is bool ? (value ? '1' : '0') : value.toString();
    });
    final t = token;
    if (auth && t != null && t.isNotEmpty) params['token'] = t;
    return params;
  }

  Future<Response<T>> _get<T>(
    String path, {
    Map<String, Object?> query = const {},
    bool auth = true,
    ResponseType? responseType,
    Duration? receiveTimeout,
    CancelToken? cancelToken,
  }) async {
    try {
      return await _dio.get<T>(
        path,
        queryParameters: _params(query, auth: auth),
        options: Options(responseType: responseType, receiveTimeout: receiveTimeout),
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) throw const OfflineException('Request cancelled');
      throw OfflineException("Can't reach ${baseUrl.replaceFirst('http://', '')}");
    }
  }

  void _check(int status, String body) {
    if (status >= 200 && status < 300) return;
    if (status == 401) throw const UnauthorizedException();
    throw HttpStatusException(status, body);
  }

  Future<String> _text(
    String path, {
    Map<String, Object?> query = const {},
    bool auth = true,
    Duration? receiveTimeout,
  }) async {
    final response = await _get<String>(path, query: query, auth: auth, receiveTimeout: receiveTimeout);
    final body = response.data ?? '';
    _check(response.statusCode ?? 0, body);
    return body;
  }

  Future<TextResult> _command(String path, {Map<String, Object?> query = const {}, Duration? receiveTimeout}) async =>
      TextResult(await _text(path, query: query, receiveTimeout: receiveTimeout));

  /// Decodes a JSON body. Husk answers some JSON endpoints with plain text
  /// (`ERR …`) under HTTP 200; that becomes a DeviceErrorException.
  Future<Object?> _json(String path, {Map<String, Object?> query = const {}, bool auth = true, Duration? receiveTimeout}) async {
    final body = (await _text(path, query: query, auth: auth, receiveTimeout: receiveTimeout)).trim();
    if (body.startsWith('{') || body.startsWith('[')) {
      try {
        return jsonDecode(body);
      } on FormatException {
        throw DeviceErrorException('Unexpected response: $body');
      }
    }
    throw DeviceErrorException(body.isEmpty ? 'Empty response' : body);
  }

  Future<Map<String, Object?>> _map(String path, {Map<String, Object?> query = const {}, bool auth = true, Duration? receiveTimeout}) async {
    final value = await _json(path, query: query, auth: auth, receiveTimeout: receiveTimeout);
    if (value is Map<String, Object?>) return value;
    throw DeviceErrorException('Unexpected response from $path');
  }

  Future<List<Object?>> _list(String path, {Map<String, Object?> query = const {}}) async {
    final value = await _json(path, query: query);
    if (value is List<Object?>) return value;
    throw DeviceErrorException('Unexpected response from $path');
  }

  Future<Uint8List> _bytes(String path) async {
    final response = await _get<List<int>>(path, responseType: ResponseType.bytes);
    final data = response.data ?? const <int>[];
    _check(response.statusCode ?? 0, utf8.decode(data, allowMalformed: true));
    return Uint8List.fromList(data);
  }
}

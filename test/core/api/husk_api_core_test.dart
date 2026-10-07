import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/api/husk_api.dart';
import 'package:huskconfig/core/api/husk_exception.dart';
import 'package:huskconfig/core/api/text_result.dart';

import '../../support/fake_adapter.dart';

void main() {
  test('healthz is true for "ok" and never sends the token', () async {
    final f = fakeApi((_) => textBody('ok\n'), token: 'secret');
    expect(await f.api.healthz(), isTrue);
    expect(f.adapter.last.path, '/healthz');
    expect(f.adapter.last.uri.queryParameters.containsKey('token'), isFalse);
  });

  test('authenticated calls carry the token, with special characters intact', () async {
    final f = fakeApi((_) => textBody('pong'), token: 'a b&c');
    expect(await f.api.rpc('ping'), 'pong');
    expect(f.adapter.last.path, '/rpc');
    expect(f.adapter.last.uri.queryParameters, {'cmd': 'ping', 'token': 'a b&c'});
  });

  test('rpc command with URL-special characters reaches the server intact', () async {
    final f = fakeApi((_) => textBody('OK'));
    await f.api.rpc('click 0 Wi-Fi & more?=1');
    expect(f.adapter.last.uri.queryParameters['cmd'], 'click 0 Wi-Fi & more?=1');
  });

  test('no token parameter when the token is null or empty', () async {
    for (final token in [null, '']) {
      final f = fakeApi((_) => textBody('x'), token: token);
      await f.api.dump();
      expect(f.adapter.last.uri.queryParameters.containsKey('token'), isFalse);
    }
  });

  test('dump sends the display id', () async {
    final f = fakeApi((_) => textBody('tree'));
    expect(await f.api.dump(display: 2), 'tree');
    expect(f.adapter.last.uri.queryParameters['d'], '2');
  });

  test('401 maps to UnauthorizedException', () async {
    final f = fakeApi((_) => textBody('unauthorized', status: 401));
    expect(f.api.rpc('ping'), throwsA(isA<UnauthorizedException>()));
  });

  test('non-2xx maps to HttpStatusException using the JSON error message', () async {
    final f = fakeApi((_) => jsonBody('{"error":"no token set; use /token/request"}', status: 409));
    expect(
      f.api.rpc('x'),
      throwsA(isA<HttpStatusException>()
          .having((e) => e.statusCode, 'statusCode', 409)
          .having((e) => e.message, 'message', 'no token set; use /token/request')),
    );
  });

  test('non-2xx plain-text body becomes the message', () async {
    final f = fakeApi((_) => textBody('not found', status: 404));
    expect(f.api.rpc('x'), throwsA(isA<HttpStatusException>().having((e) => e.message, 'message', 'not found')));
  });

  test('connection failure maps to OfflineException naming the address', () async {
    final f = fakeApi((_) => throw const SocketException('Connection refused'));
    expect(
      f.api.healthz(),
      throwsA(isA<OfflineException>().having((e) => e.message, 'message', "Can't reach 10.0.0.5:8090")),
    );
  });

  test('snapshot returns the JPEG bytes', () async {
    final f = fakeApi((_) => bytesBody([0xFF, 0xD8, 0xFF, 0xD9]));
    expect(await f.api.snapshot(), Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]));
    expect(f.adapter.last.path, '/snapshot');
  });

  test('screenshot 503 maps to HttpStatusException(503)', () async {
    final f = fakeApi((_) => textBody('screen sharing off', status: 503));
    expect(f.api.screenshot(), throwsA(isA<HttpStatusException>().having((e) => e.statusCode, 'statusCode', 503)));
  });

  test('uri() attaches the token and keeps IPv6 brackets', () {
    final api = HuskApi(baseUrl: 'http://[fd7a::1]:8090', token: 't');
    expect(api.uri('/screen.mp4').toString(), 'http://[fd7a::1]:8090/screen.mp4?token=t');
    expect(HuskApi(baseUrl: 'http://10.0.0.5:8090').uri('/control').toString(), 'http://10.0.0.5:8090/control');
  });

  test('openMultipart exposes the content type and the raw body stream', () async {
    final f = fakeApi((_) => ResponseBody(
          Stream.fromIterable([Uint8List.fromList([1, 2]), Uint8List.fromList([3])]),
          200,
          headers: {Headers.contentTypeHeader: ['multipart/x-mixed-replace; boundary=rigframe']},
        ));
    final response = await f.api.openMultipart('/stream');
    expect(response.contentType, contains('boundary=rigframe'));
    expect(await response.stream.expand((chunk) => chunk).toList(), [1, 2, 3]);
  });

  test('openMultipart throws HttpStatusException on non-2xx', () async {
    final f = fakeApi((_) => textBody('screen sharing off', status: 503));
    expect(f.api.openMultipart('/screen'), throwsA(isA<HttpStatusException>()));
  });

  group('TextResult', () {
    test('classifies OK / NONE / ERR', () {
      expect(const TextResult('OK\n').isOk, isTrue);
      expect(const TextResult('OK (media=7)').isOk, isTrue);
      expect(const TextResult('NONE no-focus').isNone, isTrue);
      expect(const TextResult('ERR cancelled').isErr, isTrue);
      expect(const TextResult('OKAY').isOk, isFalse);
      expect(const TextResult('  540 1056 ').text, '540 1056');
    });
  });
}

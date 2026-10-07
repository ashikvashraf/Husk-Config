import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:huskconfig/core/api/husk_api.dart';

typedef FakeHandler = FutureOr<ResponseBody> Function(RequestOptions options);

/// Answers every dio request with [handler] and records the requests.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);

  final FakeHandler handler;
  final List<RequestOptions> requests = [];

  RequestOptions get last => requests.last;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody textBody(String body, {int status = 200}) =>
    ResponseBody.fromString(body, status, headers: {Headers.contentTypeHeader: ['text/plain; charset=utf-8']});

ResponseBody jsonBody(String body, {int status = 200}) =>
    ResponseBody.fromString(body, status, headers: {Headers.contentTypeHeader: ['application/json; charset=utf-8']});

ResponseBody bytesBody(List<int> bytes, {int status = 200, String contentType = 'image/jpeg'}) =>
    ResponseBody.fromBytes(bytes, status, headers: {Headers.contentTypeHeader: [contentType]});

({HuskApi api, FakeAdapter adapter}) fakeApi(FakeHandler handler, {String? token, String baseUrl = 'http://10.0.0.5:8090'}) {
  final adapter = FakeAdapter(handler);
  return (api: HuskApi(baseUrl: baseUrl, token: token, adapter: adapter), adapter: adapter);
}

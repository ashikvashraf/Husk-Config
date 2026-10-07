// Shared harness for running the REAL Husk Config app (macOS) against the
// REAL Husk phone. See integration_test/device/00_smoke_test.dart for usage.
//
// Phone safety: every request the app makes through HuskApi goes through a
// [CountingAdapter], which refuses the calls the device checklist forbids
// (token/management endpoints, /set other than `front`, parameterised
// /motion, /ringer, /volume, /rpc other than `ping`). [PhoneProbe] only
// issues read-only GETs plus /key.
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/app.dart';
import 'package:huskconfig/core/api/husk_api.dart';
import 'package:huskconfig/core/providers.dart';
import 'package:huskconfig/core/storage/app_settings.dart';
import 'package:huskconfig/core/storage/server_config.dart';
import 'package:huskconfig/core/storage/server_repository.dart';
import 'package:huskconfig/core/storage/settings_repository.dart';
import 'package:huskconfig/features/servers/api_provider.dart';
import 'package:huskconfig/features/servers/servers_controller.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ------------------------------------------------------------------ Phone

/// `--dart-define=HUSK_PHONE=host:port` (default 192.168.0.106:8090).
const String phoneAddress = String.fromEnvironment('HUSK_PHONE', defaultValue: '192.168.0.106:8090');

final String phoneHost = phoneAddress.substring(0, phoneAddress.lastIndexOf(':'));
final int phonePort = int.parse(phoneAddress.substring(phoneAddress.lastIndexOf(':') + 1));

/// Saved-server fixture for the real phone.
final ServerConfig phoneServer = ServerConfig(
  id: 'phone',
  name: 'Test phone',
  host: phoneHost,
  port: phonePort,
  createdAt: DateTime.utc(2026, 10, 7),
);

/// Saved-server fixture that never answers (TEST-NET-1).
final ServerConfig offlineServer = ServerConfig(
  id: 'offline',
  name: 'Unreachable',
  host: '192.0.2.1',
  port: 8090,
  createdAt: DateTime.utc(2026, 10, 7),
);

// ---------------------------------------------------------------- Binding

bool _mediaKitReady = false;

/// Call first thing in every device test's `main()` (pumpHuskApp calls it
/// too, but the binding must exist before `testWidgets` registers tests).
IntegrationTestWidgetsFlutterBinding initDeviceHarness() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (!_mediaKitReady) {
    MediaKit.ensureInitialized();
    _mediaKitReady = true;
  }
  return binding;
}

/// Key of the RepaintBoundary that wraps the whole app; [snap] renders it.
final GlobalKey appBoundaryKey = GlobalKey(debugLabel: 'huskAppBoundary');

/// Launches the real HuskConfigApp with [servers]/[settings] seeded through
/// the real SharedPreferences repositories, at a fixed [windowSize] with
/// devicePixelRatio 1. Every HuskApi the app builds uses a fork of
/// [adapter] (a fresh [CountingAdapter] if null), which is returned so the
/// test can read request counts. Do NOT also put [countingApiOverride] in
/// [overrides]; pass the adapter here instead.
Future<CountingAdapter> pumpHuskApp(
  WidgetTester tester, {
  List<ServerConfig> servers = const [],
  AppSettings settings = const AppSettings(),
  List<Override> overrides = const [],
  Size windowSize = const Size(1280, 900),
  CountingAdapter? adapter,
}) async {
  initDeviceHarness();

  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = windowSize;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await PrefsServerRepository(prefs).saveAll(servers);
  await PrefsSettingsRepository(prefs).save(settings);

  final counting = adapter ?? CountingAdapter();
  await tester.pumpWidget(RepaintBoundary(
    key: appBoundaryKey,
    child: ProviderScope(
      retry: (_, _) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        countingApiOverride(counting),
        ...overrides,
      ],
      child: const HuskConfigApp(),
    ),
  ));
  // Unmount at the end so polling timers and streams stop before the next test.
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });
  await tester.pump(const Duration(milliseconds: 100));
  return counting;
}

// ---------------------------------------------------------------- Pumping

const Duration _step = Duration(milliseconds: 100);

/// Pumps in 100 ms steps until [finder] finds something; throws a
/// [TestFailure] naming the finder after [timeout] (real time).
Future<void> pumpUntil(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 20)}) async {
  final clock = Stopwatch()..start();
  while (true) {
    await tester.pump(_step);
    if (finder.evaluate().isNotEmpty) return;
    if (clock.elapsed >= timeout) {
      throw TestFailure('pumpUntil timed out after ${timeout.inMilliseconds} ms waiting for: ${finder.describeMatch(Plurality.many)} ($finder)');
    }
  }
}

/// Pumps in 100 ms steps for [duration] (real time). Never pumpAndSettle:
/// the app polls and streams, so it never settles.
Future<void> pumpFor(WidgetTester tester, Duration duration) async {
  final clock = Stopwatch()..start();
  while (clock.elapsed < duration) {
    await tester.pump(_step);
  }
}

// --------------------------------------------------------------- Snapshot

/// Absolute output root for snapshots.
const String deviceChecksDir = '/Users/ashikvashraf/Documents/FlutterProjects/husk_config_app/build/device_checks';

/// Inside the macOS App Sandbox HOME is the app container
/// (~/Library/Containers/com.ava.huskconfig/Data). [snap] writes here when
/// [deviceChecksDir] is not writable. To make [deviceChecksDir] work, link it
/// once from a normal shell:
///   mkdir -p ~/Library/Containers/com.ava.huskconfig/Data/device_checks
///   ln -s ~/Library/Containers/com.ava.huskconfig/Data/device_checks build/device_checks
String get sandboxChecksDir => '${Platform.environment['HOME']}/device_checks';

Future<String> _writePng(String path, Uint8List png) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(png, flush: true);
  return file.path;
}

/// Renders the app's root RepaintBoundary to
/// `build/device_checks/<group>/<name>.png` and returns the path written.
/// Platform textures (video, WebView) come out blank.
Future<String> snap(WidgetTester tester, String group, String name) async {
  await tester.pump();
  final boundary = appBoundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null) throw TestFailure('snap($group/$name): app boundary not mounted (call pumpHuskApp first)');
  final path = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final png = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
      try {
        return await _writePng('$deviceChecksDir/$group/$name.png', png);
      } on FileSystemException catch (e) {
        // The macOS App Sandbox denies paths outside the app container
        // unless build/device_checks is a symlink into it (see
        // [sandboxChecksDir]); fall back to the container itself.
        final fallback = await _writePng('$sandboxChecksDir/$group/$name.png', png);
        print('SNAP fallback (${e.osError?.message ?? e.message}): $fallback');
        return fallback;
      }
    } finally {
      image.dispose();
    }
  });
  print('SNAP $path');
  return path!;
}

// ------------------------------------------------------------------ Check

/// Prints exactly `CHECK <id> <status> <evidence>` (one line).
void check(String id, String status, String evidence) {
  print('CHECK $id $status ${evidence.replaceAll('\n', ' ')}');
}

// ------------------------------------------------------------- PhoneProbe

/// Read-only access to the phone from inside the test process, plus /key.
/// Only paths in [readOnlyPaths] are allowed through [getText]/[getJson].
class PhoneProbe {
  PhoneProbe({String? host, int? port, this.token})
      : host = host ?? phoneHost,
        port = port ?? phonePort;

  final String host;
  final int port;
  final String? token;

  static const Duration timeout = Duration(seconds: 5);

  /// GET endpoints with no side effects. /motion, /volume, /ringer and
  /// /brightness are reads only WITHOUT parameters (enforced).
  static const Set<String> readOnlyPaths = {
    '/healthz', '/info', '/flags', '/display', '/displays', '/battery', '/connectivity',
    '/location', '/mic', '/sensors', '/sensor', '/events', '/find', '/gettext', '/exists',
    '/dump', '/screen.codec', '/motion', '/volume', '/ringer', '/brightness',
  };
  static const Set<String> _readWithoutParams = {'/motion', '/volume', '/ringer', '/brightness'};

  Uri uri(String path, [Map<String, String> query = const {}]) => Uri(
        scheme: 'http',
        host: host,
        port: port,
        path: path,
        queryParameters: {...query, if (token != null && token!.isNotEmpty) 'token': token!},
      );

  /// GET [path] (must be in [readOnlyPaths]) and return the body as text.
  Future<String> getText(String path, [Map<String, String> query = const {}]) {
    if (!readOnlyPaths.contains(path)) {
      throw ArgumentError.value(path, 'path', 'PhoneProbe only allows read-only paths');
    }
    if (_readWithoutParams.contains(path) && query.isNotEmpty) {
      throw ArgumentError.value(query, 'query', 'PhoneProbe: $path may only be read without parameters');
    }
    return _get(uri(path, query));
  }

  /// GET [path] and decode JSON.
  Future<dynamic> getJson(String path, [Map<String, String> query = const {}]) async =>
      jsonDecode(await getText(path, query));

  /// Presses a navigation key: back | home | recents | notifications | enter.
  Future<String> key(String k) => _get(uri('/key', {'k': k}));

  /// Presses Home.
  Future<String> home() => key('home');

  /// Center of the first node matching [regex], or null for NONE.
  Future<({int x, int y})?> find(String regex) async {
    final text = (await getText('/find', {'match': regex})).trim();
    final m = RegExp(r'^(-?\d+)\s+(-?\d+)').firstMatch(text);
    if (m == null) return null;
    return (x: int.parse(m.group(1)!), y: int.parse(m.group(2)!));
  }

  Future<String> _get(Uri u) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(u).timeout(timeout);
      final response = await request.close().timeout(timeout);
      final body = await response.transform(utf8.decoder).join().timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('HTTP ${response.statusCode} for ${u.path}: $body', uri: u);
      }
      return body;
    } finally {
      client.close(force: true);
    }
  }
}

// --------------------------------------------------------- CountingAdapter

/// A dio adapter over the real [IOHttpClientAdapter] that counts requests
/// per URL path ([counts]) and logs every URI ([log]). It refuses the calls
/// the device checklist forbids (recorded in [blocked]) with a DioException.
///
/// [fork] returns an adapter with its own connection pool but shared
/// counters; [countingApiOverride] gives every HuskApi its own fork so one
/// HuskApi closing does not kill another's connections.
class CountingAdapter implements HttpClientAdapter {
  CountingAdapter() : this._(_CountState());

  CountingAdapter._(this._state);

  final _CountState _state;
  IOHttpClientAdapter _inner = IOHttpClientAdapter();

  /// Requests per path, e.g. `counts['/info']`.
  Map<String, int> get counts => _state.counts;

  /// Every request URI in order (allowed and blocked).
  List<Uri> get log => _state.log;

  /// Requests refused by the safety guard.
  List<Uri> get blocked => _state.blocked;

  int count(String path) => counts[path] ?? 0;

  void reset() {
    counts.clear();
    log.clear();
    blocked.clear();
  }

  CountingAdapter fork() => CountingAdapter._(_state);

  /// Null when [u] is allowed, otherwise the reason it is forbidden.
  static String? forbiddenReason(Uri u) {
    final path = u.path;
    final params = {...u.queryParameters}..remove('token');
    const never = {'/token/request', '/token/set', '/devoptions', '/wd', '/pair'};
    if (never.contains(path)) return '$path is never allowed';
    if ({'/motion', '/ringer', '/volume'}.contains(path) && params.isNotEmpty) return '$path with parameters';
    if (path == '/set' && (params.keys.toSet().difference({'front'}).isNotEmpty)) return '/set other than front';
    if (path == '/rpc' && params['cmd']?.trim() != 'ping') return '/rpc other than ping';
    if (path == '/vibrate' && (int.tryParse(params['ms'] ?? '') ?? 0) > 500) return '/vibrate over 500 ms';
    return null;
  }

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) {
    final u = options.uri;
    _state.log.add(u);
    _state.counts.update(u.path, (n) => n + 1, ifAbsent: () => 1);
    final reason = forbiddenReason(u);
    if (reason != null) {
      _state.blocked.add(u);
      print('HARNESS BLOCKED $u ($reason)');
      throw DioException(requestOptions: options, error: StateError('Device harness blocked $reason'), message: 'Blocked by device harness: $reason');
    }
    return _inner.fetch(options, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) {
    _inner.close(force: force);
    _inner = IOHttpClientAdapter();
  }
}

class _CountState {
  final Map<String, int> counts = {};
  final List<Uri> log = [];
  final List<Uri> blocked = [];
}

/// Overrides [apiProvider] so every server's HuskApi is built from its
/// saved config with a fork of [adapter] (real network, counted, guarded).
Override countingApiOverride(CountingAdapter adapter) => apiProvider.overrideWith((ref, serverId) {
      final connection = ref.watch(serversProvider.select((servers) {
        final server = servers.where((s) => s.id == serverId).firstOrNull;
        return server == null ? null : (baseUrl: server.baseUrl, token: server.token);
      }));
      if (connection == null) throw StateError('Unknown server $serverId');
      final api = HuskApi(baseUrl: connection.baseUrl, token: connection.token, adapter: adapter.fork());
      ref.onDispose(api.close);
      return api;
    });

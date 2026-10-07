// ignore_for_file: file_names, avoid_print
//
// Device checklist: Screen H.264 mode and Web control (S13, T20b, T20c, S14, T20e).
// Runs on the REAL macOS app against the REAL phone:
//   flutter test integration_test/device/06_h264_web_test.dart -d macos
//
// Phone interaction beyond PhoneProbe (read-only + /key) is limited to the
// allowed state-changing calls: /wake, /launch of android.settings.SETTINGS,
// /scroll (to keep frames flowing on the otherwise static screen) and the
// /tap the app itself sends in T20b. Every test ends with Home.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/storage/app_settings.dart';
import 'package:huskconfig/features/screen/coordinate_mapper.dart';
import 'package:huskconfig/features/screen/gesture_layer.dart';
import 'package:huskconfig/features/screen/h264_view.dart';
import 'package:huskconfig/features/screen/web_control_view.dart';
import 'package:huskconfig/shared/widgets/mjpeg_view.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'support/device_harness.dart';

const String _group = '06_h264_web_test';

final PhoneProbe _probe = PhoneProbe();

/// The only phone commands this file sends itself (besides PhoneProbe's
/// read-only GETs and /key). Anything else throws.
Future<String> _phone(String path, [Map<String, String> query = const {}]) async {
  const allowed = {'/wake', '/launch', '/scroll'};
  if (!allowed.contains(path)) throw ArgumentError.value(path, 'path', 'not an allowed phone command');
  if (path == '/launch' && query['action'] != 'android.settings.SETTINGS') {
    throw ArgumentError.value(query, 'query', 'only android.settings.SETTINGS may be launched');
  }
  if (path == '/scroll' && !(query['d'] == '0' && (query['dir'] == 'fwd' || query['dir'] == 'back'))) {
    throw ArgumentError.value(query, 'query', 'only /scroll?d=0&dir=fwd|back');
  }
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final request = await client.getUrl(_probe.uri(path, query)).timeout(const Duration(seconds: 5));
    final response = await request.close().timeout(const Duration(seconds: 8));
    return await response.transform(utf8.decoder).join().timeout(const Duration(seconds: 8));
  } finally {
    client.close(force: true);
  }
}

/// Wakes the phone and opens the Settings list so the screen has content that
/// can be scrolled to produce frames. Only opens/scrolls, never taps.
Future<void> _prepPhone(WidgetTester tester) async {
  await tester.runAsync(() async {
    await _phone('/wake');
    await Future<void>.delayed(const Duration(milliseconds: 800));
    await _phone('/launch', {'action': 'android.settings.SETTINGS'});
    await Future<void>.delayed(const Duration(seconds: 2));
  });
}

Future<void> _phoneHome(WidgetTester tester) async {
  try {
    await tester.runAsync(() => _probe.home().timeout(const Duration(seconds: 6)));
  } catch (e) {
    print('NOTE could not press Home: $e');
  }
}

bool _scrollFwd = true;

/// One /scroll nudge (alternating direction) to keep the stream producing frames.
Future<void> _nudge(WidgetTester tester) async {
  _scrollFwd = !_scrollFwd;
  try {
    await tester.runAsync(() => _phone('/scroll', {'d': '0', 'dir': _scrollFwd ? 'fwd' : 'back'}));
  } catch (_) {}
}

/// Pumps [duration] of real time in 100 ms steps, nudging the phone every 3 s.
/// Stops early (returning the elapsed time) when [stopWhen] becomes true.
Future<Duration> _pumpNudging(WidgetTester tester, Duration duration, {bool Function()? stopWhen}) async {
  final clock = Stopwatch()..start();
  var lastNudge = Duration.zero;
  while (clock.elapsed < duration) {
    await tester.pump(const Duration(milliseconds: 100));
    if (stopWhen != null && stopWhen()) break;
    if (clock.elapsed - lastNudge >= const Duration(seconds: 3)) {
      lastNudge = clock.elapsed;
      await _nudge(tester);
    }
  }
  return clock.elapsed;
}

Future<void> _pumpWhile(WidgetTester tester, bool Function() condition, Duration timeout) async {
  final clock = Stopwatch()..start();
  while (condition() && clock.elapsed < timeout) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Dashboard -> phone card -> Screen tab (wide layout: NavigationRail).
Future<void> _openScreenTab(WidgetTester tester) async {
  await pumpUntil(tester, find.text('Test phone'));
  await tester.tap(find.text('Test phone'));
  final rail = find.descendant(of: find.byType(NavigationRail), matching: find.text('Screen'));
  await pumpUntil(tester, rail);
  await tester.tap(rail);
  await pumpUntil(tester, find.byType(DropdownButton<int>));
}

Set<ScreenMode> _selectedMode(WidgetTester tester) =>
    tester.widget<SegmentedButton<ScreenMode>>(find.byType(SegmentedButton<ScreenMode>)).selected;

Finder _modeSegment(String label) =>
    find.descendant(of: find.byType(SegmentedButton<ScreenMode>), matching: find.text(label));

Finder get _fallbackSnack => find.textContaining('using MJPEG');

/// Mounts [child] alone (no app, no phone traffic) inside the snapshot boundary.
Future<void> _pumpStandalone(WidgetTester tester, Widget child) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1280, 900);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(RepaintBoundary(
    key: appBoundaryKey,
    child: MaterialApp(home: Scaffold(body: child)),
  ));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });
  await tester.pump(const Duration(milliseconds: 100));
}

/// Runs [body]; if it throws, prints a FAIL line for [id] before rethrowing.
Future<void> _guard(String id, Future<void> Function() body) async {
  try {
    await body();
  } catch (e) {
    check(id, 'FAIL', 'test threw: ${e.toString().split('\n').first}');
    rethrow;
  }
}

String _fmt(Duration d) => (d.inMilliseconds / 1000).toStringAsFixed(2);

void main() {
  initDeviceHarness();

  tearDown(() async {
    try {
      await _probe.home().timeout(const Duration(seconds: 6));
    } catch (e) {
      print('NOTE tearDown Home failed: $e');
    }
  });

  // ------------------------------------------------------------------ S13
  testWidgets('S13 H.264 mode is offered on macOS and plays for 30 s without the fallback snackbar', (tester) async {
    await _guard('S13', () async {
      await _prepPhone(tester);
      final adapter = await pumpHuskApp(tester, servers: [phoneServer]);
      await _openScreenTab(tester);
      await pumpUntil(tester, find.byType(SegmentedButton<ScreenMode>));

      final offered = _modeSegment('H.264').evaluate().isNotEmpty;
      if (!offered) {
        await snap(tester, _group, 'S13-1');
        check('S13', 'FAIL', 'H.264 segment is not offered on macOS (segments: MJPEG/Web control only)');
        fail('H.264 not offered');
      }
      final startedIn = _selectedMode(tester);
      await tester.tap(_modeSegment('H.264'));
      await pumpUntil(tester, find.byType(H264View));
      final selected = _selectedMode(tester);
      expect(selected, {ScreenMode.h264});
      await snap(tester, _group, 'S13-1');

      var snackSeenAt = -1.0;
      final elapsed = await _pumpNudging(
        tester,
        const Duration(seconds: 30),
        stopWhen: () {
          final seen = _fallbackSnack.evaluate().isNotEmpty || find.byType(H264View).evaluate().isEmpty;
          if (seen) snackSeenAt = 0;
          return seen;
        },
      );
      final snack = _fallbackSnack.evaluate().isNotEmpty;
      final stillH264 = find.byType(H264View).evaluate().isNotEmpty;
      final segmentStillThere = _modeSegment('H.264').evaluate().isNotEmpty;
      await snap(tester, _group, 'S13-2');
      final snackText = snack ? (tester.widget<Text>(_fallbackSnack.first).data ?? '') : '';

      if (snackSeenAt >= 0 || snack || !stillH264 || !segmentStillThere) {
        check('S13', 'FAIL',
            'fallback after ${_fmt(elapsed)} s snack="$snackText" H264View=$stillH264 segment=$segmentStillThere');
      } else {
        check('S13', 'PASS',
            'H.264 segment offered (started in ${startedIn.first.name}), selected, H264View alive for ${_fmt(elapsed)} s with no "using MJPEG" snackbar; '
            'blocked=${adapter.blocked.length}; texture is blank in PNG (platform texture), so playback itself is judged by no onFailed');
      }
      expect(adapter.blocked, isEmpty);
      expect(snack, isFalse, reason: 'fallback snackbar: $snackText');
      expect(stillH264, isTrue);
    });
  });

  testWidgets('S13 spike: media_kit Player on /screen.mp4 reports size, advancing position and buffer-position samples', (tester) async {
    await _guard('S13-spike', () async {
      await _prepPhone(tester);
      final url = 'http://$phoneAddress/screen.mp4';
      const seconds = 20;
      final samples = <({double t, double pos, double buf, double diff})>[];
      final errors = <String>[];
      int? w, h;
      double wait = -1;

      // Not inside tester.runAsync: VideoController/Player.open wait for the
      // native texture, which needs frames, so the body runs as a plain future
      // (real time under the live integration binding) while we keep pumping.
      Future<void> spike() async {
        final player = Player();
        // media_kit starts every Player with --vid=no; only attaching a
        // VideoController (as the app's H264View does) enables video decoding.
        // No Video widget is mounted, so the player stays headless.
        // ignore: unused_local_variable
        final controller = VideoController(player);
        final subs = <StreamSubscription<dynamic>>[];
        try {
          final native = player.platform;
          if (native is NativePlayer) {
            await native.setProperty('profile', 'low-latency');
            await native.setProperty('cache', 'no');
            await native.setProperty('untimed', 'yes');
          }
          await player.setVolume(0);
          subs.add(player.stream.error.listen((e) => errors.add(e.replaceAll(url, '/screen.mp4'))));
          subs.add(player.stream.videoParams.listen((p) {
            final pw = p.dw ?? p.w, ph = p.dh ?? p.h;
            if (pw != null && ph != null && pw > 0 && ph > 0) {
              w = pw;
              h = ph;
            }
          }));
          await player.open(Media(url));

          // Wait for the first video size (up to 15 s).
          final waitClock = Stopwatch()..start();
          while (waitClock.elapsed < const Duration(seconds: 15) && !((w ?? player.state.width ?? 0) > 0 && (h ?? player.state.height ?? 0) > 0)) {
            if (errors.isNotEmpty) break;
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          wait = waitClock.elapsed.inMilliseconds / 1000;
          if ((player.state.width ?? 0) > 0) w = player.state.width;
          if ((player.state.height ?? 0) > 0) h = player.state.height;

          // Sample once per second for 20 s, nudging the phone every 2 s so frames keep coming.
          final clock = Stopwatch()..start();
          for (var i = 1; i <= seconds; i++) {
            final target = Duration(seconds: i);
            final remaining = target - clock.elapsed;
            if (remaining > Duration.zero) await Future<void>.delayed(remaining);
            if (i % 2 == 0) {
              _scrollFwd = !_scrollFwd;
              // Not awaited, so a slow /scroll reply does not delay the 1 s sampling.
              unawaited(_phone('/scroll', {'d': '0', 'dir': _scrollFwd ? 'fwd' : 'back'}).then((_) {}, onError: (_) {}));
            }
            final st = player.state;
            final pos = st.position.inMilliseconds / 1000;
            final buf = st.buffer.inMilliseconds / 1000;
            samples.add((t: clock.elapsed.inMilliseconds / 1000, pos: pos, buf: buf, diff: buf - pos));
            print('SPIKE t=${(clock.elapsed.inMilliseconds / 1000).toStringAsFixed(2)} pos=${pos.toStringAsFixed(3)} '
                'buffer=${buf.toStringAsFixed(3)} buffer-position=${(buf - pos).toStringAsFixed(3)} '
                'size=${st.width}x${st.height} playing=${st.playing}');
          }
        } finally {
          for (final s in subs) {
            await s.cancel();
          }
          await player.dispose();
        }
      }

      await _pumpStandalone(tester, const Center(child: Text('S13 spike: headless player running')));
      var spikeDone = false;
      Object? spikeError;
      StackTrace? spikeStack;
      spike().then((_) => spikeDone = true, onError: (Object e, StackTrace st) {
        spikeError = e;
        spikeStack = st;
        spikeDone = true;
      });
      final spikeClock = Stopwatch()..start();
      while (!spikeDone && spikeClock.elapsed < const Duration(seconds: 90)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      if (spikeError != null) Error.throwWithStackTrace(spikeError!, spikeStack!);
      if (!spikeDone) fail('spike did not finish within 90 s (samples so far: ${samples.length})');
      final sizeOk = (w ?? 0) > 0 && (h ?? 0) > 0;
      final advanced = samples.length >= 2 ? samples.last.pos - samples.first.pos : 0.0;
      final posOk = advanced >= seconds * 0.5; // clearly moving over 20 s
      final diffs = [for (final s in samples) s.diff];
      final summary = diffs.isEmpty
          ? 'no samples'
          : 'buffer-position min=${diffs.reduce((a, b) => a < b ? a : b).toStringAsFixed(3)} '
              'max=${diffs.reduce((a, b) => a > b ? a : b).toStringAsFixed(3)} '
              'mean=${(diffs.reduce((a, b) => a + b) / diffs.length).toStringAsFixed(3)}';
      final evidence = 'size=${w}x$h (first size after ${wait.toStringAsFixed(1)} s) '
          'position ${samples.isEmpty ? '-' : samples.first.pos.toStringAsFixed(2)} -> ${samples.isEmpty ? '-' : samples.last.pos.toStringAsFixed(2)} '
          '(+${advanced.toStringAsFixed(2)} s over ${samples.isEmpty ? 0 : samples.last.t.toStringAsFixed(1)} s wall, ${samples.length} samples) $summary '
          'errors=${errors.isEmpty ? 'none' : errors.join(' | ')}';
      // No app is mounted for the spike; snapshot a plain summary of the samples.
      await _pumpStandalone(
        tester,
        SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Text(
            'S13 spike (headless media_kit Player, profile=low-latency cache=no untimed=yes)\n$evidence\n\n'
            '${samples.map((s) => 't=${s.t.toStringAsFixed(2)} pos=${s.pos.toStringAsFixed(3)} buffer=${s.buf.toStringAsFixed(3)} buffer-position=${s.diff.toStringAsFixed(3)}').join('\n')}',
            style: const TextStyle(fontSize: 13, fontFamily: 'Menlo'),
          ),
        ),
      );
      await snap(tester, _group, 'S13-spike-1');
      check('S13-spike', sizeOk && posOk && errors.isEmpty ? 'PASS' : 'FAIL', evidence);
      expect(sizeOk, isTrue, reason: 'no video size');
      expect(posOk, isTrue, reason: 'position did not advance: +$advanced s');
    });
  });

  // ----------------------------------------------------------------- T20b
  testWidgets('T20b taps over the H.264 view reach the phone at the right coordinates', (tester) async {
    await _guard('T20b', () async {
      final display = await tester.runAsync(() => _probe.getJson('/display')) as Map<String, dynamic>;
      final dispW = (display['width'] as num).toInt(), dispH = (display['height'] as num).toInt();
      // /info screen = the phone's real full-screen pixel size, the space /find
      // reports in and /tap acts in (it includes the nav bar; /display does not).
      final info = await tester.runAsync(() => _probe.getJson('/info')) as Map<String, dynamic>;
      final scr = info['screen'] as Map<String, dynamic>;
      final realW = (scr['width'] as num).toInt(), realH = (scr['height'] as num).toInt();
      await _prepPhone(tester);
      // Settings reopens at its last scroll position (earlier tests scroll it),
      // which can leave the search affordance above the screen; scroll back to the top.
      await tester.runAsync(() async {
        for (var i = 0; i < 5; i++) {
          try {
            await _phone('/scroll', {'d': '0', 'dir': 'back'});
          } catch (_) {}
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        await Future<void>.delayed(const Duration(seconds: 1));
      });

      // Target: the Settings search affordance (opens search only; harmless).
      // Only on-screen targets count (a node can be reported at negative y when off-screen).
      ({int x, int y})? target;
      String how = '';
      final rejected = <String>[];
      for (final re in [r'(?i)^search', r'(?i)search']) {
        final t = await tester.runAsync<({int x, int y})?>(() => _probe.find(re));
        if (t == null) continue;
        if (t.x <= 0 || t.y <= 0 || t.x >= realW || t.y >= realH) {
          rejected.add('find($re)=${t.x},${t.y} off-screen');
          continue;
        }
        target = t;
        how = 'find($re)';
        break;
      }
      if (rejected.isNotEmpty) print('NOTE T20b rejected targets: ${rejected.join('; ')}');
      if (target == null) {
        // Fallback: centre of the screen (opens at most a Settings sub-page; Back + Home restore).
        target = (x: realW ~/ 2, y: realH ~/ 2);
        how = 'fallback centre';
      }
      final before = await tester.runAsync(() async {
        try {
          return await _probe.getText('/dump');
        } catch (_) {
          return null;
        }
      });

      final adapter = await pumpHuskApp(
        tester,
        servers: [phoneServer],
        settings: const AppSettings(defaultScreenMode: ScreenMode.h264),
      );
      await _openScreenTab(tester);
      await pumpUntil(tester, find.byType(H264View), timeout: const Duration(seconds: 30));
      await pumpUntil(tester, find.byType(GestureLayer));
      await pumpFor(tester, const Duration(seconds: 5)); // let the first frame/size arrive
      expect(_selectedMode(tester), {ScreenMode.h264});

      final layerFinder = find.byType(GestureLayer);
      final layer = tester.widget<GestureLayer>(layerFinder);
      final rect = tester.getRect(layerFinder);
      final deviceSize = layer.deviceSize;
      // Where the app's own mapper would put the target (reported only: using
      // it to aim the tap would make the check agree with itself by construction).
      final appContent = CoordinateMapper(viewSize: rect.size, deviceSize: deviceSize).contentRect.shift(rect.topLeft);

      // Where the phone image is actually drawn: the video texture inside the
      // Video widget (FittedBox contain of the decoded frame), in window coordinates.
      final textureFinder = find.descendant(of: find.byType(Video), matching: find.byType(Texture));
      await pumpUntil(tester, textureFinder, timeout: const Duration(seconds: 20));
      final drawn = tester.getRect(textureFinder);
      final frameRect = tester.widget<Video>(find.byType(Video)).controller.rect.value;
      final drawnAspect = drawn.width / drawn.height, realAspect = realW / realH;
      final aspectOk = (drawnAspect - realAspect).abs() / realAspect < 0.01;
      // The aimed point: the target's position on the visible phone image.
      final global = Offset(
        drawn.left + target.x / realW * drawn.width,
        drawn.top + target.y / realH * drawn.height,
      );
      final geometry = 'video drawn at ${_r(drawn)} (frame ${frameRect?.width.toInt()}x${frameRect?.height.toInt()}, aspect ${drawnAspect.toStringAsFixed(4)} vs /info ${realW}x$realH ${realAspect.toStringAsFixed(4)}); '
          'app tap-mapping rect ${_r(appContent)} for deviceSize ${deviceSize.width.toInt()}x${deviceSize.height.toInt()}';
      print('NOTE T20b geometry: $geometry; aiming at window $global');
      final lockedBefore = before != null && _looksLocked(before);
      final sizeMatches = (deviceSize.width.toInt() == dispW && deviceSize.height.toInt() == dispH) ||
          (deviceSize.width.toInt() == dispH && deviceSize.height.toInt() == dispW);

      adapter.reset();
      await snap(tester, _group, 'T20b-1');
      await tester.tapAt(global);
      await tester.pump(const Duration(milliseconds: 100));
      final clock = Stopwatch()..start();
      while (adapter.log.where((u) => u.path == '/tap').isEmpty && clock.elapsed < const Duration(seconds: 8)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final taps = adapter.log.where((u) => u.path == '/tap').toList();
      await pumpFor(tester, const Duration(milliseconds: 1500));
      final after = await tester.runAsync(() async {
        try {
          return await _probe.getText('/dump');
        } catch (_) {
          return null;
        }
      });
      await snap(tester, _group, 'T20b-2');

      // Restore: back out of whatever the tap opened, then Home.
      await tester.runAsync(() async {
        try {
          await _probe.key('back');
          await Future<void>.delayed(const Duration(milliseconds: 500));
        } catch (_) {}
      });
      await _phoneHome(tester);

      if (taps.isEmpty) {
        check('T20b', 'FAIL', 'no /tap request reached the phone after tapping the H.264 view at $global (target $how ${target.x},${target.y})');
        fail('no /tap sent');
      }
      final q = taps.first.queryParameters;
      final sx = int.tryParse(q['x'] ?? ''), sy = int.tryParse(q['y'] ?? '');
      final dx = sx == null ? 999 : (sx - target.x).abs();
      final dy = sy == null ? 999 : (sy - target.y).abs();
      final coordsOk = dx <= 3 && dy <= 3 && (q['d'] ?? '0') == '0' && taps.length == 1;
      final dumpChanged = before != null && after != null ? before != after : null;
      final ev = 'target $how=${target.x},${target.y} in /info ${realW}x$realH space, aimed at its spot on the visible video; '
          'app sent /tap x=$sx y=$sy d=${q['d']} (count ${taps.length}, off by $dx,$dy px; tolerance 3); '
          'layer deviceSize ${deviceSize.width.toInt()}x${deviceSize.height.toInt()} ${sizeMatches ? 'matches' : 'DIFFERS from'} /display ${dispW}x$dispH; '
          'drawn video aspect matches /info=$aspectOk; $geometry; phone locked before tap=$lockedBefore; phone UI changed after tap: $dumpChanged';
      if (!coordsOk) {
        check('T20b', 'FAIL', 'tap landed at the wrong coordinates: $ev');
      } else if (lockedBefore) {
        check('T20b', 'BLOCKED', 'coordinates correct but the phone is on its secure lock screen, so the phone-side effect cannot be shown (a human must unlock it): $ev');
      } else if (dumpChanged == null) {
        check('T20b', 'BLOCKED', 'coordinates correct but phone-side effect could not be read (/dump unavailable): $ev');
      } else if (!dumpChanged) {
        check('T20b', 'FAIL', 'coordinates sent correctly but the phone UI did not react: $ev');
      } else {
        check('T20b', 'PASS', ev);
      }
      expect(taps.length, 1);
      expect(coordsOk, isTrue, reason: ev);
      expect(adapter.blocked, isEmpty);
    });
  });

  // ----------------------------------------------------------------- T20c
  testWidgets('T20c H.264 absent on display != 0 (picker only has display 0) and a forced player error falls back', (tester) async {
    await _guard('T20c', () async {
      // Part 1: what the display picker offers on the real phone.
      final displaysText = (await tester.runAsync(() => _probe.getText('/displays')))!.trim();
      final adapter = await pumpHuskApp(tester, servers: [phoneServer]);
      await _openScreenTab(tester);
      await pumpUntil(tester, find.byType(SegmentedButton<ScreenMode>));
      final h264OnDisplay0 = _modeSegment('H.264').evaluate().isNotEmpty;
      await tester.tap(find.byType(DropdownButton<int>));
      await pumpFor(tester, const Duration(milliseconds: 500));
      final labels = <String>{};
      for (final item in tester.widgetList<DropdownMenuItem<int>>(find.byType(DropdownMenuItem<int>))) {
        final child = item.child;
        if (child is Text && child.data != null) labels.add(child.data!);
      }
      await snap(tester, _group, 'T20c-1');
      // Close the menu by re-picking display 0 (no change of value).
      await tester.tap(find.text('Phone (display 0)').last);
      await pumpFor(tester, const Duration(milliseconds: 500));
      final onlyDisplay0 = labels.length == 1 && labels.contains('Phone (display 0)');
      // The phone answers /displays as one comma-separated line (e.g. "0:0,2:0"),
      // so read the ids independently of the app's parser.
      final phoneIds = [
        for (final part in displaysText.split(RegExp(r'[,\n]')).map((p) => p.trim()).where((p) => p.isNotEmpty))
          if (int.tryParse(part.split(':').first.trim()) case final int id) id,
      ];
      final missing = phoneIds.where((id) => id != 0 && !labels.contains('Display $id')).toList();
      final displaysEvidence = 'picker items=${labels.toList()} /displays="${displaysText.replaceAll('\n', ' | ')}" (display ids reported by the phone: $phoneIds'
          '${missing.isEmpty ? '' : '; NOT offered by the picker: $missing'}) H.264 segment on display 0=$h264OnDisplay0';
      expect(adapter.blocked, isEmpty);

      // Part 2: force a player error safely with a standalone H264View on a closed local port.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 300));
      final failures = <String>[];
      await _pumpStandalone(
        tester,
        H264View(
          uri: Uri.parse('http://127.0.0.1:1/screen.mp4'),
          catchUpSeek: false,
          onFailed: failures.add,
        ),
      );
      await _pumpWhile(tester, () => failures.isEmpty, const Duration(seconds: 25));
      await snap(tester, _group, 'T20c-2');
      final fallbackOk = failures.isNotEmpty;
      check('T20c-fallback', fallbackOk ? 'PASS' : 'FAIL',
          fallbackOk
              ? 'standalone H264View on closed port 127.0.0.1:1 called onFailed ${failures.length}x with "${failures.first}" '
                  '(the Screen tab turns this call into the "using MJPEG" snackbar; its own wiring is covered by unit tests, not re-driven here)'
              : 'onFailed was NOT called within 25 s for a closed port');
      check('T20c', fallbackOk ? 'BLOCKED' : 'FAIL',
          'display != 0 part BLOCKED: the picker offers no display other than 0, so H.264 absence on another display cannot be driven ($displaysEvidence; '
          'onlyDisplay0=$onlyDisplay0); forced-error fallback: ${fallbackOk ? 'PASS (T20c-fallback)' : 'FAIL (T20c-fallback)'}');
      expect(fallbackOk, isTrue);
      expect(failures.length, 1, reason: 'onFailed must fire once');
    });
  });

  // ------------------------------------------------------------------ S14
  testWidgets('S14 Web control renders and /control and /controlhw load in a WebView', (tester) async {
    await _guard('S14', () async {
      // Part 1: the app's own WebControlView.
      final adapter = await pumpHuskApp(
        tester,
        servers: [phoneServer],
        settings: const AppSettings(defaultScreenMode: ScreenMode.webview),
      );
      await _openScreenTab(tester);
      await pumpUntil(tester, find.byType(WebControlView), timeout: const Duration(seconds: 30));
      await pumpUntil(tester, find.byType(InAppWebView));
      await pumpUntil(tester, find.text('MJPEG page'));
      final viewOk = find.byType(WebControlView).evaluate().isNotEmpty && find.byType(InAppWebView).evaluate().isNotEmpty;
      await pumpFor(tester, const Duration(seconds: 3));
      await snap(tester, _group, 'S14-1');
      // Toggle to the H.264 page inside the app view, then back, to show both segments are drivable.
      await tester.tap(find.text('H.264 page'));
      await pumpFor(tester, const Duration(seconds: 3));
      final hwSelected = tester.widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>)).selected;
      await snap(tester, _group, 'S14-2');
      expect(hwSelected, {true});
      expect(adapter.blocked, isEmpty);

      // Unmount the app view before opening the standalone pages so only one stream is live.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 500));

      // Part 2: standalone InAppWebView per page, checked through onLoadStop + evaluateJavascript.
      final results = <String, String>{};
      var allOk = true;
      for (final path in ['/control', '/controlhw']) {
        final url = _probe.uri(path).toString();
        InAppWebViewController? ctl;
        var stopped = false;
        String? stoppedUrl;
        int? httpError;
        String? loadError;
        await _pumpStandalone(
          tester,
          InAppWebView(
            key: ValueKey(path),
            initialUrlRequest: URLRequest(url: WebUri(url)),
            initialSettings: InAppWebViewSettings(mediaPlaybackRequiresUserGesture: false, allowsInlineMediaPlayback: true),
            onWebViewCreated: (c) => ctl = c,
            onLoadStop: (c, u) {
              stopped = true;
              stoppedUrl = u?.toString();
            },
            onReceivedHttpError: (c, request, response) {
              if (request.isForMainFrame != false) httpError = response.statusCode;
            },
            onReceivedError: (c, request, error) {
              if (request.isForMainFrame != false) loadError = error.description;
            },
          ),
        );
        await _pumpWhile(tester, () => !stopped && httpError == null && loadError == null, const Duration(seconds: 25));

        Map<String, dynamic>? info;
        final jsClock = Stopwatch()..start();
        while (stopped && ctl != null && jsClock.elapsed < const Duration(seconds: 12)) {
          final raw = await tester.runAsync(() => ctl!.evaluateJavascript(source: '''
            JSON.stringify({
              status: ((performance.getEntriesByType('navigation')[0] || {}).responseStatus) || null,
              ready: document.readyState,
              imgs: document.getElementsByTagName('img').length,
              videos: document.getElementsByTagName('video').length,
              canvases: document.getElementsByTagName('canvas').length,
              title: document.title,
              bodyLen: document.body ? document.body.innerHTML.length : 0
            })'''));
          info = _decodeJs(raw);
          if (info != null && ((info['imgs'] as num? ?? 0) + (info['videos'] as num? ?? 0)) > 0) break;
          await pumpFor(tester, const Duration(milliseconds: 500));
        }
        await pumpFor(tester, const Duration(seconds: 2));
        await snap(tester, _group, 'S14-3${path == '/control' ? 'a' : 'b'}');

        final media = info == null ? 0 : ((info['imgs'] as num? ?? 0) + (info['videos'] as num? ?? 0)).toInt();
        final status = info?['status'];
        final ok = stopped && httpError == null && loadError == null && media > 0 && (status == null || status == 200);
        allOk &= ok;
        results[path] = '${ok ? 'ok' : 'BAD'}: onLoadStop=$stopped url=$stoppedUrl httpError=$httpError loadError=$loadError '
            'status=${status ?? 'n/a (no HTTP error callback fired)'} imgs=${info?['imgs']} videos=${info?['videos']} canvas=${info?['canvases']} '
            'title="${info?['title']}" bodyLen=${info?['bodyLen']}';
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 500));
      }

      final ev = 'WebControlView+InAppWebView rendered in app=$viewOk, H.264 page segment selectable=${hwSelected.contains(true)}; '
          '/control -> ${results['/control']}; /controlhw -> ${results['/controlhw']}; '
          'page-internal clicks not driven (BLOCKED)';
      check('S14', viewOk && allOk ? 'PASS' : 'FAIL', ev);
      check('S14-click', 'BLOCKED', 'page-internal clicks inside /control are not driven by the test');
      expect(viewOk, isTrue);
      expect(allOk, isTrue, reason: ev);
    });
  });

  // ----------------------------------------------------------------- T20e
  testWidgets('T20e Settings default mode Web control makes a freshly opened Screen tab start in Web control', (tester) async {
    await _guard('T20e', () async {
      final adapter = await pumpHuskApp(tester, servers: [phoneServer]); // default MJPEG
      await pumpUntil(tester, find.text('Test phone'));
      await tester.tap(find.byTooltip('Settings'));
      await pumpUntil(tester, find.text('Web control'));
      await snap(tester, _group, 'T20e-1');
      await tester.tap(find.text('Web control'));
      await pumpFor(tester, const Duration(milliseconds: 500));
      final settingsSelected = tester.widget<SegmentedButton<ScreenMode>>(find.byType(SegmentedButton<ScreenMode>)).selected;
      expect(settingsSelected, {ScreenMode.webview});
      await snap(tester, _group, 'T20e-2');
      await tester.pageBack();
      await pumpUntil(tester, find.text('Test phone'));

      await _openScreenTab(tester);
      await pumpUntil(tester, find.byType(SegmentedButton<ScreenMode>));
      await pumpUntil(tester, find.byType(WebControlView), timeout: const Duration(seconds: 30));
      final selected = _selectedMode(tester);
      final hasWeb = find.byType(WebControlView).evaluate().isNotEmpty;
      final hasMjpeg = find.byType(MjpegView).evaluate().isNotEmpty;
      final hasH264 = find.byType(H264View).evaluate().isNotEmpty;
      await pumpFor(tester, const Duration(seconds: 2));
      await snap(tester, _group, 'T20e-3');
      final ok = selected.length == 1 && selected.first == ScreenMode.webview && hasWeb && !hasMjpeg && !hasH264;
      check('T20e', ok ? 'PASS' : 'FAIL',
          'after setting default to Web control (Settings segment selected=${settingsSelected.first.name}) the Screen tab opened with selected=${selected.map((m) => m.name).toList()} '
          'WebControlView=$hasWeb MjpegView=$hasMjpeg H264View=$hasH264');
      expect(ok, isTrue);
      expect(adapter.blocked, isEmpty);
    });
  });
}

String _r(Rect r) => '(${r.left.toStringAsFixed(1)},${r.top.toStringAsFixed(1)} ${r.width.toStringAsFixed(1)}x${r.height.toStringAsFixed(1)})';

/// True when a /dump looks like the Samsung lock screen (keyguard) rather than an app.
bool _looksLocked(String dump) =>
    dump.contains('open Samsung Wallet') || RegExp(r'emergency call', caseSensitive: false).hasMatch(dump);

/// evaluateJavascript may hand back the JSON string itself or a quoted/escaped copy of it.
Map<String, dynamic>? _decodeJs(Object? raw) {
  Object? v = raw;
  for (var i = 0; i < 3 && v is String; i++) {
    try {
      v = jsonDecode(v);
    } catch (_) {
      return null;
    }
  }
  return v is Map ? v.cast<String, dynamic>() : null;
}

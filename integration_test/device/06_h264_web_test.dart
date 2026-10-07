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
  // Fix 703f636: the gesture layer maps clicks onto the streamed frame scaled
  // to /info's full screen (1080x2220 on the SM-A750F), not /display
  // (1080x2112, which leaves out the nav bar). Same decisive centre /
  // bottom-edge checks as S11, here over the H.264 video.
  testWidgets('T20b clicks at the centre and bottom edge of the H.264 video send /tap in the full /info screen space', (tester) async {
    await _guard('T20b', () async {
      final display = await tester.runAsync(() => _probe.getJson('/display')) as Map<String, dynamic>;
      final dispW = (display['width'] as num).toInt(), dispH = (display['height'] as num).toInt();
      // /info screen = the phone's real full-screen pixel size, the space /tap
      // acts in (it includes the nav bar; /display does not).
      final info = await tester.runAsync(() => _probe.getJson('/info')) as Map<String, dynamic>;
      final scr = info['screen'] as Map<String, dynamic>;
      final realW = (scr['width'] as num).toInt(), realH = (scr['height'] as num).toInt();
      await _prepPhone(tester);
      await _settingsTop(tester);
      // Lock state: /dump on this phone can list only the Samsung Wallet
      // overlay window even on the unlocked home screen, so it is not used.
      // The phone counts as unlocked when the Settings main list just
      // launched is visible to /find (a secure keyguard would hide it).
      final rows0 = await _visibleRows(tester);
      final locked = rows0.isEmpty;
      final lockDump = locked ? await _dumpOrNull(tester) : null;
      print('NOTE T20b /display ${dispW}x$dispH /info screen ${realW}x$realH; Settings rows on screen=${rows0.keys.toList()} -> locked=$locked'
          '${locked ? ' (/dump: ${lockDump?.trim().split('\n').take(2).join(' | ')})' : ''}');

      final adapter = await pumpHuskApp(
        tester,
        servers: [phoneServer],
        settings: const AppSettings(defaultScreenMode: ScreenMode.h264),
      );
      await _openScreenTab(tester);
      await pumpUntil(tester, find.byType(H264View), timeout: const Duration(seconds: 30));
      await pumpUntil(tester, find.byType(GestureLayer));
      expect(_selectedMode(tester), {ScreenMode.h264});

      // Where the phone image is actually drawn: the video texture inside the
      // Video widget (FittedBox contain of the decoded frame), in window
      // coordinates. Computed from the widget tree, not the app's mapper.
      final textureFinder = find.descendant(of: find.byType(Video), matching: find.byType(Texture));
      await pumpUntil(tester, textureFinder, timeout: const Duration(seconds: 20));
      Rect? frameRect() => tester.widget<Video>(find.byType(Video)).controller.rect.value;
      final frameClock = Stopwatch()..start();
      while ((frameRect() == null || frameRect()!.isEmpty) && frameClock.elapsed < const Duration(seconds: 20)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await pumpFor(tester, const Duration(seconds: 2)); // let the layout settle on the first frame
      final frame = frameRect();
      final drawn = tester.getRect(textureFinder);
      final layer = tester.widget<GestureLayer>(find.byType(GestureLayer));
      final drawnAspect = drawn.width / drawn.height, realAspect = realW / realH;
      final aspectOk = (drawnAspect - realAspect).abs() / realAspect < 0.01;
      final geometry = 'H.264 frame ${frame?.width.toInt()}x${frame?.height.toInt()} drawn at ${_r(drawn)} '
          '(aspect ${drawnAspect.toStringAsFixed(4)} vs /info ${realW}x$realH ${realAspect.toStringAsFixed(4)}, match=$aspectOk); '
          'app layer deviceSize ${layer.deviceSize.width.toInt()}x${layer.deviceSize.height.toInt()} (reported only)';
      print('NOTE T20b geometry: $geometry');
      await snap(tester, _group, 'T20b-1');

      ({int x, int y, int n}) lastTap(int before) {
        final taps = adapter.log.where((u) => u.path == '/tap').toList();
        final q = taps.isEmpty ? const <String, String>{} : taps.last.queryParameters;
        return (x: int.tryParse(q['x'] ?? '') ?? -1, y: int.tryParse(q['y'] ?? '') ?? -1, n: taps.length - before);
      }

      Future<void> waitTap(int before) async {
        final clock = Stopwatch()..start();
        while (adapter.count('/tap') <= before && clock.elapsed < const Duration(seconds: 8)) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await pumpFor(tester, const Duration(milliseconds: 400));
      }

      // ---- centre
      final cx = realW ~/ 2, cy = realH ~/ 2;
      final rowsCentre = locked ? const <String, int>{} : await _visibleRows(tester);
      var before = adapter.count('/tap');
      await tester.tapAt(drawn.center);
      await waitTap(before);
      final c = lastTap(before);
      final centreOk = c.n == 1 && (c.x - cx).abs() <= 2 && (c.y - cy).abs() <= 2;
      String centrePhone = 'phone reaction BLOCKED (locked)';
      bool? centreReacted;
      if (!locked) {
        // The element under the centre opens a Settings subpage: the main-list
        // rows that were on screen go away.
        final after = await _untilRows(tester, (rows) => !rows.keys.toSet().containsAll(rowsCentre.keys));
        centreReacted = !after.keys.toSet().containsAll(rowsCentre.keys);
        final under = rowsCentre.entries.isEmpty
            ? 'none'
            : (rowsCentre.entries.toList()..sort((a, b) => (a.value - cy).abs().compareTo((b.value - cy).abs()))).first;
        centrePhone = 'phone: Settings main rows before ${rowsCentre.keys.toList()} (nearest to y=$cy: $under) -> after ${after.keys.toList()} '
            '(${centreReacted ? 'subpage opened' : 'NO change'})';
      }
      await snap(tester, _group, 'T20b-centre');
      final centreEv = 'click at drawn centre ${_o(drawn.center)} -> app sent /tap x=${c.x} y=${c.y} (count ${c.n}; expected ~$cx,$cy +-2; '
          'the old /display mapping gave y=${dispH ~/ 2}); $centrePhone';
      print('STEP T20b ${centreOk ? 'PASS' : 'FAIL'} centre: $centreEv');

      // ---- bottom edge (nav bar strip, below /display's height)
      if (!locked) {
        // Back out of whatever the centre tap opened and reopen Settings, so the
        // nav bar Home press is visible as Settings disappearing.
        await tester.runAsync(() async {
          try {
            await _probe.key('back');
          } catch (_) {}
          await Future<void>.delayed(const Duration(milliseconds: 600));
          await _phone('/launch', {'action': 'android.settings.SETTINGS'});
          await Future<void>.delayed(const Duration(seconds: 2));
        });
      }
      final rowsBottom = locked ? const <String, int>{} : await _visibleRows(tester);
      final at = Offset(drawn.center.dx, drawn.bottom - 2);
      before = adapter.count('/tap');
      await tester.tapAt(at);
      await waitTap(before);
      final b = lastTap(before);
      final bottomOk = b.n == 1 && b.y > dispH && b.y < realH && (b.x - cx).abs() <= 2;
      String bottomPhone = 'phone reaction BLOCKED (locked)';
      bool? bottomReacted;
      if (!locked) {
        // The nav bar's Home button is under the bottom-centre click: Settings
        // leaves the screen (none of its main rows remain) and the launcher shows.
        final after = await _untilRows(tester, (rows) => rows.isEmpty);
        final launcher = await tester.runAsync(() => _probe.find(r'^Play Store$'));
        bottomReacted = rowsBottom.isNotEmpty && after.isEmpty;
        bottomPhone = 'phone: Settings main rows before ${rowsBottom.keys.toList()} -> after ${after.keys.toList()} '
            '(${bottomReacted ? 'nav bar Home pressed, Settings left' : 'Settings still on screen, nav bar NOT hit'}); '
            'launcher "Play Store" at ${launcher == null ? 'not found' : '${launcher.x},${launcher.y}'}';
      }
      await snap(tester, _group, 'T20b-navbar');
      final bottomEv = 'click at ${_o(at)} (2 px above drawn bottom ${drawn.bottom.toStringAsFixed(1)}) -> app sent /tap x=${b.x} y=${b.y} '
          '(count ${b.n}; expected $dispH < y < $realH, x ~$cx +-2); $bottomPhone';
      print('STEP T20b ${bottomOk ? 'PASS' : 'FAIL'} bottom edge: $bottomEv');

      // Restore: back out of whatever the taps opened, then Home.
      await tester.runAsync(() async {
        try {
          await _probe.key('back');
          await Future<void>.delayed(const Duration(milliseconds: 500));
        } catch (_) {}
      });
      await _phoneHome(tester);

      final ev = 'centre: $centreEv; bottom edge: $bottomEv; $geometry; blocked=${adapter.blocked.length}';
      if (!centreOk || !bottomOk || !aspectOk) {
        check('T20b', 'FAIL', 'wrong /tap mapping over the H.264 view: $ev');
      } else if (locked) {
        check('T20b-app', 'PASS', 'app-side /tap coordinates correct: $ev');
        check('T20b', 'BLOCKED', 'app-side PASS (correct /tap coordinates from the request log); phone-side reaction BLOCKED: '
            'Settings could not be shown, the phone is on its lock screen (a human must unlock it): $ev');
      } else if (centreReacted == true && bottomReacted == true) {
        check('T20b', 'PASS', ev);
      } else {
        check('T20b', 'FAIL', 'coordinates sent correctly but the phone UI did not react (centre=$centreReacted bottom=$bottomReacted): $ev');
      }
      expect(c.n, 1, reason: 'one /tap for the centre click');
      expect(b.n, 1, reason: 'one /tap for the bottom-edge click');
      expect(aspectOk, isTrue, reason: geometry);
      expect((c.x - cx).abs(), lessThanOrEqualTo(2), reason: centreEv);
      expect((c.y - cy).abs(), lessThanOrEqualTo(2), reason: centreEv);
      expect(b.y, greaterThan(dispH), reason: bottomEv);
      expect(b.y, lessThan(realH), reason: bottomEv);
      expect((b.x - cx).abs(), lessThanOrEqualTo(2), reason: bottomEv);
      if (!locked) {
        expect(centreReacted, isTrue, reason: centreEv);
        expect(bottomReacted, isTrue, reason: bottomEv);
      }
      expect(adapter.blocked, isEmpty);
    });
  });

  // ----------------------------------------------------------------- T20c
  // Fix d559fc5: /displays is one comma-separated line ("0:0,2:0,13:0"); the
  // picker must offer every id it lists, and H.264 only on display 0.
  testWidgets('T20c picker offers every /displays id, H.264 only on display 0, and a forced player error falls back', (tester) async {
    await _guard('T20c', () async {
      // ---- Part 1: the display picker against the real phone.
      // Read the ids independently of the app's parser (newline or comma separated, "id:flags").
      List<int> parseIds(String text) => <int>[
            for (final part in text.split(RegExp(r'[,\n]')).map((p) => p.trim()).where((p) => p.isNotEmpty))
              if (int.tryParse(part.split(':').first.trim()) case final int id) id,
          ];
      // The phone's list changes over time: besides 0 and 2 it reports a
      // short-lived virtual display whose id grows from run to run (13, 16,
      // 20, 23 ...), so /displays is read right before the app starts and again
      // right after the picker is read. The app's own fetch happens between
      // the two reads: the picker must offer every id present in both reads
      // and nothing that is in neither.
      final displaysText = (await tester.runAsync(() => _probe.getText('/displays')))!.trim();
      final phoneIds = parseIds(displaysText);
      String label(int id) => id == 0 ? 'Phone (display 0)' : 'Display $id';

      final adapter = await pumpHuskApp(
        tester,
        servers: [phoneServer],
        settings: const AppSettings(defaultScreenMode: ScreenMode.h264),
      );
      await _openScreenTab(tester);
      await pumpUntil(tester, find.byType(SegmentedButton<ScreenMode>));
      await pumpUntil(tester, find.byType(H264View), timeout: const Duration(seconds: 30));
      final h264On0 = _modeSegment('H.264').evaluate().isNotEmpty;
      final mode0 = _selectedMode(tester);
      // /displays is fetched asynchronously; give it time to reach the picker.
      List<int?> pickerIds() => [for (final i in tester.widget<DropdownButton<int>>(find.byType(DropdownButton<int>)).items ?? const <DropdownMenuItem<int>>[]) i.value];
      final idClock = Stopwatch()..start();
      while (pickerIds().length < 2 && idClock.elapsed < const Duration(seconds: 10)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final ids = pickerIds();
      final labels = [
        for (final i in tester.widget<DropdownButton<int>>(find.byType(DropdownButton<int>)).items!)
          if (i.child case Text(:final data?)) data,
      ];
      await tester.tap(find.byType(DropdownButton<int>));
      await pumpFor(tester, const Duration(milliseconds: 600));
      final displaysText2 = (await tester.runAsync(() => _probe.getText('/displays')))!.trim();
      final phoneIds2 = parseIds(displaysText2);
      final stable = phoneIds.toSet().intersection(phoneIds2.toSet());
      final seen = phoneIds.toSet().union(phoneIds2.toSet());
      final menuShows = {for (final id in ids.whereType<int>()) id: find.text(label(id)).evaluate().isNotEmpty};
      await snap(tester, _group, 'T20c-1');
      final pickerOk = stable.contains(0) &&
          ids.length == ids.toSet().length &&
          ids.toSet().containsAll(stable) &&
          seen.containsAll(ids.whereType<int>()) &&
          labels.toSet().containsAll([for (final id in ids.whereType<int>()) label(id)]) &&
          menuShows.values.every((v) => v);
      final pickerEv = '/displays before app="${displaysText.replaceAll('\n', ' | ')}" (ids $phoneIds), after picker read="${displaysText2.replaceAll('\n', ' | ')}" '
          '(ids $phoneIds2); ids in both=${stable.toList()..sort()}; picker items values=$ids labels=$labels; '
          'open menu shows each=${menuShows.entries.map((e) => '${e.key}:${e.value}').join(',')}';

      final others = (stable.where((id) => id != 0).toList()..sort());
      var otherEv = 'phone reports no display other than 0, H.264 absence on another display cannot be driven';
      var otherOk = false;
      var backOk = false;
      if (others.isEmpty) {
        await tester.tap(find.text(label(0)).last);
        await pumpFor(tester, const Duration(milliseconds: 500));
      } else {
        final other = others.first;
        await tester.tap(find.text(label(other)).last);
        await pumpFor(tester, const Duration(seconds: 3));
        final ddValue = tester.widget<DropdownButton<int>>(find.byType(DropdownButton<int>)).value;
        final h264OnOther = _modeSegment('H.264').evaluate().isNotEmpty;
        final modeOther = _selectedMode(tester);
        final h264ViewOther = find.byType(H264View).evaluate().isNotEmpty;
        final mjpegOther = find.byType(MjpegView).evaluate().isNotEmpty;
        final streamReq = adapter.log.where((u) => u.path == '/screen' && u.queryParameters['d'] == '$other').length;
        await snap(tester, _group, 'T20c-2');
        otherOk = ddValue == other && !h264OnOther && modeOther.length == 1 && modeOther.first == ScreenMode.mjpeg && !h264ViewOther && mjpegOther;
        otherEv = 'picked display $other (picker value=$ddValue): H.264 segment offered=$h264OnOther, selected=${modeOther.map((m) => m.name).toList()}, '
            'H264View=$h264ViewOther MjpegView=$mjpegOther, /screen?d=$other requests=$streamReq';

        // Back to display 0: H.264 is offered again and (default H.264) shown again.
        await tester.tap(find.byType(DropdownButton<int>));
        await pumpFor(tester, const Duration(milliseconds: 600));
        await tester.tap(find.text(label(0)).last);
        final backClock = Stopwatch()..start();
        while (find.byType(H264View).evaluate().isEmpty && backClock.elapsed < const Duration(seconds: 15)) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await pumpFor(tester, const Duration(seconds: 1));
        final dd0 = tester.widget<DropdownButton<int>>(find.byType(DropdownButton<int>)).value;
        final h264Back = _modeSegment('H.264').evaluate().isNotEmpty;
        final viewBack = find.byType(H264View).evaluate().isNotEmpty;
        final modeBack = _selectedMode(tester);
        await snap(tester, _group, 'T20c-3');
        backOk = dd0 == 0 && h264Back && viewBack && modeBack.contains(ScreenMode.h264);
        otherEv += '; back on display 0 (value=$dd0): H.264 segment offered=$h264Back, selected=${modeBack.map((m) => m.name).toList()}, H264View=$viewBack';
      }
      final blockedCalls = adapter.blocked.length;
      final displayEv = 'display 0: H.264 segment offered=$h264On0 selected=${mode0.map((m) => m.name).toList()}; $pickerEv; $otherEv; blocked=$blockedCalls';
      print('STEP T20c ${pickerOk && h264On0 && otherOk && backOk ? 'PASS' : 'FAIL'} picker/H.264 per display: $displayEv');
      expect(adapter.blocked, isEmpty);

      // ---- Part 2: force a player error safely with a standalone H264View on a closed local port.
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
      await snap(tester, _group, 'T20c-4');
      final fallbackOk = failures.isNotEmpty;
      check('T20c-fallback', fallbackOk ? 'PASS' : 'FAIL',
          fallbackOk
              ? 'standalone H264View on closed port 127.0.0.1:1 called onFailed ${failures.length}x with "${failures.first}" '
                  '(the Screen tab turns this call into the "using MJPEG" snackbar; its own wiring is covered by unit tests, not re-driven here)'
              : 'onFailed was NOT called within 25 s for a closed port');

      final displayPartOk = pickerOk && h264On0 && otherOk && backOk;
      final status = !pickerOk || !h264On0 || (others.isNotEmpty && (!otherOk || !backOk)) || !fallbackOk
          ? 'FAIL'
          : (others.isEmpty ? 'BLOCKED' : 'PASS');
      check('T20c', status, '$displayEv; forced-error fallback: ${fallbackOk ? 'PASS' : 'FAIL'} (T20c-fallback)');
      expect(pickerOk, isTrue, reason: pickerEv);
      expect(h264On0, isTrue, reason: 'H.264 segment must be offered on display 0');
      if (others.isNotEmpty) expect(displayPartOk, isTrue, reason: displayEv);
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

String _o(Offset o) => '(${o.dx.toStringAsFixed(1)},${o.dy.toStringAsFixed(1)})';

/// /dump of display 0 on the real clock, or null when it cannot be read.
Future<String?> _dumpOrNull(WidgetTester tester) => tester.runAsync<String?>(() async {
      try {
        return await _probe.getText('/dump', {'d': '0'});
      } catch (_) {
        return null;
      }
    });

/// Rows of the Settings main list (English One UI) used to see where the phone is.
const List<String> _settingsRows = ['Connections', 'Sounds and vibration', 'Notifications', 'Display', 'Wallpaper', 'Themes', 'Lock screen'];

/// Settings main-list rows currently on screen (via read-only /find), name -> centre y.
Future<Map<String, int>> _visibleRows(WidgetTester tester) async {
  final rows = <String, int>{};
  await tester.runAsync(() async {
    for (final name in _settingsRows) {
      try {
        final p = await _probe.find('^${RegExp.escape(name)}\$');
        if (p != null && p.y > 0 && p.y < 2112) rows[name] = p.y;
      } catch (_) {}
    }
  });
  return rows;
}

/// Polls [_visibleRows] for up to 6 s until [done]; returns the last rows.
Future<Map<String, int>> _untilRows(WidgetTester tester, bool Function(Map<String, int> rows) done) async {
  var rows = <String, int>{};
  final clock = Stopwatch()..start();
  while (clock.elapsed < const Duration(seconds: 6)) {
    await pumpFor(tester, const Duration(milliseconds: 500));
    rows = await _visibleRows(tester);
    if (done(rows)) break;
  }
  return rows;
}

/// Scrolls the just-launched Settings list back to its top (it reopens at its
/// last scroll position).
Future<void> _settingsTop(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (var i = 0; i < 4; i++) {
      try {
        await _phone('/scroll', {'d': '0', 'dir': 'back'});
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  });
}

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

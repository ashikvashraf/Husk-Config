// ignore_for_file: file_names, avoid_print
//
// Device checklist: Screen tab (S11, S11b, S12, S15) against the real phone.
// Run (one macOS run at a time): flutter test integration_test/device/05_screen_test.dart -d macos
//
// Safety: the phone is only touched through the app (tap/swipe/scroll/key/text
// on the Screen tab), read-only PhoneProbe GETs, /key, and two raw GETs:
// /wake and /launch?action=android.settings.SETTINGS. Settings is only
// opened, scrolled and backed out of. Screenshot/Stream quality are never used.
//
// Click mapping (fix 703f636): the app maps clicks onto the streamed frame as
// drawn (BoxFit.contain of the decoded frame), scaled to the full real screen
// from /info (1080x2220 on the SM-A750F), NOT onto /display (1080x2112, which
// leaves out the 108 px nav bar). This test computes where a phone pixel is
// drawn from the decoded frame and /info only, independent of the app's mapper.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/storage/app_settings.dart';
import 'package:huskconfig/features/screen/gesture_layer.dart';
import 'package:huskconfig/shared/widgets/mjpeg_view.dart';

import 'support/device_harness.dart';

const String _group = '05_screen_test';
const Timeout _longTimeout = Timeout(Duration(minutes: 8));

final PhoneProbe probe = PhoneProbe();
final _RawPhone _rawPhone = _RawPhone();

/// Rows of the Settings main list (English UI). The first two present on
/// screen become the tap target and the "sibling that must disappear".
const List<String> _mainRows = [
  'Display',
  'Connections',
  'Sounds and vibration',
  'Notifications',
  'Apps',
  'Location',
  'General management',
  'About phone',
  'Accessibility',
];

void main() {
  initDeviceHarness();

  tearDown(() async {
    try {
      await probe.home();
    } catch (_) {}
  });

  testWidgets('S11 Screen tab MJPEG: frames, tap, swipe, wheel, nav bar, Esc, text + Enter', (tester) async {
    final steps = _Steps('S11');
    Object? fatal;
    StackTrace? fatalTrace;
    CountingAdapter? adapter;
    try {
      adapter = await _s11(tester, steps);
    } catch (e, st) {
      fatal = e;
      fatalTrace = st;
      steps.bad.add('abort: ${_firstLine(e)}');
    } finally {
      try {
        await tester.runAsync(() async {
          await probe.key('back');
          await Future<void>.delayed(const Duration(milliseconds: 400));
          await probe.key('back');
          await Future<void>.delayed(const Duration(milliseconds: 400));
          await probe.home();
        });
      } catch (_) {}
    }
    final blocked = adapter?.blocked ?? const <Uri>[];
    if (blocked.isNotEmpty) steps.bad.add('harness blocked requests: $blocked');
    final status = steps.bad.isNotEmpty ? 'FAIL' : (steps.blocked.isNotEmpty ? 'BLOCKED' : 'PASS');
    check('S11', status, steps.summary());
    if (fatal != null) Error.throwWithStackTrace(fatal, fatalTrace!);
    expect(steps.bad, isEmpty, reason: steps.summary());
    expect(steps.blocked, isEmpty, reason: 'S11 is BLOCKED (not a pass): ${steps.summary()}');
  }, timeout: _longTimeout);

  testWidgets('S11b Fullscreen opens and closes; tab shows "Showing fullscreen" meanwhile (one stream)', (tester) async {
    final steps = _Steps('S11b');
    Object? fatal;
    StackTrace? fatalTrace;
    CountingAdapter? adapter;
    try {
      await tester.runAsync(() async {
        await _rawPhone.wake();
        await probe.home();
      });
      adapter = await _openScreenTab(tester);
      final placeholder = find.text('Showing fullscreen', skipOffstage: false);

      await steps.run('before: one live stream, no placeholder', () async {
        expect(find.byType(MjpegView), findsOneWidget);
        expect(placeholder, findsNothing);
        return '1 MjpegView with a frame, no placeholder';
      });

      await steps.run('open fullscreen', () async {
        final streamsBefore = adapter!.count('/screen');
        await tester.tap(find.byTooltip('Fullscreen'));
        await pumpUntil(tester, placeholder);
        await pumpUntil(tester, find.byTooltip('Exit fullscreen'));
        await pumpUntil(tester, _frame, timeout: const Duration(seconds: 30));
        // The tab's own view is replaced by the placeholder, so only the
        // fullscreen route holds a stream.
        final views = find.byType(MjpegView, skipOffstage: false).evaluate().length;
        expect(views, 1, reason: 'exactly one MjpegView (one stream) while fullscreen');
        await snap(tester, _group, 'S11b-1');
        return 'placeholder "Showing fullscreen" in the tab, Exit fullscreen shown, MjpegViews=$views, '
            '/screen requests ${adapter.count('/screen') - streamsBefore} new';
      });

      await steps.run('exit fullscreen', () async {
        await tester.tap(find.byTooltip('Exit fullscreen'));
        await _pumpUntilGone(tester, find.byTooltip('Exit fullscreen'));
        await _pumpUntilGone(tester, placeholder);
        await pumpUntil(tester, _frame, timeout: const Duration(seconds: 30));
        expect(find.byType(MjpegView, skipOffstage: false), findsOneWidget);
        await snap(tester, _group, 'S11b-2');
        return 'route closed, placeholder gone, tab streams again (1 MjpegView with a frame)';
      });
    } catch (e, st) {
      fatal = e;
      fatalTrace = st;
      steps.bad.add('abort: ${_firstLine(e)}');
    }
    final blocked = adapter?.blocked ?? const <Uri>[];
    if (blocked.isNotEmpty) steps.bad.add('harness blocked requests: $blocked');
    check('S11b', steps.bad.isEmpty ? 'PASS' : 'FAIL', steps.summary());
    if (fatal != null) Error.throwWithStackTrace(fatal, fatalTrace!);
    expect(steps.bad, isEmpty, reason: steps.summary());
  }, timeout: _longTimeout);

  testWidgets('S12 Landscape: physical rotation is BLOCKED (human); record the /display rotation', (tester) async {
    try {
      final d = await tester.runAsync(() => probe.getJson('/display')) as Map<String, dynamic>;
      final rotation = d['rotation'];
      check(
        'S12',
        'BLOCKED',
        'physically rotating the phone cannot be automated (human step); current /display rotation=$rotation '
            'size=${d['width']}x${d['height']} (0 = portrait, 1/3 = landscape)',
      );
    } catch (e) {
      check('S12', 'BLOCKED', 'physical rotation cannot be automated (human step); could not read /display: ${_firstLine(e)}');
      rethrow;
    }
  }, timeout: _longTimeout);

  testWidgets('S15 Screenshot save and Stream quality are BLOCKED; verify GET /screen.jpg returns a JPEG', (tester) async {
    String status = 'FAIL';
    String evidence = 'not run';
    try {
      final adapter = await _openScreenTab(tester);
      // Only check the controls exist; never tap them (native save dialog / non-revertible setting).
      final hasShot = find.byTooltip('Screenshot').evaluate().isNotEmpty;
      final hasQuality = find.byTooltip('Stream quality').evaluate().isNotEmpty;
      await snap(tester, _group, 'S15-1');
      final jpeg = await tester.runAsync(_rawPhone.screenJpeg) as _Jpeg;
      final ok = jpeg.status == 200 && jpeg.isJpeg;
      status = ok ? 'BLOCKED' : 'FAIL';
      evidence =
          'GET /screen.jpg status=${jpeg.status} content-type=${jpeg.contentType} bytes=${jpeg.bytes.length} '
          'magic=${jpeg.isJpeg ? 'FFD8FF' : 'not-jpeg'} decoded=${jpeg.width}x${jpeg.height} (JPEG ${ok ? 'OK' : 'BAD'}); '
          'Screenshot save (native file dialog) and Stream quality (/set sq,sfps not revertible) NOT exercised, '
          'buttons present: Screenshot=$hasShot Stream quality=$hasQuality; blocked requests=${adapter.blocked.length}';
      expect(adapter.blocked, isEmpty);
      expect(ok, isTrue, reason: evidence);
    } catch (e) {
      if (status != 'BLOCKED') evidence = '$evidence ${_firstLine(e)}'.trim();
      rethrow;
    } finally {
      check('S15', status, evidence);
    }
  }, timeout: _longTimeout);
}

// ---------------------------------------------------------------------- S11

Future<CountingAdapter> _s11(WidgetTester tester, _Steps steps) async {
  await tester.runAsync(() async {
    await _rawPhone.wake();
    await probe.home();
  });
  await pumpFor(tester, const Duration(seconds: 1));

  final flags = await tester.runAsync(() => probe.getJson('/flags')) as Map<String, dynamic>;
  if (flags['screen'] != true) throw TestFailure('screen sharing is off on the phone (/flags.screen=${flags['screen']})');
  final display = await tester.runAsync(() => probe.getJson('/display')) as Map<String, dynamic>;
  final screen = await _screenSize(tester);
  print('S11 /display ${display['width']}x${display['height']} rotation=${display['rotation']}; /info screen (real /tap space) '
      '${screen.width.toInt()}x${screen.height.toInt()}');
  if (screen != _realScreen) {
    throw TestFailure('/info screen is ${screen.width.toInt()}x${screen.height.toInt()}, expected the SM-A750F full screen 1080x2220');
  }

  final adapter = await _openScreenTab(tester);

  // ---- frames arrive
  await steps.run('frames arrive', () async {
    final image = tester.widget<RawImage>(_frame).image!;
    await pumpFor(tester, const Duration(seconds: 2));
    final fpsFinder = find.textContaining(' fps');
    final fps = fpsFinder.evaluate().isEmpty ? '?' : tester.widget<Text>(fpsFinder).data;
    final frameAspect = image.width / image.height;
    final realAspect = screen.width / screen.height;
    await snap(tester, _group, 'S11-1');
    final off = (frameAspect - realAspect).abs() / realAspect;
    if (off >= 0.03) {
      throw TestFailure(
        'frame aspect differs from the real screen by ${(off * 100).toStringAsFixed(1)}% (limit 3%): frame ${image.width}x${image.height} '
        '(aspect ${frameAspect.toStringAsFixed(4)}) vs /info screen ${screen.width.toInt()}x${screen.height.toInt()} (aspect ${realAspect.toStringAsFixed(4)})',
      );
    }
    return 'MjpegView shows a decoded frame ${image.width}x${image.height} (aspect ${frameAspect.toStringAsFixed(4)}, matches /info screen '
        '${screen.width.toInt()}x${screen.height.toInt()} within ${(off * 100).toStringAsFixed(2)}%; /display ${display['width']}x${display['height']} not used), '
        'drawn at ${_drawnFrame(tester)} in view ${tester.getRect(find.byType(GestureLayer))}, overlay "$fps", /screen requests=${adapter.count('/screen')}';
  });

  // ---- Precondition: Settings can only come up when the phone is unlocked.
  final lock = await _lockState(tester);
  const dependent = [
    'open Settings',
    'tap lands on the right element',
    'nav bar Back',
    'swipe reaches the phone (/dump changes)',
    'mouse wheel scroll reaches the phone (/dump changes)',
    'Esc acts as Back after focusing the view',
    'nav bar Recents',
    'nav bar Home',
    'Send text "wifi" reaches the focused search field',
    'Enter reaches the focused search field',
    'Back out of search and Home',
  ];
  if (lock.locked) {
    await snap(tester, _group, 'S11-locked');
    final why =
        'phone is on its lock screen (secure keyguard; swipe-up shows a FLAG_SECURE bouncer), a human must unlock it; '
        '/dump=${lock.dump.trim().split('\n').take(2).join(' | ')}';
    print('S11 precondition: $why');
    // What the APP sends is still checked (the request log); the phone's reaction is not observable.
    await _mappingSteps(tester, steps, adapter, observe: false);
    for (final name in dependent) {
      steps.blockedStep(name, 'phone locked, see S11 precondition');
    }
    steps.blockedStep('phone reaction to the centre / bottom-edge clicks', 'phone locked');
    steps.blocked.add('precondition: $why');
    return adapter;
  }

  // ---- Open Settings (safe: launch only), tap a row through the view.
  late ({String a, ({int x, int y}) aAt, String b}) main;
  final settingsOk = await steps.run('open Settings', () async {
    main = await _settingsMain(tester);
    await pumpFor(tester, const Duration(seconds: 1));
    return 'Settings main list visible; tap target "${main.a}" at ${main.aAt}, sibling "${main.b}"';
  });

  if (!settingsOk) {
    steps.notRun('tap lands on the right element', 'open Settings failed');
    steps.notRun('nav bar Back', 'open Settings failed');
  } else {
    await steps.run('tap lands on the right element', () async {
      final tapsBefore = adapter.count('/tap');
      final global = _toGlobal(tester, screen, main.aAt);
      await tester.tapAt(global.global);
      await pumpFor(tester, const Duration(milliseconds: 300));
      final sent = adapter.log.where((u) => u.path == '/tap').toList();
      expect(adapter.count('/tap'), tapsBefore + 1, reason: 'one /tap request for the click');
      final u = sent.last;
      final sx = int.parse(u.queryParameters['x']!), sy = int.parse(u.queryParameters['y']!);
      expect((sx - main.aAt.x).abs(), lessThanOrEqualTo(1), reason: 'sent x=$sx, element x=${main.aAt.x}');
      expect((sy - main.aAt.y).abs(), lessThanOrEqualTo(1), reason: 'sent y=$sy, element y=${main.aAt.y}');
      final gone = await _until(tester, () async => !await _exists(main.b));
      await snap(tester, _group, 'S11-2');
      expect(gone, isTrue, reason: 'after tapping "${main.a}" the Settings main row "${main.b}" should be gone (subpage open)');
      return 'element "${main.a}" centre ${main.aAt} is drawn at ${global.global} (drawn frame ${global.drawn}); '
          'clicking it made the app send /tap?x=$sx&y=$sy; phone opened the subpage ("${main.b}" exists 1 -> 0)';
    });

    await steps.run('nav bar Back', () async {
      await tester.tap(find.byTooltip('Back'));
      final back = await _until(tester, () => _exists(main.b));
      expect(back, isTrue, reason: 'Back should return to the Settings main list ("${main.b}" exists)');
      return 'Back button returned from the subpage ("${main.b}" exists 0 -> 1); /key back count=${_keyCount(adapter, 'back')}';
    });
  }

  // ---- Decisive mapping checks, with the phone's reaction observed.
  await _mappingSteps(tester, steps, adapter, observe: true);

  // ---- swipe + wheel
  await steps.run('swipe reaches the phone (/dump changes)', () async {
    await _settingsMain(tester); // the bottom-edge check pressed Home
    await pumpFor(tester, const Duration(seconds: 1));
    final base = await _dump(tester);
    await pumpFor(tester, const Duration(milliseconds: 400));
    final noise = await _dump(tester);
    final swipesBefore = adapter.count('/swipe');
    final from = _toGlobal(tester, screen, (x: screen.width ~/ 2, y: (screen.height * 0.75).round())).global;
    final to = _toGlobal(tester, screen, (x: screen.width ~/ 2, y: (screen.height * 0.30).round())).global;
    await _drag(tester, from, to);
    String last = base;
    final changed = await _until(tester, () async {
      last = await _dump(tester);
      return _changed(base, noise, last);
    });
    await snap(tester, _group, 'S11-3');
    expect(adapter.count('/swipe'), swipesBefore + 1, reason: 'one /swipe request');
    final u = adapter.log.lastWhere((u) => u.path == '/swipe');
    expect(changed, isTrue, reason: '/dump unchanged after swipe (tokenDiff=${_tokenDiff(base, last)}, noise=${_tokenDiff(base, noise)})');
    return 'drag sent as /swipe?x1=${u.queryParameters['x1']}&y1=${u.queryParameters['y1']}&x2=${u.queryParameters['x2']}&y2=${u.queryParameters['y2']}&ms=${u.queryParameters['ms']}; '
        '/dump changed (tokenDiff=${_tokenDiff(base, last)} vs idle noise ${_tokenDiff(base, noise)})';
  });

  await steps.run('mouse wheel scroll reaches the phone (/dump changes)', () async {
    final centre = _drawnFrame(tester).center;
    final before = adapter.log.where((u) => u.path == '/scroll').length;
    final base = await _dump(tester);
    await pumpFor(tester, const Duration(milliseconds: 400));
    final noise = await _dump(tester);
    var changed = false;
    String last = base;
    for (var i = 0; i < 3 && !changed; i++) {
      await _wheel(tester, centre, 240); // dy > 0 => /scroll?dir=fwd
      changed = await _until(tester, () async {
        last = await _dump(tester);
        return _changed(base, noise, last);
      }, timeout: const Duration(seconds: 3));
    }
    final sent = adapter.log.where((u) => u.path == '/scroll').skip(before).toList();
    expect(sent, isNotEmpty, reason: 'wheel produced no /scroll request');
    expect(sent.first.queryParameters['dir'], 'fwd');
    expect(changed, isTrue, reason: '/dump unchanged after wheel scroll');
    // Scroll back to the top with dir=back (also proves the other direction).
    final main2 = <String>[];
    for (var i = 0; i < 10; i++) {
      if (await _real(tester, () => _exists('^${RegExp.escape(_mainRows.first)}\$')) ||
          await _real(tester, () => _exists('^${RegExp.escape(_mainRows[1])}\$'))) {
        main2.add('top reached after $i back-wheel(s)');
        break;
      }
      await _wheel(tester, centre, -240);
      await pumpFor(tester, const Duration(milliseconds: 400));
    }
    final backs = adapter.log.where((u) => u.path == '/scroll' && u.queryParameters['dir'] == 'back').length;
    return 'wheel sent ${sent.length} x /scroll (dir=${sent.first.queryParameters['dir']}); /dump changed (tokenDiff=${_tokenDiff(base, last)} vs noise ${_tokenDiff(base, noise)}); '
        'dir=back requests=$backs ${main2.join()}';
  });

  // ---- Esc acts as Back after focusing the view
  await steps.run('Esc acts as Back after focusing the view', () async {
    final m = await _settingsMain(tester);
    await tester.tapAt(_toGlobal(tester, screen, m.aAt).global);
    final opened = await _until(tester, () async => !await _exists(m.b));
    expect(opened, isTrue, reason: 'subpage "${m.a}" did not open');
    // Focus the view by tapping a letterbox bar (no phone tap is sent).
    final rect = tester.getRect(find.byType(GestureLayer));
    final drawn = _drawnFrame(tester);
    expect(drawn.left - rect.left, greaterThan(8), reason: 'no letterbox bar to focus the view safely');
    final tapsBefore = adapter.count('/tap');
    await tester.tapAt(Offset((rect.left + drawn.left) / 2, rect.center.dy));
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(adapter.count('/tap'), tapsBefore, reason: 'focusing tap must not reach the phone');
    final backsBefore = _keyCount(adapter, 'back');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await pumpFor(tester, const Duration(milliseconds: 300));
    final back = await _until(tester, () => _exists(m.b));
    await snap(tester, _group, 'S11-4');
    expect(_keyCount(adapter, 'back'), backsBefore + 1, reason: 'Esc should send one /key?k=back');
    expect(back, isTrue, reason: 'after Esc the Settings main row "${m.b}" should be visible again');
    return 'opened "${m.a}", focused view via letterbox tap, Esc -> /key?k=back, phone returned to the main list ("${m.b}" exists 0 -> 1)';
  });

  // ---- Recents and Home
  await steps.run('nav bar Recents', () async {
    final m = await _settingsMain(tester);
    final base = await _dump(tester);
    final noise = await _dump(tester);
    await tester.tap(find.byTooltip('Recents'));
    String last = base;
    final changed = await _until(tester, () async {
      last = await _dump(tester);
      return _changed(base, noise, last) && !await _exists(m.b);
    });
    expect(changed, isTrue, reason: 'Recents: /dump did not change or "${m.b}" still exists');
    _recentsDump = last;
    return 'Recents opened ("${m.b}" exists 1 -> 0, /dump tokenDiff=${_tokenDiff(base, last)}); /key recents count=${_keyCount(adapter, 'recents')}';
  });

  await steps.run('nav bar Home', () async {
    final recents = _recentsDump ?? await _dump(tester);
    await tester.tap(find.byTooltip('Home'));
    String last = recents;
    final changed = await _until(tester, () async {
      last = await _dump(tester);
      return _tokenDiff(recents, last) >= 2;
    });
    final settingsGone =
        !await _real(tester, () => _exists('^${RegExp.escape(_mainRows.first)}\$')) && !await _real(tester, () => _exists('^${RegExp.escape(_mainRows[1])}\$'));
    expect(changed, isTrue, reason: 'Home: /dump did not change relative to Recents');
    expect(settingsGone, isTrue, reason: 'Home: Settings rows still on screen');
    return 'Home left Recents and Settings (/dump tokenDiff=${_tokenDiff(recents, last)}, Settings rows absent); /key home count=${_keyCount(adapter, 'home')}';
  });

  // ---- Send text + Enter into the Settings search field
  await steps.run('Send text "wifi" reaches the focused search field', () async {
    final m = await _settingsMain(tester);
    final search = await _real(tester, () => probe.find(r'(?i)^search( settings)?$'));
    expect(search, isNotNull, reason: 'no "Search" element found on the Settings main page');
    await tester.tapAt(_toGlobal(tester, screen, search!).global);
    final opened = await _until(tester, () async => !await _exists(m.b), timeout: const Duration(seconds: 8));
    expect(opened, isTrue, reason: 'Settings search page did not open');
    await pumpFor(tester, const Duration(seconds: 1));
    final before = (await _dump(tester)).toLowerCase();
    expect(before.contains('wifi'), isFalse, reason: 'baseline /dump already contains "wifi"');

    final field = find.byType(TextField);
    expect(field, findsOneWidget);
    tester.widget<TextField>(field).controller!.text = 'wifi';
    await tester.pump();
    final textCalls = adapter.count('/text');
    await tester.tap(find.byTooltip('Send text'));
    await pumpFor(tester, const Duration(milliseconds: 300));
    String after = '';
    final typed = await _until(tester, () async {
      after = (await _dump(tester)).toLowerCase();
      return after.contains('wifi');
    }, timeout: const Duration(seconds: 8));
    await snap(tester, _group, 'S11-5');
    final snacks = find.byType(SnackBar).evaluate().isEmpty
        ? ''
        : ' snackbar="${find.descendant(of: find.byType(SnackBar), matching: find.byType(Text)).evaluate().map((e) => (e.widget as Text).data).join(' | ')}"';
    expect(adapter.count('/text'), textCalls + 1, reason: 'one /text request');
    expect(typed, isTrue, reason: '/dump never showed "wifi" after Send text.$snacks');
    final u = adapter.log.lastWhere((u) => u.path == '/text');
    return 'search page open ("${m.b}" exists 1 -> 0); app sent /text?t=${u.queryParameters['t']}; /dump now contains "wifi" (absent before)$snacks';
  });

  await steps.run('Enter reaches the focused search field', () async {
    final base = await _dump(tester);
    final enters = _keyCount(adapter, 'enter');
    await tester.tap(find.widgetWithText(OutlinedButton, 'Enter'));
    await pumpFor(tester, const Duration(milliseconds: 300));
    String last = base;
    final changed = await _until(tester, () async {
      last = await _dump(tester);
      return _tokenDiff(base, last) >= 2;
    }, timeout: const Duration(seconds: 5));
    expect(_keyCount(adapter, 'enter'), enters + 1, reason: 'Enter should send /key?k=enter');
    return 'Enter sent /key?k=enter (answered OK); /dump ${changed ? 'changed (search submitted)' : 'did not change'} (tokenDiff=${_tokenDiff(base, last)})';
  });

  await steps.run('Back out of search and Home', () async {
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byTooltip('Back'));
      await pumpFor(tester, const Duration(milliseconds: 800));
      if (await _real(tester, () => _exists('^${RegExp.escape(_mainRows.first)}\$')) ||
          await _real(tester, () => _exists('^${RegExp.escape(_mainRows[1])}\$'))) {
        break;
      }
    }
    final onMain =
        await _real(tester, () => _exists('^${RegExp.escape(_mainRows.first)}\$')) || await _real(tester, () => _exists('^${RegExp.escape(_mainRows[1])}\$'));
    await tester.tap(find.byTooltip('Home'));
    final left = await _until(
      tester,
      () async => !await _exists('^${RegExp.escape(_mainRows.first)}\$') && !await _exists('^${RegExp.escape(_mainRows[1])}\$'),
    );
    expect(onMain, isTrue, reason: 'Back did not leave the search page');
    expect(left, isTrue, reason: 'Home did not leave Settings');
    return 'Back left the search page (main list visible), Home left Settings';
  });

  return adapter;
}

String? _recentsDump;

// ------------------------------------------------------------------ helpers

final Finder _frame = find.descendant(of: find.byType(MjpegView), matching: find.byType(RawImage));

/// Launches the app on the phone's saved server, goes to the Screen tab (MJPEG)
/// and waits for a live frame.
Future<CountingAdapter> _openScreenTab(WidgetTester tester) async {
  final adapter = await pumpHuskApp(
    tester,
    servers: [phoneServer],
    settings: const AppSettings(defaultScreenMode: ScreenMode.mjpeg),
  );
  await pumpUntil(tester, find.text('Test phone'));
  await tester.tap(find.text('Test phone'));
  final rail = find.descendant(of: find.byType(NavigationRail), matching: find.text('Screen'));
  await pumpUntil(tester, rail);
  await tester.tap(rail);
  await pumpUntil(tester, find.byType(GestureLayer), timeout: const Duration(seconds: 30));
  await pumpUntil(tester, _frame, timeout: const Duration(seconds: 30));
  return adapter;
}

/// Runs [f] on the real clock. Errors are caught inside the runAsync zone and
/// rethrown here, because runAsync itself reports a thrown error to the test
/// framework, returns null and can leave later runAsync calls "reentrant".
Future<T> _real<T>(WidgetTester t, Future<T> Function() f) async {
  Object? error;
  StackTrace? trace;
  final result = await t.runAsync(() async {
    try {
      return await f();
    } catch (e, st) {
      error = e;
      trace = st;
      return null;
    }
  });
  if (error != null) Error.throwWithStackTrace(error!, trace!);
  return result as T;
}

/// True when the phone shows its lock screen (keyguard). One UI's lock
/// screen exposes the Samsung Wallet shortcut; the secure bouncer is
/// FLAG_SECURE (black frame) and exposes almost nothing.
Future<({bool locked, String dump})> _lockState(WidgetTester t) async {
  final dump = await _dump(t);
  final nodes = dump.split('\n').where((l) => l.startsWith('[')).length;
  final locked = RegExp(r'samsung wallet|emergency call', caseSensitive: false).hasMatch(dump) || nodes <= 2;
  return (locked: locked, dump: dump);
}

/// The SM-A750F's full screen in /tap pixels (/info screen, nav bar included).
const Size _realScreen = Size(1080, 2220);

/// /info's screen size: the real /tap and /swipe pixel space.
Future<Size> _screenSize(WidgetTester t) async {
  final info = await _real(t, () => probe.getJson('/info')) as Map<String, dynamic>;
  final s = info['screen'] as Map<String, dynamic>;
  return Size((s['width'] as num).toDouble(), (s['height'] as num).toDouble());
}

Future<String> _dump(WidgetTester t) => _real(t, () => probe.getText('/dump', {'d': '0'}));

Future<bool> _exists(String regex) async {
  final r = (await probe.getText('/exists', {'match': regex})).trim().toLowerCase();
  return r == '1' || r == 'true' || r == 'yes';
}

int _keyCount(CountingAdapter a, String k) => a.log.where((u) => u.path == '/key' && u.queryParameters['k'] == k).length;

Set<String> _tokens(String s) => RegExp(r'\w+').allMatches(s).map((m) => m.group(0)!).toSet();

int _tokenDiff(String a, String b) {
  final x = _tokens(a), y = _tokens(b);
  return x.difference(y).length + y.difference(x).length;
}

/// True when [after] differs from [base] by clearly more than idle noise.
bool _changed(String base, String noiseSample, String after) {
  final d = _tokenDiff(base, after);
  return d >= 2 && d > _tokenDiff(base, noiseSample);
}

/// Polls [cond] (real-time, off the fake clock) while pumping frames.
Future<bool> _until(
  WidgetTester t,
  Future<bool> Function() cond, {
  Duration timeout = const Duration(seconds: 6),
  Duration every = const Duration(milliseconds: 400),
}) async {
  final clock = Stopwatch()..start();
  while (true) {
    try {
      if (await _real(t, cond)) return true;
    } on IOException catch (_) {
    } on TimeoutException catch (_) {}
    if (clock.elapsed >= timeout) return false;
    await pumpFor(t, every);
  }
}

Future<void> _pumpUntilGone(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 20)}) async {
  final clock = Stopwatch()..start();
  while (finder.evaluate().isNotEmpty) {
    if (clock.elapsed >= timeout) throw TestFailure('still present after ${timeout.inMilliseconds} ms: $finder');
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Opens Settings (safe /launch) and returns two visible main-list rows, going
/// Back/Home between attempts if Settings resumed on a subpage.
Future<({String a, ({int x, int y}) aAt, String b})> _settingsMain(WidgetTester t) async {
  for (var attempt = 0; attempt < 6; attempt++) {
    if (attempt == 3) await _real(t, probe.home);
    await _real(t, _rawPhone.launchSettings);
    await pumpFor(t, const Duration(milliseconds: 1500));
    final found = <(String, ({int x, int y}))>[];
    for (final name in _mainRows) {
      final p = await _real(t, () => probe.find('^${RegExp.escape(name)}\$'));
      if (p != null) found.add((name, p));
      if (found.length >= 2) break;
    }
    if (found.length >= 2) return (a: found[0].$1, aAt: found[0].$2, b: found[1].$1);
    await _real(t, () => probe.key('back'));
    await pumpFor(t, const Duration(milliseconds: 700));
  }
  throw TestFailure('could not get the Settings main list on screen (looked for rows $_mainRows)');
}

/// Global rect where the live frame is actually drawn: BoxFit.contain of the
/// decoded frame inside the RawImage box (alignment centre). Computed from the
/// frame alone, independent of the app's CoordinateMapper.
Rect _drawnFrame(WidgetTester t) {
  final image = t.widget<RawImage>(_frame).image!;
  final box = t.getRect(_frame);
  final fitted = applyBoxFit(BoxFit.contain, Size(image.width.toDouble(), image.height.toDouble()), box.size);
  return Alignment.center.inscribe(fitted.destination, box);
}

/// Global position where phone pixel [p] (in the full /info [screen] space,
/// which the frame covers) is drawn, i.e. where a user would click it.
({Offset global, Rect drawn}) _toGlobal(WidgetTester t, Size screen, ({int x, int y}) p) {
  final drawn = _drawnFrame(t);
  return (global: drawn.topLeft + Offset(p.x / screen.width * drawn.width, p.y / screen.height * drawn.height), drawn: drawn);
}

/// The decisive S11 mapping checks (fix 703f636), read from the request log:
/// a click at the visual centre of the drawn frame sends /tap ~(540, 1110), and
/// a click near its bottom edge sends y > 2112 (the nav bar strip that
/// /display's 1080x2112 leaves out). With [observe] the phone's reaction is
/// also verified: the bottom-centre click lands on the nav bar's Home button
/// and leaves Settings.
Future<void> _mappingSteps(WidgetTester tester, _Steps steps, CountingAdapter adapter, {required bool observe}) async {
  ({int x, int y}) lastTap() {
    final u = adapter.log.lastWhere((u) => u.path == '/tap');
    return (x: int.parse(u.queryParameters['x']!), y: int.parse(u.queryParameters['y']!));
  }

  await steps.run('click at the visual centre of the drawn frame sends /tap ~(540,1110)', () async {
    final image = tester.widget<RawImage>(_frame).image!;
    final drawn = _drawnFrame(tester);
    final base = observe ? await _dump(tester) : '';
    final before = adapter.count('/tap');
    await tester.tapAt(drawn.center);
    await pumpFor(tester, const Duration(milliseconds: 400));
    expect(adapter.count('/tap'), before + 1, reason: 'one /tap request for the click');
    final t = lastTap();
    var phone = 'phone reaction BLOCKED (locked)';
    if (observe) {
      String last = base;
      await _until(tester, () async {
        last = await _dump(tester);
        return _tokenDiff(base, last) >= 2;
      });
      phone = 'phone /dump tokenDiff=${_tokenDiff(base, last)} after the tap';
    }
    await snap(tester, _group, 'S11-centre');
    expect((t.x - 540).abs(), lessThanOrEqualTo(2), reason: 'centre click sent x=${t.x}, expected ~540');
    expect((t.y - 1110).abs(), lessThanOrEqualTo(2), reason: 'centre click sent y=${t.y}, expected ~1110 (the old /display mapping sent 1056)');
    return 'frame ${image.width}x${image.height} drawn at $drawn; click at its centre ${drawn.center} -> app sent /tap?x=${t.x}&y=${t.y} '
        '(expected ~540,1110; old /display mapping gave 1056); $phone';
  });

  await steps.run('click near the bottom edge of the drawn frame sends /tap y > 2112 (nav bar reachable)', () async {
    ({String a, ({int x, int y}) aAt, String b})? m;
    if (observe) {
      if (!(await _real(tester, () => _exists('^${RegExp.escape(_mainRows.first)}\$')) ||
          await _real(tester, () => _exists('^${RegExp.escape(_mainRows[1])}\$')))) {
        await tester.tap(find.byTooltip('Back'));
        await pumpFor(tester, const Duration(milliseconds: 800));
      }
      m = await _settingsMain(tester);
      await pumpFor(tester, const Duration(seconds: 1));
    }
    final drawn = _drawnFrame(tester);
    final at = Offset(drawn.center.dx, drawn.bottom - 2);
    final before = adapter.count('/tap');
    await tester.tapAt(at);
    await pumpFor(tester, const Duration(milliseconds: 400));
    expect(adapter.count('/tap'), before + 1, reason: 'one /tap request for the click');
    final t = lastTap();
    var phone = 'phone reaction BLOCKED (locked)';
    bool? left;
    if (observe) {
      left = await _until(tester, () async => !await _exists('^${RegExp.escape(m!.a)}\$') && !await _exists('^${RegExp.escape(m.b)}\$'));
      phone = left
          ? 'phone: nav bar Home pressed, Settings left ("${m!.a}"/"${m.b}" exist 1 -> 0)'
          : 'phone: Settings rows "${m!.a}"/"${m.b}" still present (nav bar not hit)';
    }
    await snap(tester, _group, 'S11-navbar');
    expect(t.y, greaterThan(2112), reason: 'bottom-edge click sent y=${t.y}; must be inside the nav bar strip (> 2112)');
    expect(t.y, lessThan(2220), reason: 'bottom-edge click sent y=${t.y}, outside the 2220 px screen');
    expect((t.x - 540).abs(), lessThanOrEqualTo(2), reason: 'bottom-centre click sent x=${t.x}, expected ~540');
    if (observe) expect(left, isTrue, reason: phone);
    return 'click at $at (2 px above the drawn bottom ${drawn.bottom}) -> app sent /tap?x=${t.x}&y=${t.y} (> 2112, nav bar strip 2112..2219); $phone';
  });
}

Future<void> _drag(WidgetTester t, Offset from, Offset to) async {
  final g = await t.startGesture(from);
  const steps = 8;
  for (var i = 1; i <= steps; i++) {
    await g.moveTo(Offset.lerp(from, to, i / steps)!);
    await t.pump(const Duration(milliseconds: 40));
  }
  await g.up();
  await t.pump(const Duration(milliseconds: 100));
}

Future<void> _wheel(WidgetTester t, Offset at, double dy) async {
  final pointer = TestPointer(99, PointerDeviceKind.mouse);
  await t.sendEventToBinding(pointer.hover(at));
  await t.sendEventToBinding(pointer.scroll(Offset(0, dy)));
  await t.pump(const Duration(milliseconds: 100));
}

String _firstLine(Object e) => e.toString().split('\n').where((l) => l.trim().isNotEmpty).take(2).join(' ').trim();

class _Steps {
  _Steps(this.id);

  final String id;
  final List<String> ok = [];
  final List<String> bad = [];
  final List<String> blocked = [];

  /// Records a sub-step that cannot be observed (BLOCKED: never a pass).
  void blockedStep(String name, String why) {
    blocked.add('$name: BLOCKED ($why)');
    print('STEP $id BLOCKED $name: $why');
  }

  /// Records a sub-step that could not run (counts as failed: never a pass).
  void notRun(String name, String why) {
    bad.add('$name: NOT RUN ($why)');
    print('STEP $id FAIL $name: NOT RUN ($why)');
  }

  Future<bool> run(String name, Future<String> Function() body) async {
    try {
      final evidence = await body();
      ok.add('$name: $evidence');
      print('STEP $id PASS $name: $evidence');
      return true;
    } catch (e) {
      final why = _firstLine(e);
      bad.add('$name: $why');
      print('STEP $id FAIL $name: $why');
      return false;
    }
  }

  String summary() => [
        if (ok.isNotEmpty) 'PASSED: ${ok.join(' ; ')}',
        if (bad.isNotEmpty) 'FAILED: ${bad.join(' ; ')}',
        if (blocked.isNotEmpty) 'BLOCKED: ${blocked.join(' ; ')}',
      ].join(' || ');
}

// ------------------------------------------------------------ raw phone I/O

class _Jpeg {
  _Jpeg(this.status, this.contentType, this.bytes, this.width, this.height);

  final int status;
  final String contentType;
  final Uint8List bytes;
  final int width;
  final int height;

  bool get isJpeg => bytes.length > 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;
}

/// The only non-probe phone calls this file makes: /wake, a SETTINGS launch
/// and the read of /screen.jpg.
class _RawPhone {
  Future<(int, ContentType?, Uint8List)> _get(String path, Map<String, String> query) async {
    final client = HttpClient()..connectionTimeout = PhoneProbe.timeout;
    try {
      final request = await client.getUrl(probe.uri(path, query)).timeout(PhoneProbe.timeout);
      final response = await request.close().timeout(const Duration(seconds: 10));
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(const Duration(seconds: 10))) {
        builder.add(chunk);
      }
      return (response.statusCode, response.headers.contentType, builder.takeBytes());
    } finally {
      client.close(force: true);
    }
  }

  Future<void> wake() async {
    await _get('/wake', const {});
  }

  Future<void> launchSettings() async {
    await _get('/launch', const {'action': 'android.settings.SETTINGS', 'd': '0'});
  }

  Future<_Jpeg> screenJpeg() async {
    final (status, type, bytes) = await _get('/screen.jpg', const {});
    var w = 0, h = 0;
    if (status == 200 && bytes.length > 3) {
      try {
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        w = frame.image.width;
        h = frame.image.height;
        frame.image.dispose();
        codec.dispose();
      } catch (_) {}
    }
    return _Jpeg(status, type?.mimeType ?? '?', bytes, w, h);
  }
}

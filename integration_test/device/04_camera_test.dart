// ignore_for_file: file_names, avoid_print
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/shared/widgets/mjpeg_view.dart';

import 'support/device_harness.dart';

/// S10 Camera tab: live /stream, Snapshot dialog (never Save), Back/Front switch.
void main() {
  initDeviceHarness();
  final probe = PhoneProbe();

  /// Restores the camera side to Front (the only /set the checklist allows is
  /// front=0 then front=1) and presses Home. Never throws.
  Future<void> restorePhone() async {
    try {
      final flags = await probe.getJson('/flags') as Map<String, dynamic>;
      if (flags['front'] != true) {
        final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
        try {
          final req = await client.getUrl(probe.uri('/set', {'front': '1'}));
          final res = await req.close().timeout(const Duration(seconds: 5));
          await res.drain<void>();
        } finally {
          client.close(force: true);
        }
      }
    } catch (e) {
      print('S10 teardown: could not restore front=1: $e');
    }
    try {
      await probe.home();
    } catch (e) {
      print('S10 teardown: home failed: $e');
    }
  }

  tearDown(restorePhone);

  final decodedFrame = find.descendant(
    of: find.byType(MjpegView),
    matching: find.byWidgetPredicate((w) => w is RawImage && w.image != null, description: 'RawImage with a decoded frame'),
  );
  final fpsReadout = find.descendant(
    of: find.byType(MjpegView),
    matching: find.byWidgetPredicate(
      (w) => w is Text && RegExp(r'^[1-9]\d* fps$').hasMatch(w.data ?? ''),
      description: 'fps readout > 0',
    ),
  );

  Future<bool?> readFront() async {
    final flags = await probe.getJson('/flags') as Map<String, dynamic>;
    return flags['front'] as bool?;
  }

  /// SnackBar texts seen while polling (diagnostics: the tab reports /set errors there).
  final snacks = <String>{};
  void collectSnacks() {
    for (final e in find.descendant(of: find.byType(SnackBar), matching: find.byType(Text)).evaluate()) {
      final t = (e.widget as Text).data;
      if (t != null) snacks.add(t);
    }
  }

  /// Polls /flags (real time) until `front == want`; returns the last value read.
  Future<bool?> waitForFront(WidgetTester tester, bool want) async {
    bool? last;
    final clock = Stopwatch()..start();
    while (clock.elapsed < const Duration(seconds: 15)) {
      last = await tester.runAsync<bool?>(readFront);
      collectSnacks();
      if (last == want) {
        print('S10 diag: /flags front=$last after ${clock.elapsed.inMilliseconds} ms');
        return last;
      }
      await pumpFor(tester, const Duration(milliseconds: 500));
      collectSnacks();
    }
    // A pump can stall (e.g. the window is occluded), so never return a stale
    // value: read /flags once more after the deadline.
    last = await tester.runAsync<bool?>(readFront);
    print('S10 diag: /flags front=$last on final read after ${clock.elapsed.inMilliseconds} ms (wanted $want)');
    return last;
  }

  Key? streamKey() => find.byType(MjpegView).evaluate().map((e) => e.widget.key).firstOrNull;

  /// Waits until the tab rebuilt MjpegView with a new key (it bumps the key
  /// only after a successful /set), then for a decoded frame from the new view.
  Future<void> waitForFreshFrame(WidgetTester tester, Key? before) async {
    await pumpUntil(
      tester,
      find.byWidgetPredicate((w) => w is MjpegView && w.key != before, description: 'MjpegView reconnected (key != $before)'),
      timeout: const Duration(seconds: 20),
    );
    await pumpUntil(tester, decodedFrame, timeout: const Duration(seconds: 20));
  }

  void diag(String label, CountingAdapter adapter) {
    final firstSet = adapter.log.indexWhere((u) => u.path == '/set');
    final interesting = adapter.log
        .skip(firstSet < 0 ? adapter.log.length : firstSet)
        .where((u) => const {'/set', '/stream', '/snapshot', '/flags'}.contains(u.path))
        .map((u) => u.toString().replaceFirst(RegExp(r'^http://[^/]+'), ''));
    final keys = find.byType(MjpegView).evaluate().map((e) => e.widget.key).toList();
    final sel = find.byType(SegmentedButton<bool>).evaluate().map((e) => (e.widget as SegmentedButton<bool>).selected).toList();
    print('S10 diag [$label]: requests=${interesting.toList()} snacks=$snacks mjpegKey=$keys uiSelected=$sel');
  }

  Future<CountingAdapter> openCameraTab(WidgetTester tester) async {
    final adapter = await pumpHuskApp(tester, servers: [phoneServer]);
    await pumpUntil(tester, find.text('Test phone'));
    await tester.tap(find.text('Test phone'));
    await pumpUntil(tester, find.text('Camera'));
    final rail = find.byType(NavigationRail);
    final bar = find.byType(NavigationBar);
    final scope = rail.evaluate().isNotEmpty ? rail : bar;
    await tester.tap(find.descendant(of: scope, matching: find.text('Camera')));
    await pumpUntil(tester, find.text('Camera side'));
    expect(adapter.blocked, isEmpty);
    return adapter;
  }

  testWidgets('S10 Camera tab: live stream, Snapshot dialog, Back/Front switch', (tester) async {
    try {
      final initialFront = await tester.runAsync<bool?>(readFront);
      final adapter = await openCameraTab(tester);

      // 1. Live /stream shows decoded frames and fps > 0 within 20 s.
      await pumpUntil(tester, decodedFrame, timeout: const Duration(seconds: 20));
      await pumpUntil(tester, fpsReadout, timeout: const Duration(seconds: 20));
      final fpsText = tester.widget<Text>(fpsReadout.first).data;
      final streamPath = await snap(tester, '04_camera_test', 'S10-1');
      expect(adapter.count('/stream'), greaterThanOrEqualTo(1));

      // 2. Snapshot opens the image dialog (Save is NEVER pressed).
      await tester.tap(find.widgetWithText(FilledButton, 'Snapshot'));
      await pumpUntil(tester, find.byType(Dialog), timeout: const Duration(seconds: 20));
      await pumpUntil(tester, find.descendant(of: find.byType(Dialog), matching: find.byType(Image)));
      expect(find.descendant(of: find.byType(Dialog), matching: find.text('Save')), findsOneWidget);
      await pumpFor(tester, const Duration(milliseconds: 500));
      final snapshotPath = await snap(tester, '04_camera_test', 'S10-2');
      expect(adapter.count('/snapshot'), greaterThanOrEqualTo(1));
      await tester.tap(find.descendant(of: find.byType(Dialog), matching: find.text('Close')));
      await pumpUntil(tester, find.text('Camera side'));
      await pumpFor(tester, const Duration(milliseconds: 500));
      expect(find.byType(Dialog), findsNothing);

      // 3. Back then Front switches /flags.front false then true; ends on Front.
      final side = find.byType(SegmentedButton<bool>);
      if (initialFront != true) {
        await tester.tap(find.descendant(of: side, matching: find.text('Front')));
        expect(await waitForFront(tester, true), isTrue, reason: 'precondition: front=true before the switch test');
        await pumpFor(tester, const Duration(seconds: 1));
      }
      var keyBefore = streamKey();
      await tester.tap(find.descendant(of: side, matching: find.text('Back')));
      final afterBack = await waitForFront(tester, false);
      await waitForFreshFrame(tester, keyBefore);
      diag('after Back', adapter);
      final backPath = await snap(tester, '04_camera_test', 'S10-3');
      expect(afterBack, isFalse, reason: 'GET /flags front after pressing Back');

      keyBefore = streamKey();
      await tester.tap(find.descendant(of: side, matching: find.text('Front')));
      final afterFront = await waitForFront(tester, true);
      await waitForFreshFrame(tester, keyBefore);
      diag('after Front', adapter);
      await pumpFor(tester, const Duration(seconds: 1));
      final frontPath = await snap(tester, '04_camera_test', 'S10-4');
      expect(afterFront, isTrue, reason: 'GET /flags front after pressing Front');
      // The tab shows /flags.front (refetched after /set, then polled every
      // 10 s). Allow one poll interval plus margin, and record the lag.
      final uiClock = Stopwatch()..start();
      final frontSelected = find.byWidgetPredicate(
        (w) => w is SegmentedButton<bool> && w.selected.length == 1 && w.selected.first,
        description: 'Camera side SegmentedButton with Front selected',
      );
      try {
        await pumpUntil(tester, frontSelected, timeout: const Duration(seconds: 15));
      } on TestFailure catch (_) {
        // fall through to the assertion below with the real value
      }
      final uiLagMs = uiClock.elapsedMilliseconds;
      diag('UI selection after ${uiLagMs}ms', adapter);
      final selected = tester.widget<SegmentedButton<bool>>(side).selected;
      final uiPath = await snap(tester, '04_camera_test', 'S10-5');
      print('S10 diag: UI selection=$selected after ${uiLagMs}ms (phone /flags.front=true) $uiPath');
      expect(selected, {true}, reason: 'UI selection ends on Front');
      expect(adapter.blocked, isEmpty);

      check(
        'S10',
        'PASS',
        'stream decoded frame + "$fpsText" ($streamPath); Snapshot dialog with Image + Save shown, Save not pressed ($snapshotPath); '
            '/flags front false after Back ($backPath) then true after Front ($frontPath); UI ends on Front after ${uiLagMs}ms ($uiPath); '
            'app requests /stream=${adapter.count('/stream')} /snapshot=${adapter.count('/snapshot')} /set=${adapter.count('/set')}',
      );
    } catch (e) {
      try {
        final texts = find.descendant(of: find.byType(MjpegView), matching: find.byType(Text)).evaluate().map((el) => (el.widget as Text).data).toList();
        final failPath = await snap(tester, '04_camera_test', 'S10-fail');
        print('S10 diag [on failure]: MjpegView texts=$texts snacks=$snacks $failPath');
      } catch (d) {
        print('S10 diag [on failure]: could not capture state: $d');
      }
      check('S10', 'FAIL', '$e');
      rethrow;
    }
  });
}

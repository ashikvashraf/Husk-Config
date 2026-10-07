// ignore_for_file: file_names, avoid_print
// Device checklist S16 (Tools: Inspect + Launch), S17 (Motion alarm load, no
// save), S18 (RPC console ping) and T20i (switching server on the wide Tools
// tab). Runs the real app on macOS against the real phone.
//
// Phone side effects: /wake, /key home, one tap on a home-screen app label
// (chosen from a safe allow-list when possible) and /launch of
// android.settings.SETTINGS, and /rpc ping. Motion is only ever READ (no Save).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/storage/server_config.dart';
import 'package:huskconfig/shared/widgets/result_box.dart';

import 'support/device_harness.dart';

const String _group = '07_tools_test';

/// Regex matching things only the Settings app shows on its main page.
const String _settingsOpened = 'Search settings|Connections|About phone|Software update|Sounds and vibration';

/// Home-screen labels that are safe to open (opening is the only effect).
const List<String> _safeLabels = [
  'Settings', 'Clock', 'Calculator', 'Calendar', 'Gallery', 'Camera', 'Files', 'My Files',
  'Notes', 'Samsung Notes', 'Tools', 'Galaxy Store', 'Play Store', 'Internet', 'Chrome', 'Google',
];

/// Never picked by the fallback chooser.
final RegExp _denyLabel = RegExp(
  r'phone|call|dial|message|sms|contact|mail|whatsapp|telegram|signal|messenger|bank|pay|wallet|'
  r'uninstall|install|store|delete|reset|backup|pass|secure|vault|find my',
  caseSensitive: false,
);

void main() {
  initDeviceHarness();
  final probe = PhoneProbe();

  /// Presses Home; never throws.
  Future<void> homeQuietly() async {
    try {
      await probe.home();
    } catch (e) {
      print('tearDown: could not press Home: $e');
    }
  }

  /// GET /wake (allowed, safe) so the dump is of a lit screen. Never throws.
  Future<void> wake() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await client.getUrl(probe.uri('/wake'));
      final res = await req.close().timeout(const Duration(seconds: 5));
      await res.drain<void>();
    } catch (e) {
      print('wake failed: $e');
    } finally {
      client.close(force: true);
    }
  }

  tearDown(homeQuietly);

  /// Polls [cond] (a phone probe call, run in real time) until true or [timeout].
  Future<bool> pollPhone(WidgetTester tester, Future<bool> Function() cond, {Duration timeout = const Duration(seconds: 12)}) async {
    final clock = Stopwatch()..start();
    while (true) {
      final ok = await tester.runAsync<bool>(() async {
            try {
              return await cond();
            } catch (_) {
              return false;
            }
          }) ??
          false;
      if (ok) return true;
      if (clock.elapsed >= timeout) return false;
      await pumpFor(tester, const Duration(milliseconds: 500));
    }
  }

  Future<bool> exists(String regex) async => (await probe.getText('/exists', {'match': regex})).trim() == '1';

  /// Wake the screen and go Home; waits (real time) for the launcher to settle.
  Future<void> goHome(WidgetTester tester) async {
    await tester.runAsync(() async {
      await wake();
      await probe.home();
      await Future<void>.delayed(const Duration(milliseconds: 1500));
    });
  }

  /// Dashboard -> device -> Tools tab (wide layout rail).
  Future<CountingAdapter> openTools(WidgetTester tester, {List<ServerConfig> servers = const []}) async {
    final adapter = await pumpHuskApp(tester, servers: servers.isEmpty ? [phoneServer] : servers);
    await pumpUntil(tester, find.text('Test phone'));
    await tester.tap(find.text('Test phone'));
    await pumpUntil(tester, find.byType(NavigationRail));
    await tester.tap(find.descendant(of: find.byType(NavigationRail), matching: find.text('Tools')));
    await pumpUntil(tester, find.text('Pattern (regex)'));
    return adapter;
  }

  /// Taps a Tools page entry in the wide master list.
  Future<void> openToolPage(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(ListTile, label).first);
    await tester.pump(const Duration(milliseconds: 200));
  }

  /// Waits until the single ResultBox shows text satisfying [ok]; returns it.
  Future<String> waitResult(WidgetTester tester, bool Function(String) ok, {Duration timeout = const Duration(seconds: 20)}) async {
    final clock = Stopwatch()..start();
    while (true) {
      await tester.pump(const Duration(milliseconds: 100));
      final boxes = find.byType(ResultBox).evaluate();
      if (boxes.isNotEmpty) {
        final text = (boxes.first.widget as ResultBox).text;
        if (ok(text)) return text;
      }
      if (clock.elapsed >= timeout) throw TestFailure('waitResult timed out after ${timeout.inMilliseconds} ms');
    }
  }

  /// Pumps until any of [finders] matches; throws a TestFailure on timeout.
  Future<void> pumpUntilAny(WidgetTester tester, List<Finder> finders, {Duration timeout = const Duration(seconds: 20)}) async {
    final clock = Stopwatch()..start();
    while (true) {
      await tester.pump(const Duration(milliseconds: 100));
      if (finders.any((f) => f.evaluate().isNotEmpty)) return;
      if (clock.elapsed >= timeout) throw TestFailure('pumpUntilAny timed out waiting for: $finders');
    }
  }

  final textsOf = RegExp(r"""\b[td]='([^']*)'""");

  /// Picks a home-screen label from a fresh /dump: allow-list first, then any
  /// plain label that is not on the deny list. Needs on-screen Find coordinates.
  Future<({String label, int x, int y, String? opened, List<String> others, String dump})?> chooseHomeLabel() async {
    final dump = await probe.getText('/dump');
    final texts = <String>{
      for (final m in textsOf.allMatches(dump)) m.group(1)!.trim(),
    }.where((t) => RegExp(r'^[A-Za-z0-9][A-Za-z0-9 ]{2,24}$').hasMatch(t) && !RegExp(r'^\d+$').hasMatch(t)).toList();
    final safe = [for (final s in _safeLabels) if (texts.contains(s)) s];
    final fallback = [for (final t in texts) if (!safe.contains(t) && !_denyLabel.hasMatch(t)) t];
    for (final label in [...safe, ...fallback].take(8)) {
      final p = await probe.find('^$label\$');
      if (p == null || p.x < 0 || p.y < 0 || p.x > 1080 || p.y > 2220) continue;
      final opened = switch (label) {
        'Settings' => _settingsOpened,
        'Clock' => 'Alarm|World clock|Stopwatch|Timer',
        _ => null,
      };
      return (label: label, x: p.x, y: p.y, opened: opened, others: [for (final t in texts) if (t != label) t], dump: dump);
    }
    return null;
  }

  testWidgets('S16 Tools: Inspect dump/find/tap here, then Launch Settings preset', (tester) async {
    try {
      await goHome(tester);
      final chosen = await tester.runAsync(chooseHomeLabel);
      if (chosen == null) {
        // Say what the phone showed so a reviewer can tell a lock screen from a launcher problem.
        final seen = await tester.runAsync(() async {
          try {
            final dump = await probe.getText('/dump');
            final lines = dump.split('\n').where((l) => l.trim().isNotEmpty).toList();
            final texts = {for (final m in textsOf.allMatches(dump)) m.group(1)!.trim()}.where((t) => t.isNotEmpty).take(4);
            return '${lines.length} dump line(s), texts: ${texts.map((t) => '"$t"').join(', ')}';
          } catch (e) {
            return 'dump unavailable: $e';
          }
        });
        check('S16', 'BLOCKED', 'no on-screen home-screen label found in GET /dump after /wake + Home (screen off, locked, or unusual launcher); phone showed $seen');
        return;
      }
      final label = chosen.label;
      final regex = '^$label\$';

      final adapter = await openTools(tester);

      // --- Dump: non-empty tree containing text the phone shows.
      await tester.tap(find.widgetWithText(OutlinedButton, 'Dump'));
      final dumped = await waitResult(tester, (t) => t.startsWith('Dumped ') || t.startsWith('ERR'));
      expect(dumped, startsWith('Dumped '), reason: 'Dump result');
      final lineCount = int.parse(RegExp(r'Dumped (\d+) lines').firstMatch(dumped)!.group(1)!);
      expect(lineCount, greaterThan(0));
      await tester.enterText(find.widgetWithText(TextField, 'Filter lines'), label);
      await pumpFor(tester, const Duration(milliseconds: 500));
      final dumpLine = find.byWidgetPredicate(
        (w) => w is Text && w.style?.fontFamily == 'monospace' && (w.data ?? '').contains(label),
        description: 'dump line containing "$label"',
      );
      expect(dumpLine, findsWidgets, reason: 'app dump shows a line with the phone text "$label"');
      final dumpLineText = tester.widget<Text>(dumpLine.first).data;
      final snapDump = await snap(tester, _group, 'S16-1');

      // --- Find on the visible home-screen label.
      await tester.enterText(find.widgetWithText(TextField, 'Pattern (regex)'), regex);
      final expectedPoint = await tester.runAsync(() => probe.find(regex));
      await tester.tap(find.widgetWithText(OutlinedButton, 'Find'));
      final found = await waitResult(tester, (t) => t.startsWith('Found at') || t == 'No match' || t.startsWith('ERR'));
      expect(found, startsWith('Found at '), reason: 'Find "$regex" result');
      expect(expectedPoint, isNotNull, reason: 'GET /find agrees there is a match');
      expect(found, 'Found at ${expectedPoint!.x}, ${expectedPoint.y}', reason: 'app Find vs GET /find');
      final snapFind = await snap(tester, _group, 'S16-2');

      // --- Tap here opens the app (verified through /exists).
      await tester.tap(find.text('Tap here'));
      await pumpFor(tester, const Duration(milliseconds: 500));
      await waitResult(tester, (t) => t != found, timeout: const Duration(seconds: 10));
      bool opened;
      String how;
      if (chosen.opened != null) {
        opened = await pollPhone(tester, () => exists(chosen.opened!));
        how = '/exists "${chosen.opened}" = ${opened ? 1 : 0}';
      } else {
        // Generic: most of the other home-screen labels are gone from the screen.
        final markers = chosen.others;
        int stillThere = markers.length;
        opened = await pollPhone(tester, () async {
          stillThere = 0;
          for (final m in markers.take(6)) {
            if (await exists('^$m\$')) stillThere++;
          }
          return markers.isNotEmpty && stillThere * 2 < markers.take(6).length;
        });
        how = '/exists of ${markers.take(6).length} other home labels: $stillThere still present';
      }
      final snapTap = await snap(tester, _group, 'S16-3');
      expect(opened, isTrue, reason: 'tapping "$label" opened it ($how)');
      await goHome(tester);

      // --- Launch "Settings" preset.
      await openToolPage(tester, 'Launch');
      await pumpUntil(tester, find.text('Intent action'));
      // Precondition: Settings is not already showing.
      final clean = await pollPhone(tester, () async => !await exists(_settingsOpened));
      expect(clean, isTrue, reason: 'phone is on the home screen before Launch (Settings main page not visible)');
      await tester.tap(find.widgetWithText(ActionChip, 'Settings'));
      await pumpFor(tester, const Duration(milliseconds: 300));
      expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Intent action')).controller!.text, 'android.settings.SETTINGS');
      await tester.tap(find.ancestor(of: find.text('Launch'), matching: find.byWidgetPredicate((w) => w is FilledButton)));
      final launchReply = await waitResult(tester, (_) => true);
      final settingsOpen = await pollPhone(tester, () => exists(_settingsOpened));
      final snapLaunch = await snap(tester, _group, 'S16-4');
      expect(settingsOpen, isTrue, reason: 'Launch Settings preset opened Settings (/exists "$_settingsOpened"); reply "$launchReply"');
      await goHome(tester);
      final backHome = await pollPhone(tester, () async => !await exists(_settingsOpened));

      expect(adapter.blocked, isEmpty);
      check(
        'S16',
        'PASS',
        'Dump "$dumped", filter "$label" shows line "$dumpLineText" ($snapDump); Find "$regex" -> "$found" = GET /find ($snapFind); '
            'Tap here opened "$label": $how ($snapTap); Launch Settings preset reply "$launchReply", /exists Settings page=1 ($snapLaunch); '
            'Home restored=$backHome; app /dump=${adapter.count('/dump')} /find=${adapter.count('/find')} /tap=${adapter.count('/tap')} /launch=${adapter.count('/launch')}',
      );
    } catch (e) {
      check('S16', 'FAIL', '$e');
      rethrow;
    }
  });

  testWidgets('S17 Tools: Motion alarm config and events match GET /motion and /events (no Save)', (tester) async {
    try {
      final adapter = await openTools(tester);
      await openToolPage(tester, 'Motion alarm');
      await pumpUntil(tester, find.textContaining('Sensitivity:'));
      final noEvents = find.text('No motion events yet.');
      final eventTitles = find.textContaining(' % change');
      await pumpUntilAny(tester, [noEvents, eventTitles]);
      await pumpFor(tester, const Duration(milliseconds: 500));

      final motion = await tester.runAsync(() => probe.getJson('/motion')) as Map<String, dynamic>;
      final events = await tester.runAsync(() => probe.getJson('/events')) as List<dynamic>;

      // Config card.
      final fields = find.byType(TextField);
      final serverUi = tester.widget<TextField>(fields.at(0)).controller!.text;
      final topicUi = tester.widget<TextField>(fields.at(1)).controller!.text;
      final enabledUi = tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value;
      final sensUi = tester.widget<Text>(find.textContaining('Sensitivity:')).data!;
      expect(serverUi, motion['ntfyServer'] ?? 'https://ntfy.sh', reason: 'ntfy server field vs GET /motion');
      expect(topicUi, motion['ntfyTopic'] ?? '', reason: 'ntfy topic field vs GET /motion');
      expect(enabledUi, motion['enabled'] ?? false, reason: 'enabled switch vs GET /motion');
      final sens = ((motion['sensitivity'] as num?)?.toInt() ?? 5).clamp(1, 10);
      expect(sensUi, startsWith('Sensitivity: $sens '), reason: 'sensitivity vs GET /motion');
      final lastNtfy = (motion['lastNtfy'] as String?) ?? '';
      if (lastNtfy.isNotEmpty) expect(find.text(lastNtfy), findsOneWidget, reason: 'Last push row');

      // Events card.
      if (events.isEmpty) {
        expect(noEvents, findsOneWidget, reason: 'GET /events is empty');
      } else {
        expect(eventTitles, findsNWidgets(events.length), reason: 'event rows vs GET /events');
        for (final e in events.cast<Map<String, dynamic>>()) {
          final title = '${((e['change'] as num?) ?? 0).toDouble().toStringAsFixed(1)} % change';
          expect(find.text(title), findsWidgets, reason: 'event "$title"');
          final source = (e['source'] as String?) ?? '';
          expect(find.textContaining('$source · '), findsWidgets, reason: 'event source "$source"');
        }
      }
      final snapPath = await snap(tester, _group, 'S17-1');

      // Save was never pressed: the app only issued parameterless /motion GETs.
      final motionCalls = adapter.log.where((u) => u.path == '/motion').toList();
      expect(motionCalls, isNotEmpty);
      expect(motionCalls.every((u) => (Map.of(u.queryParameters)..remove('token')).isEmpty), isTrue, reason: 'only parameterless /motion reads');
      expect(adapter.blocked, isEmpty);

      check(
        'S17',
        'PASS',
        'config matches GET /motion (enabled=$enabledUi server="$serverUi" topic="$topicUi" "$sensUi"); '
            '${events.length} event(s) shown = GET /events; Save not pressed, /motion reads=${motionCalls.length}, /events=${adapter.count('/events')}; $snapPath',
      );
    } catch (e) {
      check('S17', 'FAIL', '$e');
      rethrow;
    }
  });

  testWidgets('S18 Tools: RPC console sends ping after one-time confirmation and shows engine reply', (tester) async {
    try {
      final adapter = await openTools(tester);
      await openToolPage(tester, 'RPC console');
      await pumpUntil(tester, find.widgetWithText(TextField, 'Command'));
      final command = find.widgetWithText(TextField, 'Command');
      final replies = find.descendant(of: find.byType(Card), matching: find.byType(SelectableText));

      await tester.enterText(command, 'ping');
      await tester.tap(find.widgetWithText(FilledButton, 'Send'));
      await pumpUntil(tester, find.text('Send raw commands?'));
      final snapDialog = await snap(tester, _group, 'S18-1');
      expect(adapter.count('/rpc'), 0, reason: 'nothing sent before the confirmation');
      await tester.tap(find.text('Continue'));
      await pumpUntil(tester, replies);
      final reply = tester.widget<SelectableText>(replies.first).data!;
      expect(find.text('> ping'), findsOneWidget);
      expect(reply.trim(), isNotEmpty, reason: 'engine reply to ping');
      expect(reply, isNot(startsWith('ERR')), reason: 'engine reply to ping: $reply');
      final snapReply = await snap(tester, _group, 'S18-2');

      // One-time: a second ping goes out without another dialog.
      await tester.enterText(command, 'ping');
      await tester.tap(find.widgetWithText(FilledButton, 'Send'));
      await pumpUntil(tester, find.byType(Card).at(1));
      expect(find.byType(AlertDialog), findsNothing, reason: 'no second confirmation');
      expect(adapter.count('/rpc'), 2);
      expect(adapter.log.where((u) => u.path == '/rpc').every((u) => u.queryParameters['cmd'] == 'ping'), isTrue);
      expect(adapter.blocked, isEmpty);

      check('S18', 'PASS', 'confirmation dialog "Send raw commands?" shown once ($snapDialog); ping reply "${reply.trim()}" ($snapReply); second ping sent with no dialog; app /rpc=${adapter.count('/rpc')}');
    } catch (e) {
      check('S18', 'FAIL', '$e');
      rethrow;
    }
  });

  testWidgets('T20i Tools tab: switching server resets the tool page to the second server state', (tester) async {
    try {
      final adapter = await openTools(tester, servers: [phoneServer, offlineServer]);
      await openToolPage(tester, 'Motion alarm');
      await pumpUntil(tester, find.textContaining('Sensitivity:'));
      final phoneServerUrl = tester.widget<TextField>(find.byType(TextField).at(0)).controller!.text;
      final snapBefore = await snap(tester, _group, 'T20i-1');
      expect(find.text('Recent events'), findsOneWidget);

      // Switch server in the app bar to the unreachable one.
      final dropdown = find.byType(DropdownButton<String>);
      await tester.tap(dropdown);
      await pumpUntil(tester, find.text('Unreachable'));
      await tester.tap(find.text('Unreachable').last);
      await pumpFor(tester, const Duration(seconds: 1));
      expect(tester.widget<DropdownButton<String>>(dropdown).value, offlineServer.id, reason: 'app bar shows the unreachable server');

      // The phone's config must be gone.
      expect(find.textContaining('Sensitivity:'), findsNothing, reason: "phone's motion config still shown after the switch");
      final motionPageStillOpen = find.text('Recent events').evaluate().isNotEmpty;
      final landing = motionPageStillOpen ? 'Motion alarm page (reloading)' : 'tool list reset to Inspect';
      final snapAfter = await snap(tester, _group, 'T20i-2');

      // Open Motion alarm for the second server: loading or error, never the phone's config.
      if (!motionPageStillOpen) await openToolPage(tester, 'Motion alarm');
      await pumpUntilAny(tester, [find.byType(LinearProgressIndicator), find.text('Retry')]);
      final loadingNow = find.byType(LinearProgressIndicator).evaluate().isNotEmpty;
      expect(find.textContaining('Sensitivity:'), findsNothing);
      // Let the 3 s connect timeout produce the error state (soft: loading is also acceptable).
      var errored = false;
      try {
        await pumpUntil(tester, find.text('Retry'), timeout: const Duration(seconds: 15));
        errored = true;
      } on TestFailure {
        errored = false;
      }
      expect(find.textContaining('Sensitivity:'), findsNothing, reason: "phone's motion config shown for the unreachable server");
      if (phoneServerUrl.isNotEmpty) {
        expect(find.byWidgetPredicate((w) => w is EditableText && w.controller.text == phoneServerUrl && phoneServerUrl != 'https://ntfy.sh'), findsNothing);
      }
      final snapSecond = await snap(tester, _group, 'T20i-3');
      expect(adapter.log.any((u) => u.host == offlineServer.host && u.path == '/motion'), isTrue, reason: 'app asked the unreachable server for /motion');
      expect(adapter.blocked, isEmpty);

      check(
        'T20i',
        'PASS',
        'phone Motion alarm loaded ($snapBefore); after switching to "Unreachable": $landing, no phone config ($snapAfter); '
            'Motion alarm for 192.0.2.1 shows ${errored ? 'error + Retry' : (loadingNow ? 'loading' : 'error')} ($snapSecond)',
      );
    } catch (e) {
      check('T20i', 'FAIL', '$e');
      rethrow;
    }
  });
}

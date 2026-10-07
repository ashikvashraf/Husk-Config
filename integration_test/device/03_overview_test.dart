// ignore_for_file: file_names, avoid_print
// Device checklist S07, S08, S09, S09b: the Overview tab against the REAL phone.
// Run later with: flutter test integration_test/device/03_overview_test.dart -d macos
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/api/husk_api.dart';
import 'package:huskconfig/shared/widgets/section_card.dart';

import 'support/device_harness.dart';

const String _group = '03_overview_test';
const Size _window = Size(1600, 1300);

void main() {
  initDeviceHarness();
  final probe = PhoneProbe();

  // Every test leaves the phone on its home screen.
  tearDown(() async {
    try {
      await probe.home();
    } catch (e) {
      print('TEARDOWN home failed: $e');
    }
  });

  testWidgets('S07 Overview cards load real data matching /info /battery /display /connectivity', (tester) async {
    await _item('S07', () async {
      final info = await tester.runAsync(() => probe.getJson('/info')) as Map<String, dynamic>;
      final device = info['device'] as Map<String, dynamic>;
      final expectedModel = [device['manufacturer'], device['model']].where((s) => s != null && '$s'.isNotEmpty).join(' ');
      final expectedAndroid = '${device['androidRelease']} (SDK ${device['sdkInt'] ?? '?'})';

      final adapter = await _openOverview(tester);
      // Wait for every card that is compared (each loads independently).
      for (final label in ['Model', 'Level', 'Resolution', 'Type']) {
        await pumpUntil(tester, _infoRow(label));
      }
      // Location: either a position or the phone's ERR message.
      final locationCard = find.ancestor(of: find.text('Location'), matching: find.byType(Card));
      final positionRow = _infoRow('Position');
      final errText = find.descendant(
        of: locationCard,
        matching: find.byWidgetPredicate((w) => w is Text && (w.data ?? '').trim().startsWith('ERR')),
      );
      await pumpUntil(
        tester,
        find.byWidgetPredicate(
          (w) => (w is InfoRow && w.label == 'Position') || (w is Text && (w.data ?? '').trim().startsWith('ERR')),
          description: 'Location Position row or ERR text',
        ),
      );

      // Read-only GETs straight from the phone, after the app has loaded.
      final battery = await tester.runAsync(() => probe.getJson('/battery')) as Map<String, dynamic>;
      final display = await tester.runAsync(() => probe.getJson('/display')) as Map<String, dynamic>;
      final connectivity = await tester.runAsync(() => probe.getJson('/connectivity')) as Map<String, dynamic>;
      final locationProbe = (await tester.runAsync(() => probe.getText('/location')))!.trim();

      _expectRow(tester, 'Model', expectedModel);
      _expectRow(tester, 'Android', expectedAndroid);

      final shownLevel = int.parse(RegExp(r'\d+').firstMatch(_rowValue(tester, 'Level'))!.group(0)!);
      final probeLevel = (battery['level'] as num).toInt();
      expect((shownLevel - probeLevel).abs(), lessThanOrEqualTo(2), reason: 'battery level shown $shownLevel vs /battery $probeLevel');

      _expectRow(tester, 'Resolution', '${display['width']} × ${display['height']}');
      _expectRow(tester, 'Type', '${connectivity['type']}');

      var locationShown = '';
      if (positionRow.evaluate().isNotEmpty) {
        locationShown = 'position ${_rowValue(tester, 'Position')}';
      } else {
        final shown = tester.widgetList<Text>(errText).map((t) => t.data!.trim()).first;
        locationShown = 'ERR "$shown"';
        if (locationProbe.startsWith('ERR')) {
          expect(shown, locationProbe, reason: 'Location card text must be the phone ERR message verbatim');
        }
      }
      expect(positionRow.evaluate().isNotEmpty || errText.evaluate().isNotEmpty, isTrue, reason: 'Location shows neither a position nor an ERR message');

      await snap(tester, _group, 'S07-1');
      await tester.ensureVisible(locationCard.first);
      await tester.pump(const Duration(milliseconds: 100));
      final path = await snap(tester, _group, 'S07-2');
      expect(adapter.blocked, isEmpty);
      return 'model="$expectedModel" android="$expectedAndroid" battery=$shownLevel%(probe $probeLevel%) '
          'display=${display['width']}x${display['height']} connectivity=${connectivity['type']} '
          'location=$locationShown (probe: ${locationProbe.length > 70 ? locationProbe.substring(0, 70) : locationProbe}); $path';
    });
  });

  testWidgets('S08 Wake, vibrate 300 ms and torch on then off reply OK in a snackbar; torch ends OFF', (tester) async {
    addTearDown(() => _restorePhone(torchOff: true));
    await _item('S08', () async {
      final adapter = await _openOverview(tester);
      final wakeBtn = find.ancestor(of: find.byIcon(Icons.light_mode), matching: find.bySubtype<OutlinedButton>());
      final vibrateBtn = find.ancestor(of: find.byIcon(Icons.vibration), matching: find.bySubtype<OutlinedButton>());
      final torchTile = find.widgetWithText(SwitchListTile, 'Torch');
      await pumpUntil(tester, wakeBtn);
      await pumpUntil(tester, vibrateBtn);
      await pumpUntil(tester, torchTile);
      expect(tester.widget<TextField>(find.widgetWithText(TextField, '300')).controller!.text, '300', reason: 'vibrate default is 300 ms');

      // Wake
      final wake = await _snack(tester, () async {
        await tester.ensureVisible(wakeBtn);
        await tester.tap(wakeBtn);
      });
      expect(wake.isError, isFalse, reason: 'wake replied: ${wake.text}');
      expect(adapter.count('/wake'), 1);
      final snapPath = await snap(tester, _group, 'S08-1');
      _clearSnacks(tester);

      // Vibrate 300 ms
      final vib = await _snack(tester, () async {
        await tester.ensureVisible(vibrateBtn);
        await tester.tap(vibrateBtn);
      });
      expect(vib.isError, isFalse, reason: 'vibrate replied: ${vib.text}');
      expect(adapter.log.where((u) => u.path == '/vibrate' && u.queryParameters['ms'] == '300'), hasLength(1));
      await snap(tester, _group, 'S08-2');
      _clearSnacks(tester);

      // Torch on
      final on = await _snack(tester, () async {
        await tester.ensureVisible(torchTile);
        await tester.tap(torchTile);
      });
      await snap(tester, _group, 'S08-3');
      _clearSnacks(tester);
      if (on.isError) {
        // Handled-correctly: the phone's ERR (e.g. camera busy) is shown to the user and the switch stays off.
        expect(on.text.startsWith('ERR'), isTrue, reason: 'torch error snackbar should show the phone ERR: ${on.text}');
        expect(tester.widget<SwitchListTile>(torchTile).value, isFalse, reason: 'switch must stay off after a torch ERR');
        expect(adapter.blocked, isEmpty);
        return 'wake="${wake.text}" vibrate="${vib.text}" torch-on ERR shown to user (handled correctly, torch never lit): "${on.text}"; torch ends OFF (teardown sends on=0); $snapPath';
      }
      expect(tester.widget<SwitchListTile>(torchTile).value, isTrue, reason: 'switch should be on after OK reply "${on.text}"');

      // Torch off
      final off = await _snack(tester, () async {
        await tester.tap(torchTile);
      });
      expect(off.isError, isFalse, reason: 'torch off replied: ${off.text}');
      expect(tester.widget<SwitchListTile>(torchTile).value, isFalse, reason: 'torch must end OFF');
      await snap(tester, _group, 'S08-4');
      expect(adapter.log.where((u) => u.path == '/torch').map((u) => u.queryParameters['on']).toList(), ['1', '0']);
      expect(adapter.blocked, isEmpty);
      return 'wake="${wake.text}" vibrate300="${vib.text}" torch-on="${on.text}" torch-off="${off.text}"; switch ends OFF; $snapPath';
    });
  });

  testWidgets('S09 Brightness slider changes /brightness level (or shows WRITE_SETTINGS hint); original restored', (tester) async {
    final original = await tester.runAsync(() => probe.getJson('/brightness')) as Map<String, dynamic>;
    final origLevel = (original['level'] as num).toInt();
    final maxLevel = (original['max'] as num).toInt();
    final origAuto = original['auto'] == true;
    addTearDown(() => _restorePhone(brightness: origLevel));
    await _item('S09', () async {
      // Never go near 0 (dark screen): move by 40 towards the middle.
      final target = origLevel < maxLevel ~/ 2 ? origLevel + 40 : origLevel - 40;
      final adapter = await _openOverview(tester);
      final sliderFinder = find.byWidgetPredicate((w) => w is Slider && w.max == maxLevel.toDouble(), description: 'brightness Slider (max $maxLevel)');
      await pumpUntil(tester, sliderFinder);
      await tester.ensureVisible(sliderFinder);
      await tester.pump(const Duration(milliseconds: 100));

      // Drive the slider exactly like a drag (onChanged then onChangeEnd on release).
      final set = await _snack(tester, () async {
        final s = tester.widget<Slider>(sliderFinder);
        s.onChanged!(target.toDouble());
        await tester.pump(const Duration(milliseconds: 100));
        tester.widget<Slider>(sliderFinder).onChangeEnd!(target.toDouble());
      });
      final snapPath = await snap(tester, _group, 'S09-1');
      _clearSnacks(tester);
      await pumpFor(tester, const Duration(milliseconds: 500));

      final after = await tester.runAsync(() => probe.getJson('/brightness')) as Map<String, dynamic>;
      final afterLevel = (after['level'] as num).toInt();
      final afterAuto = after['auto'] == true;
      String outcome;
      if (afterLevel == target) {
        expect(set.isError, isFalse, reason: 'level changed but snackbar was an error: ${set.text}');
        outcome = 'level $origLevel -> $afterLevel confirmed by GET /brightness';
      } else if (set.text.contains('WRITE_SETTINGS') && set.text.contains('Modify system settings')) {
        outcome = 'phone replied WRITE_SETTINGS; app showed the hint "${set.text.replaceAll('\n', ' ')}"; level unchanged $afterLevel';
      } else {
        fail('level after set = $afterLevel (expected $target); snackbar="${set.text}"');
      }

      // Restore the exact original level (through the app slider), verify with a GET.
      var restoredVia = 'not needed';
      if (afterLevel != origLevel) {
        await pumpUntil(tester, sliderFinder);
        final restore = await _snack(tester, () async {
          tester.widget<Slider>(sliderFinder).onChanged!(origLevel.toDouble());
          await tester.pump(const Duration(milliseconds: 100));
          tester.widget<Slider>(sliderFinder).onChangeEnd!(origLevel.toDouble());
        });
        _clearSnacks(tester);
        await pumpFor(tester, const Duration(milliseconds: 500));
        restoredVia = 'app slider, reply "${restore.text}"';
      }
      final finalState = await tester.runAsync(() => probe.getJson('/brightness')) as Map<String, dynamic>;
      expect((finalState['level'] as num).toInt(), origLevel, reason: 'brightness not restored to the exact original level');
      await snap(tester, _group, 'S09-2');
      expect(adapter.blocked, isEmpty);
      return '$outcome; restored to exactly $origLevel ($restoredVia); auto before=$origAuto after-set=$afterAuto final=${finalState['auto']}'
          '${origAuto && !afterAuto ? ' (NOTE: setting a level DISABLED auto brightness; not re-enabled)' : ''}; $snapPath';
    });
  });

  testWidgets('S09b Sensors reading "light" shows values; Mic Sample shows an amplitude', (tester) async {
    await _item('S09b', () async {
      final light = await tester.runAsync(() => probe.getJson('/sensor', {'type': 'light'})) as Map<String, dynamic>;
      final sensorName = light['sensor'] as String;
      final probeValues = (light['values'] as List).length;
      final micProbe = await tester.runAsync(() => probe.getJson('/mic')) as Map<String, dynamic>;

      final adapter = await _openOverview(tester);
      final chip = find.widgetWithText(ChoiceChip, 'light');
      await pumpUntil(tester, chip);
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      final reading = find.byWidgetPredicate(
        (w) => w is Text && RegExp('^${RegExp.escape(sensorName)}: -?\\d').hasMatch(w.data ?? ''),
        description: 'sensor reading text "$sensorName: <values>"',
      );
      await pumpUntil(tester, reading);
      final readingText = tester.widget<Text>(reading.first).data!;
      final shownValues = readingText.substring(sensorName.length + 2).split(', ');
      expect(shownValues, hasLength(probeValues), reason: 'value count in "$readingText"');
      for (final v in shownValues) {
        expect(double.tryParse(v), isNotNull, reason: '"$v" is not a number');
      }
      final snapPath1 = await snap(tester, _group, 'S09b-1');

      final sample = find.widgetWithText(OutlinedButton, 'Sample');
      await pumpUntil(tester, sample);
      await tester.ensureVisible(sample);
      await tester.tap(sample);
      final amp = find.byWidgetPredicate((w) => w is Text && RegExp(r'^\d+ / \d+$').hasMatch((w.data ?? '').trim()), description: 'mic amplitude "<n> / <max>"');
      await pumpUntil(tester, amp);
      final ampText = tester.widget<Text>(amp.first).data!.trim();
      expect(ampText.split(' / ').last, '${micProbe['max']}', reason: 'mic max shown vs /mic');
      await snap(tester, _group, 'S09b-2');
      expect(adapter.blocked, isEmpty);
      return 'light reading "$readingText" (probe $light); mic amplitude "$ampText" (probe amplitude=${micProbe['amplitude']}); $snapPath1';
    });
  });
}

// ---------------------------------------------------------------- Helpers

/// Runs [body]; prints `CHECK <id> PASS <evidence>` or `CHECK <id> FAIL <error>` (then rethrows).
Future<void> _item(String id, Future<String> Function() body) async {
  try {
    check(id, 'PASS', await body());
  } catch (e) {
    check(id, 'FAIL', '$e');
    rethrow;
  }
}

/// Launches the app with the real phone saved and opens its Overview tab.
Future<CountingAdapter> _openOverview(WidgetTester tester) async {
  final adapter = await pumpHuskApp(tester, servers: [phoneServer], windowSize: _window);
  await pumpUntil(tester, find.text('Test phone'));
  await tester.tap(find.text('Test phone').first);
  await pumpUntil(tester, find.text('Quick controls'));
  return adapter;
}

Finder _infoRow(String label) => find.byWidgetPredicate((w) => w is InfoRow && w.label == label, description: 'InfoRow "$label"');

String _rowValue(WidgetTester tester, String label) => tester.widget<InfoRow>(_infoRow(label).first).value;

/// The row exists, holds [expected], and the text is actually rendered.
void _expectRow(WidgetTester tester, String label, String expected) {
  expect(_rowValue(tester, label), expected, reason: 'Overview row "$label"');
  expect(find.descendant(of: _infoRow(label).first, matching: find.text(expected)), findsOneWidget, reason: 'row "$label" renders "$expected"');
}

({String text, bool isError}) _readSnack(WidgetTester tester) {
  final bar = tester.widget<SnackBar>(find.byType(SnackBar).first);
  final text = tester
      .widgetList<Text>(find.descendant(of: find.byType(SnackBar).first, matching: find.byType(Text)))
      .map((t) => t.data ?? '')
      .join('\n');
  // runCommand colours ERR replies and thrown errors with the error colour.
  return (text: text, isError: bar.backgroundColor != null || text.startsWith('ERR'));
}

void _clearSnacks(WidgetTester tester) =>
    ScaffoldMessenger.of(tester.element(find.byType(Scaffold).first)).clearSnackBars();

/// Runs [act] with no snackbar showing, waits for the app's snackbar and returns its text.
Future<({String text, bool isError})> _snack(WidgetTester tester, Future<void> Function() act) async {
  _clearSnacks(tester);
  // clearSnackBars animates the current bar out (~250 ms); wait for it to go.
  final gone = Stopwatch()..start();
  do {
    await tester.pump(const Duration(milliseconds: 100));
  } while (find.byType(SnackBar).evaluate().isNotEmpty && gone.elapsed < const Duration(seconds: 3));
  expect(find.byType(SnackBar), findsNothing, reason: 'previous snackbar still showing');
  await act();
  await pumpUntil(tester, find.byType(SnackBar), timeout: const Duration(seconds: 15));
  await tester.pump(const Duration(milliseconds: 300));
  final r = _readSnack(tester);
  print('SNACKBAR ${r.isError ? 'ERROR ' : ''}${r.text.replaceAll('\n', ' | ')}');
  return r;
}

/// Teardown safety net: torch off and/or restore the exact brightness level.
Future<void> _restorePhone({bool torchOff = false, int? brightness}) async {
  final api = HuskApi(baseUrl: phoneServer.baseUrl, adapter: CountingAdapter());
  try {
    if (torchOff) print('TEARDOWN torch off: ${await api.torch(on: false)}');
    if (brightness != null) {
      final now = await api.brightness();
      if (now.level != brightness) {
        print('TEARDOWN brightness ${now.level} -> $brightness: ${await api.setBrightness(brightness)}');
      }
    }
  } catch (e) {
    print('TEARDOWN RESTORE FAILED: $e');
  } finally {
    api.close();
  }
}

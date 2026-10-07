// ignore_for_file: file_names, avoid_print
// Device checklist section S: servers (S01 empty dashboard, S02 add by IP,
// S03 LAN scan, S04 dashboard card + unreachable server).
//
// Run (one flutter macOS run at a time):
//   flutter test integration_test/device/01_servers_test.dart -d macos
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/device_harness.dart';

const String _group = '01_servers';

void main() {
  initDeviceHarness();
  final probe = PhoneProbe();

  // Nothing here drives the phone, but the checklist wants every test to end
  // with the phone on Home.
  tearDown(() async {
    try {
      await probe.home();
    } catch (e) {
      print('TEARDOWN home failed: $e');
    }
  });

  /// Runs [body]; prints CHECK <id> PASS <evidence> on success, or
  /// CHECK <id> FAIL <error> and rethrows.
  Future<void> guarded(String id, Future<String> Function() body) async {
    try {
      check(id, 'PASS', await body());
    } on Object catch (e) {
      check(id, 'FAIL', e.toString());
      rethrow;
    }
  }

  Future<Map<String, dynamic>> readInfo(WidgetTester tester) async =>
      (await tester.runAsync(() => probe.getJson('/info')))! as Map<String, dynamic>;

  String displayNameOf(Map<String, dynamic> info) {
    final d = info['device'] as Map<String, dynamic>;
    return [d['manufacturer'], d['model']].where((s) => s != null && '$s'.isNotEmpty).join(' ');
  }

  /// enterText that also works when [field] is already the binding's
  /// focusedEditable: showKeyboard is then a no-op and the text would go to a
  /// stale input connection, so clear it first. Verifies the field took the text.
  Future<void> typeInto(WidgetTester tester, Finder field, String text) async {
    tester.binding.focusedEditable = null;
    await tester.enterText(field, text);
    final shown = tester.widget<EditableText>(find.descendant(of: field, matching: find.byType(EditableText))).controller.text;
    expect(shown, text, reason: 'typing into $field');
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.tap(find.text(text));
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('S01 Launch with no servers shows the empty dashboard (Add server / Scan network)', (tester) async {
    await guarded('S01', () async {
      final adapter = await pumpHuskApp(tester);
      await pumpUntil(tester, find.text('No Husk servers yet'));
      expect(find.text('Add server'), findsOneWidget);
      expect(find.text('Scan network'), findsOneWidget);
      expect(find.text('Husk Config'), findsOneWidget);
      expect(find.byTooltip('Server actions'), findsNothing);
      await pumpFor(tester, const Duration(seconds: 1));
      expect(adapter.log, isEmpty, reason: 'no servers saved, so the app must not call any phone');
      final path = await snap(tester, _group, 'S01-1');
      return 'empty dashboard shows "No Husk servers yet" with Add server and Scan network buttons, 0 requests; $path';
    });
  });

  testWidgets('S02 Add server by IP, hostname rejected, Test connection shows the model', (tester) async {
    await guarded('S02', () async {
      final info = await readInfo(tester);
      final model = displayNameOf(info);
      final device = info['device'] as Map<String, dynamic>;
      final expectedResult =
          'Connected: $model, Android ${device['androidRelease']}, Husk ${(info['app'] as Map<String, dynamic>)['versionName']}';
      expect(model, 'samsung SM-A750F', reason: 'checklist expects the test phone to be samsung SM-A750F (/info says "$model")');

      final adapter = await pumpHuskApp(tester);
      await pumpUntil(tester, find.text('No Husk servers yet'));
      await tapText(tester, 'Add server');
      await pumpUntil(tester, find.text('Test connection'));
      expect(find.text('Add server'), findsOneWidget, reason: 'form title');

      final hostField = find.widgetWithText(TextFormField, 'IP address');
      final portField = find.widgetWithText(TextFormField, 'Port');
      expect(hostField, findsOneWidget);
      expect(portField, findsOneWidget);

      // A hostname is rejected by both Save and Test connection.
      const hostnameError = 'Husk only accepts IP addresses (e.g. 192.168.0.106)';
      await typeInto(tester, hostField, 'phone.local');
      await tester.pump(const Duration(milliseconds: 100));
      await tapText(tester, 'Save');
      await pumpUntil(tester, find.text(hostnameError));
      await snap(tester, _group, 'S02-1');
      await tapText(tester, 'Test connection');
      await pumpFor(tester, const Duration(milliseconds: 500));
      expect(find.text(hostnameError), findsOneWidget);
      expect(find.textContaining('Connected:'), findsNothing);
      expect(find.text('Test connection'), findsOneWidget, reason: 'still on the form, nothing saved');

      // The real IP is accepted and Test connection shows the model.
      await typeInto(tester, hostField, phoneHost);
      await typeInto(tester, portField, '$phonePort');
      await tester.pump(const Duration(milliseconds: 100));
      await tapText(tester, 'Test connection');
      try {
        await pumpUntil(tester, find.textContaining('Connected:'), timeout: const Duration(seconds: 15));
      } on TestFailure {
        final texts = find.byType(Text).evaluate().map((e) => (e.widget as Text).data).whereType<String>().toList();
        print('S02 DIAG visible texts: $texts');
        await snap(tester, _group, 'S02-diag');
        rethrow;
      }
      expect(find.text(expectedResult), findsOneWidget, reason: 'Test connection result must match /info');
      final testPath = await snap(tester, _group, 'S02-2');

      // Save with the Name left empty: the detected model becomes the name.
      await tapText(tester, 'Save');
      await pumpUntil(tester, find.text(model));
      expect(find.byTooltip('Server actions'), findsOneWidget, reason: 'exactly one server saved (the hostname was not)');
      expect(find.text(phoneAddress), findsOneWidget);
      await pumpUntil(tester, find.textContaining('$model · Android'), timeout: const Duration(seconds: 15));
      final savedPath = await snap(tester, _group, 'S02-3');
      expect(adapter.blocked, isEmpty);
      return 'hostname "phone.local" rejected ("$hostnameError") on Save and Test; $phoneAddress accepted; '
          'Test connection showed "$expectedResult" (matches GET /info); saved as "$model" on dashboard; $testPath $savedPath';
    });
  });

  testWidgets(
    'S03 LAN scan finds the phone and marks it Saved',
    timeout: const Timeout(Duration(minutes: 4)),
    (tester) async {
      await guarded('S03', () async {
        final info = await readInfo(tester);
        final model = displayNameOf(info);
        final prefix = phoneHost.split('.').take(3).join('.');

        await pumpHuskApp(tester, servers: [phoneServer]);
        await pumpUntil(tester, find.text('Test phone'));
        await tester.tap(find.byTooltip('Scan network'));
        await pumpUntil(tester, find.text('Start scan'));
        // Give network_info_plus time to report the Wi-Fi IP.
        await pumpFor(tester, const Duration(seconds: 2));

        final subnetField = find.widgetWithText(TextField, 'Subnet');
        final portField = find.widgetWithText(TextField, 'Port');
        expect(subnetField, findsOneWidget);
        final detected = find.textContaining('This device:').evaluate().isNotEmpty;
        final prefilled = tester.widget<TextField>(subnetField).controller!.text.trim();
        final notes = <String>[];
        if (detected && prefilled == prefix) {
          notes.add('Wi-Fi IP auto-detected, subnet prefilled as $prefilled');
        } else {
          notes.add(detected
              ? 'Wi-Fi IP detected but subnet "$prefilled" differs from phone subnet, typed $prefix'
              : 'NOTE Wi-Fi IP not detected on macOS, typed subnet $prefix');
          await typeInto(tester, subnetField, prefix);
        }
        if (tester.widget<TextField>(portField).controller!.text.trim() != '$phonePort') {
          await typeInto(tester, portField, '$phonePort');
        }
        await tester.pump(const Duration(milliseconds: 100));

        await tapText(tester, 'Start scan');
        await pumpUntil(tester, find.text(phoneHost), timeout: const Duration(seconds: 60));
        // The tile resolves the model through /info and shows the Saved chip.
        await pumpUntil(tester, find.text(model), timeout: const Duration(seconds: 20));
        expect(find.text('Saved'), findsOneWidget, reason: 'the phone is already saved so its tile must be marked Saved');
        final tile = find.widgetWithText(ListTile, phoneHost);
        expect(tile, findsOneWidget);
        expect(find.descendant(of: tile, matching: find.text('Saved')), findsOneWidget);
        // Let the scan run to the end so the progress line is final.
        await pumpUntil(tester, find.text('Start scan'), timeout: const Duration(seconds: 90));
        expect(find.textContaining(RegExp(r'Checked \d+ of \d+')), findsOneWidget);
        expect(find.text('Stop'), findsNothing);
        final progress = (tester.widget<Text>(find.textContaining(RegExp(r'Checked \d+ of \d+'))).data) ?? '';
        final path = await snap(tester, _group, 'S03-1');
        return 'scan of $prefix.0/24 found $phoneHost, tile "$model" marked Saved; $progress; ${notes.join('; ')}; $path';
      });
    },
  );

  testWidgets('S04 Dashboard card shows real status; an unreachable second server shows Offline with a reason', (tester) async {
    await guarded('S04', () async {
      final before = await readInfo(tester);
      final model = displayNameOf(before);
      final release = (before['device'] as Map<String, dynamic>)['androidRelease'];

      final adapter = await pumpHuskApp(tester, servers: [phoneServer, offlineServer]);
      await pumpUntil(tester, find.text('Test phone'));
      await pumpUntil(tester, find.text('Unreachable'));

      // Online card: model, Android release, battery, services.
      await pumpUntil(tester, find.text('$model · Android $release'), timeout: const Duration(seconds: 15));
      final batteryText = find.byWidgetPredicate((w) => w is Text && RegExp(r'^\d+%$').hasMatch(w.data ?? ''));
      await pumpUntil(tester, batteryText);
      expect(batteryText, findsOneWidget);
      final shownBattery = int.parse((tester.widget<Text>(batteryText).data!).replaceAll('%', ''));
      final after = await readInfo(tester);
      final levels = {
        (before['battery'] as Map<String, dynamic>)['level'] as int,
        (after['battery'] as Map<String, dynamic>)['level'] as int,
      };
      expect(levels.contains(shownBattery), isTrue, reason: 'card battery $shownBattery% vs /info $levels');
      final charging = (after['battery'] as Map<String, dynamic>)['charging'] as bool;
      expect(find.byIcon(charging ? Icons.battery_charging_full : Icons.battery_std), findsOneWidget,
          reason: 'battery icon must match charging=$charging');
      expect(find.textContaining('Checked '), findsOneWidget);

      final services = after['services'] as Map<String, dynamic>;
      final scheme = Theme.of(tester.element(find.text('a11y'))).colorScheme;
      final serviceSummary = <String>[];
      for (final label in ['a11y', 'camera', 'screen']) {
        final container = tester.widget<Container>(find.ancestor(of: find.text(label), matching: find.byType(Container)).first);
        final color = (container.decoration! as BoxDecoration).color;
        final shownOn = color == scheme.primaryContainer;
        expect(shownOn || color == scheme.surfaceContainerHighest, isTrue, reason: 'unexpected chip color for $label');
        expect(shownOn, services[label] as bool, reason: 'service chip $label on/off must match /info services.$label');
        serviceSummary.add('$label=${services[label]}');
      }

      // Offline card: unreachable TEST-NET server shows Offline plus a reason.
      await pumpUntil(tester, find.text('Offline'), timeout: const Duration(seconds: 25));
      final reason = "Can't reach ${offlineServer.host}:${offlineServer.port}";
      await pumpUntil(tester, find.text(reason));
      expect(find.byTooltip('Online'), findsOneWidget);
      expect(find.byTooltip('Offline'), findsOneWidget);
      expect(find.text('Offline'), findsOneWidget);
      final path = await snap(tester, _group, 'S04-1');
      expect(adapter.blocked, isEmpty);
      return 'phone card online "$model · Android $release", battery $shownBattery% (/info $levels, charging=$charging), '
          'services ${serviceSummary.join(' ')} match /info; second server ${offlineServer.host} (TEST-NET, unreachable) '
          'shows Offline with reason "$reason" (replaces the human-only "turn phone Wi-Fi off" step); $path';
    });
  });
}

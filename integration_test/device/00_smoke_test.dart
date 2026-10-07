// ignore_for_file: file_names
import 'package:flutter_test/flutter_test.dart';

import 'support/device_harness.dart';

void main() {
  initDeviceHarness();
  final probe = PhoneProbe();

  tearDown(() async {
    await probe.home();
  });

  testWidgets('H00 app launches with no servers', (tester) async {
    await pumpHuskApp(tester);
    await pumpUntil(tester, find.text('No Husk servers yet'));
    final path = await snap(tester, 'smoke', 'empty_dashboard');
    check('H00', 'PASS', 'empty dashboard shows "No Husk servers yet"; $path');
  });

  testWidgets('H01 phone card shows the real model from /info', (tester) async {
    final info = await tester.runAsync(() => probe.getJson('/info')) as Map<String, dynamic>;
    final model = (info['device'] as Map<String, dynamic>)['model'] as String;
    final adapter = await pumpHuskApp(tester, servers: [phoneServer]);
    await pumpUntil(tester, find.textContaining(model));
    await pumpUntil(tester, find.text('Test phone'));
    final path = await snap(tester, 'smoke', 'phone_card');
    check('H01', 'PASS', 'card shows "$model" from GET /info; app /info requests=${adapter.count('/info')}; $path');
    expect(adapter.blocked, isEmpty);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/net/lan_scanner.dart';
import 'package:huskconfig/features/servers/scan_screen.dart';

import '../../support/fixtures.dart';
import '../../support/test_app.dart';

void main() {
  Future<void> pump(WidgetTester tester, {String? wifiIp}) async {
    await tester.pumpWidget(testScope(
      servers: [server1],
      overrides: [
        lanScannerProvider.overrideWithValue(LanScanner(probe: (host, port) async => host.endsWith('.106') || host.endsWith('.7'))),
        wifiIpProvider.overrideWith((ref) async => wifiIp),
        scanDeviceNameProvider.overrideWith((ref, target) async => 'samsung SM-A750F'),
      ],
      child: const MaterialApp(home: ScanScreen()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('prefills the subnet and lists found devices, marking saved ones', (tester) async {
    await pump(tester, wifiIp: '192.168.0.20');
    expect(find.widgetWithText(TextField, '192.168.0'), findsOneWidget);
    await tester.tap(find.text('Start scan'));
    await tester.pumpAndSettle();
    expect(find.text('192.168.0.106'), findsOneWidget);
    expect(find.text('192.168.0.7'), findsOneWidget);
    expect(find.text('samsung SM-A750F'), findsNWidgets(2));
    expect(find.text('Saved'), findsOneWidget);
    expect(find.text('Checked 253 of 253'), findsOneWidget);
  });

  testWidgets('without a Wi-Fi address asks for a subnet', (tester) async {
    await pump(tester);
    expect(find.textContaining('Could not detect'), findsOneWidget);
    await tester.tap(find.text('Start scan'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a subnet like 192.168.0 and a valid port.'), findsOneWidget);
  });
}

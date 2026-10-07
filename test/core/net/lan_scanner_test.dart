import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/net/lan_scanner.dart';

void main() {
  test('prefixOf takes the first three IPv4 octets', () {
    expect(LanScanner.prefixOf('192.168.0.106'), '192.168.0');
    expect(LanScanner.prefixOf('fd7a::1'), isNull);
    expect(LanScanner.prefixOf(null), isNull);
    expect(LanScanner.prefixOf('nonsense'), isNull);
  });

  test('isValidPrefix', () {
    expect(LanScanner.isValidPrefix('192.168.0'), isTrue);
    expect(LanScanner.isValidPrefix(' 10.0.5 '), isTrue);
    expect(LanScanner.isValidPrefix('192.168'), isFalse);
    expect(LanScanner.isValidPrefix('192.168.256'), isFalse);
    expect(LanScanner.isValidPrefix('a.b.c'), isFalse);
  });

  test('finds matching hosts, skips the excluded one, and reports progress to the end', () async {
    final probed = <String>[];
    final scanner = LanScanner(probe: (host, port) async {
      probed.add('$host:$port');
      return host == '192.168.0.106' || host == '192.168.0.7';
    });
    final events = await scanner.scan(prefix: '192.168.0', port: 8090, excludeHost: '192.168.0.50').toList();
    expect(events.whereType<ScanFound>().map((e) => e.host).toSet(), {'192.168.0.106', '192.168.0.7'});
    final last = events.whereType<ScanProgress>().last;
    expect((last.done, last.total), (253, 253));
    expect(probed, isNot(contains('192.168.0.50:8090')));
    expect(probed, contains('192.168.0.1:8090'));
    expect(probed, contains('192.168.0.254:8090'));
  });

  test('a throwing probe counts as no match', () async {
    final scanner = LanScanner(probe: (host, port) async => throw StateError('boom'));
    final events = await scanner.scan(prefix: '10.0.0', port: 8090).toList();
    expect(events.whereType<ScanFound>(), isEmpty);
    expect(events.whereType<ScanProgress>().last.done, 254);
  });

  test('never exceeds the concurrency limit', () async {
    var inFlight = 0, maxInFlight = 0;
    final scanner = LanScanner(
      concurrency: 4,
      probe: (host, port) async {
        inFlight++;
        maxInFlight = inFlight > maxInFlight ? inFlight : maxInFlight;
        await Future<void>.delayed(Duration.zero);
        inFlight--;
        return false;
      },
    );
    await scanner.scan(prefix: '10.0.0', port: 8090).drain<void>();
    expect(maxInFlight, 4);
  });

  test('cancelling the subscription stops probing', () async {
    var calls = 0;
    final scanner = LanScanner(
      concurrency: 2,
      probe: (host, port) async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 1));
        return false;
      },
    );
    final sub = scanner.scan(prefix: '10.0.0', port: 8090).listen(null);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await sub.cancel();
    final callsAtCancel = calls;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(calls, lessThan(254));
    expect(calls, lessThanOrEqualTo(callsAtCancel + 2));
  });
}

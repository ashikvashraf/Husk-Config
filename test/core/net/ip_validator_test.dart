import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/net/ip_validator.dart';

void main() {
  group('isIpLiteral', () {
    test('accepts IPv4, IPv6 and bracketed IPv6, ignoring surrounding spaces', () {
      for (final ok in ['192.168.0.106', '100.100.101.101', '::1', 'fd7a:115c:a1e0::1', '[fd7a:115c:a1e0::1]', ' 10.0.0.1 ']) {
        expect(IpValidator.isIpLiteral(ok), isTrue, reason: ok);
      }
    });

    test('rejects hostnames, partial or out-of-range IPs, scoped IPv6 and empty input', () {
      for (final bad in ['phone.local', 'localhost', '192.168.0', '256.1.1.1', '1.2.3.4.5', 'fe80::1%en0', '', '   ', 'http://10.0.0.1']) {
        expect(IpValidator.isIpLiteral(bad), isFalse, reason: bad);
      }
    });
  });

  test('normalizeHost trims and strips IPv6 brackets', () {
    expect(IpValidator.normalizeHost(' [::1] '), '::1');
    expect(IpValidator.normalizeHost(' 10.0.0.1'), '10.0.0.1');
  });

  test('isValidPort boundaries', () {
    expect(IpValidator.isValidPort(null), isFalse);
    expect(IpValidator.isValidPort(0), isFalse);
    expect(IpValidator.isValidPort(1), isTrue);
    expect(IpValidator.isValidPort(65535), isTrue);
    expect(IpValidator.isValidPort(65536), isFalse);
  });

  test('baseUrl brackets IPv6 hosts', () {
    expect(IpValidator.baseUrl('192.168.0.106', 8090), 'http://192.168.0.106:8090');
    expect(IpValidator.baseUrl('fd7a::1', 8090), 'http://[fd7a::1]:8090');
    expect(IpValidator.authority('fd7a::1', 8090), '[fd7a::1]:8090');
  });
}

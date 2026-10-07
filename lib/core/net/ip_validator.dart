import 'dart:io';

/// Husk rejects requests whose Host header is not an IP literal, so every
/// server address in the app is validated and formatted here.
abstract final class IpValidator {
  /// Trims whitespace and strips surrounding IPv6 brackets.
  static String normalizeHost(String input) {
    final s = input.trim();
    if (s.length > 2 && s.startsWith('[') && s.endsWith(']')) {
      return s.substring(1, s.length - 1);
    }
    return s;
  }

  /// True for IPv4/IPv6 literals. Scoped IPv6 (`fe80::1%en0`) is rejected
  /// because the zone id cannot be expressed in a plain http URL.
  static bool isIpLiteral(String input) {
    final host = normalizeHost(input);
    if (host.isEmpty || host.contains('%')) return false;
    return InternetAddress.tryParse(host) != null;
  }

  static bool isValidPort(int? port) => port != null && port >= 1 && port <= 65535;

  /// `host:port`, with IPv6 hosts bracketed.
  static String authority(String host, int port) =>
      host.contains(':') ? '[$host]:$port' : '$host:$port';

  static String baseUrl(String host, int port) => 'http://${authority(host, port)}';
}

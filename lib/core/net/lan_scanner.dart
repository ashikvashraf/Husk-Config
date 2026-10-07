import 'dart:async';

import '../api/husk_api.dart';
import '../api/husk_exception.dart';
import 'ip_validator.dart';

typedef HostProbe = Future<bool> Function(String host, int port);

sealed class ScanEvent {
  const ScanEvent();
}

final class ScanProgress extends ScanEvent {
  const ScanProgress(this.done, this.total);

  final int done;
  final int total;
}

final class ScanFound extends ScanEvent {
  const ScanFound(this.host);

  final String host;
}

/// Probes every host of a /24 for Husk's /healthz with bounded concurrency.
class LanScanner {
  LanScanner({HostProbe? probe, this.concurrency = 32}) : _probe = probe ?? defaultProbe;

  static final _prefixPattern = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})$');

  final int concurrency;
  final HostProbe _probe;

  /// "192.168.0" for "192.168.0.106"; null for IPv6, null or invalid input.
  static String? prefixOf(String? ipv4) {
    if (ipv4 == null || ipv4.contains(':') || !IpValidator.isIpLiteral(ipv4)) return null;
    return ipv4.trim().split('.').take(3).join('.');
  }

  static bool isValidPrefix(String prefix) {
    final match = _prefixPattern.firstMatch(prefix.trim());
    if (match == null) return false;
    return [1, 2, 3].every((g) => int.parse(match.group(g)!) <= 255);
  }

  static Future<bool> defaultProbe(String host, int port) async {
    final api = HuskApi(
      baseUrl: IpValidator.baseUrl(host, port),
      connectTimeout: const Duration(seconds: 1),
      receiveTimeout: const Duration(seconds: 1),
    );
    try {
      return await api.healthz();
    } on HuskException {
      return false;
    } finally {
      api.close();
    }
  }

  Stream<ScanEvent> scan({required String prefix, required int port, String? excludeHost}) {
    final base = prefix.trim();
    final hosts = [for (var i = 1; i <= 254; i++) '$base.$i']..remove(excludeHost);
    late final StreamController<ScanEvent> controller;
    var cancelled = false;
    var next = 0;
    var done = 0;

    Future<void> worker() async {
      while (!cancelled && next < hosts.length) {
        final host = hosts[next++];
        bool found;
        try {
          found = await _probe(host, port);
        } catch (_) {
          found = false; // A probe failure just means "not a Husk device".
        }
        if (cancelled) return;
        if (found) controller.add(ScanFound(host));
        controller.add(ScanProgress(++done, hosts.length));
      }
    }

    controller = StreamController<ScanEvent>(
      onListen: () async {
        await Future.wait([for (var i = 0; i < concurrency; i++) worker()]);
        if (!cancelled) await controller.close();
      },
      onCancel: () => cancelled = true,
    );
    return controller.stream;
  }
}

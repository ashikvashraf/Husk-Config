import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:network_info_plus/network_info_plus.dart';

import '../../core/api/husk_api.dart';
import '../../core/api/husk_exception.dart';
import '../../core/net/ip_validator.dart';
import '../../core/net/lan_scanner.dart';
import '../../core/storage/server_config.dart';
import 'servers_controller.dart';

final lanScannerProvider = Provider<LanScanner>((ref) => LanScanner());

/// This device's Wi-Fi IPv4, or null when unavailable (desktop on ethernet, VPN only…).
final wifiIpProvider = FutureProvider.autoDispose<String?>((ref) async {
  try {
    return await NetworkInfo().getWifiIP();
  } catch (_) {
    return null; // Treated as "unknown"; the user types the subnet instead.
  }
});

/// Model name of a found device; works only when no token is required.
final scanDeviceNameProvider = FutureProvider.autoDispose.family<String, ({String host, int port})>((ref, target) async {
  final api = HuskApi(
    baseUrl: IpValidator.baseUrl(target.host, target.port),
    connectTimeout: const Duration(seconds: 2),
    receiveTimeout: const Duration(seconds: 3),
  );
  ref.onDispose(api.close);
  try {
    return (await api.info()).displayName;
  } on UnauthorizedException {
    return 'Token required';
  } on HuskException {
    return 'Husk device';
  }
});

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final _prefix = TextEditingController();
  final _port = TextEditingController(text: '${ServerConfig.defaultPort}');
  final _found = <String>[];
  StreamSubscription<ScanEvent>? _subscription;
  String? _ownIp;
  String? _error;
  bool _running = false;
  int _done = 0;
  int _total = 0;
  int _scanPort = ServerConfig.defaultPort;

  @override
  void initState() {
    super.initState();
    ref.listenManual(wifiIpProvider, (previous, next) {
      final ip = next.value;
      final prefix = LanScanner.prefixOf(ip);
      setState(() => _ownIp = ip);
      if (prefix != null && _prefix.text.isEmpty) _prefix.text = prefix;
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _prefix.dispose();
    _port.dispose();
    super.dispose();
  }

  void _start() {
    final prefix = _prefix.text.trim();
    final port = int.tryParse(_port.text.trim());
    if (!LanScanner.isValidPrefix(prefix) || !IpValidator.isValidPort(port)) {
      setState(() => _error = 'Enter a subnet like 192.168.0 and a valid port.');
      return;
    }
    _subscription?.cancel();
    setState(() {
      _found.clear();
      _done = 0;
      _total = 0;
      _error = null;
      _running = true;
      _scanPort = port!;
    });
    _subscription = ref.read(lanScannerProvider).scan(prefix: prefix, port: port!, excludeHost: _ownIp).listen(
      (event) => setState(() {
        switch (event) {
          case ScanFound(:final host):
            _found.add(host);
          case ScanProgress(:final done, :final total):
            _done = done;
            _total = total;
        }
      }),
      onDone: () {
        if (mounted) setState(() => _running = false);
      },
    );
  }

  void _stop() {
    _subscription?.cancel();
    setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Scan network')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('Looks for Husk on every address of a /24 subnet by calling /healthz.'),
              const SizedBox(height: 16),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: TextField(
                    controller: _prefix,
                    decoration: InputDecoration(
                      labelText: 'Subnet',
                      hintText: '192.168.1',
                      helperText: _ownIp == null
                          ? 'Could not detect a Wi-Fi address. Type your subnet.'
                          : 'This device: $_ownIp',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 110,
                  child: TextField(controller: _port, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Port')),
                ),
              ]),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: _running ? _stop : _start,
                  icon: Icon(_running ? Icons.stop : Icons.search),
                  label: Text(_running ? 'Stop' : 'Start scan'),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
              if (_total > 0) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(value: _done / _total),
                const SizedBox(height: 4),
                Text('Checked $_done of $_total', style: theme.textTheme.bodySmall),
              ],
              if (!_running && _total > 0 && _found.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Text('No Husk devices found. Check the subnet and port, and that Husk is running on the phone.'),
                ),
              for (final host in _found) _FoundTile(host: host, port: _scanPort),
            ],
          ),
        ),
      ),
    );
  }
}

class _FoundTile extends ConsumerWidget {
  const _FoundTile({required this.host, required this.port});

  final String host;
  final int port;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(scanDeviceNameProvider((host: host, port: port)));
    final saved = ref.watch(serversProvider).any((s) => s.host == host && s.port == port);
    return ListTile(
      leading: const Icon(Icons.phone_android),
      title: Text(host),
      subtitle: Text(name.value ?? 'Identifying…'),
      trailing: saved ? const Chip(label: Text('Saved')) : const Icon(Icons.chevron_right),
      onTap: () => context.push(Uri(path: '/servers/new', queryParameters: {'host': host, 'port': '$port'}).toString()),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/husk_api.dart';
import '../../core/api/husk_exception.dart';
import '../../core/api/token_request_flow.dart';
import '../../core/net/ip_validator.dart';
import '../../core/storage/server_config.dart';
import '../../shared/widgets/confirm_dialog.dart';
import '../settings/settings_controller.dart';
import 'servers_controller.dart';
import 'token_request_dialog.dart';

class ServerFormScreen extends ConsumerStatefulWidget {
  const ServerFormScreen({super.key, this.serverId, this.initialHost, this.initialPort});

  final String? serverId;
  final String? initialHost;
  final int? initialPort;

  @override
  ConsumerState<ServerFormScreen> createState() => _ServerFormScreenState();
}

class _ServerFormScreenState extends ConsumerState<ServerFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _token;
  bool _showToken = false;
  bool _testing = false;
  bool _testOk = false;
  String? _testResult;
  String? _detectedName;

  ServerConfig? get _existing => widget.serverId == null ? null : ref.read(serversProvider.notifier).byId(widget.serverId!);

  @override
  void initState() {
    super.initState();
    final s = _existing;
    _name = TextEditingController(text: s?.name ?? '');
    _host = TextEditingController(text: s?.host ?? widget.initialHost ?? '');
    _port = TextEditingController(text: '${s?.port ?? widget.initialPort ?? ServerConfig.defaultPort}');
    _token = TextEditingController(text: s?.token ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _port.dispose();
    _token.dispose();
    super.dispose();
  }

  String? _validateHost(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return "Enter the phone's IP address";
    if (!IpValidator.isIpLiteral(text)) return 'Husk only accepts IP addresses (e.g. 192.168.0.106)';
    return null;
  }

  String? _validatePort(String? value) =>
      IpValidator.isValidPort(int.tryParse(value?.trim() ?? '')) ? null : 'Port must be 1–65535';

  String get _hostValue => IpValidator.normalizeHost(_host.text);
  int get _portValue => int.parse(_port.text.trim());

  /// A client for the address currently in the form, or null if it is invalid.
  HuskApi? _apiFromFields({required bool withToken}) {
    if (!(_formKey.currentState?.validate() ?? false)) return null;
    return HuskApi(baseUrl: IpValidator.baseUrl(_hostValue, _portValue), token: withToken ? _token.text.trim() : null);
  }

  Future<void> _test() async {
    final api = _apiFromFields(withToken: true);
    if (api == null) return;
    setState(() {
      _testing = true;
      _testResult = null;
    });
    String result;
    var ok = false;
    try {
      if (!await api.healthz()) throw const DeviceErrorException('This address answered, but it is not a Husk server.');
      final info = await api.info();
      _detectedName = info.displayName;
      result = 'Connected: ${info.displayName}, Android ${info.androidRelease}, Husk ${info.appVersionName}';
      ok = true;
    } on HuskException catch (e) {
      result = e.message;
    } finally {
      api.close();
    }
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testOk = ok;
      _testResult = result;
    });
  }

  Future<void> _requestToken() async {
    final api = _apiFromFields(withToken: false);
    if (api == null) return;
    final token = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => TokenRequestDialog(
        flow: TokenRequestFlow(api: api, clientName: ref.read(settingsProvider).tokenClientName),
      ),
    );
    api.close();
    if (token != null && mounted) setState(() => _token.text = token);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final host = _hostValue;
    final port = _portValue;
    final token = _token.text.trim();
    final controller = ref.read(serversProvider.notifier);
    if (controller.isDuplicate(host, port, exceptId: widget.serverId)) {
      final ok = await confirm(
        context,
        title: 'Duplicate address',
        message: 'A server with ${IpValidator.authority(host, port)} is already saved. Save anyway?',
        confirmLabel: 'Save anyway',
      );
      if (!ok) return;
    }
    final typedName = _name.text.trim();
    final name = typedName.isNotEmpty ? typedName : (_detectedName ?? host);
    final existing = _existing;
    if (existing == null) {
      await controller.add(name: name, host: host, port: port, token: token);
    } else {
      await controller.update(existing.copyWith(name: name, host: host, port: port, token: token, clearToken: token.isEmpty));
    }
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.serverId == null ? 'Add server' : 'Edit server')),
      body: Form(
        key: _formKey,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    helperText: 'Optional. Defaults to the phone model after a successful test.',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _host,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: 'IP address', hintText: '192.168.1.20'),
                  validator: _validateHost,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _port,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Port'),
                  validator: _validatePort,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _token,
                  obscureText: !_showToken,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'Token (optional)',
                    helperText: 'Only needed if a token is set on the phone.',
                    suffixIcon: IconButton(
                      tooltip: _showToken ? 'Hide token' : 'Show token',
                      icon: Icon(_showToken ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _showToken = !_showToken),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Wrap(spacing: 12, runSpacing: 12, children: [
                  OutlinedButton.icon(
                    onPressed: _testing ? null : _test,
                    icon: _testing
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.network_check),
                    label: const Text('Test connection'),
                  ),
                  OutlinedButton.icon(onPressed: _requestToken, icon: const Icon(Icons.key), label: const Text('Request token')),
                  FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save), label: const Text('Save')),
                ]),
                if (_testResult != null) ...[
                  const SizedBox(height: 16),
                  Text(_testResult!, style: TextStyle(color: _testOk ? scheme.primary : scheme.error)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

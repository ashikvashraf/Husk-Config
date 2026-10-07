import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/husk_exception.dart';
import '../../core/api/token_rules.dart';
import '../../shared/widgets/confirm_dialog.dart';
import '../../shared/widgets/result_box.dart';
import '../../shared/widgets/section_card.dart';
import '../servers/api_provider.dart';
import '../servers/servers_controller.dart';
import '../servers/token_request_dialog.dart';

class TokenTool extends ConsumerStatefulWidget {
  const TokenTool({super.key, required this.serverId});

  final String serverId;

  @override
  ConsumerState<TokenTool> createState() => _TokenToolState();
}

class _TokenToolState extends ConsumerState<TokenTool> {
  final _newToken = TextEditingController();
  bool _show = false;
  String? _message;
  bool _isError = false;

  @override
  void dispose() {
    _newToken.dispose();
    super.dispose();
  }

  void _report(String message, {bool error = false}) => setState(() {
        _message = message;
        _isError = error;
      });

  Future<void> _change() async {
    final token = _newToken.text.trim();
    if (!isValidNewToken(token)) {
      _report('The new token must be 24–128 letters and digits.', error: true);
      return;
    }
    final ok = await confirm(
      context,
      title: "Change the phone's token?",
      message: 'Every client using the old token, including other apps, loses access until it is updated.',
      confirmLabel: 'Change token',
    );
    if (!ok) return;
    final api = ref.read(apiProvider(widget.serverId));
    try {
      await api.setToken(token);
      try {
        await ref.read(serversProvider.notifier).setToken(widget.serverId, token);
      } catch (_) {
        // The phone already uses the new token: keep it in the field so the user can copy it.
        if (mounted) {
          _report('The phone now uses the new token but saving it failed. Copy it before leaving this page.', error: true);
        }
        return;
      }
      _newToken.clear();
      if (mounted) _report('Token changed and saved.');
    } on HttpStatusException catch (e) {
      if (!mounted) return;
      _report(
        switch (e.statusCode) {
          409 => 'No token is set on the phone. Use Request token instead.',
          400 => 'The phone rejected the new token: ${e.message}',
          _ => e.message,
        },
        error: true,
      );
    } on UnauthorizedException {
      if (mounted) _report('The current token is invalid. Request a new one first.', error: true);
    } on HuskException catch (e) {
      if (mounted) _report(e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final server = ref.watch(serverByIdProvider(widget.serverId));
    ref.watch(apiProvider(widget.serverId));
    if (server == null) return const SizedBox.shrink();
    return ListView(padding: const EdgeInsets.all(16), children: [
      SectionCard(
        title: 'Current token',
        icon: Icons.key,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(server.hasToken
              ? 'A token is saved for this server (${server.token!.length} characters).'
              : 'No token saved. The phone may not have one set.'),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => requestTokenForServer(context, ref, widget.serverId),
            icon: const Icon(Icons.key),
            label: const Text('Request token'),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      SectionCard(
        title: 'Change token',
        icon: Icons.autorenew,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Sets a new token on the phone. Requires the current token and takes effect immediately.'),
          TextField(
            controller: _newToken,
            obscureText: !_show,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'New token',
              helperText: '24–128 letters and digits.',
              suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  tooltip: _show ? 'Hide' : 'Show',
                  icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _show = !_show),
                ),
                IconButton(
                  tooltip: 'Generate',
                  icon: const Icon(Icons.casino),
                  onPressed: () => setState(() => _newToken.text = generateToken()),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: _change, child: const Text('Change token')),
          if (_message != null) ...[const SizedBox(height: 12), ResultBox(_message!, isError: _isError)],
        ]),
      ),
    ]);
  }
}

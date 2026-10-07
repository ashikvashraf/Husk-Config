import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/husk_api.dart';
import '../../core/api/token_request_flow.dart';
import '../settings/settings_controller.dart';
import 'servers_controller.dart';

/// Runs a [TokenRequestFlow]; pops with the token on approval.
class TokenRequestDialog extends StatefulWidget {
  const TokenRequestDialog({super.key, required this.flow});

  final TokenRequestFlow flow;

  @override
  State<TokenRequestDialog> createState() => _TokenRequestDialogState();
}

class _TokenRequestDialogState extends State<TokenRequestDialog> {
  late final StreamSubscription<TokenFlowState> _subscription;
  TokenFlowState _state = const TokenFlowRequesting();
  int? _initialSeconds;

  @override
  void initState() {
    super.initState();
    _subscription = widget.flow.run().listen((state) {
      if (!mounted) return;
      if (state is TokenFlowApproved) {
        Navigator.of(context).pop(state.token);
        return;
      }
      setState(() {
        _state = state;
        if (state is TokenFlowPending) _initialSeconds ??= state.secondsLeft;
      });
    });
  }

  @override
  void dispose() {
    widget.flow.cancel();
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Request access token'),
      content: SizedBox(
        width: 360,
        child: switch (_state) {
          TokenFlowRequesting() || TokenFlowApproved() => const Row(children: [
              SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 16),
              Expanded(child: Text('Sending the request to the phone…')),
            ]),
          TokenFlowPending(:final secondsLeft) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Approve the request on your phone.'),
                const SizedBox(height: 4),
                Text('Look for the notification "${widget.flow.clientName} asks for the access token".',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 16),
                LinearProgressIndicator(value: secondsLeft / (_initialSeconds ?? secondsLeft)),
                const SizedBox(height: 4),
                Text('Expires in ${secondsLeft}s'),
              ],
            ),
          TokenFlowDenied() => const Text('The request was denied on the phone.'),
          TokenFlowExpired() => const Text('The request expired before it was approved.'),
          TokenFlowFailed(:final message) => Text(message),
        },
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(_state.isTerminal ? 'Close' : 'Cancel')),
      ],
    );
  }
}

/// Requests a token for a saved server and stores it on approval.
/// /token/request is unauthenticated, so the current token is not sent.
Future<void> requestTokenForServer(BuildContext context, WidgetRef ref, String serverId) async {
  final server = ref.read(serverByIdProvider(serverId));
  if (server == null) return;
  final api = HuskApi(baseUrl: server.baseUrl);
  final token = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => TokenRequestDialog(
      flow: TokenRequestFlow(api: api, clientName: ref.read(settingsProvider).tokenClientName),
    ),
  );
  api.close();
  if (token == null) return;
  await ref.read(serversProvider.notifier).setToken(serverId, token);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Token saved.')));
  }
}

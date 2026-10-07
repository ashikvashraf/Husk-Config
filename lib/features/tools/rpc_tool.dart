import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/husk_exception.dart';
import '../../shared/widgets/confirm_dialog.dart';
import '../servers/api_provider.dart';
import 'tools_providers.dart';

/// Vocabulary of the a11y engine on port 8127 (from the API description).
const _vocabulary = [
  ('ping', 'Check that the engine is alive'),
  ('displays', 'List displays'),
  ('rotation 0', 'rotation D'),
  ('tap 540 1000 0', 'tap X Y D [ms]'),
  ('swipe 540 1500 540 500 0 300', 'swipe X1 Y1 X2 Y2 D [ms]'),
  ('dump 0', 'dump D: accessibility tree'),
  ('find 0 Settings', 'find|click|state|gettext D <regex>'),
  ('launch 0 android.settings.SETTINGS', 'launch D <action> [data] [pkg]'),
  ('scroll 0', 'scroll D [b]'),
  ('global home', 'global <name>'),
  ('devoptions probe', 'devoptions [probe]'),
  ('text hello', 'text <string>'),
  ('enter', 'Press Enter in the focused field'),
  ('wake', 'Wake the screen'),
];

class RpcTool extends ConsumerStatefulWidget {
  const RpcTool({super.key, required this.serverId});

  final String serverId;

  @override
  ConsumerState<RpcTool> createState() => _RpcToolState();
}

class _RpcToolState extends ConsumerState<RpcTool> {
  final _command = TextEditingController();
  final _history = <({String command, String reply, bool isError})>[];
  bool _busy = false;

  @override
  void dispose() {
    _command.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final command = _command.text.trim();
    if (command.isEmpty) return;
    if (!ref.read(rpcConfirmedProvider)) {
      final ok = await confirm(
        context,
        title: 'Send raw commands?',
        message: "Raw commands go straight to Husk's accessibility engine and can tap, type and launch anything on the phone.",
      );
      if (!ok) return;
      ref.read(rpcConfirmedProvider.notifier).confirm();
    }
    setState(() => _busy = true);
    ({String command, String reply, bool isError}) entry;
    try {
      final reply = await ref.read(apiProvider(widget.serverId)).rpc(command);
      entry = (command: command, reply: reply.trim(), isError: reply.trim().startsWith('ERR'));
    } on HuskException catch (e) {
      entry = (command: command, reply: e.message, isError: true);
    }
    if (!mounted) return;
    setState(() {
      _history.insert(0, entry);
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(apiProvider(widget.serverId));
    final scheme = Theme.of(context).colorScheme;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        Expanded(
          child: TextField(
            controller: _command,
            style: const TextStyle(fontFamily: 'monospace'),
            decoration: const InputDecoration(labelText: 'Command', hintText: 'ping'),
            onSubmitted: (_) => _send(),
          ),
        ),
        const SizedBox(width: 12),
        FilledButton(onPressed: _busy ? null : _send, child: const Text('Send')),
      ]),
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: const Text('Command reference'),
        children: [
          for (final (syntax, description) in _vocabulary)
            ListTile(
              dense: true,
              title: Text(syntax, style: const TextStyle(fontFamily: 'monospace')),
              subtitle: Text(description),
              onTap: () => _command.text = syntax,
            ),
        ],
      ),
      for (final entry in _history)
        Card(
          child: ListTile(
            title: Text('> ${entry.command}', style: const TextStyle(fontFamily: 'monospace')),
            subtitle: SelectableText(
              entry.reply,
              style: TextStyle(fontFamily: 'monospace', color: entry.isError ? scheme.error : null),
            ),
          ),
        ),
    ]);
  }
}

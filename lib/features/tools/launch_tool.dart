import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/husk_exception.dart';
import '../../shared/widgets/result_box.dart';
import '../servers/api_provider.dart';

const _presets = [
  (label: 'Settings', action: 'android.settings.SETTINGS', data: ''),
  (label: 'Wi-Fi settings', action: 'android.settings.WIFI_SETTINGS', data: ''),
  (label: 'Developer options', action: 'android.settings.APPLICATION_DEVELOPMENT_SETTINGS', data: ''),
  (label: 'Open URL', action: 'android.intent.action.VIEW', data: 'https://'),
];

class LaunchTool extends ConsumerStatefulWidget {
  const LaunchTool({super.key, required this.serverId});

  final String serverId;

  @override
  ConsumerState<LaunchTool> createState() => _LaunchToolState();
}

class _LaunchToolState extends ConsumerState<LaunchTool> {
  final _action = TextEditingController();
  final _data = TextEditingController();
  final _package = TextEditingController();
  final _display = TextEditingController(text: '0');
  String? _result;
  bool _isError = false;

  @override
  void dispose() {
    for (final c in [_action, _data, _package, _display]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _orNull(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  void _show(String text, bool isError) => setState(() {
        _result = text;
        _isError = isError;
      });

  @override
  Widget build(BuildContext context) {
    final api = ref.watch(apiProvider(widget.serverId));
    return ListView(padding: const EdgeInsets.all(16), children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final p in _presets)
          ActionChip(
            label: Text(p.label),
            onPressed: () => setState(() {
              _action.text = p.action;
              _data.text = p.data;
            }),
          ),
      ]),
      const SizedBox(height: 12),
      TextField(controller: _action, decoration: const InputDecoration(labelText: 'Intent action', hintText: 'android.settings.SETTINGS')),
      TextField(controller: _data, decoration: const InputDecoration(labelText: 'Data URI (optional)')),
      TextField(controller: _package, decoration: const InputDecoration(labelText: 'Target package (optional)')),
      SizedBox(
        width: 120,
        child: TextField(controller: _display, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Display')),
      ),
      const SizedBox(height: 16),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          icon: const Icon(Icons.open_in_new),
          label: const Text('Launch'),
          onPressed: () async {
            final action = _action.text.trim();
            if (action.isEmpty) {
              _show('Enter an intent action.', true);
              return;
            }
            try {
              final r = await api.launch(
                action: action,
                data: _orNull(_data),
                package: _orNull(_package),
                display: int.tryParse(_display.text.trim()) ?? 0,
              );
              if (mounted) _show(r.text, r.isErr);
            } on HuskException catch (e) {
              if (mounted) _show(e.message, true);
            }
          },
        ),
      ),
      if (_result != null) ...[const SizedBox(height: 16), ResultBox(_result!, isError: _isError)],
    ]);
  }
}

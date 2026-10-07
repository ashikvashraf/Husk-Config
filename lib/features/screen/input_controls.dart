import 'package:flutter/material.dart';

import '../../core/api/models/tools_models.dart';

class NavBar extends StatelessWidget {
  const NavBar({super.key, required this.onKey, required this.onWake});

  final void Function(NavKey key) onKey;
  final VoidCallback onWake;

  @override
  Widget build(BuildContext context) => Wrap(alignment: WrapAlignment.center, spacing: 4, children: [
        IconButton(tooltip: 'Back', icon: const Icon(Icons.arrow_back), onPressed: () => onKey(NavKey.back)),
        IconButton(tooltip: 'Home', icon: const Icon(Icons.circle_outlined), onPressed: () => onKey(NavKey.home)),
        IconButton(tooltip: 'Recents', icon: const Icon(Icons.crop_square), onPressed: () => onKey(NavKey.recents)),
        IconButton(tooltip: 'Notifications', icon: const Icon(Icons.notifications_none), onPressed: () => onKey(NavKey.notifications)),
        IconButton(tooltip: 'Wake screen', icon: const Icon(Icons.power_settings_new), onPressed: onWake),
      ]);
}

class KeyboardPanel extends StatefulWidget {
  const KeyboardPanel({super.key, required this.onSendText, required this.onEnter});

  final void Function(String text) onSendText;
  final VoidCallback onEnter;

  @override
  State<KeyboardPanel> createState() => _KeyboardPanelState();
}

class _KeyboardPanelState extends State<KeyboardPanel> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _send() {
    if (_text.text.isEmpty) return;
    widget.onSendText(_text.text);
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _text,
              decoration: const InputDecoration(
                labelText: 'Text for the focused field',
                helperText: "Replaces the field's whole content.",
                isDense: true,
              ),
              onSubmitted: (_) => _send(),
            ),
          ),
          IconButton(tooltip: 'Send text', icon: const Icon(Icons.send), onPressed: _send),
          OutlinedButton(onPressed: widget.onEnter, child: const Text('Enter')),
        ]),
      );
}

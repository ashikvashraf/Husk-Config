import 'package:flutter/material.dart';

/// Monospace, selectable output of a device command.
class ResultBox extends StatelessWidget {
  const ResultBox(this.text, {super.key, this.isError = false});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isError ? scheme.errorContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectableText(
        text,
        style: TextStyle(fontFamily: 'monospace', color: isError ? scheme.onErrorContainer : null),
      ),
    );
  }
}

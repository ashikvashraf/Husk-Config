import 'package:flutter/material.dart';

enum DotState { online, offline, unauthorized, unknown }

class StatusDot extends StatelessWidget {
  const StatusDot(this.state, {super.key, this.size = 10});

  final DotState state;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (color, label) = switch (state) {
      DotState.online => (Colors.green, 'Online'),
      DotState.offline => (scheme.error, 'Offline'),
      DotState.unauthorized => (Colors.amber.shade700, 'Token required'),
      DotState.unknown => (scheme.outline, 'Checking'),
    };
    return Tooltip(
      message: label,
      child: Container(width: size, height: size, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    );
  }
}

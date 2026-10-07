import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/storage/server_config.dart';
import '../../shared/error_text.dart';
import '../../shared/widgets/status_dot.dart';
import '../servers/server_actions.dart';
import '../servers/token_request_dialog.dart';
import 'server_status.dart';

enum _CardAction { edit, requestToken, delete }

class ServerCard extends ConsumerWidget {
  const ServerCard({super.key, required this.server});

  final ServerConfig server;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(serverStatusProvider(server.id));
    final theme = Theme.of(context);
    final dot = status.value?.dot ?? (status.hasError ? DotState.offline : DotState.unknown);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go('/device/${server.id}/overview'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  StatusDot(dot),
                  const SizedBox(width: 8),
                  Expanded(child: Text(server.name, style: theme.textTheme.titleMedium, overflow: TextOverflow.ellipsis)),
                  PopupMenuButton<_CardAction>(
                    tooltip: 'Server actions',
                    onSelected: (action) => _onAction(context, ref, action),
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: _CardAction.edit, child: Text('Edit')),
                      PopupMenuItem(value: _CardAction.requestToken, child: Text('Request token')),
                      PopupMenuItem(value: _CardAction.delete, child: Text('Delete')),
                    ],
                  ),
                ],
              ),
              Text(server.address, style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              switch (status) {
                AsyncValue(value: final ServerStatus value) => _StatusBody(value),
                AsyncValue(error: final Object error) => _OfflineBody(describeError(error), null),
                _ => const Text('Checking…'),
              },
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onAction(BuildContext context, WidgetRef ref, _CardAction action) async {
    switch (action) {
      case _CardAction.edit:
        await context.push('/servers/${server.id}/edit');
      case _CardAction.requestToken:
        await requestTokenForServer(context, ref, server.id);
      case _CardAction.delete:
        await confirmDeleteServer(context, ref, server);
    }
  }
}

class _StatusBody extends StatelessWidget {
  const _StatusBody(this.status);

  final ServerStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return switch (status) {
      ServerOnline(:final info, :final checkedAt) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${info.displayName} · Android ${info.androidRelease}'),
            const SizedBox(height: 4),
            Row(children: [
              Icon(info.batteryCharging ? Icons.battery_charging_full : Icons.battery_std, size: 18),
              const SizedBox(width: 4),
              Text(info.batteryLevel == null ? '—' : '${info.batteryLevel}%'),
            ]),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, children: [
              _ServiceChip('a11y', info.services.a11y),
              _ServiceChip('camera', info.services.camera),
              _ServiceChip('screen', info.services.screen),
            ]),
            const SizedBox(height: 6),
            Text('Checked ${TimeOfDay.fromDateTime(checkedAt).format(context)}', style: theme.textTheme.bodySmall),
          ],
        ),
      ServerOffline(:final message, :final lastSeen) => _OfflineBody(message, lastSeen),
      ServerUnauthorized() => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Token required', style: TextStyle(color: Colors.amber.shade800, fontWeight: FontWeight.w600)),
            const Text('Edit the server or request a token.'),
          ],
        ),
    };
  }
}

class _OfflineBody extends StatelessWidget {
  const _OfflineBody(this.message, this.lastSeen);

  final String message;
  final DateTime? lastSeen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final seen = lastSeen;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Offline', style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.w600)),
        Text(message, style: theme.textTheme.bodySmall),
        if (seen != null) Text('Last seen ${TimeOfDay.fromDateTime(seen).format(context)}', style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _ServiceChip extends StatelessWidget {
  const _ServiceChip(this.label, this.on);

  final String label;
  final bool on;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: on ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label, style: TextStyle(fontSize: 12, color: on ? scheme.onPrimaryContainer : scheme.onSurfaceVariant)),
    );
  }
}

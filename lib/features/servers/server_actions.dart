import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/server_config.dart';
import '../../shared/widgets/confirm_dialog.dart';
import 'servers_controller.dart';

Future<void> confirmDeleteServer(BuildContext context, WidgetRef ref, ServerConfig server) async {
  final ok = await confirm(
    context,
    title: 'Delete ${server.name}?',
    message: 'This removes ${server.address} and its token from this app. Nothing changes on the phone.',
    confirmLabel: 'Delete',
  );
  if (ok) await ref.read(serversProvider.notifier).remove(server.id);
}

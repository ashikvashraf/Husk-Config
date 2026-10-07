import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/husk_api.dart';
import 'servers_controller.dart';

/// The HuskApi for a saved server. Rebuilt only when its address or token
/// changes (not on lastUsedAt/name edits). Widgets must `ref.watch` this in
/// build and use that instance in their callbacks.
final apiProvider = Provider.autoDispose.family<HuskApi, String>((ref, serverId) {
  final connection = ref.watch(serversProvider.select((servers) {
    final server = servers.where((s) => s.id == serverId).firstOrNull;
    return server == null ? null : (baseUrl: server.baseUrl, token: server.token);
  }));
  if (connection == null) throw StateError('Unknown server $serverId');
  final api = HuskApi(baseUrl: connection.baseUrl, token: connection.token);
  ref.onDispose(api.close);
  return api;
});

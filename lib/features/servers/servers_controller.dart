import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/providers.dart';
import '../../core/storage/server_config.dart';

class ServersController extends Notifier<List<ServerConfig>> {
  @override
  List<ServerConfig> build() => ref.watch(serverRepositoryProvider).loadAll();

  ServerConfig? byId(String id) => state.where((s) => s.id == id).firstOrNull;

  bool isDuplicate(String host, int port, {String? exceptId}) =>
      state.any((s) => s.id != exceptId && s.host == host && s.port == port);

  Future<ServerConfig> add({required String name, required String host, required int port, String? token}) async {
    final server = ServerConfig(
      id: const Uuid().v4(),
      name: name,
      host: host,
      port: port,
      token: token == null || token.isEmpty ? null : token,
      createdAt: DateTime.now(),
    );
    await _save([...state, server]);
    return server;
  }

  Future<void> update(ServerConfig server) => _save([for (final s in state) s.id == server.id ? server : s]);

  Future<void> remove(String id) => _save([for (final s in state) if (s.id != id) s]);

  Future<void> setToken(String id, String token) async {
    final server = byId(id);
    if (server != null) await update(server.copyWith(token: token));
  }

  Future<void> touch(String id) async {
    final server = byId(id);
    if (server != null) await update(server.copyWith(lastUsedAt: DateTime.now()));
  }

  Future<void> _save(List<ServerConfig> servers) async {
    state = servers;
    await ref.read(serverRepositoryProvider).saveAll(servers);
  }
}

final serversProvider = NotifierProvider<ServersController, List<ServerConfig>>(ServersController.new);

final serverByIdProvider = Provider.family<ServerConfig?, String>(
  (ref, id) => ref.watch(serversProvider).where((s) => s.id == id).firstOrNull,
);

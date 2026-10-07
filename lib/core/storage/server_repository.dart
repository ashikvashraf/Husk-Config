import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'server_config.dart';

abstract interface class ServerRepository {
  List<ServerConfig> loadAll();
  Future<void> saveAll(List<ServerConfig> servers);
}

class PrefsServerRepository implements ServerRepository {
  PrefsServerRepository(this._prefs);

  static const key = 'servers.v1';
  final SharedPreferences _prefs;

  @override
  List<ServerConfig> loadAll() {
    final raw = _prefs.getString(key);
    if (raw == null) return [];
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return [];
    }
    if (decoded is! List) return [];
    final servers = <ServerConfig>[];
    for (final entry in decoded) {
      if (entry is Map<String, Object?>) {
        final server = ServerConfig.tryFromJson(entry);
        if (server != null) servers.add(server);
      }
    }
    return servers;
  }

  @override
  Future<void> saveAll(List<ServerConfig> servers) =>
      _prefs.setString(key, jsonEncode([for (final s in servers) s.toJson()]));
}

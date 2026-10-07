import 'package:huskconfig/core/storage/app_settings.dart';
import 'package:huskconfig/core/storage/server_config.dart';
import 'package:huskconfig/core/storage/server_repository.dart';
import 'package:huskconfig/core/storage/settings_repository.dart';

class MemoryServerRepository implements ServerRepository {
  MemoryServerRepository([List<ServerConfig> initial = const []]) : saved = [...initial];

  List<ServerConfig> saved;

  @override
  List<ServerConfig> loadAll() => [...saved];

  @override
  Future<void> saveAll(List<ServerConfig> servers) async => saved = [...servers];
}

class MemorySettingsRepository implements SettingsRepository {
  MemorySettingsRepository([this.saved = const AppSettings()]);

  AppSettings saved;

  @override
  AppSettings load() => saved;

  @override
  Future<void> save(AppSettings settings) async => saved = settings;
}

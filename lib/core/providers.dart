import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'storage/server_repository.dart';
import 'storage/settings_repository.dart';

/// Overridden in main() with the loaded instance (and in tests by the repositories).
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPreferencesProvider must be overridden'),
);

final serverRepositoryProvider = Provider<ServerRepository>(
  (ref) => PrefsServerRepository(ref.watch(sharedPreferencesProvider)),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => PrefsSettingsRepository(ref.watch(sharedPreferencesProvider)),
);

/// False while the app is hidden or paused; set by HuskConfigApp's lifecycle listener.
class AppForeground extends Notifier<bool> {
  @override
  bool build() => true;

  void set(bool value) => state = value;
}

final appForegroundProvider = NotifierProvider<AppForeground, bool>(AppForeground.new);

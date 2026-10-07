import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'app_settings.dart';

abstract interface class SettingsRepository {
  AppSettings load();
  Future<void> save(AppSettings settings);
}

class PrefsSettingsRepository implements SettingsRepository {
  PrefsSettingsRepository(this._prefs);

  static const key = 'settings.v1';
  final SharedPreferences _prefs;

  @override
  AppSettings load() {
    final raw = _prefs.getString(key);
    if (raw == null) return const AppSettings();
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, Object?> ? AppSettings.fromJson(decoded) : const AppSettings();
    } on FormatException {
      return const AppSettings();
    }
  }

  @override
  Future<void> save(AppSettings settings) => _prefs.setString(key, jsonEncode(settings.toJson()));
}

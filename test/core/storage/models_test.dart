import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/storage/app_settings.dart';
import 'package:huskconfig/core/storage/server_config.dart';

void main() {
  final created = DateTime.utc(2026, 10, 7, 12);

  group('ServerConfig', () {
    final server = ServerConfig(
      id: 'a1',
      name: 'Kitchen phone',
      host: '192.168.0.106',
      port: 8090,
      token: 'secret',
      createdAt: created,
    );

    test('JSON round trip preserves all fields', () {
      final withUse = server.copyWith(lastUsedAt: created.add(const Duration(hours: 1)));
      expect(ServerConfig.tryFromJson(withUse.toJson()), withUse);
    });

    test('derived getters', () {
      expect(server.baseUrl, 'http://192.168.0.106:8090');
      expect(server.address, '192.168.0.106:8090');
      expect(server.hasToken, isTrue);
      expect(server.copyWith(clearToken: true).hasToken, isFalse);
      expect(server.copyWith(token: '').hasToken, isFalse);
    });

    test('tryFromJson returns null for missing required fields or wrong types', () {
      expect(ServerConfig.tryFromJson({'id': 'x'}), isNull);
      expect(ServerConfig.tryFromJson({'id': 'x', 'host': '10.0.0.1', 'port': '8090', 'createdAt': created.toIso8601String()}), isNull);
      expect(ServerConfig.tryFromJson({'id': 'x', 'host': '10.0.0.1', 'port': 8090, 'createdAt': 'not a date'}), isNull);
    });

    test('tryFromJson tolerates missing optional fields and uses host as name', () {
      final parsed = ServerConfig.tryFromJson({'id': 'x', 'host': '10.0.0.1', 'port': 8090, 'createdAt': created.toIso8601String()});
      expect(parsed, isNotNull);
      expect(parsed!.name, '10.0.0.1');
      expect(parsed.token, isNull);
      expect(parsed.lastUsedAt, isNull);
    });
  });

  group('AppSettings', () {
    test('defaults', () {
      const s = AppSettings();
      expect(s.themeMode, ThemeMode.system);
      expect(s.pollIntervalSeconds, 10);
      expect(s.defaultScreenMode, ScreenMode.mjpeg);
      expect(s.tokenClientName, 'Husk Config');
    });

    test('JSON round trip', () {
      const s = AppSettings(themeMode: ThemeMode.dark, pollIntervalSeconds: 30, defaultScreenMode: ScreenMode.webview, tokenClientName: 'My Mac');
      expect(AppSettings.fromJson(s.toJson()), s);
    });

    test('fromJson falls back to defaults for unknown or invalid values', () {
      final s = AppSettings.fromJson({'themeMode': 'purple', 'pollIntervalSeconds': 7, 'defaultScreenMode': 'vr', 'tokenClientName': 'bad/name!'});
      expect(s, const AppSettings());
    });

    test('isValidClientName', () {
      expect(AppSettings.isValidClientName('Husk Config'), isTrue);
      expect(AppSettings.isValidClientName('mac-mini_2.local'), isTrue);
      expect(AppSettings.isValidClientName(''), isFalse);
      expect(AppSettings.isValidClientName('a' * 33), isFalse);
      expect(AppSettings.isValidClientName('emoji 😀'), isFalse);
    });
  });
}

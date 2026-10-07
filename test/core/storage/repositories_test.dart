import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/storage/app_settings.dart';
import 'package:huskconfig/core/storage/server_config.dart';
import 'package:huskconfig/core/storage/server_repository.dart';
import 'package:huskconfig/core/storage/settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final server = ServerConfig(id: 'a', name: 'A', host: '10.0.0.1', port: 8090, createdAt: DateTime.utc(2026));

  group('PrefsServerRepository', () {
    test('empty when nothing stored', () async {
      SharedPreferences.setMockInitialValues({});
      final repo = PrefsServerRepository(await SharedPreferences.getInstance());
      expect(repo.loadAll(), isEmpty);
    });

    test('saveAll then loadAll round trips', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await PrefsServerRepository(prefs).saveAll([server]);
      expect(PrefsServerRepository(prefs).loadAll(), [server]);
    });

    test('corrupt JSON yields an empty list instead of throwing', () async {
      SharedPreferences.setMockInitialValues({PrefsServerRepository.key: '{not json'});
      final repo = PrefsServerRepository(await SharedPreferences.getInstance());
      expect(repo.loadAll(), isEmpty);
    });

    test('invalid entries are skipped, valid ones kept', () async {
      SharedPreferences.setMockInitialValues({
        PrefsServerRepository.key: jsonEncode([server.toJson(), {'id': 'broken'}, 42]),
      });
      final repo = PrefsServerRepository(await SharedPreferences.getInstance());
      expect(repo.loadAll(), [server]);
    });

    test('a non-list top-level value yields an empty list', () async {
      SharedPreferences.setMockInitialValues({PrefsServerRepository.key: '{"id":"a"}'});
      final repo = PrefsServerRepository(await SharedPreferences.getInstance());
      expect(repo.loadAll(), isEmpty);
    });
  });

  group('PrefsSettingsRepository', () {
    test('defaults when nothing stored or corrupt', () async {
      SharedPreferences.setMockInitialValues({PrefsSettingsRepository.key: '[1,2'});
      final repo = PrefsSettingsRepository(await SharedPreferences.getInstance());
      expect(repo.load(), const AppSettings());
    });

    test('save then load round trips', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      const s = AppSettings(themeMode: ThemeMode.light, pollIntervalSeconds: 60);
      await PrefsSettingsRepository(prefs).save(s);
      expect(PrefsSettingsRepository(prefs).load(), s);
    });
  });
}

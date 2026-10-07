import 'dart:convert';

import 'package:huskconfig/core/api/models/device_models.dart';
import 'package:huskconfig/core/storage/server_config.dart';

final server1 = ServerConfig(id: 's1', name: 'Kitchen phone', host: '192.168.0.106', port: 8090, createdAt: DateTime.utc(2026, 10, 7));

DeviceInfo deviceInfoFixture({int battery = 87, bool charging = false}) => DeviceInfo.fromJson(jsonDecode(
      '{"app":{"package":"co.xplat.husk","versionName":"1.4","versionCode":"55"},'
      '"device":{"manufacturer":"samsung","model":"SM-A750F","androidRelease":"10","sdkInt":29,"dexCapable":false,"hasCamera":true},'
      '"screen":{"width":1080,"height":2220},"net":{"localIp":"192.168.0.106","tailscaleIp":null},'
      '"battery":{"level":$battery,"charging":$charging},"services":{"a11y":true,"camera":true,"screen":false,"dexReconnect":false}}',
    ) as Map<String, Object?>);

Flags flagsFixture({bool screen = false, bool front = true}) => Flags.fromJson({
      'dexReconnect': false, 'a11y': true, 'camera': false, 'front': front, 'screen': screen,
      'motion': false, 'ntfy': false, 'batteryOptIgnored': true, 'lastNtfy': '',
    });

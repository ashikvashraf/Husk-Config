import 'json_read.dart';

/// Sensor names accepted by GET /sensor?type=.
const List<String> sensorTypes = [
  'accelerometer', 'gyroscope', 'magnetic', 'light', 'proximity', 'pressure',
  'gravity', 'linear', 'rotation', 'temperature', 'humidity', 'stepcounter',
];

class BatteryInfo {
  const BatteryInfo({
    required this.level,
    required this.charging,
    required this.status,
    required this.health,
    required this.plugged,
    required this.temperatureC,
    required this.voltageMv,
    required this.technology,
  });

  factory BatteryInfo.fromJson(Map<String, Object?> j) => BatteryInfo(
        level: readInt(j['level']),
        charging: readBool(j['charging']) ?? false,
        status: readString(j['status']) ?? '',
        health: readString(j['health']) ?? '',
        plugged: readString(j['plugged']) ?? '',
        temperatureC: readDouble(j['temperatureC']),
        voltageMv: readInt(j['voltageMv']),
        technology: readString(j['technology']) ?? '',
      );

  final int? level;
  final bool charging;
  final String status;
  final String health;
  final String plugged;
  final double? temperatureC;
  final int? voltageMv;
  final String technology;
}

class ConnectivityInfo {
  const ConnectivityInfo({required this.connected, required this.type, required this.metered, required this.validated});

  factory ConnectivityInfo.fromJson(Map<String, Object?> j) => ConnectivityInfo(
        connected: readBool(j['connected']) ?? false,
        type: readString(j['type']) ?? 'none',
        metered: readBool(j['metered']) ?? false,
        validated: readBool(j['validated']) ?? false,
      );

  final bool connected;
  final String type;
  final bool metered;
  final bool validated;
}

/// GET /display. width/height are the real pixel size Husk uses for /tap.
class DisplayInfo {
  const DisplayInfo({
    required this.width,
    required this.height,
    required this.densityDpi,
    required this.density,
    required this.refreshHz,
    required this.rotation,
  });

  factory DisplayInfo.fromJson(Map<String, Object?> j) => DisplayInfo(
        width: readInt(j['width']) ?? 0,
        height: readInt(j['height']) ?? 0,
        densityDpi: readInt(j['densityDpi']),
        density: readDouble(j['density']),
        refreshHz: readDouble(j['refreshHz']),
        rotation: readInt(j['rotation']) ?? 0,
      );

  final int width;
  final int height;
  final int? densityDpi;
  final double? density;
  final double? refreshHz;
  final int rotation;
}

class LocationInfo {
  const LocationInfo({
    required this.lat,
    required this.lon,
    required this.accuracyM,
    required this.altitude,
    required this.time,
    required this.provider,
  });

  factory LocationInfo.fromJson(Map<String, Object?> j) => LocationInfo(
        lat: readDouble(j['lat']),
        lon: readDouble(j['lon']),
        accuracyM: readDouble(j['accuracyM']),
        altitude: readDouble(j['altitude']),
        time: readEpochMs(j['time']),
        provider: readString(j['provider']) ?? '',
      );

  final double? lat;
  final double? lon;
  final double? accuracyM;
  final double? altitude;
  final DateTime? time;
  final String provider;
}

class MicLevel {
  const MicLevel({required this.amplitude, required this.max});

  factory MicLevel.fromJson(Map<String, Object?> j) =>
      MicLevel(amplitude: readInt(j['amplitude']) ?? 0, max: readInt(j['max']) ?? 32767);

  final int amplitude;
  final int max;

  double get fraction => max <= 0 ? 0 : (amplitude / max).clamp(0.0, 1.0);
}

class SensorInfo {
  const SensorInfo({required this.name, required this.type, required this.vendor, required this.power, required this.max});

  factory SensorInfo.fromJson(Map<String, Object?> j) => SensorInfo(
        name: readString(j['name']) ?? '',
        type: readInt(j['type']),
        vendor: readString(j['vendor']) ?? '',
        power: readDouble(j['power']),
        max: readDouble(j['max']),
      );

  final String name;
  final int? type;
  final String vendor;
  final double? power;
  final double? max;
}

class SensorReading {
  const SensorReading({required this.sensor, required this.type, required this.values});

  factory SensorReading.fromJson(Map<String, Object?> j) {
    final raw = j['values'];
    return SensorReading(
      sensor: readString(j['sensor']) ?? '',
      type: readInt(j['type']),
      values: raw is List ? [for (final v in raw) readDouble(v) ?? double.nan] : const [],
    );
  }

  final String sensor;
  final int? type;
  final List<double> values;
}

class VolumeLevel {
  const VolumeLevel({required this.level, required this.max});

  factory VolumeLevel.fromJson(Map<String, Object?> j) =>
      VolumeLevel(level: readInt(j['level']) ?? 0, max: readInt(j['max']) ?? 0);

  /// Parses `{"media":{"level","max"},…}` keeping the server's stream order.
  static Map<String, VolumeLevel> parseAll(Map<String, Object?> j) => {
        for (final entry in j.entries)
          if (entry.value is Map) entry.key: VolumeLevel.fromJson(readMap(entry.value)),
      };

  final int level;
  final int max;
}

class BrightnessInfo {
  const BrightnessInfo({required this.level, required this.max, required this.auto});

  factory BrightnessInfo.fromJson(Map<String, Object?> j) => BrightnessInfo(
        level: readInt(j['level']) ?? 0,
        max: readInt(j['max']) ?? 255,
        auto: readBool(j['auto']) ?? false,
      );

  final int level;
  final int max;
  final bool auto;
}

/// One line of GET /displays (plain text, `id:state` per line, e.g. `0:0`).
class DisplayEntry {
  const DisplayEntry({required this.id, required this.raw});

  static List<DisplayEntry> parseList(String text) => [
        for (final line in text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty))
          if (int.tryParse(line.split(':').first.trim()) case final int id) DisplayEntry(id: id, raw: line),
      ];

  final int id;
  final String raw;
}

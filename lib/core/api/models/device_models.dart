import 'json_read.dart';

class ServiceState {
  const ServiceState({required this.a11y, required this.camera, required this.screen, required this.dexReconnect});

  factory ServiceState.fromJson(Map<String, Object?> j) => ServiceState(
        a11y: readBool(j['a11y']) ?? false,
        camera: readBool(j['camera']) ?? false,
        screen: readBool(j['screen']) ?? false,
        dexReconnect: readBool(j['dexReconnect']) ?? false,
      );

  final bool a11y;
  final bool camera;
  final bool screen;
  final bool dexReconnect;
}

/// GET /info.
class DeviceInfo {
  const DeviceInfo({
    required this.appPackage,
    required this.appVersionName,
    required this.appVersionCode,
    required this.manufacturer,
    required this.model,
    required this.androidRelease,
    required this.sdkInt,
    required this.dexCapable,
    required this.hasCamera,
    required this.screenWidth,
    required this.screenHeight,
    required this.localIp,
    required this.tailscaleIp,
    required this.batteryLevel,
    required this.batteryCharging,
    required this.services,
  });

  factory DeviceInfo.fromJson(Map<String, Object?> j) {
    final app = readMap(j['app']);
    final device = readMap(j['device']);
    final screen = readMap(j['screen']);
    final net = readMap(j['net']);
    final battery = readMap(j['battery']);
    return DeviceInfo(
      appPackage: readString(app['package']) ?? '',
      appVersionName: readString(app['versionName']) ?? '',
      appVersionCode: readString(app['versionCode']) ?? '',
      manufacturer: readString(device['manufacturer']) ?? '',
      model: readString(device['model']) ?? '',
      androidRelease: readString(device['androidRelease']) ?? '',
      sdkInt: readInt(device['sdkInt']),
      dexCapable: readBool(device['dexCapable']) ?? false,
      hasCamera: readBool(device['hasCamera']) ?? false,
      screenWidth: readInt(screen['width']),
      screenHeight: readInt(screen['height']),
      localIp: readString(net['localIp']),
      tailscaleIp: readString(net['tailscaleIp']),
      batteryLevel: readInt(battery['level']),
      batteryCharging: readBool(battery['charging']) ?? false,
      services: ServiceState.fromJson(readMap(j['services'])),
    );
  }

  final String appPackage;
  final String appVersionName;
  final String appVersionCode;
  final String manufacturer;
  final String model;
  final String androidRelease;
  final int? sdkInt;
  final bool dexCapable;
  final bool hasCamera;
  final int? screenWidth;
  final int? screenHeight;
  final String? localIp;
  final String? tailscaleIp;
  final int? batteryLevel;
  final bool batteryCharging;
  final ServiceState services;

  String get displayName => [manufacturer, model].where((s) => s.isNotEmpty).join(' ');
}

/// GET /flags. `front` is the SELECTED camera side, not proof of a frame;
/// `camera: false` is the normal idle state of the lazy camera.
class Flags {
  const Flags({
    required this.dexReconnect,
    required this.a11y,
    required this.camera,
    required this.front,
    required this.screen,
    required this.motion,
    required this.ntfy,
    required this.batteryOptIgnored,
    required this.lastNtfy,
  });

  factory Flags.fromJson(Map<String, Object?> j) => Flags(
        dexReconnect: readBool(j['dexReconnect']) ?? false,
        a11y: readBool(j['a11y']) ?? false,
        camera: readBool(j['camera']) ?? false,
        front: readBool(j['front']) ?? false,
        screen: readBool(j['screen']) ?? false,
        motion: readBool(j['motion']) ?? false,
        ntfy: readBool(j['ntfy']) ?? false,
        batteryOptIgnored: readBool(j['batteryOptIgnored']) ?? false,
        lastNtfy: readString(j['lastNtfy']) ?? '',
      );

  final bool dexReconnect;
  final bool a11y;
  final bool camera;
  final bool front;
  final bool screen;
  final bool motion;
  final bool ntfy;
  final bool batteryOptIgnored;
  final String lastNtfy;
}

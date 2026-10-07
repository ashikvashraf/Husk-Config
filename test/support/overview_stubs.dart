import 'package:huskconfig/core/api/husk_exception.dart';
import 'package:huskconfig/core/api/models/hardware_models.dart';
import 'package:huskconfig/core/api/models/tools_models.dart';
import 'package:huskconfig/core/api/text_result.dart';
import 'package:mocktail/mocktail.dart';

import 'fixtures.dart';
import 'mocks.dart';

/// Stubs every endpoint the device shell and overview read, with the
/// test phone's real values; /location answers ERR like the real phone did.
void stubOverview(MockHuskApi api, {bool screenSharing = false}) {
  registerFallbackValue(NavKey.back);
  when(() => api.info()).thenAnswer((_) async => deviceInfoFixture());
  when(() => api.flags()).thenAnswer((_) async => flagsFixture(screen: screenSharing));
  when(() => api.battery()).thenAnswer((_) async => BatteryInfo.fromJson({
        'level': 100, 'charging': true, 'status': 'full', 'health': 'good', 'plugged': 'usb',
        'temperatureC': 28.8, 'voltageMv': 4150, 'technology': 'Li-ion',
      }));
  when(() => api.connectivity()).thenAnswer((_) async =>
      ConnectivityInfo.fromJson({'connected': true, 'type': 'wifi', 'metered': false, 'validated': true}));
  when(() => api.display()).thenAnswer((_) async =>
      DisplayInfo.fromJson({'width': 1080, 'height': 2112, 'densityDpi': 360, 'density': 2.25, 'refreshHz': 60.0, 'rotation': '0'}));
  when(() => api.location()).thenThrow(const DeviceErrorException('ERR no-fix (no known position; is location turned on?)'));
  when(() => api.volume()).thenAnswer((_) async => {'media': const VolumeLevel(level: 3, max: 15), 'call': const VolumeLevel(level: 4, max: 5)});
  when(() => api.ringerMode()).thenAnswer((_) async => 'normal');
  when(() => api.brightness()).thenAnswer((_) async => const BrightnessInfo(level: 105, max: 255, auto: true));
  when(() => api.sensors()).thenAnswer((_) async => const [SensorInfo(name: 'CM36658 Light', type: 5, vendor: 'Capella', power: 0.75, max: 60000)]);
  when(() => api.displays()).thenAnswer((_) async => const [DisplayEntry(id: 0, raw: '0:0')]);
  when(() => api.wake()).thenAnswer((_) async => const TextResult('OK'));
  when(() => api.torch(on: any(named: 'on'))).thenAnswer((_) async => const TextResult('OK (on)'));
  when(() => api.vibrate(ms: any(named: 'ms'))).thenAnswer((_) async => const TextResult('OK (300ms)'));
}

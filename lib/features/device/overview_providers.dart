import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/models/device_models.dart';
import '../../core/api/models/hardware_models.dart';
import '../../core/polling.dart';
import '../servers/api_provider.dart';
import '../settings/settings_controller.dart';

final deviceInfoProvider = FutureProvider.autoDispose.family<DeviceInfo, String>((ref, id) => ref.watch(apiProvider(id)).info());

/// Polled: services can change while the page is open.
final flagsProvider = StreamProvider.autoDispose.family<Flags, String>((ref, id) {
  final api = ref.watch(apiProvider(id));
  return pollEvery(ref, ref.watch(pollIntervalProvider), api.flags);
});

/// Polled: battery level and charging change while the page is open.
final batteryProvider = StreamProvider.autoDispose.family<BatteryInfo, String>((ref, id) {
  final api = ref.watch(apiProvider(id));
  return pollEvery(ref, ref.watch(pollIntervalProvider), api.battery);
});

final connectivityProvider =
    FutureProvider.autoDispose.family<ConnectivityInfo, String>((ref, id) => ref.watch(apiProvider(id)).connectivity());

final displayInfoProvider = FutureProvider.autoDispose.family<DisplayInfo, String>((ref, id) => ref.watch(apiProvider(id)).display());

final locationProvider = FutureProvider.autoDispose.family<LocationInfo, String>((ref, id) => ref.watch(apiProvider(id)).location());

final volumeProvider =
    FutureProvider.autoDispose.family<Map<String, VolumeLevel>, String>((ref, id) => ref.watch(apiProvider(id)).volume());

final ringerProvider = FutureProvider.autoDispose.family<String, String>((ref, id) => ref.watch(apiProvider(id)).ringerMode());

final brightnessProvider =
    FutureProvider.autoDispose.family<BrightnessInfo, String>((ref, id) => ref.watch(apiProvider(id)).brightness());

final sensorsProvider = FutureProvider.autoDispose.family<List<SensorInfo>, String>((ref, id) => ref.watch(apiProvider(id)).sensors());

final displaysProvider =
    FutureProvider.autoDispose.family<List<DisplayEntry>, String>((ref, id) => ref.watch(apiProvider(id)).displays());

void refreshOverview(WidgetRef ref, String id) {
  ref.invalidate(deviceInfoProvider(id));
  ref.invalidate(flagsProvider(id));
  ref.invalidate(batteryProvider(id));
  ref.invalidate(connectivityProvider(id));
  ref.invalidate(displayInfoProvider(id));
  ref.invalidate(locationProvider(id));
  ref.invalidate(volumeProvider(id));
  ref.invalidate(ringerProvider(id));
  ref.invalidate(brightnessProvider(id));
  ref.invalidate(sensorsProvider(id));
}

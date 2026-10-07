import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/husk_api.dart';
import '../../core/api/husk_exception.dart';
import '../../core/api/models/device_models.dart';
import '../../core/polling.dart';
import '../../shared/widgets/status_dot.dart';
import '../servers/api_provider.dart';
import '../settings/settings_controller.dart';

sealed class ServerStatus {
  const ServerStatus();

  DotState get dot;
}

final class ServerOnline extends ServerStatus {
  const ServerOnline(this.info, this.checkedAt);

  final DeviceInfo info;
  final DateTime checkedAt;

  @override
  DotState get dot => DotState.online;
}

final class ServerOffline extends ServerStatus {
  const ServerOffline(this.message, {this.lastSeen});

  final String message;
  final DateTime? lastSeen;

  @override
  DotState get dot => DotState.offline;
}

final class ServerUnauthorized extends ServerStatus {
  const ServerUnauthorized();

  @override
  DotState get dot => DotState.unauthorized;
}

Future<ServerStatus> checkServer(HuskApi api, {DateTime? lastSeen}) async {
  try {
    return ServerOnline(await api.info(), DateTime.now());
  } on UnauthorizedException {
    return const ServerUnauthorized();
  } on HuskException catch (e) {
    return ServerOffline(e.message, lastSeen: lastSeen);
  }
}

/// When each server last answered /info successfully, by server id.
///
/// Kept alive (not autoDispose) so "Last seen" survives pull-to-refresh,
/// poll-interval changes, app background/foreground cycles and cards
/// scrolling off screen. Session-only; not persisted.
class LastSeen extends Notifier<Map<String, DateTime>> {
  @override
  Map<String, DateTime> build() => const {};

  void record(String serverId, DateTime at) => state = {...state, serverId: at};
}

final lastSeenProvider = NotifierProvider<LastSeen, Map<String, DateTime>>(LastSeen.new);

/// True while the dashboard is the topmost route. Polling pauses while a
/// pushed route (settings, add/edit server, scan) covers it. Set by
/// DashboardScreen from ModalRoute.isCurrent.
class DashboardVisible extends Notifier<bool> {
  @override
  bool build() => true;

  void set(bool value) => state = value;
}

final dashboardVisibleProvider = NotifierProvider<DashboardVisible, bool>(DashboardVisible.new);

/// Live status per server, polled with /info at the configured interval
/// (not at all while the dashboard is covered or the app is in the background).
final serverStatusProvider = StreamProvider.autoDispose.family<ServerStatus, String>((ref, serverId) {
  final api = ref.watch(apiProvider(serverId));
  final visible = ref.watch(dashboardVisibleProvider);
  final interval = visible ? ref.watch(pollIntervalProvider) : null;
  return pollEvery(ref, interval, () async {
    final status = await checkServer(api, lastSeen: ref.read(lastSeenProvider)[serverId]);
    if (status is ServerOnline && ref.mounted) {
      ref.read(lastSeenProvider.notifier).record(serverId, status.checkedAt);
    }
    return status;
  });
});

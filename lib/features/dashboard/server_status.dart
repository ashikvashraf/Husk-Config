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

/// Live status per server, polled with /info at the configured interval.
final serverStatusProvider = StreamProvider.autoDispose.family<ServerStatus, String>((ref, serverId) {
  final api = ref.watch(apiProvider(serverId));
  final interval = ref.watch(pollIntervalProvider);
  DateTime? lastSeen;
  return pollEvery(ref, interval, () async {
    final status = await checkServer(api, lastSeen: lastSeen);
    if (status is ServerOnline) lastSeen = status.checkedAt;
    return status;
  });
});

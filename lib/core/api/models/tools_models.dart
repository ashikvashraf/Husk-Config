import 'json_read.dart';

enum NavKey { back, home, recents, notifications, enter }

class MotionConfig {
  const MotionConfig({
    required this.enabled,
    required this.ntfyServer,
    required this.ntfyTopic,
    required this.sensitivity,
    required this.lastNtfy,
  });

  factory MotionConfig.fromJson(Map<String, Object?> j) => MotionConfig(
        enabled: readBool(j['enabled']) ?? false,
        ntfyServer: readString(j['ntfyServer']) ?? 'https://ntfy.sh',
        ntfyTopic: readString(j['ntfyTopic']) ?? '',
        sensitivity: readInt(j['sensitivity']) ?? 5,
        lastNtfy: readString(j['lastNtfy']) ?? '',
      );

  final bool enabled;
  final String ntfyServer;
  final String ntfyTopic;
  final int sensitivity;
  final String lastNtfy;
}

class MotionEvent {
  const MotionEvent({required this.time, required this.source, required this.change});

  factory MotionEvent.fromJson(Map<String, Object?> j) => MotionEvent(
        time: readEpochMs(j['t']) ?? DateTime.fromMillisecondsSinceEpoch(0),
        source: readString(j['source']) ?? '',
        change: readDouble(j['change']) ?? 0,
      );

  final DateTime time;
  final String source;
  final double change;
}

class WdInfo {
  const WdInfo({required this.ip, required this.port, required this.ipport});

  factory WdInfo.fromJson(Map<String, Object?> j) => WdInfo(
        ip: readString(j['ip']) ?? '',
        port: readInt(j['port']),
        ipport: readString(j['ipport']) ?? '',
      );

  final String ip;
  final int? port;
  final String ipport;
}

class PairInfo {
  const PairInfo({required this.addr, required this.code});

  factory PairInfo.fromJson(Map<String, Object?> j) =>
      PairInfo(addr: readString(j['addr']) ?? '', code: readString(j['code']) ?? '');

  final String addr;
  final String code;
}

class TokenRequest {
  const TokenRequest({required this.id, required this.expiresIn});

  factory TokenRequest.fromJson(Map<String, Object?> j) =>
      TokenRequest(id: readString(j['id']) ?? '', expiresIn: readInt(j['expires_in']) ?? 120);

  final String id;
  final int expiresIn;
}

enum TokenState { pending, denied, expired, approved }

class TokenStatus {
  const TokenStatus({required this.state, this.token});

  /// Unknown states are treated as expired so a polling loop always ends.
  factory TokenStatus.fromJson(Map<String, Object?> j) => TokenStatus(
        state: TokenState.values.asNameMap()[j['status']] ?? TokenState.expired,
        token: readString(j['token']),
      );

  final TokenState state;
  final String? token;
}

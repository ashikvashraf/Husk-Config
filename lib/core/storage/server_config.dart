import '../net/ip_validator.dart';

/// A saved Husk phone. [host] is an IP literal without brackets.
class ServerConfig {
  const ServerConfig({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    this.token,
    required this.createdAt,
    this.lastUsedAt,
  });

  static const int defaultPort = 8090;

  final String id;
  final String name;
  final String host;
  final int port;
  final String? token;
  final DateTime createdAt;
  final DateTime? lastUsedAt;

  String get baseUrl => IpValidator.baseUrl(host, port);
  String get address => IpValidator.authority(host, port);
  bool get hasToken => token != null && token!.isNotEmpty;

  ServerConfig copyWith({
    String? name,
    String? host,
    int? port,
    String? token,
    bool clearToken = false,
    DateTime? lastUsedAt,
  }) =>
      ServerConfig(
        id: id,
        name: name ?? this.name,
        host: host ?? this.host,
        port: port ?? this.port,
        token: clearToken ? null : (token ?? this.token),
        createdAt: createdAt,
        lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        'token': token,
        'createdAt': createdAt.toIso8601String(),
        'lastUsedAt': lastUsedAt?.toIso8601String(),
      };

  /// Returns null instead of throwing when required fields are missing or
  /// have the wrong type, so one bad entry never breaks the whole list.
  static ServerConfig? tryFromJson(Map<String, Object?> json) {
    if (json case {'id': final String id, 'host': final String host, 'port': final int port, 'createdAt': final String created}) {
      final createdAt = DateTime.tryParse(created);
      if (createdAt == null) return null;
      final name = json['name'];
      final token = json['token'];
      final lastUsed = json['lastUsedAt'];
      return ServerConfig(
        id: id,
        name: name is String && name.isNotEmpty ? name : host,
        host: host,
        port: port,
        token: token is String ? token : null,
        createdAt: createdAt,
        lastUsedAt: lastUsed is String ? DateTime.tryParse(lastUsed) : null,
      );
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is ServerConfig &&
      other.id == id &&
      other.name == name &&
      other.host == host &&
      other.port == port &&
      other.token == token &&
      other.createdAt == createdAt &&
      other.lastUsedAt == lastUsedAt;

  @override
  int get hashCode => Object.hash(id, name, host, port, token, createdAt, lastUsedAt);
}

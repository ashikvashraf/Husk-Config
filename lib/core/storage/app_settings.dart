import 'package:flutter/material.dart';

enum ScreenMode { mjpeg, h264, webview }

class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.pollIntervalSeconds = 10,
    this.defaultScreenMode = ScreenMode.mjpeg,
    this.tokenClientName = 'Husk Config',
  });

  /// 0 means "off" (manual refresh only).
  static const List<int> pollIntervalOptions = [0, 5, 10, 30, 60];

  /// Husk accepts `[A-Za-z0-9 ._-]`, at most 32 characters, for the token client name.
  static bool isValidClientName(String name) => RegExp(r'^[A-Za-z0-9 ._-]{1,32}$').hasMatch(name);

  final ThemeMode themeMode;
  final int pollIntervalSeconds;
  final ScreenMode defaultScreenMode;
  final String tokenClientName;

  AppSettings copyWith({
    ThemeMode? themeMode,
    int? pollIntervalSeconds,
    ScreenMode? defaultScreenMode,
    String? tokenClientName,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        pollIntervalSeconds: pollIntervalSeconds ?? this.pollIntervalSeconds,
        defaultScreenMode: defaultScreenMode ?? this.defaultScreenMode,
        tokenClientName: tokenClientName ?? this.tokenClientName,
      );

  Map<String, Object?> toJson() => {
        'themeMode': themeMode.name,
        'pollIntervalSeconds': pollIntervalSeconds,
        'defaultScreenMode': defaultScreenMode.name,
        'tokenClientName': tokenClientName,
      };

  factory AppSettings.fromJson(Map<String, Object?> json) {
    const d = AppSettings();
    final poll = json['pollIntervalSeconds'];
    final name = json['tokenClientName'];
    return AppSettings(
      themeMode: ThemeMode.values.asNameMap()[json['themeMode']] ?? d.themeMode,
      pollIntervalSeconds: poll is int && pollIntervalOptions.contains(poll) ? poll : d.pollIntervalSeconds,
      defaultScreenMode: ScreenMode.values.asNameMap()[json['defaultScreenMode']] ?? d.defaultScreenMode,
      tokenClientName: name is String && isValidClientName(name) ? name : d.tokenClientName,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.themeMode == themeMode &&
      other.pollIntervalSeconds == pollIntervalSeconds &&
      other.defaultScreenMode == defaultScreenMode &&
      other.tokenClientName == tokenClientName;

  @override
  int get hashCode => Object.hash(themeMode, pollIntervalSeconds, defaultScreenMode, tokenClientName);
}

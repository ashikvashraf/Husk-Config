# Husk Config Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build "Husk Config", a personal Flutter app for iOS, Android, Windows and macOS that manages multiple Husk phones (status, hardware controls, camera, live screen with remote input, and advanced tools) over the Husk Device API.

**Architecture:** Riverpod providers sit between Material 3 adaptive screens and a hand-written `HuskApi` (dio) client. The client injects the `?token=` query parameter and maps failures to a sealed `HuskException`. Pure-Dart services (`MjpegParser`, `LanScanner`, `TokenRequestFlow`, `CoordinateMapper`) carry the logic and are unit-tested. Servers and settings are stored as plain JSON in `shared_preferences` behind repository interfaces.

**Tech Stack:**
- Flutter 3.44.8 / Dart 3.12.2
- Riverpod 3 (`flutter_riverpod` ^3.4.3), `go_router` ^18.0.2, `dio` ^5.11.1, `shared_preferences` ^2.5.6
- `media_kit` ^1.2.6, `flutter_inappwebview` ^6.1.5, `network_info_plus` ^8.2.2
- Tests: `flutter_test` + `mocktail`

**Spec:** `docs/superpowers/specs/2026-10-07-husk-config-app-design.md` (read it before starting any task; section numbers below refer to it).

## Global Constraints

- Project: `flutter create --org com.ava --project-name huskconfig`.
  - Bundle/application id `com.ava.huskconfig`.
  - Display name **"Husk Config"**.
  - Dart package imports are `package:huskconfig/...`.
- Platforms: **ios, android, windows, macos only.** No web/linux, so `dart:io` may be used anywhere.
- Dependency versions (as resolved on 2026-10-07):
  - `flutter_riverpod ^3.4.3`, `go_router ^18.0.2`, `dio ^5.11.1`, `shared_preferences ^2.5.6`, `uuid ^4.6.0`
  - `media_kit ^1.2.6`, `media_kit_video ^2.0.1`, `media_kit_libs_video ^1.0.7`, `flutter_inappwebview ^6.1.5`
  - `network_info_plus ^8.2.2`, `file_selector ^1.1.0`, `share_plus ^13.3.1`, `url_launcher ^6.3.3`, `package_info_plus ^10.2.2`
  - dev: `mocktail`
- Riverpod 3 conventions:
  - Functional providers get a non-generic `Ref`.
  - Family notifiers receive their argument through the constructor.
  - Auto-retry is **disabled** everywhere: `ProviderScope(retry: (_, _) => null)` and `ProviderContainer(retry: (_, _) => null)`.
- UI text is **English only**. Material 3, `ColorScheme.fromSeed(seedColor: Colors.teal)`, light/dark/system from settings.
- Adaptive breakpoint: width **≥ 600** logical px uses `NavigationRail`; narrower uses `NavigationBar`.
- Server hosts are **IP literals only** (Husk rejects hostnames). Default port **8090**.
- Tokens are stored in plain text in `shared_preferences` (user decision) and are **never logged or printed**.
- All network access goes through `HuskApi`; widgets never touch `Dio`.
- Confirmation dialogs only for `/devoptions`, `/wd`, `/pair`, `/token/set`, and the first `/rpc` per app session.
- After every task: `flutter analyze` reports **No issues found** and `flutter test` passes. If the analyzer raises a style info the plan's code didn't anticipate (e.g. a missing `const`), fix it in place; that is expected and not a deviation.
- Commit after every task. Commit message trailer:
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_018vGW2sL6yV3eTZKrrtJar3
  ```
- Test device: `http://192.168.0.106:8090` (no token configured). **Never** call `/token/request`, `/token/set`, `/devoptions`, `/wd`, `/pair` or `/set` against it from automated steps. Those are manual, user-approved checks (Task 23).

## Review Focus

1. **JSON endpoint answering plain-text `ERR …` with HTTP 200.** Observed: `/location` without a GPS fix. The user should see the device's message, not a crash or "FormatException". Pinned by Task 6 (`location() turns a plain-text ERR reply into DeviceErrorException`) and Task 17 (overview shows the message).
2. **Corrupt or partially invalid stored JSON** (hand-edited prefs, future schema change). The app must still start, keep every valid server and fall back to default settings. Pinned by Task 4.
3. **Host typed with spaces, brackets, a hostname, a partial IP or an IPv6 scope id.** The host should be normalized or rejected with "Husk only accepts IP addresses", and IPv6 URLs must be bracketed. Pinned by Task 3 and Task 14.
4. **MJPEG part that never ends** (missing boundary, bogus Content-Length). Memory must stay bounded and the parser must recover on the next valid part. Pinned by Task 8.
5. **Query values with URL-special characters** (token `a b&c`, `/text` input `a&b c`, `/rpc` command `click 0 Wi-Fi & more`). They must reach the phone intact. Pinned by Task 5 and Task 7.

---

## File Structure

```
lib/
  main.dart                                  # bootstraps prefs, MediaKit, ProviderScope
  app.dart                                   # HuskConfigApp: theme, router, lifecycle → appForegroundProvider
  core/
    providers.dart                           # sharedPreferences/repository/appForeground/pollInterval providers
    polling.dart                             # pollEvery() stream helper
    router.dart                              # createRouter()
    api/
      husk_api.dart                          # HuskApi: plumbing + every endpoint
      husk_exception.dart                    # sealed HuskException + subtypes
      text_result.dart                       # TextResult (OK/NONE/ERR helpers)
      token_request_flow.dart                # TokenRequestFlow state machine
      token_rules.dart                       # generateToken / isValidNewToken
      models/json_read.dart                  # tolerant JSON readers
      models/device_models.dart              # DeviceInfo, ServiceState, Flags
      models/hardware_models.dart            # Battery/Connectivity/Display/Location/Mic/Sensor/Volume/Brightness/DisplayEntry
      models/tools_models.dart               # Motion*, WdInfo, PairInfo, TokenRequest, TokenStatus, NavKey
    net/
      ip_validator.dart                      # IP literal validation, base URL building
      lan_scanner.dart                       # /24 scan with bounded concurrency
    storage/
      server_config.dart                     # ServerConfig model
      app_settings.dart                      # AppSettings + ScreenMode
      server_repository.dart                 # ServerRepository + PrefsServerRepository
      settings_repository.dart               # SettingsRepository + PrefsSettingsRepository
    stream/
      mjpeg_stream.dart                      # MjpegParser stream transformer
  features/
    servers/
      servers_controller.dart                # serversProvider, serverByIdProvider
      api_provider.dart                      # apiProvider family (HuskApi per server)
      server_actions.dart                    # confirmDeleteServer helper
      server_form_screen.dart                # add/edit server
      token_request_dialog.dart              # TokenRequestDialog + requestTokenForServer
      scan_screen.dart                       # LAN scan UI + providers
    settings/
      settings_controller.dart               # settingsProvider
      settings_screen.dart
    dashboard/
      server_status.dart                     # ServerStatus + serverStatusProvider
      server_card.dart
      dashboard_screen.dart
    device/
      device_shell.dart                      # tabs + rail/bottom nav + server switcher
      overview_providers.dart                # per-endpoint providers (incl. flags, displays) + refreshOverview
      overview_tab.dart                      # layout of overview cards
      status_cards.dart                      # Device/Services/Battery/Connectivity/Display/Location cards
      controls_card.dart                     # torch, vibrate, wake, brightness, ringer, volume
      sensors_card.dart                      # SensorsCard + MicCard
    camera/
      snapshot.dart                          # fetchWithWarmup()
      camera_tab.dart
    screen/
      coordinate_mapper.dart
      input_queue.dart
      gesture_layer.dart
      input_controls.dart                    # NavBar + KeyboardPanel
      screen_mode.dart                       # session mode + effectiveScreenMode()
      h264_view.dart
      web_control_view.dart
      screen_tab.dart
    tools/
      tools_tab.dart
      tools_providers.dart
      inspect_tool.dart
      launch_tool.dart
      motion_tool.dart
      management_tool.dart
      rpc_tool.dart
      token_tool.dart
  shared/
    error_text.dart                          # describeError()
    run_command.dart                         # runCommand(): snackbar feedback for TextResult actions
    save_image.dart                          # saveImage(): desktop save dialog / mobile share
    widgets/
      status_dot.dart
      confirm_dialog.dart
      section_card.dart                      # SectionCard + AsyncSection + InfoRow
      result_box.dart
      mjpeg_view.dart
test/
  support/fake_adapter.dart                  # dio HttpClientAdapter fake
  support/memory_repos.dart                  # in-memory repositories
  support/mocks.dart                         # MockHuskApi
  support/fixtures.dart                      # server1, deviceInfoFixture(), flagsFixture()
  support/test_app.dart                      # testScope(), testApp()
  support/overview_stubs.dart                # stubOverview(MockHuskApi)
  ...mirrors lib/ paths with *_test.dart
docs/manual-test-checklist.md
README.md
```

---

### Task 1: Scaffold the Flutter project and platform configuration

**Files:**
- Create (by `flutter create`): `pubspec.yaml`, `lib/main.dart`, `android/`, `ios/`, `macos/`, `windows/`, `test/widget_test.dart`, `analysis_options.yaml`, `.gitignore`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Create: `android/app/src/main/res/xml/network_security_config.xml`
- Modify: `ios/Runner/Info.plist`, `macos/Runner/Info.plist`, `macos/Runner/DebugProfile.entitlements`, `macos/Runner/Release.entitlements`, `macos/Runner/Configs/AppInfo.xcconfig`, `windows/runner/main.cpp`, `windows/runner/Runner.rc`
- Replace: `lib/main.dart`, `test/widget_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: a buildable project named `huskconfig` with all dependencies resolved.

- [ ] **Step 1: Create the project in the existing repo root**

The repo already contains `husk-openapi-json.json` and `docs/`; `flutter create` works in a non-empty directory.

Run:
```bash
cd /Users/ashikvashraf/Documents/FlutterProjects/husk_config_app
flutter create --org com.ava --project-name huskconfig --platforms ios,android,windows,macos .
```
Expected: ends with `All done!`.

- [ ] **Step 2: Add dependencies**

Run:
```bash
flutter pub add flutter_riverpod go_router dio shared_preferences uuid media_kit media_kit_video media_kit_libs_video flutter_inappwebview network_info_plus file_selector share_plus url_launcher package_info_plus
flutter pub add dev:mocktail
```
Expected: `Changed N dependencies!`. `pubspec.yaml` now lists the versions in Global Constraints (newer patch versions are fine).

- [ ] **Step 3: Android: permissions, cleartext HTTP, label**

Edit `android/app/src/main/AndroidManifest.xml`.

Add these lines directly inside `<manifest …>`, before `<application`:
```xml
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
```

Then change the `<application` opening tag attributes to:
```xml
    <application
        android:label="Husk Config"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher"
        android:usesCleartextTraffic="true"
        android:networkSecurityConfig="@xml/network_security_config">
```

Create `android/app/src/main/res/xml/network_security_config.xml`:
```xml
<?xml version="1.0" encoding="utf-8"?>
<!-- Husk serves plain HTTP on LAN/Tailscale IPs; allow cleartext everywhere. -->
<network-security-config>
    <base-config cleartextTrafficPermitted="true" />
</network-security-config>
```

- [ ] **Step 4: iOS: display name, ATS, local network permission**

In `ios/Runner/Info.plist`, set the `CFBundleDisplayName` string value to `Husk Config`. Then add these keys inside the top-level `<dict>`:
```xml
	<key>NSAppTransportSecurity</key>
	<dict>
		<key>NSAllowsArbitraryLoads</key>
		<true/>
		<key>NSAllowsLocalNetworking</key>
		<true/>
	</dict>
	<key>NSLocalNetworkUsageDescription</key>
	<string>Husk Config connects to Husk phones on your local network and scans it to find them.</string>
```

- [ ] **Step 5: macOS: name, ATS, entitlements**

In `macos/Runner/Configs/AppInfo.xcconfig`, set:
```
PRODUCT_NAME = Husk Config
```

In `macos/Runner/Info.plist`, add the same `NSAppTransportSecurity` dict as Step 4, inside the top-level `<dict>`.

In **both** `macos/Runner/DebugProfile.entitlements` and `macos/Runner/Release.entitlements`, add inside `<dict>`:
```xml
	<key>com.apple.security.network.client</key>
	<true/>
	<key>com.apple.security.files.user-selected.read-write</key>
	<true/>
```
(`DebugProfile` already has `network.server`; keep it.)

- [ ] **Step 6: Windows: window title and product name**

In `windows/runner/main.cpp`, replace `L"huskconfig"` in the `window.Create(...)` call with `L"Husk Config"`.

In `windows/runner/Runner.rc`, set:
- the `"FileDescription"` value to `"Husk Config"`
- the `"ProductName"` value to `"Husk Config"`

- [ ] **Step 7: Replace the counter app with a minimal placeholder and its test**

`lib/main.dart` (replaced in Task 13):
```dart
import 'package:flutter/material.dart';

void main() => runApp(const MaterialApp(home: Scaffold(body: Center(child: Text('Husk Config')))));
```

`test/widget_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/main.dart' as app;

void main() {
  testWidgets('app boots', (tester) async {
    app.main();
    await tester.pump();
    expect(find.text('Husk Config'), findsOneWidget);
  });
}
```

- [ ] **Step 8: Verify analyze, test, and a macOS + Android debug build**

Run:
```bash
flutter analyze && flutter test && flutter build macos --debug && flutter build apk --debug
```
Expected:
- `No issues found!`
- `All tests passed!`
- `✓ Built build/macos/Build/Products/Debug/Husk Config.app`
- `✓ Built build/app/outputs/flutter-apk/app-debug.apk`

If the APK build fails with a minSdk error from `media_kit` or `flutter_inappwebview`, set `minSdk = 24` in `android/app/build.gradle.kts` (replacing `flutter.minSdkVersion`) and re-run.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "chore: scaffold huskconfig Flutter app with platform network config

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_018vGW2sL6yV3eTZKrrtJar3"
```

---

### Task 2 (spike, throwaway code): H.264 `/screen.mp4` playback via media_kit

This is the spec's highest-risk item (§5.9, §8). Its output is a **findings document**, not kept code. Task 20 reads the findings to decide which platforms get the H.264 mode.

**Files:**
- Create (temporary, deleted in Step 4): `lib/spike_h264_main.dart`
- Create: `docs/superpowers/spikes/2026-10-07-h264-media-kit.md`

**Interfaces:**
- Consumes: Task 1 project.
- Produces: the findings doc with a line `H264_PLATFORMS: <comma list>` used by Task 20.

- [ ] **Step 1: Ask the user to enable screen sharing on the test phone**

The phone at `192.168.0.106` currently reports `"screen": false` in `/flags`. `/screen.mp4` needs screen sharing on. Ask the user to enable it in the Husk app, then confirm:

```bash
curl -s http://192.168.0.106:8090/flags
```
Expected: JSON containing `"screen":true`.

- [ ] **Step 2: Write the throwaway spike entrypoint**

`lib/spike_h264_main.dart`:
```dart
// THROWAWAY SPIKE — deleted at the end of Task 2.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const MaterialApp(home: _Spike()));
}

class _Spike extends StatefulWidget {
  const _Spike();
  @override
  State<_Spike> createState() => _SpikeState();
}

class _SpikeState extends State<_Spike> {
  final player = Player();
  late final controller = VideoController(player);
  final log = <String>[];
  Timer? timer;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final native = player.platform;
    if (native is NativePlayer) {
      await native.setProperty('profile', 'low-latency');
      await native.setProperty('cache', 'no');
      await native.setProperty('untimed', 'yes');
    }
    player.stream.error.listen((e) => setState(() => log.add('ERROR $e')));
    await player.open(Media('http://192.168.0.106:8090/screen.mp4'));
    timer = Timer.periodic(const Duration(seconds: 2), (_) {
      final s = player.state;
      setState(() => log.add('pos=${s.position} buf=${s.buffer} w=${s.width} h=${s.height} playing=${s.playing}'));
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Row(children: [
          Expanded(child: Video(controller: controller, controls: NoVideoControls)),
          SizedBox(width: 360, child: ListView(children: [for (final l in log.reversed) Text(l, style: const TextStyle(fontSize: 11))])),
        ]),
      );
}
```

- [ ] **Step 3: Run on macOS (and on Android if a device is attached) and observe**

Run:
```bash
flutter run -d macos -t lib/spike_h264_main.dart
```

Observe for about 60 s while scrolling or opening apps on the phone:
1. Does video appear?
2. Is there any `ERROR` line?
3. Rough end-to-end latency: tap something on the phone and estimate how long until the change shows in the app.
4. Does latency grow over time? Compare `pos` vs `buf` growth.

Then try a catch-up seek. Add `player.seek(player.state.buffer)` inside the timer when `buf - pos > 2s`, re-run, and note whether it helps.

Repeat with `flutter run -d <android-device-id> -t lib/spike_h264_main.dart` if available. Windows and iOS can only be tested on those machines/devices; mark them `untested`.

- [ ] **Step 4: Record findings, delete the spike, commit**

Write `docs/superpowers/spikes/2026-10-07-h264-media-kit.md`:
```markdown
# Spike: H.264 /screen.mp4 via media_kit (2026-10-07)

Question: Can media_kit play Husk's live fMP4 /screen.mp4 with acceptable latency?

| Platform | Plays? | Errors | Approx. latency | Drift over 60 s | Catch-up seek helps? |
|---|---|---|---|---|---|
| macOS | <yes/no> | <none / text> | <~N ms> | <yes/no> | <yes/no/n.a.> |
| Android | <…> | <…> | <…> | <…> | <…> |
| iOS | untested | | | | |
| Windows | untested | | | | |

Recommendation: <one or two sentences>.

H264_PLATFORMS: <comma-separated subset of android,ios,macos,windows that passed; include untested platforms only if macOS passed>
CATCH_UP_SEEK: <on|off>
```
Fill every `<…>` with what you observed.

Then delete the spike and commit:
```bash
rm lib/spike_h264_main.dart
git add docs/superpowers/spikes/2026-10-07-h264-media-kit.md
git commit -m "docs: record H.264 media_kit spike findings

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_018vGW2sL6yV3eTZKrrtJar3"
```

---

### Task 3: IP validation, `ServerConfig`, `AppSettings`

**Files:**
- Create: `lib/core/net/ip_validator.dart`, `lib/core/storage/server_config.dart`, `lib/core/storage/app_settings.dart`
- Test: `test/core/net/ip_validator_test.dart`, `test/core/storage/models_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `abstract final class IpValidator`, with static methods:
    - `String normalizeHost(String input)`
    - `bool isIpLiteral(String input)`
    - `bool isValidPort(int? port)`
    - `String authority(String host, int port)`
    - `String baseUrl(String host, int port)`
  - `class ServerConfig`:
    - fields `id, name, host, port, token, createdAt, lastUsedAt`
    - `static const int defaultPort = 8090`
    - getters `baseUrl`, `address`, `hasToken`
    - `copyWith({String? name, String? host, int? port, String? token, bool clearToken = false, DateTime? lastUsedAt})`
    - `Map<String, Object?> toJson()`, `static ServerConfig? tryFromJson(Map<String, Object?> json)`
    - value `==`/`hashCode`
  - `enum ScreenMode { mjpeg, h264, webview }`
  - `class AppSettings`:
    - fields `themeMode, pollIntervalSeconds, defaultScreenMode, tokenClientName`
    - `static const List<int> pollIntervalOptions = [0, 5, 10, 30, 60]`
    - `static bool isValidClientName(String name)`
    - `copyWith(...)`, `toJson()`, `factory AppSettings.fromJson(Map<String, Object?>)`
    - value `==`/`hashCode`

- [ ] **Step 1: Write failing tests for `IpValidator`**

`test/core/net/ip_validator_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/net/ip_validator.dart';

void main() {
  group('isIpLiteral', () {
    test('accepts IPv4, IPv6 and bracketed IPv6, ignoring surrounding spaces', () {
      for (final ok in ['192.168.0.106', '100.100.101.101', '::1', 'fd7a:115c:a1e0::1', '[fd7a:115c:a1e0::1]', ' 10.0.0.1 ']) {
        expect(IpValidator.isIpLiteral(ok), isTrue, reason: ok);
      }
    });

    test('rejects hostnames, partial or out-of-range IPs, scoped IPv6 and empty input', () {
      for (final bad in ['phone.local', 'localhost', '192.168.0', '256.1.1.1', '1.2.3.4.5', 'fe80::1%en0', '', '   ', 'http://10.0.0.1']) {
        expect(IpValidator.isIpLiteral(bad), isFalse, reason: bad);
      }
    });
  });

  test('normalizeHost trims and strips IPv6 brackets', () {
    expect(IpValidator.normalizeHost(' [::1] '), '::1');
    expect(IpValidator.normalizeHost(' 10.0.0.1'), '10.0.0.1');
  });

  test('isValidPort boundaries', () {
    expect(IpValidator.isValidPort(null), isFalse);
    expect(IpValidator.isValidPort(0), isFalse);
    expect(IpValidator.isValidPort(1), isTrue);
    expect(IpValidator.isValidPort(65535), isTrue);
    expect(IpValidator.isValidPort(65536), isFalse);
  });

  test('baseUrl brackets IPv6 hosts', () {
    expect(IpValidator.baseUrl('192.168.0.106', 8090), 'http://192.168.0.106:8090');
    expect(IpValidator.baseUrl('fd7a::1', 8090), 'http://[fd7a::1]:8090');
    expect(IpValidator.authority('fd7a::1', 8090), '[fd7a::1]:8090');
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/core/net/ip_validator_test.dart`
Expected: FAIL, compilation error `Target of URI doesn't exist: 'package:huskconfig/core/net/ip_validator.dart'`.

- [ ] **Step 3: Implement `IpValidator`**

`lib/core/net/ip_validator.dart`:
```dart
import 'dart:io';

/// Husk rejects requests whose Host header is not an IP literal, so every
/// server address in the app is validated and formatted here.
abstract final class IpValidator {
  /// Trims whitespace and strips surrounding IPv6 brackets.
  static String normalizeHost(String input) {
    final s = input.trim();
    if (s.length > 2 && s.startsWith('[') && s.endsWith(']')) {
      return s.substring(1, s.length - 1);
    }
    return s;
  }

  /// True for IPv4/IPv6 literals. Scoped IPv6 (`fe80::1%en0`) is rejected
  /// because the zone id cannot be expressed in a plain http URL.
  static bool isIpLiteral(String input) {
    final host = normalizeHost(input);
    if (host.isEmpty || host.contains('%')) return false;
    return InternetAddress.tryParse(host) != null;
  }

  static bool isValidPort(int? port) => port != null && port >= 1 && port <= 65535;

  /// `host:port`, with IPv6 hosts bracketed.
  static String authority(String host, int port) =>
      host.contains(':') ? '[$host]:$port' : '$host:$port';

  static String baseUrl(String host, int port) => 'http://${authority(host, port)}';
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/core/net/ip_validator_test.dart`
Expected: `All tests passed!`

- [ ] **Step 5: Write failing tests for `ServerConfig` and `AppSettings`**

`test/core/storage/models_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/storage/app_settings.dart';
import 'package:huskconfig/core/storage/server_config.dart';

void main() {
  final created = DateTime.utc(2026, 10, 7, 12);

  group('ServerConfig', () {
    final server = ServerConfig(
      id: 'a1',
      name: 'Kitchen phone',
      host: '192.168.0.106',
      port: 8090,
      token: 'secret',
      createdAt: created,
    );

    test('JSON round trip preserves all fields', () {
      final withUse = server.copyWith(lastUsedAt: created.add(const Duration(hours: 1)));
      expect(ServerConfig.tryFromJson(withUse.toJson()), withUse);
    });

    test('derived getters', () {
      expect(server.baseUrl, 'http://192.168.0.106:8090');
      expect(server.address, '192.168.0.106:8090');
      expect(server.hasToken, isTrue);
      expect(server.copyWith(clearToken: true).hasToken, isFalse);
      expect(server.copyWith(token: '').hasToken, isFalse);
    });

    test('tryFromJson returns null for missing required fields or wrong types', () {
      expect(ServerConfig.tryFromJson({'id': 'x'}), isNull);
      expect(ServerConfig.tryFromJson({'id': 'x', 'host': '10.0.0.1', 'port': '8090', 'createdAt': created.toIso8601String()}), isNull);
      expect(ServerConfig.tryFromJson({'id': 'x', 'host': '10.0.0.1', 'port': 8090, 'createdAt': 'not a date'}), isNull);
    });

    test('tryFromJson tolerates missing optional fields and uses host as name', () {
      final parsed = ServerConfig.tryFromJson({'id': 'x', 'host': '10.0.0.1', 'port': 8090, 'createdAt': created.toIso8601String()});
      expect(parsed, isNotNull);
      expect(parsed!.name, '10.0.0.1');
      expect(parsed.token, isNull);
      expect(parsed.lastUsedAt, isNull);
    });
  });

  group('AppSettings', () {
    test('defaults', () {
      const s = AppSettings();
      expect(s.themeMode, ThemeMode.system);
      expect(s.pollIntervalSeconds, 10);
      expect(s.defaultScreenMode, ScreenMode.mjpeg);
      expect(s.tokenClientName, 'Husk Config');
    });

    test('JSON round trip', () {
      const s = AppSettings(themeMode: ThemeMode.dark, pollIntervalSeconds: 30, defaultScreenMode: ScreenMode.webview, tokenClientName: 'My Mac');
      expect(AppSettings.fromJson(s.toJson()), s);
    });

    test('fromJson falls back to defaults for unknown or invalid values', () {
      final s = AppSettings.fromJson({'themeMode': 'purple', 'pollIntervalSeconds': 7, 'defaultScreenMode': 'vr', 'tokenClientName': 'bad/name!'});
      expect(s, const AppSettings());
    });

    test('isValidClientName', () {
      expect(AppSettings.isValidClientName('Husk Config'), isTrue);
      expect(AppSettings.isValidClientName('mac-mini_2.local'), isTrue);
      expect(AppSettings.isValidClientName(''), isFalse);
      expect(AppSettings.isValidClientName('a' * 33), isFalse);
      expect(AppSettings.isValidClientName('emoji 😀'), isFalse);
    });
  });
}
```

- [ ] **Step 6: Run to verify it fails**

Run: `flutter test test/core/storage/models_test.dart`
Expected: FAIL, compilation errors for missing `server_config.dart` / `app_settings.dart`.

- [ ] **Step 7: Implement `ServerConfig`**

`lib/core/storage/server_config.dart`:
```dart
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
```

- [ ] **Step 8: Implement `AppSettings`**

`lib/core/storage/app_settings.dart`:
```dart
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
```

- [ ] **Step 9: Run tests and analyze**

Run: `flutter test test/core && flutter analyze`
Expected: `All tests passed!` and `No issues found!`

- [ ] **Step 10: Commit**

```bash
git add lib/core test/core
git commit -m "feat: add IP validation and server/settings models

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_018vGW2sL6yV3eTZKrrtJar3"
```

---

### Task 4: Server and settings repositories

**Files:**
- Create: `lib/core/storage/server_repository.dart`, `lib/core/storage/settings_repository.dart`, `test/support/memory_repos.dart`
- Test: `test/core/storage/repositories_test.dart`

**Interfaces:**
- Consumes: `ServerConfig.tryFromJson/toJson`, `AppSettings.fromJson/toJson` (Task 3).
- Produces:
  - `abstract interface class ServerRepository { List<ServerConfig> loadAll(); Future<void> saveAll(List<ServerConfig> servers); }`
  - `class PrefsServerRepository implements ServerRepository` with `PrefsServerRepository(SharedPreferences prefs)` and `static const key = 'servers.v1'`
  - `abstract interface class SettingsRepository { AppSettings load(); Future<void> save(AppSettings settings); }`
  - `class PrefsSettingsRepository implements SettingsRepository` with `static const key = 'settings.v1'`
  - test helpers `MemoryServerRepository([List<ServerConfig> initial])` (public `List<ServerConfig> saved`) and `MemorySettingsRepository([AppSettings initial])` (public `AppSettings saved`)

- [ ] **Step 1: Write failing tests**

`test/core/storage/repositories_test.dart`:
```dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/storage/app_settings.dart';
import 'package:huskconfig/core/storage/server_config.dart';
import 'package:huskconfig/core/storage/server_repository.dart';
import 'package:huskconfig/core/storage/settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final server = ServerConfig(id: 'a', name: 'A', host: '10.0.0.1', port: 8090, createdAt: DateTime.utc(2026));

  group('PrefsServerRepository', () {
    test('empty when nothing stored', () async {
      SharedPreferences.setMockInitialValues({});
      final repo = PrefsServerRepository(await SharedPreferences.getInstance());
      expect(repo.loadAll(), isEmpty);
    });

    test('saveAll then loadAll round trips', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await PrefsServerRepository(prefs).saveAll([server]);
      expect(PrefsServerRepository(prefs).loadAll(), [server]);
    });

    test('corrupt JSON yields an empty list instead of throwing', () async {
      SharedPreferences.setMockInitialValues({PrefsServerRepository.key: '{not json'});
      final repo = PrefsServerRepository(await SharedPreferences.getInstance());
      expect(repo.loadAll(), isEmpty);
    });

    test('invalid entries are skipped, valid ones kept', () async {
      SharedPreferences.setMockInitialValues({
        PrefsServerRepository.key: jsonEncode([server.toJson(), {'id': 'broken'}, 42]),
      });
      final repo = PrefsServerRepository(await SharedPreferences.getInstance());
      expect(repo.loadAll(), [server]);
    });

    test('a non-list top-level value yields an empty list', () async {
      SharedPreferences.setMockInitialValues({PrefsServerRepository.key: '{"id":"a"}'});
      final repo = PrefsServerRepository(await SharedPreferences.getInstance());
      expect(repo.loadAll(), isEmpty);
    });
  });

  group('PrefsSettingsRepository', () {
    test('defaults when nothing stored or corrupt', () async {
      SharedPreferences.setMockInitialValues({PrefsSettingsRepository.key: '[1,2'});
      final repo = PrefsSettingsRepository(await SharedPreferences.getInstance());
      expect(repo.load(), const AppSettings());
    });

    test('save then load round trips', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      const s = AppSettings(themeMode: ThemeMode.light, pollIntervalSeconds: 60);
      await PrefsSettingsRepository(prefs).save(s);
      expect(PrefsSettingsRepository(prefs).load(), s);
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/core/storage/repositories_test.dart`
Expected: FAIL, compilation errors for missing repository files.

- [ ] **Step 3: Implement the repositories**

`lib/core/storage/server_repository.dart`:
```dart
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'server_config.dart';

abstract interface class ServerRepository {
  List<ServerConfig> loadAll();
  Future<void> saveAll(List<ServerConfig> servers);
}

class PrefsServerRepository implements ServerRepository {
  PrefsServerRepository(this._prefs);

  static const key = 'servers.v1';
  final SharedPreferences _prefs;

  @override
  List<ServerConfig> loadAll() {
    final raw = _prefs.getString(key);
    if (raw == null) return [];
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return [];
    }
    if (decoded is! List) return [];
    final servers = <ServerConfig>[];
    for (final entry in decoded) {
      if (entry is Map<String, Object?>) {
        final server = ServerConfig.tryFromJson(entry);
        if (server != null) servers.add(server);
      }
    }
    return servers;
  }

  @override
  Future<void> saveAll(List<ServerConfig> servers) =>
      _prefs.setString(key, jsonEncode([for (final s in servers) s.toJson()]));
}
```

`lib/core/storage/settings_repository.dart`:
```dart
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'app_settings.dart';

abstract interface class SettingsRepository {
  AppSettings load();
  Future<void> save(AppSettings settings);
}

class PrefsSettingsRepository implements SettingsRepository {
  PrefsSettingsRepository(this._prefs);

  static const key = 'settings.v1';
  final SharedPreferences _prefs;

  @override
  AppSettings load() {
    final raw = _prefs.getString(key);
    if (raw == null) return const AppSettings();
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, Object?> ? AppSettings.fromJson(decoded) : const AppSettings();
    } on FormatException {
      return const AppSettings();
    }
  }

  @override
  Future<void> save(AppSettings settings) => _prefs.setString(key, jsonEncode(settings.toJson()));
}
```

`test/support/memory_repos.dart`:
```dart
import 'package:huskconfig/core/storage/app_settings.dart';
import 'package:huskconfig/core/storage/server_config.dart';
import 'package:huskconfig/core/storage/server_repository.dart';
import 'package:huskconfig/core/storage/settings_repository.dart';

class MemoryServerRepository implements ServerRepository {
  MemoryServerRepository([List<ServerConfig> initial = const []]) : saved = [...initial];

  List<ServerConfig> saved;

  @override
  List<ServerConfig> loadAll() => [...saved];

  @override
  Future<void> saveAll(List<ServerConfig> servers) async => saved = [...servers];
}

class MemorySettingsRepository implements SettingsRepository {
  MemorySettingsRepository([this.saved = const AppSettings()]);

  AppSettings saved;

  @override
  AppSettings load() => saved;

  @override
  Future<void> save(AppSettings settings) async => saved = settings;
}
```

- [ ] **Step 4: Run tests and analyze**

Run: `flutter test test/core/storage && flutter analyze`
Expected: `All tests passed!` and `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/core/storage test/core/storage test/support
git commit -m "feat: add shared_preferences repositories for servers and settings

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_018vGW2sL6yV3eTZKrrtJar3"
```

---

### Task 5: `HuskApi` plumbing, exceptions and `TextResult`

**Files:**
- Create: `lib/core/api/husk_exception.dart`, `lib/core/api/text_result.dart`, `lib/core/api/husk_api.dart`, `test/support/fake_adapter.dart`
- Test: `test/core/api/husk_api_core_test.dart`

**Interfaces:**
- Consumes: nothing from earlier tasks (callers pass `baseUrl` strings built by `IpValidator.baseUrl`).
- Produces:
  - `sealed class HuskException implements Exception { final String message; }` with subtypes:
    - `OfflineException(String message)`
    - `UnauthorizedException()`
    - `HttpStatusException(int statusCode, String body)`
    - `DeviceErrorException(String message)`
  - `class TextResult { final String raw; String get text; bool get isOk; bool get isNone; bool get isErr; }`
  - `typedef MultipartResponse = ({String contentType, Stream<Uint8List> stream});`
  - `class HuskApi`, constructed with `HuskApi({required String baseUrl, String? token, HttpClientAdapter? adapter, Duration connectTimeout = 3s, Duration receiveTimeout = 10s})`. Members:
    - `final String baseUrl`, `final String? token`
    - `void close()`
    - `Uri uri(String path, [Map<String, Object?> query])`
    - `Future<bool> healthz()`
    - `Future<Uint8List> snapshot()`, `Future<Uint8List> screenshot()`
    - `Future<MultipartResponse> openMultipart(String path, {CancelToken? cancelToken})`
    - `Future<String> dump({int display = 0})`, `Future<String> rpc(String command)`
  - Private helpers used by Tasks 6–7 inside the same class: `_text`, `_command`, `_json`, `_map`, `_list`, `_bytes`, with the signatures shown in Step 3.
  - Test helpers: `FakeAdapter`, `textBody()`, `jsonBody()`, `bytesBody()`, `fakeApi()`.
  - Query-value rules: `null` values are dropped; `bool` is sent as `1`/`0`; everything else via `toString()`; `token` is added only when non-empty and the endpoint is authenticated.

- [ ] **Step 1: Write the dio fake adapter**

`test/support/fake_adapter.dart`:
```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:huskconfig/core/api/husk_api.dart';

typedef FakeHandler = FutureOr<ResponseBody> Function(RequestOptions options);

/// Answers every dio request with [handler] and records the requests.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);

  final FakeHandler handler;
  final List<RequestOptions> requests = [];

  RequestOptions get last => requests.last;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody textBody(String body, {int status = 200}) =>
    ResponseBody.fromString(body, status, headers: {Headers.contentTypeHeader: ['text/plain; charset=utf-8']});

ResponseBody jsonBody(String body, {int status = 200}) =>
    ResponseBody.fromString(body, status, headers: {Headers.contentTypeHeader: ['application/json; charset=utf-8']});

ResponseBody bytesBody(List<int> bytes, {int status = 200, String contentType = 'image/jpeg'}) =>
    ResponseBody.fromBytes(bytes, status, headers: {Headers.contentTypeHeader: [contentType]});

({HuskApi api, FakeAdapter adapter}) fakeApi(FakeHandler handler, {String? token, String baseUrl = 'http://10.0.0.5:8090'}) {
  final adapter = FakeAdapter(handler);
  return (api: HuskApi(baseUrl: baseUrl, token: token, adapter: adapter), adapter: adapter);
}
```

- [ ] **Step 2: Write failing tests**

`test/core/api/husk_api_core_test.dart`:
```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/api/husk_api.dart';
import 'package:huskconfig/core/api/husk_exception.dart';
import 'package:huskconfig/core/api/text_result.dart';

import '../../support/fake_adapter.dart';

void main() {
  test('healthz is true for "ok" and never sends the token', () async {
    final f = fakeApi((_) => textBody('ok\n'), token: 'secret');
    expect(await f.api.healthz(), isTrue);
    expect(f.adapter.last.path, '/healthz');
    expect(f.adapter.last.uri.queryParameters.containsKey('token'), isFalse);
  });

  test('authenticated calls carry the token, with special characters intact', () async {
    final f = fakeApi((_) => textBody('pong'), token: 'a b&c');
    expect(await f.api.rpc('ping'), 'pong');
    expect(f.adapter.last.path, '/rpc');
    expect(f.adapter.last.uri.queryParameters, {'cmd': 'ping', 'token': 'a b&c'});
  });

  test('rpc command with URL-special characters reaches the server intact', () async {
    final f = fakeApi((_) => textBody('OK'));
    await f.api.rpc('click 0 Wi-Fi & more?=1');
    expect(f.adapter.last.uri.queryParameters['cmd'], 'click 0 Wi-Fi & more?=1');
  });

  test('no token parameter when the token is null or empty', () async {
    for (final token in [null, '']) {
      final f = fakeApi((_) => textBody('x'), token: token);
      await f.api.dump();
      expect(f.adapter.last.uri.queryParameters.containsKey('token'), isFalse);
    }
  });

  test('dump sends the display id', () async {
    final f = fakeApi((_) => textBody('tree'));
    expect(await f.api.dump(display: 2), 'tree');
    expect(f.adapter.last.uri.queryParameters['d'], '2');
  });

  test('401 maps to UnauthorizedException', () async {
    final f = fakeApi((_) => textBody('unauthorized', status: 401));
    expect(f.api.rpc('ping'), throwsA(isA<UnauthorizedException>()));
  });

  test('non-2xx maps to HttpStatusException using the JSON error message', () async {
    final f = fakeApi((_) => jsonBody('{"error":"no token set; use /token/request"}', status: 409));
    expect(
      f.api.rpc('x'),
      throwsA(isA<HttpStatusException>()
          .having((e) => e.statusCode, 'statusCode', 409)
          .having((e) => e.message, 'message', 'no token set; use /token/request')),
    );
  });

  test('non-2xx plain-text body becomes the message', () async {
    final f = fakeApi((_) => textBody('not found', status: 404));
    expect(f.api.rpc('x'), throwsA(isA<HttpStatusException>().having((e) => e.message, 'message', 'not found')));
  });

  test('connection failure maps to OfflineException naming the address', () async {
    final f = fakeApi((_) => throw const SocketException('Connection refused'));
    expect(
      f.api.healthz(),
      throwsA(isA<OfflineException>().having((e) => e.message, 'message', "Can't reach 10.0.0.5:8090")),
    );
  });

  test('snapshot returns the JPEG bytes', () async {
    final f = fakeApi((_) => bytesBody([0xFF, 0xD8, 0xFF, 0xD9]));
    expect(await f.api.snapshot(), Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]));
    expect(f.adapter.last.path, '/snapshot');
  });

  test('screenshot 503 maps to HttpStatusException(503)', () async {
    final f = fakeApi((_) => textBody('screen sharing off', status: 503));
    expect(f.api.screenshot(), throwsA(isA<HttpStatusException>().having((e) => e.statusCode, 'statusCode', 503)));
  });

  test('uri() attaches the token and keeps IPv6 brackets', () {
    final api = HuskApi(baseUrl: 'http://[fd7a::1]:8090', token: 't');
    expect(api.uri('/screen.mp4').toString(), 'http://[fd7a::1]:8090/screen.mp4?token=t');
    expect(HuskApi(baseUrl: 'http://10.0.0.5:8090').uri('/control').toString(), 'http://10.0.0.5:8090/control');
  });

  test('openMultipart exposes the content type and the raw body stream', () async {
    final f = fakeApi((_) => ResponseBody(
          Stream.fromIterable([Uint8List.fromList([1, 2]), Uint8List.fromList([3])]),
          200,
          headers: {Headers.contentTypeHeader: ['multipart/x-mixed-replace; boundary=rigframe']},
        ));
    final response = await f.api.openMultipart('/stream');
    expect(response.contentType, contains('boundary=rigframe'));
    expect(await response.stream.expand((chunk) => chunk).toList(), [1, 2, 3]);
  });

  test('openMultipart throws HttpStatusException on non-2xx', () async {
    final f = fakeApi((_) => textBody('screen sharing off', status: 503));
    expect(f.api.openMultipart('/screen'), throwsA(isA<HttpStatusException>()));
  });

  group('TextResult', () {
    test('classifies OK / NONE / ERR', () {
      expect(const TextResult('OK\n').isOk, isTrue);
      expect(const TextResult('OK (media=7)').isOk, isTrue);
      expect(const TextResult('NONE no-focus').isNone, isTrue);
      expect(const TextResult('ERR cancelled').isErr, isTrue);
      expect(const TextResult('OKAY').isOk, isFalse);
      expect(const TextResult('  540 1056 ').text, '540 1056');
    });
  });
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `flutter test test/core/api/husk_api_core_test.dart`
Expected: FAIL, compilation errors for missing `husk_api.dart`, `husk_exception.dart`, `text_result.dart`.

- [ ] **Step 4: Implement exceptions and `TextResult`**

`lib/core/api/husk_exception.dart`:
```dart
import 'dart:convert';

/// Every failure surfaced by HuskApi. [message] is safe to show to the user.
sealed class HuskException implements Exception {
  const HuskException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Connection refused, timed out, or otherwise unreachable.
final class OfflineException extends HuskException {
  const OfflineException(super.message);
}

final class UnauthorizedException extends HuskException {
  const UnauthorizedException() : super('Token missing or invalid. Edit the server or request a token.');
}

/// Any other non-2xx response.
final class HttpStatusException extends HuskException {
  HttpStatusException(this.statusCode, this.body) : super(_messageFor(statusCode, body));

  final int statusCode;
  final String body;

  static String _messageFor(int statusCode, String body) {
    final text = body.trim();
    if (text.startsWith('{')) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map && decoded['error'] is String) return decoded['error'] as String;
      } on FormatException {
        // Not JSON after all; fall through to the raw text.
      }
    }
    return text.isEmpty ? 'HTTP $statusCode' : text;
  }
}

/// A JSON endpoint answered plain text, e.g. `ERR no-fix (…)` from /location.
final class DeviceErrorException extends HuskException {
  const DeviceErrorException(super.message);
}
```

`lib/core/api/text_result.dart`:
```dart
/// A plain-text reply from an accessibility/command endpoint: `OK …`, `NONE …`,
/// `ERR …` or a value. These arrive with HTTP 200 and are shown, not thrown.
class TextResult {
  const TextResult(this.raw);

  final String raw;

  String get text => raw.trim();
  bool get isOk => _startsWithWord('OK');
  bool get isNone => _startsWithWord('NONE');
  bool get isErr => _startsWithWord('ERR');

  bool _startsWithWord(String word) => text == word || text.startsWith('$word ');

  @override
  String toString() => text;
}
```

- [ ] **Step 5: Implement `HuskApi` plumbing and the Task 5 endpoints**

`lib/core/api/husk_api.dart`:
```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'husk_exception.dart';
import 'text_result.dart';

/// Body of a streaming (MJPEG) response plus its Content-Type header.
typedef MultipartResponse = ({String contentType, Stream<Uint8List> stream});

/// Typed client for one Husk phone. Every endpoint is a GET with query
/// parameters; the token travels as `?token=`.
class HuskApi {
  HuskApi({
    required this.baseUrl,
    this.token,
    HttpClientAdapter? adapter,
    Duration connectTimeout = const Duration(seconds: 3),
    Duration receiveTimeout = const Duration(seconds: 10),
  }) : _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: connectTimeout,
          receiveTimeout: receiveTimeout,
          responseType: ResponseType.plain,
          validateStatus: (_) => true,
        )) {
    if (adapter != null) _dio.httpClientAdapter = adapter;
  }

  /// For endpoints that drive the phone's UI (dump, rpc, management).
  static const _slow = Duration(seconds: 30);

  /// Maximum silence between chunks of a live stream before it is dropped.
  static const _streamIdle = Duration(seconds: 15);

  final String baseUrl;
  final String? token;
  final Dio _dio;

  void close() => _dio.close(force: true);

  /// Absolute URL for [path] with the token attached, for consumers that do
  /// their own HTTP (media_kit, WebView).
  Uri uri(String path, [Map<String, Object?> query = const {}]) {
    final params = _params(query, auth: true);
    return Uri.parse(baseUrl).replace(path: path, queryParameters: params.isEmpty ? null : params);
  }

  // ---------------------------------------------------------------- Status

  Future<bool> healthz() async => (await _text('/healthz', auth: false)).trim() == 'ok';

  // ------------------------------------------------------- Camera & screen

  Future<Uint8List> snapshot() => _bytes('/snapshot');

  Future<Uint8List> screenshot() => _bytes('/screen.jpg');

  Future<MultipartResponse> openMultipart(String path, {CancelToken? cancelToken}) async {
    final response = await _get<ResponseBody>(
      path,
      responseType: ResponseType.stream,
      receiveTimeout: _streamIdle,
      cancelToken: cancelToken,
    );
    final status = response.statusCode ?? 0;
    final body = response.data;
    if (body == null) throw HttpStatusException(status, '');
    if (status < 200 || status >= 300) {
      final bytes = await body.stream.fold<List<int>>(<int>[], (all, chunk) => all..addAll(chunk));
      _check(status, utf8.decode(bytes, allowMalformed: true));
    }
    return (contentType: response.headers.value(Headers.contentTypeHeader) ?? '', stream: body.stream);
  }

  // --------------------------------------------------- Inspection & generic

  Future<String> dump({int display = 0}) => _text('/dump', query: {'d': display}, receiveTimeout: _slow);

  Future<String> rpc(String command) => _text('/rpc', query: {'cmd': command}, receiveTimeout: _slow);

  // ------------------------------------------------------------- Plumbing

  Map<String, String> _params(Map<String, Object?> query, {required bool auth}) {
    final params = <String, String>{};
    query.forEach((key, value) {
      if (value == null) return;
      params[key] = value is bool ? (value ? '1' : '0') : value.toString();
    });
    final t = token;
    if (auth && t != null && t.isNotEmpty) params['token'] = t;
    return params;
  }

  Future<Response<T>> _get<T>(
    String path, {
    Map<String, Object?> query = const {},
    bool auth = true,
    ResponseType? responseType,
    Duration? receiveTimeout,
    CancelToken? cancelToken,
  }) async {
    try {
      return await _dio.get<T>(
        path,
        queryParameters: _params(query, auth: auth),
        options: Options(responseType: responseType, receiveTimeout: receiveTimeout),
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) throw const OfflineException('Request cancelled');
      throw OfflineException("Can't reach ${baseUrl.replaceFirst('http://', '')}");
    }
  }

  void _check(int status, String body) {
    if (status >= 200 && status < 300) return;
    if (status == 401) throw const UnauthorizedException();
    throw HttpStatusException(status, body);
  }

  Future<String> _text(
    String path, {
    Map<String, Object?> query = const {},
    bool auth = true,
    Duration? receiveTimeout,
  }) async {
    final response = await _get<String>(path, query: query, auth: auth, receiveTimeout: receiveTimeout);
    final body = response.data ?? '';
    _check(response.statusCode ?? 0, body);
    return body;
  }

  // ignore: unused_element
  Future<TextResult> _command(String path, {Map<String, Object?> query = const {}, Duration? receiveTimeout}) async =>
      TextResult(await _text(path, query: query, receiveTimeout: receiveTimeout));

  /// Decodes a JSON body. Husk answers some JSON endpoints with plain text
  /// (`ERR …`) under HTTP 200; that becomes a DeviceErrorException.
  Future<Object?> _json(String path, {Map<String, Object?> query = const {}, bool auth = true, Duration? receiveTimeout}) async {
    final body = (await _text(path, query: query, auth: auth, receiveTimeout: receiveTimeout)).trim();
    if (body.startsWith('{') || body.startsWith('[')) {
      try {
        return jsonDecode(body);
      } on FormatException {
        throw DeviceErrorException('Unexpected response: $body');
      }
    }
    throw DeviceErrorException(body.isEmpty ? 'Empty response' : body);
  }

  // ignore: unused_element
  Future<Map<String, Object?>> _map(String path, {Map<String, Object?> query = const {}, bool auth = true, Duration? receiveTimeout}) async {
    final value = await _json(path, query: query, auth: auth, receiveTimeout: receiveTimeout);
    if (value is Map<String, Object?>) return value;
    throw DeviceErrorException('Unexpected response from $path');
  }

  // ignore: unused_element
  Future<List<Object?>> _list(String path, {Map<String, Object?> query = const {}}) async {
    final value = await _json(path, query: query);
    if (value is List<Object?>) return value;
    throw DeviceErrorException('Unexpected response from $path');
  }

  Future<Uint8List> _bytes(String path) async {
    final response = await _get<List<int>>(path, responseType: ResponseType.bytes);
    final data = response.data ?? const <int>[];
    _check(response.statusCode ?? 0, utf8.decode(data, allowMalformed: true));
    return Uint8List.fromList(data);
  }
}
```
The three `// ignore: unused_element` lines are needed only until Tasks 6–7 call those helpers. **Remove them in Task 7, Step 4.**

- [ ] **Step 6: Run tests and analyze**

Run: `flutter test test/core/api && flutter analyze`
Expected: `All tests passed!` and `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add lib/core/api test/core/api test/support/fake_adapter.dart
git commit -m "feat: add HuskApi plumbing with token injection and error mapping

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_018vGW2sL6yV3eTZKrrtJar3"
```

---

### Task 6: API models and JSON endpoints

**Files:**
- Create: `lib/core/api/models/json_read.dart`, `lib/core/api/models/device_models.dart`, `lib/core/api/models/hardware_models.dart`, `lib/core/api/models/tools_models.dart`
- Modify: `lib/core/api/husk_api.dart` (add imports and endpoint methods)
- Test: `test/core/api/husk_api_models_test.dart`

**Interfaces:**
- Consumes: `HuskApi` private helpers `_map`, `_list`, `_text`, `_slow` (Task 5); `fakeApi`, `jsonBody`, `textBody` (Task 5).
- Produces:
  - **Models** (all fields final; nested maps tolerated as missing):
    - `DeviceInfo`:
      - strings: `appPackage`, `appVersionName`, `appVersionCode`, `manufacturer`, `model`, `androidRelease`
      - `int? sdkInt`, `bool dexCapable`, `bool hasCamera`
      - `int? screenWidth`, `int? screenHeight`
      - `String? localIp`, `String? tailscaleIp`
      - `int? batteryLevel`, `bool batteryCharging`
      - `ServiceState services` (`bool a11y`, `camera`, `screen`, `dexReconnect`)
      - getter `String displayName`
    - `Flags`: bools `dexReconnect`, `a11y`, `camera`, `front`, `screen`, `motion`, `ntfy`, `batteryOptIgnored`; `String lastNtfy`.
    - `BatteryInfo`: `int? level`, `bool charging`, strings `status`, `health`, `plugged`, `technology`, `double? temperatureC`, `int? voltageMv`.
    - `ConnectivityInfo`: `bool connected`, `String type`, `bool metered`, `bool validated`.
    - `DisplayInfo`: `int width`, `int height`, `int? densityDpi`, `double? density`, `double? refreshHz`, `int rotation`.
    - `LocationInfo`: `double? lat`, `double? lon`, `double? accuracyM`, `double? altitude`, `DateTime? time`, `String provider`.
    - `MicLevel`: `int amplitude`, `int max`, getter `double fraction`.
    - `SensorInfo`: `String name`, `int? type`, `String vendor`, `double? power`, `double? max`.
    - `SensorReading`: `String sensor`, `int? type`, `List<double> values`.
    - `VolumeLevel`: `int level`, `int max`; `static Map<String, VolumeLevel> parseAll(Map<String, Object?>)`.
    - `BrightnessInfo`: `int level`, `int max`, `bool auto`.
    - `DisplayEntry`: `int id`, `String raw`; `static List<DisplayEntry> parseList(String text)`.
    - `const List<String> sensorTypes`.
    - `MotionConfig`: `bool enabled`, `String ntfyServer`, `String ntfyTopic`, `int sensitivity`, `String lastNtfy`.
    - `MotionEvent`: `DateTime time`, `String source`, `double change`.
    - `WdInfo`: `String ip`, `int? port`, `String ipport`.
    - `PairInfo`: `String addr`, `String code`.
    - `TokenRequest`: `String id`, `int expiresIn`.
    - `enum TokenState { pending, denied, expired, approved }`.
    - `TokenStatus`: `TokenState state`, `String? token`.
    - `enum NavKey { back, home, recents, notifications, enter }`.
  - **New `HuskApi` methods:**
    - `info()`, `flags()`, `battery()`, `connectivity()`, `display()`, `location()`, `mic()`
    - `sensors()` → `List<SensorInfo>`; `sensor(String type)`
    - `volume()` → `Map<String, VolumeLevel>`; `ringerMode()` → `String`; `brightness()`
    - `displays()` → `List<DisplayEntry>`
    - `motion()`; `events()` → `List<MotionEvent>`
    - `requestToken({required String client})`; `tokenStatus(String id)`
    - `wd()`, `pair()`

- [ ] **Step 1: Write failing tests using responses captured from the test phone**

`test/core/api/husk_api_models_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/api/husk_exception.dart';
import 'package:huskconfig/core/api/models/tools_models.dart';

import '../../support/fake_adapter.dart';

// Captured from the SM-A750F test phone on 2026-10-07.
const infoJson = '{"app":{"package":"co.xplat.husk","versionName":"1.4","versionCode":"55"},'
    '"device":{"manufacturer":"samsung","model":"SM-A750F","androidRelease":"10","sdkInt":29,"dexCapable":false,"hasCamera":true},'
    '"screen":{"width":1080,"height":2112},"net":{"localIp":"192.168.0.106","tailscaleIp":null},'
    '"battery":{"level":87,"charging":false},"services":{"a11y":true,"camera":true,"screen":false,"dexReconnect":false}}';
const flagsJson = '{"dexReconnect":false,"a11y":true,"camera":true,"front":true,"screen":false,"motion":false,"ntfy":false,"batteryOptIgnored":true,"lastNtfy":""}';
const batteryJson = '{"level":100,"charging":true,"status":"full","health":"good","plugged":"usb","temperatureC":28.8,"voltageMv":4150,"technology":"Li-ion"}';
const displayJson = '{"width":1080,"height":2112,"densityDpi":360,"density":2.25,"refreshHz":60.000004,"rotation":"0"}';
const volumeJson = '{"media":{"level":0,"max":15},"ring":{"level":0,"max":15},"alarm":{"level":11,"max":15},"notification":{"level":0,"max":15},"system":{"level":0,"max":15},"call":{"level":4,"max":5}}';
const sensorsJson = '[{"name":"LSM6DSL Accelerometer","type":1,"vendor":"STM","power":0.13,"max":39.2266},{"name":"CM36658 Light","type":5,"vendor":"Capella Microsystems, Inc.","power":0.75,"max":60000.0}]';
const motionJson = '{"enabled":false,"ntfyServer":"https://ntfy.sh","ntfyTopic":"","sensitivity":5,"lastNtfy":""}';

void main() {
  test('info() parses the nested device snapshot', () async {
    final f = fakeApi((_) => jsonBody(infoJson));
    final info = await f.api.info();
    expect(info.appVersionName, '1.4');
    expect(info.displayName, 'samsung SM-A750F');
    expect(info.sdkInt, 29);
    expect(info.screenWidth, 1080);
    expect(info.localIp, '192.168.0.106');
    expect(info.tailscaleIp, isNull);
    expect(info.batteryLevel, 87);
    expect(info.services.a11y, isTrue);
    expect(info.services.screen, isFalse);
  });

  test('flags()', () async {
    final flags = await fakeApi((_) => jsonBody(flagsJson)).api.flags();
    expect(flags.front, isTrue);
    expect(flags.screen, isFalse);
    expect(flags.batteryOptIgnored, isTrue);
  });

  test('battery()', () async {
    final b = await fakeApi((_) => jsonBody(batteryJson)).api.battery();
    expect(b.level, 100);
    expect(b.charging, isTrue);
    expect(b.temperatureC, 28.8);
    expect(b.voltageMv, 4150);
    expect(b.technology, 'Li-ion');
  });

  test('display() accepts rotation as a string', () async {
    final d = await fakeApi((_) => jsonBody(displayJson)).api.display();
    expect((d.width, d.height, d.rotation, d.densityDpi), (1080, 2112, 0, 360));
  });

  test('connectivity()', () async {
    final c = await fakeApi((_) => jsonBody('{"connected":true,"type":"wifi","metered":false,"validated":true}')).api.connectivity();
    expect((c.connected, c.type, c.metered, c.validated), (true, 'wifi', false, true));
  });

  test('location() turns a plain-text ERR reply into DeviceErrorException', () async {
    final f = fakeApi((_) => textBody('ERR no-fix (no known position; is location turned on?)'));
    expect(f.api.location(), throwsA(isA<DeviceErrorException>().having((e) => e.message, 'message', contains('no-fix'))));
  });

  test('location() parses a fix', () async {
    final l = await fakeApi((_) => jsonBody('{"lat":55.67,"lon":12.56,"accuracyM":12.5,"altitude":20.0,"time":1759838400000,"provider":"fused"}')).api.location();
    expect((l.lat, l.lon, l.provider), (55.67, 12.56, 'fused'));
    expect(l.time, DateTime.fromMillisecondsSinceEpoch(1759838400000));
  });

  test('mic()', () async {
    final m = await fakeApi((_) => jsonBody('{"amplitude":16383,"max":32767}')).api.mic();
    expect(m.fraction, closeTo(0.5, 0.001));
  });

  test('volume() keeps every stream in order', () async {
    final v = await fakeApi((_) => jsonBody(volumeJson)).api.volume();
    expect(v.keys, ['media', 'ring', 'alarm', 'notification', 'system', 'call']);
    expect((v['alarm']!.level, v['call']!.max), (11, 5));
  });

  test('ringerMode() and brightness()', () async {
    expect(await fakeApi((_) => jsonBody('{"mode":"silent"}')).api.ringerMode(), 'silent');
    final b = await fakeApi((_) => jsonBody('{"level":105,"max":255,"auto":true}')).api.brightness();
    expect((b.level, b.max, b.auto), (105, 255, true));
  });

  test('sensors() and sensor(type)', () async {
    final list = await fakeApi((_) => jsonBody(sensorsJson)).api.sensors();
    expect(list.map((s) => s.name), ['LSM6DSL Accelerometer', 'CM36658 Light']);
    expect(list.last.type, 5);
    final f = fakeApi((_) => jsonBody('{"sensor":"CM36658 Light","type":5,"values":[5.0]}'));
    final reading = await f.api.sensor('light');
    expect(f.adapter.last.uri.queryParameters['type'], 'light');
    expect(reading.values, [5.0]);
  });

  test('displays() parses the plain-text list', () async {
    final d = await fakeApi((_) => textBody('0:0\n2:1\n')).api.displays();
    expect(d.map((e) => e.id), [0, 2]);
    expect(d.first.raw, '0:0');
  });

  test('motion() and events()', () async {
    final m = await fakeApi((_) => jsonBody(motionJson)).api.motion();
    expect((m.enabled, m.ntfyServer, m.ntfyTopic, m.sensitivity), (false, 'https://ntfy.sh', '', 5));
    final e = await fakeApi((_) => jsonBody('[{"t":1759838400000,"source":"camera","change":12.5}]')).api.events();
    expect(e.single.source, 'camera');
    expect(e.single.change, 12.5);
    expect(e.single.time, DateTime.fromMillisecondsSinceEpoch(1759838400000));
    expect(await fakeApi((_) => jsonBody('[]')).api.events(), isEmpty);
  });

  test('requestToken() sends client, never the token', () async {
    final f = fakeApi((_) => jsonBody('{"id":"0123456789abcdef0123456789abcdef","expires_in":120}'), token: 'old');
    final r = await f.api.requestToken(client: 'Husk Config');
    expect((r.id, r.expiresIn), ('0123456789abcdef0123456789abcdef', 120));
    expect(f.adapter.last.uri.queryParameters, {'client': 'Husk Config'});
  });

  test('tokenStatus() parses every state', () async {
    Future<TokenStatus> status(String body) => fakeApi((_) => jsonBody(body)).api.tokenStatus('id1');
    expect((await status('{"status":"pending"}')).state, TokenState.pending);
    expect((await status('{"status":"denied"}')).state, TokenState.denied);
    expect((await status('{"status":"expired"}')).state, TokenState.expired);
    final approved = await status('{"status":"approved","token":"abc"}');
    expect((approved.state, approved.token), (TokenState.approved, 'abc'));
    expect((await status('{"status":"weird"}')).state, TokenState.expired);
  });

  test('wd() and pair()', () async {
    final wd = await fakeApi((_) => jsonBody('{"ip":"192.168.0.106","port":37123,"ipport":"192.168.0.106:37123"}')).api.wd();
    expect((wd.ip, wd.port, wd.ipport), ('192.168.0.106', 37123, '192.168.0.106:37123'));
    final pair = await fakeApi((_) => jsonBody('{"addr":"192.168.0.106:41234","code":"123456"}')).api.pair();
    expect((pair.addr, pair.code), ('192.168.0.106:41234', '123456'));
    expect(fakeApi((_) => textBody('ERR needs-api30')).api.wd(), throwsA(isA<DeviceErrorException>()));
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/core/api/husk_api_models_test.dart`
Expected: FAIL, compilation errors (missing models and methods).

- [ ] **Step 3: Implement the JSON readers**

`lib/core/api/models/json_read.dart`:
```dart
// Tolerant readers: Husk sends some numbers as strings ("rotation":"0") and
// may omit fields on older versions.

int? readInt(Object? v) => switch (v) {
      int i => i,
      num n => n.toInt(),
      String s => int.tryParse(s) ?? double.tryParse(s)?.toInt(),
      _ => null,
    };

double? readDouble(Object? v) => switch (v) {
      num n => n.toDouble(),
      String s => double.tryParse(s),
      _ => null,
    };

bool? readBool(Object? v) => switch (v) {
      bool b => b,
      num n => n != 0,
      'true' || '1' => true,
      'false' || '0' => false,
      _ => null,
    };

String? readString(Object? v) => switch (v) {
      null => null,
      String s => s,
      _ => v.toString(),
    };

Map<String, Object?> readMap(Object? v) => v is Map<String, Object?> ? v : const {};

DateTime? readEpochMs(Object? v) {
  final ms = readInt(v);
  return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
}
```

- [ ] **Step 4: Implement the device models**

`lib/core/api/models/device_models.dart`:
```dart
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
```

- [ ] **Step 5: Implement the hardware models**

`lib/core/api/models/hardware_models.dart`:
```dart
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
```

- [ ] **Step 6: Implement the tools models**

`lib/core/api/models/tools_models.dart`:
```dart
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
```

- [ ] **Step 7: Add the JSON endpoint methods to `HuskApi`**

In `lib/core/api/husk_api.dart`, add these imports below the existing ones:
```dart
import 'models/device_models.dart';
import 'models/hardware_models.dart';
import 'models/tools_models.dart';
import 'models/json_read.dart';
```

Insert this block directly after the `healthz()` method:
```dart
  Future<DeviceInfo> info() async => DeviceInfo.fromJson(await _map('/info'));

  Future<Flags> flags() async => Flags.fromJson(await _map('/flags'));

  // -------------------------------------------------------------- Hardware

  Future<BatteryInfo> battery() async => BatteryInfo.fromJson(await _map('/battery'));

  Future<ConnectivityInfo> connectivity() async => ConnectivityInfo.fromJson(await _map('/connectivity'));

  Future<DisplayInfo> display() async => DisplayInfo.fromJson(await _map('/display'));

  Future<LocationInfo> location() async => LocationInfo.fromJson(await _map('/location'));

  Future<MicLevel> mic() async => MicLevel.fromJson(await _map('/mic'));

  Future<List<SensorInfo>> sensors() async => [for (final e in await _list('/sensors')) SensorInfo.fromJson(readMap(e))];

  Future<SensorReading> sensor(String type) async => SensorReading.fromJson(await _map('/sensor', query: {'type': type}));

  Future<Map<String, VolumeLevel>> volume() async => VolumeLevel.parseAll(await _map('/volume'));

  Future<String> ringerMode() async => readString((await _map('/ringer'))['mode']) ?? 'unknown';

  Future<BrightnessInfo> brightness() async => BrightnessInfo.fromJson(await _map('/brightness'));

  Future<List<DisplayEntry>> displays() async => DisplayEntry.parseList(await _text('/displays'));

  // ---------------------------------------------------------------- Motion

  Future<MotionConfig> motion() async => MotionConfig.fromJson(await _map('/motion'));

  Future<List<MotionEvent>> events() async => [for (final e in await _list('/events')) MotionEvent.fromJson(readMap(e))];

  // ----------------------------------------------------------------- Token

  Future<TokenRequest> requestToken({required String client}) async =>
      TokenRequest.fromJson(await _map('/token/request', query: {'client': client}, auth: false));

  Future<TokenStatus> tokenStatus(String id) async =>
      TokenStatus.fromJson(await _map('/token/status', query: {'id': id}, auth: false));

  // ------------------------------------------------------------ Management

  Future<WdInfo> wd() async => WdInfo.fromJson(await _map('/wd', receiveTimeout: _slow));

  Future<PairInfo> pair() async => PairInfo.fromJson(await _map('/pair', receiveTimeout: _slow));
```

Remove the `// ignore: unused_element` lines above `_map` and `_list`; they are used now. Leave the one above `_command` until Task 7.

- [ ] **Step 8: Run tests and analyze**

Run: `flutter test test/core/api && flutter analyze`
Expected: `All tests passed!` and `No issues found!`

- [ ] **Step 9: Commit**

```bash
git add lib/core/api test/core/api
git commit -m "feat: add Husk API models and JSON endpoints

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_018vGW2sL6yV3eTZKrrtJar3"
```

---

### Task 7: Command endpoints (input, camera config, tools, hardware setters)

**Files:**
- Modify: `lib/core/api/husk_api.dart`
- Test: `test/core/api/husk_api_commands_test.dart`

**Interfaces:**
- Consumes: `_command`, `_text`, `_slow` (Task 5); `NavKey` (Task 6).
- Produces (`HuskApi` methods):
  - Camera and input:
    - `Future<TextResult> setCamera({int? rotation, bool? flip, bool? front, int? fps, int? screenQuality, int? screenFps})`
    - `Future<TextResult> wake()`
    - `Future<TextResult> tap(int x, int y, {int display = 0, int? ms})`
    - `Future<TextResult> swipe(int x1, int y1, int x2, int y2, {int display = 0, int? ms})`
    - `Future<TextResult> key(NavKey key)`
    - `Future<TextResult> click(String match, {int display = 0})`
    - `Future<TextResult> typeText(String text)`
  - Inspection and navigation:
    - `Future<({int x, int y})?> find(String match, {int display = 0})`
    - `Future<String?> getText(String match, {int display = 0})`
    - `Future<bool> exists(String match, {int display = 0})`
    - `Future<TextResult> scroll({int display = 0, bool forward = true})`
    - `Future<TextResult> launch({required String action, String? data, String? package, int display = 0})`
  - Token and management:
    - `Future<void> setToken(String newToken)`
    - `Future<TextResult> devOptions({bool probe = false})`
  - Hardware setters:
    - `Future<TextResult> torch({required bool on})`
    - `Future<TextResult> vibrate({int? ms})`
    - `Future<TextResult> setVolume(String stream, int level)`
    - `Future<TextResult> setRinger(String mode)`
    - `Future<TextResult> setBrightness(int level)`
  - Motion: `Future<void> setMotion({bool? enabled, String? topic, String? server, int? sensitivity})`

- [ ] **Step 1: Write failing tests**

`test/core/api/husk_api_commands_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/api/husk_api.dart';
import 'package:huskconfig/core/api/husk_exception.dart';
import 'package:huskconfig/core/api/models/tools_models.dart';

import '../../support/fake_adapter.dart';

void main() {
  // name → (call, expected path, expected query without token)
  final cases = <String, (Future<Object?> Function(HuskApi), String, Map<String, String>)>{
    'setCamera': ((a) => a.setCamera(front: true, flip: false, rotation: 90, fps: 15, screenQuality: 60, screenFps: 20), '/set',
        {'front': '1', 'flip': '0', 'rot': '90', 'fps': '15', 'sq': '60', 'sfps': '20'}),
    'setCamera partial': ((a) => a.setCamera(front: false), '/set', {'front': '0'}),
    'wake': ((a) => a.wake(), '/wake', {}),
    'tap': ((a) => a.tap(10, 20, display: 2, ms: 600), '/tap', {'x': '10', 'y': '20', 'd': '2', 'ms': '600'}),
    'tap defaults': ((a) => a.tap(1, 2), '/tap', {'x': '1', 'y': '2', 'd': '0'}),
    'swipe': ((a) => a.swipe(1, 2, 3, 4, ms: 300), '/swipe', {'x1': '1', 'y1': '2', 'x2': '3', 'y2': '4', 'd': '0', 'ms': '300'}),
    'key': ((a) => a.key(NavKey.recents), '/key', {'k': 'recents'}),
    'click': ((a) => a.click('Wi-Fi|WLAN', display: 2), '/click', {'match': 'Wi-Fi|WLAN', 'd': '2'}),
    'typeText keeps special characters': ((a) => a.typeText('a&b c?=%'), '/text', {'t': 'a&b c?=%'}),
    'scroll back': ((a) => a.scroll(forward: false), '/scroll', {'d': '0', 'dir': 'back'}),
    'launch drops nulls': ((a) => a.launch(action: 'android.settings.SETTINGS'), '/launch', {'action': 'android.settings.SETTINGS', 'd': '0'}),
    'launch full': ((a) => a.launch(action: 'android.intent.action.VIEW', data: 'https://x.y/?a=1&b=2', package: 'com.android.chrome', display: 2), '/launch',
        {'action': 'android.intent.action.VIEW', 'data': 'https://x.y/?a=1&b=2', 'pkg': 'com.android.chrome', 'd': '2'}),
    'setToken': ((a) => a.setToken('A' * 32), '/token/set', {'new': 'A' * 32}),
    'devOptions probe': ((a) => a.devOptions(probe: true), '/devoptions', {'probe': '1'}),
    'devOptions': ((a) => a.devOptions(), '/devoptions', {}),
    'torch': ((a) => a.torch(on: true), '/torch', {'on': '1'}),
    'vibrate': ((a) => a.vibrate(ms: 500), '/vibrate', {'ms': '500'}),
    'setVolume': ((a) => a.setVolume('media', 7), '/volume', {'stream': 'media', 'level': '7'}),
    'setRinger': ((a) => a.setRinger('vibrate'), '/ringer', {'mode': 'vibrate'}),
    'setBrightness': ((a) => a.setBrightness(128), '/brightness', {'level': '128'}),
    'setMotion keeps an empty topic': ((a) => a.setMotion(enabled: true, topic: '', server: 'https://ntfy.sh', sensitivity: 7), '/motion',
        {'on': '1', 'topic': '', 'server': 'https://ntfy.sh', 'sensitivity': '7'}),
  };

  for (final MapEntry(key: name, value: (call, path, query)) in cases.entries) {
    test('$name → $path $query', () async {
      final f = fakeApi((_) => textBody('OK'), token: 'tok');
      await call(f.api);
      expect(f.adapter.last.path, path);
      expect(f.adapter.last.uri.queryParameters, {...query, 'token': 'tok'});
    });
  }

  group('find', () {
    test('parses "x y"', () async {
      expect(await fakeApi((_) => textBody('540 1056\n')).api.find('Settings'), (x: 540, y: 1056));
    });
    test('NONE → null', () async {
      expect(await fakeApi((_) => textBody('NONE')).api.find('nope'), isNull);
    });
    test('ERR → DeviceErrorException', () async {
      expect(fakeApi((_) => textBody('ERR a11y-off')).api.find('x'), throwsA(isA<DeviceErrorException>()));
    });
  });

  test('getText returns text or null for NONE', () async {
    expect(await fakeApi((_) => textBody('Battery 87%')).api.getText('Battery'), 'Battery 87%');
    expect(await fakeApi((_) => textBody('NONE')).api.getText('x'), isNull);
  });

  test('exists maps 1/0 to bool', () async {
    expect(await fakeApi((_) => textBody('1')).api.exists('x'), isTrue);
    expect(await fakeApi((_) => textBody('0')).api.exists('x'), isFalse);
  });

  test('setMotion throws on an ERR reply', () async {
    expect(fakeApi((_) => textBody('ERR https only')).api.setMotion(server: 'http://x'), throwsA(isA<DeviceErrorException>()));
  });

  test('setToken surfaces 409 as HttpStatusException', () async {
    final f = fakeApi((_) => jsonBody('{"error":"no token set; use /token/request"}', status: 409));
    expect(f.api.setToken('A' * 32), throwsA(isA<HttpStatusException>().having((e) => e.statusCode, 'statusCode', 409)));
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/core/api/husk_api_commands_test.dart`
Expected: FAIL, `The method 'setCamera' isn't defined for the type 'HuskApi'` (and others).

- [ ] **Step 3: Implement the command methods**

In `lib/core/api/husk_api.dart`, add the import `import 'models/tools_models.dart';` if it is not already present (it was added in Task 6). Insert this block directly before the `// --------------------------------------------------- Inspection & generic` comment:
```dart
  Future<TextResult> setCamera({int? rotation, bool? flip, bool? front, int? fps, int? screenQuality, int? screenFps}) =>
      _command('/set', query: {'rot': rotation, 'flip': flip, 'front': front, 'fps': fps, 'sq': screenQuality, 'sfps': screenFps});

  // ----------------------------------------------------------------- Input

  Future<TextResult> wake() => _command('/wake');

  Future<TextResult> tap(int x, int y, {int display = 0, int? ms}) =>
      _command('/tap', query: {'x': x, 'y': y, 'd': display, 'ms': ms});

  Future<TextResult> swipe(int x1, int y1, int x2, int y2, {int display = 0, int? ms}) =>
      _command('/swipe', query: {'x1': x1, 'y1': y1, 'x2': x2, 'y2': y2, 'd': display, 'ms': ms});

  Future<TextResult> key(NavKey key) => _command('/key', query: {'k': key.name});

  Future<TextResult> click(String match, {int display = 0}) => _command('/click', query: {'match': match, 'd': display});

  /// Replaces the focused field's whole content (newlines are stripped by Husk).
  Future<TextResult> typeText(String text) => _command('/text', query: {'t': text});
```

Insert this block directly after the `rpc(...)` method:
```dart
  Future<({int x, int y})?> find(String match, {int display = 0}) async {
    final r = await _command('/find', query: {'match': match, 'd': display});
    if (r.isNone) return null;
    if (r.isErr) throw DeviceErrorException(r.text);
    final parts = r.text.split(RegExp(r'\s+'));
    final x = int.tryParse(parts.first);
    final y = parts.length > 1 ? int.tryParse(parts[1]) : null;
    if (x == null || y == null) throw DeviceErrorException('Unexpected response: ${r.text}');
    return (x: x, y: y);
  }

  Future<String?> getText(String match, {int display = 0}) async {
    final r = await _command('/gettext', query: {'match': match, 'd': display});
    if (r.isNone) return null;
    if (r.isErr) throw DeviceErrorException(r.text);
    return r.text;
  }

  Future<bool> exists(String match, {int display = 0}) async {
    final r = await _command('/exists', query: {'match': match, 'd': display});
    if (r.isErr) throw DeviceErrorException(r.text);
    return r.text == '1';
  }

  Future<TextResult> scroll({int display = 0, bool forward = true}) =>
      _command('/scroll', query: {'d': display, 'dir': forward ? 'fwd' : 'back'});

  // ------------------------------------------------------------ Navigation

  Future<TextResult> launch({required String action, String? data, String? package, int display = 0}) =>
      _command('/launch', query: {'action': action, 'data': data, 'pkg': package, 'd': display});

  // ------------------------------------------------------- Token & control

  /// Requires the current token; 409 when no token is set, 400 for an invalid one.
  Future<void> setToken(String newToken) async {
    await _text('/token/set', query: {'new': newToken});
  }

  Future<TextResult> devOptions({bool probe = false}) =>
      _command('/devoptions', query: {'probe': probe ? true : null}, receiveTimeout: _slow);

  // ------------------------------------------------------ Hardware setters

  Future<TextResult> torch({required bool on}) => _command('/torch', query: {'on': on});

  Future<TextResult> vibrate({int? ms}) => _command('/vibrate', query: {'ms': ms});

  Future<TextResult> setVolume(String stream, int level) => _command('/volume', query: {'stream': stream, 'level': level});

  Future<TextResult> setRinger(String mode) => _command('/ringer', query: {'mode': mode});

  Future<TextResult> setBrightness(int level) => _command('/brightness', query: {'level': level});

  /// An empty [topic] is sent as-is: it means "log to /events only, no push".
  Future<void> setMotion({bool? enabled, String? topic, String? server, int? sensitivity}) async {
    final r = await _command('/motion', query: {'on': enabled, 'topic': topic, 'server': server, 'sensitivity': sensitivity});
    if (r.isErr) throw DeviceErrorException(r.text);
  }
```

- [ ] **Step 4: Remove the last `// ignore: unused_element`**

Delete the `// ignore: unused_element` line above `_command`.

- [ ] **Step 5: Run tests and analyze**

Run: `flutter test test/core/api && flutter analyze`
Expected: `All tests passed!` and `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/core/api test/core/api
git commit -m "feat: add Husk command endpoints

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_018vGW2sL6yV3eTZKrrtJar3"
```

---

### Task 8: MJPEG multipart parser

**Files:**
- Create: `lib/core/stream/mjpeg_stream.dart`
- Test: `test/core/stream/mjpeg_stream_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `class MjpegParser extends StreamTransformerBase<Uint8List, Uint8List>`
    - constructor `MjpegParser(String boundary, {int maxBufferBytes = 16 * 1024 * 1024})`
    - `static String? boundaryFrom(String contentType)`
  - Usage: `response.stream.transform(MjpegParser(boundary))` emits one `Uint8List` per JPEG frame.

The wire format observed on the test phone:
```
--rigframe\r\nContent-Type: image/jpeg\r\nContent-Length: 257649\r\n\r\n<jpeg bytes>\r\n--rigframe…
```

- [ ] **Step 1: Write failing tests**

`test/core/stream/mjpeg_stream_test.dart`:
```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/stream/mjpeg_stream.dart';

Uint8List jpeg(int seed, [int size = 32]) =>
    Uint8List.fromList([0xFF, 0xD8, for (var i = 0; i < size; i++) (seed + i) % 256, 0xFF, 0xD9]);

List<int> part(Uint8List frame, {bool withLength = true, String boundary = 'rigframe'}) => [
      ...ascii.encode('--$boundary\r\nContent-Type: image/jpeg\r\n'
          '${withLength ? 'Content-Length: ${frame.length}\r\n' : ''}\r\n'),
      ...frame,
      ...ascii.encode('\r\n'),
    ];

Future<List<Uint8List>> parse(List<List<int>> chunks, {String boundary = 'rigframe', int maxBufferBytes = 16 << 20}) =>
    Stream.fromIterable(chunks.map(Uint8List.fromList))
        .transform(MjpegParser(boundary, maxBufferBytes: maxBufferBytes))
        .toList();

void main() {
  final a = jpeg(1), b = jpeg(2, 500), c = jpeg(3);

  group('boundaryFrom', () {
    test('plain, quoted and missing', () {
      expect(MjpegParser.boundaryFrom('multipart/x-mixed-replace; boundary=rigframe'), 'rigframe');
      expect(MjpegParser.boundaryFrom('multipart/x-mixed-replace;boundary="abc def"'), 'abc def');
      expect(MjpegParser.boundaryFrom('image/jpeg'), isNull);
    });
  });

  test('two frames in one chunk', () async {
    expect(await parse([[...part(a), ...part(b)]]), [a, b]);
  });

  test('frames split byte by byte', () async {
    final bytes = [...part(a), ...part(b), ...part(c)];
    expect(await parse([for (final byte in bytes) [byte]]), [a, b, c]);
  });

  test('frames without Content-Length are cut at the next boundary', () async {
    expect(
      await parse([[...part(a, withLength: false), ...part(b, withLength: false), ...ascii.encode('--rigframe')]]),
      [a, b],
    );
  });

  test('garbage before the first boundary is ignored', () async {
    expect(await parse([ascii.encode('HTTP junk\r\n'), part(a)]), [a]);
  });

  test('an oversized part is discarded and the parser recovers on the next part', () async {
    final frames = await parse(
      [
        ascii.encode('--rigframe\r\nContent-Type: image/jpeg\r\nContent-Length: 100000\r\n\r\n'),
        List.filled(300, 0),
        part(c),
      ],
      maxBufferBytes: 200,
    );
    expect(frames, [c]);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/core/stream/mjpeg_stream_test.dart`
Expected: FAIL, missing `mjpeg_stream.dart`.

- [ ] **Step 3: Implement the parser**

`lib/core/stream/mjpeg_stream.dart`:
```dart
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// Splits a `multipart/x-mixed-replace` body (Husk /stream and /screen) into
/// JPEG frames. Uses Content-Length when present, otherwise cuts at the next
/// boundary. If more than [maxBufferBytes] pile up without a complete frame,
/// the buffer is dropped so a broken stream cannot grow memory without bound.
class MjpegParser extends StreamTransformerBase<Uint8List, Uint8List> {
  MjpegParser(String boundary, {this.maxBufferBytes = 16 * 1024 * 1024}) : _delimiter = utf8.encode('--$boundary');

  final int maxBufferBytes;
  final List<int> _delimiter;

  /// The `boundary` parameter of a Content-Type header value, or null.
  static String? boundaryFrom(String contentType) {
    final match = RegExp(r'boundary="?([^";]+)"?', caseSensitive: false).firstMatch(contentType);
    final value = match?.group(1)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  @override
  Stream<Uint8List> bind(Stream<Uint8List> stream) =>
      Stream<Uint8List>.eventTransformed(stream, (sink) => _MjpegSink(sink, _delimiter, maxBufferBytes));
}

enum _Part { boundary, headers, body }

class _MjpegSink implements EventSink<Uint8List> {
  _MjpegSink(this._out, this._delimiter, this._maxBytes);

  static const _headerEnd = [13, 10, 13, 10];
  static final _contentLength = RegExp(r'content-length:\s*(\d+)', caseSensitive: false);

  final EventSink<Uint8List> _out;
  final List<int> _delimiter;
  final int _maxBytes;
  final _buffer = _ByteBuffer();
  _Part _part = _Part.boundary;
  int _length = -1;
  int _scanFrom = 0;

  @override
  void add(Uint8List chunk) {
    _buffer.add(chunk);
    _drain();
    if (_buffer.length > _maxBytes) {
      _buffer.clear();
      _part = _Part.boundary;
    }
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) => _out.addError(error, stackTrace);

  @override
  void close() => _out.close();

  void _drain() {
    while (true) {
      switch (_part) {
        case _Part.boundary:
          final at = _buffer.indexOf(_delimiter);
          if (at < 0) {
            // Keep a tail that could be the start of a delimiter split across chunks.
            _buffer.skip(math.max(0, _buffer.length - (_delimiter.length - 1)));
            return;
          }
          _buffer.skip(at + _delimiter.length);
          _part = _Part.headers;
        case _Part.headers:
          final at = _buffer.indexOf(_headerEnd);
          if (at < 0) return;
          final headers = latin1.decode(_buffer.peek(at));
          _buffer.skip(at + _headerEnd.length);
          _length = int.tryParse(_contentLength.firstMatch(headers)?.group(1) ?? '') ?? -1;
          _scanFrom = 0;
          _part = _Part.body;
        case _Part.body:
          if (_length >= 0) {
            if (_buffer.length < _length) return;
            _emit(_buffer.take(_length));
          } else {
            final at = _buffer.indexOf(_delimiter, _scanFrom);
            if (at < 0) {
              _scanFrom = math.max(0, _buffer.length - _delimiter.length);
              return;
            }
            var end = at;
            if (end >= 2 && _buffer[end - 2] == 13 && _buffer[end - 1] == 10) end -= 2;
            _emit(_buffer.take(end));
            _buffer.skip(at - end);
          }
          _part = _Part.boundary;
      }
    }
  }

  void _emit(Uint8List frame) {
    if (frame.isNotEmpty) _out.add(frame);
  }
}

/// Growable byte queue with cheap consumption from the front.
class _ByteBuffer {
  Uint8List _data = Uint8List(64 * 1024);
  int _start = 0;
  int _end = 0;

  int get length => _end - _start;

  int operator [](int index) => _data[_start + index];

  void add(Uint8List chunk) {
    final used = length;
    if (_end + chunk.length > _data.length) {
      final target = used + chunk.length > _data.length ? Uint8List(math.max(used + chunk.length, _data.length * 2)) : _data;
      target.setRange(0, used, _data, _start);
      _data = target;
      _start = 0;
      _end = used;
    }
    _data.setRange(_end, _end + chunk.length, chunk);
    _end += chunk.length;
  }

  /// Index of [pattern] relative to the front, searching from [from], or -1.
  int indexOf(List<int> pattern, [int from = 0]) {
    final last = length - pattern.length;
    outer:
    for (var i = from; i <= last; i++) {
      for (var j = 0; j < pattern.length; j++) {
        if (_data[_start + i + j] != pattern[j]) continue outer;
      }
      return i;
    }
    return -1;
  }

  /// A view of the first [count] bytes; valid only until the next mutation.
  Uint8List peek(int count) => Uint8List.sublistView(_data, _start, _start + count);

  /// Copies and removes the first [count] bytes.
  Uint8List take(int count) {
    final out = _data.sublist(_start, _start + count);
    skip(count);
    return out;
  }

  void skip(int count) {
    _start += count;
    if (_start >= _end) clear();
  }

  void clear() {
    _start = 0;
    _end = 0;
  }
}
```

- [ ] **Step 4: Run tests and analyze**

Run: `flutter test test/core/stream && flutter analyze`
Expected: `All tests passed!` and `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/core/stream test/core/stream
git commit -m "feat: add bounded MJPEG multipart parser

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_018vGW2sL6yV3eTZKrrtJar3"
```

---

### Task 9: Screen coordinate mapper

**Files:**
- Create: `lib/features/screen/coordinate_mapper.dart`
- Test: `test/features/screen/coordinate_mapper_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `class CoordinateMapper`:
  - constructor `const CoordinateMapper({required Size viewSize, required Size deviceSize})`
  - `Rect get contentRect`
  - `({int x, int y})? toDevice(Offset local)`: null in the letterbox bars
  - `({int x, int y})? toDeviceClamped(Offset local)`: null only when sizes are empty

- [ ] **Step 1: Write failing tests**

`test/features/screen/coordinate_mapper_test.dart`:
```dart
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/features/screen/coordinate_mapper.dart';

void main() {
  const tallPhone = Size(1080, 2112);

  group('portrait phone in a square view (bars left/right)', () {
    const mapper = CoordinateMapper(viewSize: Size(400, 400), deviceSize: tallPhone);

    test('content rect is centred horizontally', () {
      final r = mapper.contentRect;
      expect(r.top, 0);
      expect(r.height, 400);
      expect(r.width, closeTo(204.545, 0.01));
      expect(r.left, closeTo(97.727, 0.01));
    });

    test('centre maps to device centre', () {
      expect(mapper.toDevice(const Offset(200, 200)), (x: 540, y: 1056));
    });

    test('points in the bars are rejected', () {
      expect(mapper.toDevice(const Offset(50, 200)), isNull);
      expect(mapper.toDevice(const Offset(390, 10)), isNull);
    });

    test('corners clamp to the last pixel', () {
      final r = mapper.contentRect;
      expect(mapper.toDevice(r.topLeft), (x: 0, y: 0));
      expect(mapper.toDevice(r.bottomRight), (x: 1079, y: 2111));
    });

    test('toDeviceClamped pulls bar points onto the edge', () {
      expect(mapper.toDeviceClamped(const Offset(0, 200)), (x: 0, y: 1056));
    });
  });

  test('landscape device in a tall view (bars top/bottom)', () {
    const mapper = CoordinateMapper(viewSize: Size(400, 800), deviceSize: Size(2112, 1080));
    expect(mapper.toDevice(const Offset(200, 100)), isNull);
    expect(mapper.toDevice(const Offset(200, 400)), (x: 1056, y: 540));
  });

  test('empty sizes map to null', () {
    expect(const CoordinateMapper(viewSize: Size(400, 400), deviceSize: Size.zero).toDevice(const Offset(1, 1)), isNull);
    expect(const CoordinateMapper(viewSize: Size.zero, deviceSize: tallPhone).toDeviceClamped(Offset.zero), isNull);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/screen/coordinate_mapper_test.dart`
Expected: FAIL, missing `coordinate_mapper.dart`.

- [ ] **Step 3: Implement**

`lib/features/screen/coordinate_mapper.dart`:
```dart
import 'dart:math' as math;
import 'dart:ui';

/// Maps pointer positions on a letterboxed (BoxFit.contain) view of the
/// phone screen to the phone's real pixel coordinates used by /tap and /swipe.
class CoordinateMapper {
  const CoordinateMapper({required this.viewSize, required this.deviceSize});

  final Size viewSize;
  final Size deviceSize;

  /// Where the phone image is drawn inside the view.
  Rect get contentRect {
    if (viewSize.isEmpty || deviceSize.isEmpty) return Rect.zero;
    final scale = math.min(viewSize.width / deviceSize.width, viewSize.height / deviceSize.height);
    final width = deviceSize.width * scale;
    final height = deviceSize.height * scale;
    return Rect.fromLTWH((viewSize.width - width) / 2, (viewSize.height - height) / 2, width, height);
  }

  /// Device pixel under [local], or null when [local] is in the letterbox bars.
  ({int x, int y})? toDevice(Offset local) {
    final rect = contentRect;
    if (rect.isEmpty) return null;
    if (local.dx < rect.left || local.dx > rect.right || local.dy < rect.top || local.dy > rect.bottom) return null;
    return _map(local, rect);
  }

  /// Like [toDevice] but clamps points outside the image onto its edge
  /// (drag end points may leave the image).
  ({int x, int y})? toDeviceClamped(Offset local) {
    final rect = contentRect;
    if (rect.isEmpty) return null;
    return _map(Offset(local.dx.clamp(rect.left, rect.right), local.dy.clamp(rect.top, rect.bottom)), rect);
  }

  ({int x, int y}) _map(Offset point, Rect rect) => (
        x: ((point.dx - rect.left) / rect.width * deviceSize.width).round().clamp(0, deviceSize.width.toInt() - 1),
        y: ((point.dy - rect.top) / rect.height * deviceSize.height).round().clamp(0, deviceSize.height.toInt() - 1),
      );
}
```

- [ ] **Step 4: Run tests and analyze**

Run: `flutter test test/features/screen && flutter analyze`
Expected: `All tests passed!` and `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/features/screen test/features/screen
git commit -m "feat: add letterbox-aware screen coordinate mapper

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_018vGW2sL6yV3eTZKrrtJar3"
```

---

### Task 10: Token request flow and token rules

**Files:**
- Create: `lib/core/api/token_request_flow.dart`, `lib/core/api/token_rules.dart`, `test/support/mocks.dart`
- Test: `test/core/api/token_request_flow_test.dart`, `test/core/api/token_rules_test.dart`

**Interfaces:**
- Consumes: `HuskApi.requestToken`, `HuskApi.tokenStatus`, `TokenRequest`, `TokenStatus`, `TokenState` (Task 6); `HttpStatusException`, `OfflineException`, `HuskException` (Task 5).
- Produces:
  - `sealed class TokenFlowState { bool get isTerminal; }` with subtypes:
    - `TokenFlowRequesting()` (`toString` → `requesting`)
    - `TokenFlowPending(int secondsLeft)` (`pending(N)`)
    - `TokenFlowApproved(String token)` (`approved`; the token is never in `toString`)
    - `TokenFlowDenied()` (`denied`)
    - `TokenFlowExpired()` (`expired`)
    - `TokenFlowFailed(String message)` (`failed: …`)
  - `typedef Delay = Future<void> Function(Duration duration);`
  - `class TokenRequestFlow`:
    - constructor `TokenRequestFlow({required HuskApi api, required String clientName, Duration pollInterval = 2s, Delay? delay, DateTime Function()? now})`
    - `Stream<TokenFlowState> run()`, `void cancel()`
  - `bool isValidNewToken(String token)` (alphanumeric, 24–128 chars), `String generateToken({int length = 32, Random? random})`
  - `class MockHuskApi extends Mock implements HuskApi` in `test/support/mocks.dart`

- [ ] **Step 1: Write the shared mock**

`test/support/mocks.dart`:
```dart
import 'package:huskconfig/core/api/husk_api.dart';
import 'package:mocktail/mocktail.dart';

class MockHuskApi extends Mock implements HuskApi {}
```

- [ ] **Step 2: Write failing tests**

`test/core/api/token_rules_test.dart`:
```dart
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/api/token_rules.dart';

void main() {
  test('isValidNewToken enforces alphanumeric 24–128', () {
    expect(isValidNewToken('a' * 24), isTrue);
    expect(isValidNewToken('A1' * 64), isTrue);
    expect(isValidNewToken('a' * 23), isFalse);
    expect(isValidNewToken('a' * 129), isFalse);
    expect(isValidNewToken('${'a' * 30}-'), isFalse);
    expect(isValidNewToken(''), isFalse);
  });

  test('generateToken produces valid, different tokens', () {
    final t1 = generateToken();
    final t2 = generateToken();
    expect(t1.length, 32);
    expect(isValidNewToken(t1), isTrue);
    expect(t1, isNot(t2));
    expect(generateToken(length: 40, random: Random(1)).length, 40);
  });
}
```

`test/core/api/token_request_flow_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/api/husk_exception.dart';
import 'package:huskconfig/core/api/models/tools_models.dart';
import 'package:huskconfig/core/api/token_request_flow.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/mocks.dart';

const pending = TokenStatus(state: TokenState.pending);

void main() {
  late MockHuskApi api;
  late DateTime clock;

  setUp(() {
    api = MockHuskApi();
    clock = DateTime(2026, 10, 7, 12);
  });

  TokenRequestFlow flow() => TokenRequestFlow(
        api: api,
        clientName: 'Husk Config',
        now: () => clock,
        delay: (d) async => clock = clock.add(d),
      );

  void requestReturns({int expiresIn = 120}) => when(() => api.requestToken(client: 'Husk Config'))
      .thenAnswer((_) async => TokenRequest(id: 'req1', expiresIn: expiresIn));

  void statuses(List<Object> answers) {
    var i = 0;
    when(() => api.tokenStatus('req1')).thenAnswer((_) async {
      final answer = answers[i++];
      if (answer is Exception) throw answer;
      return answer as TokenStatus;
    });
  }

  Future<List<String>> names(TokenRequestFlow f) async => [for (final s in await f.run().toList()) s.toString()];

  test('approved after one pending poll', () async {
    requestReturns();
    statuses([pending, const TokenStatus(state: TokenState.approved, token: 'tok')]);
    final states = await flow().run().toList();
    expect(states.map((s) => s.toString()), ['requesting', 'pending(120)', 'pending(118)', 'approved']);
    expect((states.last as TokenFlowApproved).token, 'tok');
    expect(states.last.isTerminal, isTrue);
  });

  test('denied on the phone', () async {
    requestReturns();
    statuses([const TokenStatus(state: TokenState.denied)]);
    expect(await names(flow()), ['requesting', 'pending(120)', 'denied']);
  });

  test('expired reported by the phone', () async {
    requestReturns();
    statuses([const TokenStatus(state: TokenState.expired)]);
    expect(await names(flow()), ['requesting', 'pending(120)', 'expired']);
  });

  test('local deadline expires while still pending', () async {
    requestReturns(expiresIn: 4);
    statuses([pending, pending, pending, pending]);
    expect(await names(flow()), ['requesting', 'pending(4)', 'pending(2)', 'expired']);
  });

  test('a transient offline poll is tolerated', () async {
    requestReturns();
    statuses([const OfflineException('blip'), const TokenStatus(state: TokenState.approved, token: 'tok')]);
    expect(await names(flow()), ['requesting', 'pending(120)', 'pending(118)', 'approved']);
  });

  test('approved without a token is a failure', () async {
    requestReturns();
    statuses([const TokenStatus(state: TokenState.approved)]);
    final states = await flow().run().toList();
    expect(states.last, isA<TokenFlowFailed>());
  });

  test('429 explains that another request is pending', () async {
    when(() => api.requestToken(client: 'Husk Config')).thenThrow(HttpStatusException(429, ''));
    final states = await flow().run().toList();
    expect(states.last, isA<TokenFlowFailed>().having((s) => s.message, 'message', contains('already waiting')));
  });

  test('503 explains that notifications are disabled', () async {
    when(() => api.requestToken(client: 'Husk Config')).thenThrow(HttpStatusException(503, ''));
    final states = await flow().run().toList();
    expect(states.last, isA<TokenFlowFailed>().having((s) => s.message, 'message', contains('Notifications are disabled')));
  });

  test('offline request fails with the offline message', () async {
    when(() => api.requestToken(client: 'Husk Config')).thenThrow(const OfflineException("Can't reach 10.0.0.5:8090"));
    expect(await names(flow()), ['requesting', "failed: Can't reach 10.0.0.5:8090"]);
  });

  test('cancel stops polling', () async {
    requestReturns();
    statuses([pending, pending, pending]);
    final f = flow();
    final seen = <String>[];
    await for (final s in f.run()) {
      seen.add(s.toString());
      if (s is TokenFlowPending) f.cancel();
    }
    expect(seen, ['requesting', 'pending(120)']);
    verifyNever(() => api.tokenStatus(any()));
  });
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `flutter test test/core/api/token_rules_test.dart test/core/api/token_request_flow_test.dart`
Expected: FAIL, missing `token_rules.dart` / `token_request_flow.dart`.

- [ ] **Step 4: Implement token rules**

`lib/core/api/token_rules.dart`:
```dart
import 'dart:math';

final _validToken = RegExp(r'^[A-Za-z0-9]{24,128}$');
const _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

/// Husk accepts new tokens that are alphanumeric and 24–128 characters long.
bool isValidNewToken(String token) => _validToken.hasMatch(token);

String generateToken({int length = 32, Random? random}) {
  final rng = random ?? Random.secure();
  return String.fromCharCodes([for (var i = 0; i < length; i++) _alphabet.codeUnitAt(rng.nextInt(_alphabet.length))]);
}
```

- [ ] **Step 5: Implement the flow**

`lib/core/api/token_request_flow.dart`:
```dart
import 'husk_api.dart';
import 'husk_exception.dart';
import 'models/tools_models.dart';

sealed class TokenFlowState {
  const TokenFlowState();

  bool get isTerminal => true;
}

final class TokenFlowRequesting extends TokenFlowState {
  const TokenFlowRequesting();

  @override
  bool get isTerminal => false;

  @override
  String toString() => 'requesting';
}

final class TokenFlowPending extends TokenFlowState {
  const TokenFlowPending(this.secondsLeft);

  final int secondsLeft;

  @override
  bool get isTerminal => false;

  @override
  String toString() => 'pending($secondsLeft)';
}

final class TokenFlowApproved extends TokenFlowState {
  const TokenFlowApproved(this.token);

  final String token;

  /// Deliberately omits the token so it never ends up in logs.
  @override
  String toString() => 'approved';
}

final class TokenFlowDenied extends TokenFlowState {
  const TokenFlowDenied();

  @override
  String toString() => 'denied';
}

final class TokenFlowExpired extends TokenFlowState {
  const TokenFlowExpired();

  @override
  String toString() => 'expired';
}

final class TokenFlowFailed extends TokenFlowState {
  const TokenFlowFailed(this.message);

  final String message;

  @override
  String toString() => 'failed: $message';
}

typedef Delay = Future<void> Function(Duration duration);

/// /token/request → poll /token/status until approved, denied or expired.
/// The phone shows an Approve/Deny notification; nothing here can approve.
class TokenRequestFlow {
  TokenRequestFlow({
    required this.api,
    required this.clientName,
    this.pollInterval = const Duration(seconds: 2),
    Delay? delay,
    DateTime Function()? now,
  })  : _delay = delay ?? Future<void>.delayed,
        _now = now ?? DateTime.now;

  final HuskApi api;
  final String clientName;
  final Duration pollInterval;
  final Delay _delay;
  final DateTime Function() _now;
  bool _cancelled = false;

  void cancel() => _cancelled = true;

  Stream<TokenFlowState> run() async* {
    yield const TokenFlowRequesting();
    final TokenRequest request;
    try {
      request = await api.requestToken(client: clientName);
    } on HttpStatusException catch (e) {
      yield TokenFlowFailed(switch (e.statusCode) {
        429 => 'Another token request is already waiting on the phone. Try again in a couple of minutes.',
        503 => 'Notifications are disabled on the phone, so it cannot ask for approval.',
        _ => e.message,
      });
      return;
    } on HuskException catch (e) {
      yield TokenFlowFailed(e.message);
      return;
    }

    final deadline = _now().add(Duration(seconds: request.expiresIn));
    while (!_cancelled) {
      final secondsLeft = deadline.difference(_now()).inSeconds;
      if (secondsLeft <= 0) {
        yield const TokenFlowExpired();
        return;
      }
      yield TokenFlowPending(secondsLeft);
      await _delay(pollInterval);
      if (_cancelled) return;

      final TokenStatus status;
      try {
        status = await api.tokenStatus(request.id);
      } on OfflineException {
        continue; // Transient network blip; keep polling until the deadline.
      } on HuskException catch (e) {
        yield TokenFlowFailed(e.message);
        return;
      }

      switch (status.state) {
        case TokenState.pending:
          break;
        case TokenState.approved:
          final token = status.token;
          yield token == null || token.isEmpty
              ? const TokenFlowFailed('The phone approved the request but sent no token.')
              : TokenFlowApproved(token);
          return;
        case TokenState.denied:
          yield const TokenFlowDenied();
          return;
        case TokenState.expired:
          yield const TokenFlowExpired();
          return;
      }
    }
  }
}
```

- [ ] **Step 6: Run tests and analyze**

Run: `flutter test test/core/api && flutter analyze`
Expected: `All tests passed!` and `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add lib/core/api test/core/api test/support/mocks.dart
git commit -m "feat: add token request flow state machine and token rules

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_018vGW2sL6yV3eTZKrrtJar3"
```

---

### Task 11: LAN scanner

**Files:**
- Create: `lib/core/net/lan_scanner.dart`
- Test: `test/core/net/lan_scanner_test.dart`

**Interfaces:**
- Consumes: `HuskApi.healthz`, `HuskApi.close` (Task 5); `IpValidator.isIpLiteral`, `IpValidator.baseUrl` (Task 3).
- Produces:
  - `typedef HostProbe = Future<bool> Function(String host, int port);`
  - `sealed class ScanEvent` with subtypes `ScanProgress(int done, int total)` and `ScanFound(String host)`
  - `class LanScanner`:
    - constructor `LanScanner({HostProbe? probe, int concurrency = 32})`
    - `static String? prefixOf(String? ipv4)`
    - `static bool isValidPrefix(String prefix)`
    - `static Future<bool> defaultProbe(String host, int port)`
    - `Stream<ScanEvent> scan({required String prefix, required int port, String? excludeHost})`

- [ ] **Step 1: Write failing tests**

`test/core/net/lan_scanner_test.dart`:
```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/net/lan_scanner.dart';

void main() {
  test('prefixOf takes the first three IPv4 octets', () {
    expect(LanScanner.prefixOf('192.168.0.106'), '192.168.0');
    expect(LanScanner.prefixOf('fd7a::1'), isNull);
    expect(LanScanner.prefixOf(null), isNull);
    expect(LanScanner.prefixOf('nonsense'), isNull);
  });

  test('isValidPrefix', () {
    expect(LanScanner.isValidPrefix('192.168.0'), isTrue);
    expect(LanScanner.isValidPrefix(' 10.0.5 '), isTrue);
    expect(LanScanner.isValidPrefix('192.168'), isFalse);
    expect(LanScanner.isValidPrefix('192.168.256'), isFalse);
    expect(LanScanner.isValidPrefix('a.b.c'), isFalse);
  });

  test('finds matching hosts, skips the excluded one, and reports progress to the end', () async {
    final probed = <String>[];
    final scanner = LanScanner(probe: (host, port) async {
      probed.add('$host:$port');
      return host == '192.168.0.106' || host == '192.168.0.7';
    });
    final events = await scanner.scan(prefix: '192.168.0', port: 8090, excludeHost: '192.168.0.50').toList();
    expect(events.whereType<ScanFound>().map((e) => e.host).toSet(), {'192.168.0.106', '192.168.0.7'});
    final last = events.whereType<ScanProgress>().last;
    expect((last.done, last.total), (253, 253));
    expect(probed, isNot(contains('192.168.0.50:8090')));
    expect(probed, contains('192.168.0.1:8090'));
    expect(probed, contains('192.168.0.254:8090'));
  });

  test('a throwing probe counts as no match', () async {
    final scanner = LanScanner(probe: (host, port) async => throw StateError('boom'));
    final events = await scanner.scan(prefix: '10.0.0', port: 8090).toList();
    expect(events.whereType<ScanFound>(), isEmpty);
    expect(events.whereType<ScanProgress>().last.done, 254);
  });

  test('never exceeds the concurrency limit', () async {
    var inFlight = 0, maxInFlight = 0;
    final scanner = LanScanner(
      concurrency: 4,
      probe: (host, port) async {
        inFlight++;
        maxInFlight = inFlight > maxInFlight ? inFlight : maxInFlight;
        await Future<void>.delayed(Duration.zero);
        inFlight--;
        return false;
      },
    );
    await scanner.scan(prefix: '10.0.0', port: 8090).drain<void>();
    expect(maxInFlight, 4);
  });

  test('cancelling the subscription stops probing', () async {
    var calls = 0;
    final scanner = LanScanner(
      concurrency: 2,
      probe: (host, port) async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 1));
        return false;
      },
    );
    final sub = scanner.scan(prefix: '10.0.0', port: 8090).listen(null);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await sub.cancel();
    final callsAtCancel = calls;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(calls, lessThan(254));
    expect(calls, lessThanOrEqualTo(callsAtCancel + 2));
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/core/net/lan_scanner_test.dart`
Expected: FAIL, missing `lan_scanner.dart`.

- [ ] **Step 3: Implement**

`lib/core/net/lan_scanner.dart`:
```dart
import 'dart:async';

import '../api/husk_api.dart';
import '../api/husk_exception.dart';
import 'ip_validator.dart';

typedef HostProbe = Future<bool> Function(String host, int port);

sealed class ScanEvent {
  const ScanEvent();
}

final class ScanProgress extends ScanEvent {
  const ScanProgress(this.done, this.total);

  final int done;
  final int total;
}

final class ScanFound extends ScanEvent {
  const ScanFound(this.host);

  final String host;
}

/// Probes every host of a /24 for Husk's /healthz with bounded concurrency.
class LanScanner {
  LanScanner({HostProbe? probe, this.concurrency = 32}) : _probe = probe ?? defaultProbe;

  static final _prefixPattern = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})$');

  final int concurrency;
  final HostProbe _probe;

  /// "192.168.0" for "192.168.0.106"; null for IPv6, null or invalid input.
  static String? prefixOf(String? ipv4) {
    if (ipv4 == null || ipv4.contains(':') || !IpValidator.isIpLiteral(ipv4)) return null;
    return ipv4.trim().split('.').take(3).join('.');
  }

  static bool isValidPrefix(String prefix) {
    final match = _prefixPattern.firstMatch(prefix.trim());
    if (match == null) return false;
    return [1, 2, 3].every((g) => int.parse(match.group(g)!) <= 255);
  }

  static Future<bool> defaultProbe(String host, int port) async {
    final api = HuskApi(
      baseUrl: IpValidator.baseUrl(host, port),
      connectTimeout: const Duration(seconds: 1),
      receiveTimeout: const Duration(seconds: 1),
    );
    try {
      return await api.healthz();
    } on HuskException {
      return false;
    } finally {
      api.close();
    }
  }

  Stream<ScanEvent> scan({required String prefix, required int port, String? excludeHost}) {
    final base = prefix.trim();
    final hosts = [for (var i = 1; i <= 254; i++) '$base.$i']..remove(excludeHost);
    late final StreamController<ScanEvent> controller;
    var cancelled = false;
    var next = 0;
    var done = 0;

    Future<void> worker() async {
      while (!cancelled && next < hosts.length) {
        final host = hosts[next++];
        bool found;
        try {
          found = await _probe(host, port);
        } catch (_) {
          found = false; // A probe failure just means "not a Husk device".
        }
        if (cancelled) return;
        if (found) controller.add(ScanFound(host));
        controller.add(ScanProgress(++done, hosts.length));
      }
    }

    controller = StreamController<ScanEvent>(
      onListen: () async {
        await Future.wait([for (var i = 0; i < concurrency; i++) worker()]);
        if (!cancelled) await controller.close();
      },
      onCancel: () => cancelled = true,
    );
    return controller.stream;
  }
}
```

- [ ] **Step 4: Run tests and analyze**

Run: `flutter test test/core/net && flutter analyze`
Expected: `All tests passed!` and `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/core/net test/core/net
git commit -m "feat: add LAN /24 scanner for Husk devices

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_018vGW2sL6yV3eTZKrrtJar3"
```

---

### Task 12: Core providers, controllers and polling

**Files:**
- Create: `lib/core/providers.dart`, `lib/core/polling.dart`, `lib/features/settings/settings_controller.dart`, `lib/features/servers/servers_controller.dart`, `lib/features/servers/api_provider.dart`
- Test: `test/features/servers/servers_controller_test.dart`, `test/features/settings/settings_controller_test.dart`, `test/core/polling_test.dart`

**Interfaces:**
- Consumes:
  - repositories (Task 4) and `ServerConfig`, `AppSettings` (Task 3)
  - `HuskApi` (Task 5)
  - test helpers `MemoryServerRepository`, `MemorySettingsRepository` (Task 4)
- Produces:
  - `final sharedPreferencesProvider = Provider<SharedPreferences>` (must be overridden)
  - `final serverRepositoryProvider = Provider<ServerRepository>`
  - `final settingsRepositoryProvider = Provider<SettingsRepository>`
  - `final appForegroundProvider = NotifierProvider<AppForeground, bool>` (`AppForeground.set(bool)`)
  - `Stream<T> pollEvery<T>(Ref ref, Duration? interval, Future<T> Function() fetch)`:
    - `null` interval: no fetch at all
    - `Duration.zero`: fetch once
    - errors are emitted and polling continues
  - `final settingsProvider = NotifierProvider<SettingsController, AppSettings>` (`Future<void> update(AppSettings Function(AppSettings) change)`)
  - `final pollIntervalProvider = Provider<Duration?>`: null in background, `Duration.zero` when polling is off
  - `final serversProvider = NotifierProvider<ServersController, List<ServerConfig>>`. `ServersController` methods:
    - `ServerConfig? byId(String id)`
    - `bool isDuplicate(String host, int port, {String? exceptId})`
    - `Future<ServerConfig> add({required String name, required String host, required int port, String? token})`
    - `Future<void> update(ServerConfig)`, `Future<void> remove(String id)`
    - `Future<void> setToken(String id, String token)`, `Future<void> touch(String id)`
  - `final serverByIdProvider = Provider.family<ServerConfig?, String>`
  - `final apiProvider = Provider.autoDispose.family<HuskApi, String>`:
    - rebuilt only when the server's address or token changes
    - throws `StateError` for unknown ids
    - **widgets must `ref.watch` it in `build`** and use that instance in callbacks

- [ ] **Step 1: Write failing tests**

`test/features/servers/servers_controller_test.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/providers.dart';
import 'package:huskconfig/core/storage/server_config.dart';
import 'package:huskconfig/features/servers/api_provider.dart';
import 'package:huskconfig/features/servers/servers_controller.dart';

import '../../support/memory_repos.dart';

void main() {
  late MemoryServerRepository repo;

  ProviderContainer container() {
    final c = ProviderContainer(
      retry: (_, _) => null,
      overrides: [serverRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() => repo = MemoryServerRepository([
        ServerConfig(id: 's1', name: 'One', host: '10.0.0.1', port: 8090, createdAt: DateTime.utc(2026)),
      ]));

  test('loads saved servers', () {
    expect(container().read(serversProvider).map((s) => s.id), ['s1']);
  });

  test('add persists with a fresh id and drops an empty token', () async {
    final c = container();
    final added = await c.read(serversProvider.notifier).add(name: 'Two', host: '10.0.0.2', port: 8091, token: '');
    expect(added.id, isNot('s1'));
    expect(added.token, isNull);
    expect(repo.saved.map((s) => s.name), ['One', 'Two']);
  });

  test('update, setToken, touch and remove persist', () async {
    final c = container();
    final notifier = c.read(serversProvider.notifier);
    await notifier.update(notifier.byId('s1')!.copyWith(name: 'Renamed'));
    await notifier.setToken('s1', 'tok');
    await notifier.touch('s1');
    expect(repo.saved.single.name, 'Renamed');
    expect(repo.saved.single.token, 'tok');
    expect(repo.saved.single.lastUsedAt, isNotNull);
    await notifier.remove('s1');
    expect(repo.saved, isEmpty);
  });

  test('isDuplicate compares host and port, excluding the edited server', () {
    final notifier = container().read(serversProvider.notifier);
    expect(notifier.isDuplicate('10.0.0.1', 8090), isTrue);
    expect(notifier.isDuplicate('10.0.0.1', 8091), isFalse);
    expect(notifier.isDuplicate('10.0.0.1', 8090, exceptId: 's1'), isFalse);
  });

  test('apiProvider builds a client for the server and is stable across touch()', () async {
    final c = container();
    final sub = c.listen(apiProvider('s1'), (_, _) {});
    final first = sub.read();
    expect(first.baseUrl, 'http://10.0.0.1:8090');
    await c.read(serversProvider.notifier).touch('s1');
    expect(c.read(apiProvider('s1')), same(first));
    await c.read(serversProvider.notifier).setToken('s1', 'new');
    expect(c.read(apiProvider('s1')).token, 'new');
    sub.close();
  });
}
```

`test/features/settings/settings_controller_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/providers.dart';
import 'package:huskconfig/core/storage/app_settings.dart';
import 'package:huskconfig/features/settings/settings_controller.dart';

import '../../support/memory_repos.dart';

void main() {
  test('update persists and pollIntervalProvider follows settings and foreground', () async {
    final repo = MemorySettingsRepository();
    final c = ProviderContainer(retry: (_, _) => null, overrides: [settingsRepositoryProvider.overrideWithValue(repo)]);
    addTearDown(c.dispose);

    expect(c.read(pollIntervalProvider), const Duration(seconds: 10));
    await c.read(settingsProvider.notifier).update((s) => s.copyWith(themeMode: ThemeMode.dark, pollIntervalSeconds: 0));
    expect(repo.saved.themeMode, ThemeMode.dark);
    expect(c.read(pollIntervalProvider), Duration.zero);

    c.read(appForegroundProvider.notifier).set(false);
    expect(c.read(pollIntervalProvider), isNull);
    expect(c.read(settingsProvider), const AppSettings(themeMode: ThemeMode.dark, pollIntervalSeconds: 0));
  });
}
```

`test/core/polling_test.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/polling.dart';

void main() {
  ProviderContainer container() {
    final c = ProviderContainer(retry: (_, _) => null);
    addTearDown(c.dispose);
    return c;
  }

  test('Duration.zero fetches exactly once', () async {
    var calls = 0;
    final p = StreamProvider.autoDispose<int>((ref) => pollEvery(ref, Duration.zero, () async => ++calls));
    final c = container();
    final sub = c.listen(p, (_, _) {});
    expect(await c.read(p.future), 1);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(calls, 1);
    sub.close();
  });

  test('null interval never fetches', () async {
    var calls = 0;
    final p = StreamProvider.autoDispose<int>((ref) => pollEvery(ref, null, () async => ++calls));
    final c = container();
    final sub = c.listen(p, (_, _) {});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(calls, 0);
    sub.close();
  });

  test('repeats at the interval, keeps going after errors, stops when disposed', () async {
    var calls = 0;
    final p = StreamProvider.autoDispose<int>((ref) => pollEvery(ref, const Duration(milliseconds: 5), () async {
          calls++;
          if (calls == 1) throw StateError('first fails');
          return calls;
        }));
    final c = ProviderContainer(retry: (_, _) => null);
    final seen = <AsyncValue<int>>[];
    c.listen(p, (_, next) => seen.add(next));
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(calls, greaterThanOrEqualTo(3));
    expect(seen.any((v) => v.hasError), isTrue);
    expect(seen.last.value, greaterThanOrEqualTo(2));
    c.dispose();
    final atDispose = calls;
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(calls, lessThanOrEqualTo(atDispose + 1));
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features test/core/polling_test.dart`
Expected: FAIL, missing `providers.dart`, `polling.dart`, controllers.

- [ ] **Step 3: Implement core providers and polling**

`lib/core/providers.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'storage/server_repository.dart';
import 'storage/settings_repository.dart';

/// Overridden in main() with the loaded instance (and in tests by the repositories).
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPreferencesProvider must be overridden'),
);

final serverRepositoryProvider = Provider<ServerRepository>(
  (ref) => PrefsServerRepository(ref.watch(sharedPreferencesProvider)),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => PrefsSettingsRepository(ref.watch(sharedPreferencesProvider)),
);

/// False while the app is hidden or paused; set by HuskConfigApp's lifecycle listener.
class AppForeground extends Notifier<bool> {
  @override
  bool build() => true;

  void set(bool value) => state = value;
}

final appForegroundProvider = NotifierProvider<AppForeground, bool>(AppForeground.new);
```

`lib/core/polling.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Repeatedly calls [fetch] for a StreamProvider.
///
/// [interval] null → do nothing (app in background); Duration.zero → fetch
/// once (polling off). Errors are emitted and polling continues. Stops when
/// the provider is disposed or rebuilt.
Stream<T> pollEvery<T>(Ref ref, Duration? interval, Future<T> Function() fetch) async* {
  if (interval == null) return;
  while (ref.mounted) {
    try {
      final value = await fetch();
      if (!ref.mounted) return;
      yield value;
    } catch (error, stackTrace) {
      if (!ref.mounted) return;
      yield* Stream<T>.error(error, stackTrace);
    }
    if (interval == Duration.zero) return;
    await Future<void>.delayed(interval);
  }
}
```

- [ ] **Step 4: Implement the settings and servers controllers and `apiProvider`**

`lib/features/settings/settings_controller.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/storage/app_settings.dart';

class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.watch(settingsRepositoryProvider).load();

  Future<void> update(AppSettings Function(AppSettings current) change) async {
    final next = change(state);
    state = next;
    await ref.read(settingsRepositoryProvider).save(next);
  }
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(SettingsController.new);

/// How often live data refreshes: null while the app is in the background,
/// Duration.zero when polling is off (fetch once), otherwise the interval.
final pollIntervalProvider = Provider<Duration?>((ref) {
  if (!ref.watch(appForegroundProvider)) return null;
  return Duration(seconds: ref.watch(settingsProvider.select((s) => s.pollIntervalSeconds)));
});
```

`lib/features/servers/servers_controller.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/providers.dart';
import '../../core/storage/server_config.dart';

class ServersController extends Notifier<List<ServerConfig>> {
  @override
  List<ServerConfig> build() => ref.watch(serverRepositoryProvider).loadAll();

  ServerConfig? byId(String id) => state.where((s) => s.id == id).firstOrNull;

  bool isDuplicate(String host, int port, {String? exceptId}) =>
      state.any((s) => s.id != exceptId && s.host == host && s.port == port);

  Future<ServerConfig> add({required String name, required String host, required int port, String? token}) async {
    final server = ServerConfig(
      id: const Uuid().v4(),
      name: name,
      host: host,
      port: port,
      token: token == null || token.isEmpty ? null : token,
      createdAt: DateTime.now(),
    );
    await _save([...state, server]);
    return server;
  }

  Future<void> update(ServerConfig server) => _save([for (final s in state) s.id == server.id ? server : s]);

  Future<void> remove(String id) => _save([for (final s in state) if (s.id != id) s]);

  Future<void> setToken(String id, String token) async {
    final server = byId(id);
    if (server != null) await update(server.copyWith(token: token));
  }

  Future<void> touch(String id) async {
    final server = byId(id);
    if (server != null) await update(server.copyWith(lastUsedAt: DateTime.now()));
  }

  Future<void> _save(List<ServerConfig> servers) async {
    state = servers;
    await ref.read(serverRepositoryProvider).saveAll(servers);
  }
}

final serversProvider = NotifierProvider<ServersController, List<ServerConfig>>(ServersController.new);

final serverByIdProvider = Provider.family<ServerConfig?, String>(
  (ref, id) => ref.watch(serversProvider).where((s) => s.id == id).firstOrNull,
);
```

`lib/features/servers/api_provider.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/husk_api.dart';
import 'servers_controller.dart';

/// The HuskApi for a saved server. Rebuilt only when its address or token
/// changes (not on lastUsedAt/name edits). Widgets must `ref.watch` this in
/// build and use that instance in their callbacks.
final apiProvider = Provider.autoDispose.family<HuskApi, String>((ref, serverId) {
  final connection = ref.watch(serversProvider.select((servers) {
    final server = servers.where((s) => s.id == serverId).firstOrNull;
    return server == null ? null : (baseUrl: server.baseUrl, token: server.token);
  }));
  if (connection == null) throw StateError('Unknown server $serverId');
  final api = HuskApi(baseUrl: connection.baseUrl, token: connection.token);
  ref.onDispose(api.close);
  return api;
});
```

- [ ] **Step 5: Run tests and analyze**

Run: `flutter test && flutter analyze`
Expected: `All tests passed!` and `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib test
git commit -m "feat: add Riverpod controllers, api provider and polling helper

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_018vGW2sL6yV3eTZKrrtJar3"
```

---

### Task 13: App shell, router and dashboard

**Files:**
- Create:
  - `lib/app.dart`, `lib/core/router.dart`
  - `lib/shared/error_text.dart`, `lib/shared/widgets/status_dot.dart`, `lib/shared/widgets/confirm_dialog.dart`
  - `lib/features/servers/server_actions.dart`
  - `lib/features/dashboard/server_status.dart`, `lib/features/dashboard/server_card.dart`, `lib/features/dashboard/dashboard_screen.dart`
  - `test/support/test_app.dart`, `test/support/fixtures.dart`
- Replace: `lib/main.dart`
- Delete: `test/widget_test.dart`
- Test: `test/app_test.dart`, `test/features/dashboard/dashboard_test.dart`

**Interfaces:**
- Consumes:
  - `serversProvider`, `apiProvider`, `settingsProvider`, `pollIntervalProvider`, `appForegroundProvider`, `pollEvery` (Task 12)
  - `HuskApi.info`, `DeviceInfo` (Task 6)
  - exceptions (Task 5)
- Produces:
  - `class HuskConfigApp extends ConsumerStatefulWidget`
  - `GoRouter createRouter()`: route `/` → `DashboardScreen`; later tasks add routes here
  - `String describeError(Object error)`
  - `enum DotState { online, offline, unauthorized, unknown }`, `class StatusDot(DotState state, {double size = 10})`
  - `Future<bool> confirm(BuildContext context, {required String title, required String message, String confirmLabel = 'Continue'})`
  - `Future<void> confirmDeleteServer(BuildContext context, WidgetRef ref, ServerConfig server)`
  - `sealed class ServerStatus` with subtypes:
    - `ServerOnline(DeviceInfo info, DateTime checkedAt)`
    - `ServerOffline(String message, {DateTime? lastSeen})`
    - `ServerUnauthorized()`
    - getter `DotState dot`
  - `Future<ServerStatus> checkServer(HuskApi api, {DateTime? lastSeen})`
  - `final serverStatusProvider = StreamProvider.autoDispose.family<ServerStatus, String>`
  - `class ServerCard(ServerConfig server)`, `class DashboardScreen`
  - test helpers:
    - `Widget testApp({List<ServerConfig> servers, AppSettings settings, List<Override> overrides})`
    - `ProviderScope testScope({required Widget child, List<ServerConfig> servers, AppSettings settings, List<Override> overrides, MemoryServerRepository? serverRepo, MemorySettingsRepository? settingsRepo})`
    - fixtures `deviceInfoFixture()`, `flagsFixture({bool screen})`, `server1`

- [ ] **Step 1: Write test support**

`test/support/fixtures.dart`:
```dart
import 'dart:convert';

import 'package:huskconfig/core/api/models/device_models.dart';
import 'package:huskconfig/core/storage/server_config.dart';

final server1 = ServerConfig(id: 's1', name: 'Kitchen phone', host: '192.168.0.106', port: 8090, createdAt: DateTime.utc(2026, 10, 7));

DeviceInfo deviceInfoFixture({int battery = 87, bool charging = false}) => DeviceInfo.fromJson(jsonDecode(
      '{"app":{"package":"co.xplat.husk","versionName":"1.4","versionCode":"55"},'
      '"device":{"manufacturer":"samsung","model":"SM-A750F","androidRelease":"10","sdkInt":29,"dexCapable":false,"hasCamera":true},'
      '"screen":{"width":1080,"height":2112},"net":{"localIp":"192.168.0.106","tailscaleIp":null},'
      '"battery":{"level":$battery,"charging":$charging},"services":{"a11y":true,"camera":true,"screen":false,"dexReconnect":false}}',
    ) as Map<String, Object?>);

Flags flagsFixture({bool screen = false, bool front = true}) => Flags.fromJson({
      'dexReconnect': false, 'a11y': true, 'camera': false, 'front': front, 'screen': screen,
      'motion': false, 'ntfy': false, 'batteryOptIgnored': true, 'lastNtfy': '',
    });
```

`test/support/test_app.dart`:
```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:huskconfig/app.dart';
import 'package:huskconfig/core/providers.dart';
import 'package:huskconfig/core/storage/app_settings.dart';
import 'package:huskconfig/core/storage/server_config.dart';

import 'memory_repos.dart';

/// A ProviderScope wired to in-memory repositories with retries disabled.
ProviderScope testScope({
  required Widget child,
  List<ServerConfig> servers = const [],
  AppSettings settings = const AppSettings(),
  List<Override> overrides = const [],
  MemoryServerRepository? serverRepo,
  MemorySettingsRepository? settingsRepo,
}) =>
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        serverRepositoryProvider.overrideWithValue(serverRepo ?? MemoryServerRepository(servers)),
        settingsRepositoryProvider.overrideWithValue(settingsRepo ?? MemorySettingsRepository(settings)),
        ...overrides,
      ],
      child: child,
    );

Widget testApp({
  List<ServerConfig> servers = const [],
  AppSettings settings = const AppSettings(),
  List<Override> overrides = const [],
}) =>
    testScope(servers: servers, settings: settings, overrides: overrides, child: const HuskConfigApp());
```

- [ ] **Step 2: Write failing tests**

Delete `test/widget_test.dart`:
```bash
git rm -q test/widget_test.dart
```

`test/app_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app.dart';

void main() {
  testWidgets('boots to the empty dashboard with add and scan actions', (tester) async {
    await tester.pumpWidget(testApp());
    await tester.pumpAndSettle();
    expect(find.text('No Husk servers yet'), findsOneWidget);
    expect(find.text('Add server'), findsOneWidget);
    expect(find.text('Scan network'), findsOneWidget);
  });
}
```

`test/features/dashboard/dashboard_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/features/dashboard/server_status.dart';

import '../../support/fixtures.dart';
import '../../support/test_app.dart';

void main() {
  Future<void> pumpWith(WidgetTester tester, ServerStatus status) async {
    await tester.pumpWidget(testApp(
      servers: [server1],
      overrides: [serverStatusProvider.overrideWith((ref, id) => Stream.value(status))],
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('online card shows model, Android version, battery and services', (tester) async {
    await pumpWith(tester, ServerOnline(deviceInfoFixture(battery: 87), DateTime(2026, 10, 7, 12)));
    expect(find.text('Kitchen phone'), findsOneWidget);
    expect(find.text('192.168.0.106:8090'), findsOneWidget);
    expect(find.textContaining('samsung SM-A750F'), findsOneWidget);
    expect(find.textContaining('Android 10'), findsOneWidget);
    expect(find.text('87%'), findsOneWidget);
    expect(find.text('a11y'), findsOneWidget);
    expect(find.text('Add server'), findsOneWidget); // FAB
  });

  testWidgets('offline card shows the reason', (tester) async {
    await pumpWith(tester, const ServerOffline("Can't reach 192.168.0.106:8090"));
    expect(find.text('Offline'), findsOneWidget);
    expect(find.text("Can't reach 192.168.0.106:8090"), findsOneWidget);
  });

  testWidgets('unauthorized card asks for a token', (tester) async {
    await pumpWith(tester, const ServerUnauthorized());
    expect(find.text('Token required'), findsOneWidget);
  });

  testWidgets('delete asks for confirmation and removes the card', (tester) async {
    await pumpWith(tester, const ServerUnauthorized());
    await tester.tap(find.byTooltip('Server actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete Kitchen phone?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.text('No Husk servers yet'), findsOneWidget);
  });
}

```

- [ ] **Step 3: Run to verify it fails**

Run: `flutter test test/app_test.dart test/features/dashboard`
Expected: FAIL, missing `app.dart`, `server_status.dart`, etc.

- [ ] **Step 4: Implement shared helpers and widgets**

`lib/shared/error_text.dart`:
```dart
import '../core/api/husk_exception.dart';

/// User-facing text for any error caught in the UI.
String describeError(Object error) => error is HuskException ? error.message : 'Unexpected error: $error';
```

`lib/shared/widgets/status_dot.dart`:
```dart
import 'package:flutter/material.dart';

enum DotState { online, offline, unauthorized, unknown }

class StatusDot extends StatelessWidget {
  const StatusDot(this.state, {super.key, this.size = 10});

  final DotState state;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (color, label) = switch (state) {
      DotState.online => (Colors.green, 'Online'),
      DotState.offline => (scheme.error, 'Offline'),
      DotState.unauthorized => (Colors.amber.shade700, 'Token required'),
      DotState.unknown => (scheme.outline, 'Checking'),
    };
    return Tooltip(
      message: label,
      child: Container(width: size, height: size, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    );
  }
}
```

`lib/shared/widgets/confirm_dialog.dart`:
```dart
import 'package:flutter/material.dart';

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Continue',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(confirmLabel)),
      ],
    ),
  );
  return result ?? false;
}
```

`lib/features/servers/server_actions.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/server_config.dart';
import '../../shared/widgets/confirm_dialog.dart';
import 'servers_controller.dart';

Future<void> confirmDeleteServer(BuildContext context, WidgetRef ref, ServerConfig server) async {
  final ok = await confirm(
    context,
    title: 'Delete ${server.name}?',
    message: 'This removes ${server.address} and its token from this app. Nothing changes on the phone.',
    confirmLabel: 'Delete',
  );
  if (ok) await ref.read(serversProvider.notifier).remove(server.id);
}
```

- [ ] **Step 5: Implement server status and the dashboard**

`lib/features/dashboard/server_status.dart`:
```dart
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
```

`lib/features/dashboard/server_card.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/storage/server_config.dart';
import '../../shared/error_text.dart';
import '../../shared/widgets/status_dot.dart';
import '../servers/server_actions.dart';
import 'server_status.dart';

enum _CardAction { edit, delete }

class ServerCard extends ConsumerWidget {
  const ServerCard({super.key, required this.server});

  final ServerConfig server;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(serverStatusProvider(server.id));
    final theme = Theme.of(context);
    final dot = status.value?.dot ?? (status.hasError ? DotState.offline : DotState.unknown);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go('/device/${server.id}/overview'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  StatusDot(dot),
                  const SizedBox(width: 8),
                  Expanded(child: Text(server.name, style: theme.textTheme.titleMedium, overflow: TextOverflow.ellipsis)),
                  PopupMenuButton<_CardAction>(
                    tooltip: 'Server actions',
                    onSelected: (action) => _onAction(context, ref, action),
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: _CardAction.edit, child: Text('Edit')),
                      PopupMenuItem(value: _CardAction.delete, child: Text('Delete')),
                    ],
                  ),
                ],
              ),
              Text(server.address, style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              switch (status) {
                AsyncValue(value: final ServerStatus value) => _StatusBody(value),
                AsyncValue(error: final Object error) => _OfflineBody(describeError(error), null),
                _ => const Text('Checking…'),
              },
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onAction(BuildContext context, WidgetRef ref, _CardAction action) async {
    switch (action) {
      case _CardAction.edit:
        await context.push('/servers/${server.id}/edit');
      case _CardAction.delete:
        await confirmDeleteServer(context, ref, server);
    }
  }
}

class _StatusBody extends StatelessWidget {
  const _StatusBody(this.status);

  final ServerStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return switch (status) {
      ServerOnline(:final info, :final checkedAt) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${info.displayName} · Android ${info.androidRelease}'),
            const SizedBox(height: 4),
            Row(children: [
              Icon(info.batteryCharging ? Icons.battery_charging_full : Icons.battery_std, size: 18),
              const SizedBox(width: 4),
              Text(info.batteryLevel == null ? '—' : '${info.batteryLevel}%'),
            ]),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, children: [
              _ServiceChip('a11y', info.services.a11y),
              _ServiceChip('camera', info.services.camera),
              _ServiceChip('screen', info.services.screen),
            ]),
            const SizedBox(height: 6),
            Text('Checked ${TimeOfDay.fromDateTime(checkedAt).format(context)}', style: theme.textTheme.bodySmall),
          ],
        ),
      ServerOffline(:final message, :final lastSeen) => _OfflineBody(message, lastSeen),
      ServerUnauthorized() => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Token required', style: TextStyle(color: Colors.amber.shade800, fontWeight: FontWeight.w600)),
            const Text('Edit the server or request a token.'),
          ],
        ),
    };
  }
}

class _OfflineBody extends StatelessWidget {
  const _OfflineBody(this.message, this.lastSeen);

  final String message;
  final DateTime? lastSeen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final seen = lastSeen;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Offline', style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.w600)),
        Text(message, style: theme.textTheme.bodySmall),
        if (seen != null) Text('Last seen ${TimeOfDay.fromDateTime(seen).format(context)}', style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _ServiceChip extends StatelessWidget {
  const _ServiceChip(this.label, this.on);

  final String label;
  final bool on;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: on ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label, style: TextStyle(fontSize: 12, color: on ? scheme.onPrimaryContainer : scheme.onSurfaceVariant)),
    );
  }
}
```

`lib/features/dashboard/dashboard_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../servers/servers_controller.dart';
import 'server_card.dart';
import 'server_status.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(serversProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Husk Config'),
        actions: [
          if (servers.isNotEmpty)
            IconButton(tooltip: 'Scan network', icon: const Icon(Icons.wifi_find), onPressed: () => context.push('/servers/scan')),
          IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: () => ref.invalidate(serverStatusProvider)),
          IconButton(tooltip: 'Settings', icon: const Icon(Icons.settings), onPressed: () => context.push('/settings')),
        ],
      ),
      floatingActionButton: servers.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push('/servers/new'),
              icon: const Icon(Icons.add),
              label: const Text('Add server'),
            ),
      body: servers.isEmpty
          ? const _EmptyState()
          : RefreshIndicator(
              onRefresh: () async => ref.invalidate(serverStatusProvider),
              child: LayoutBuilder(builder: (context, constraints) {
                const gap = 12.0, padding = 16.0;
                final columns = (constraints.maxWidth / 360).floor().clamp(1, 4);
                final cardWidth = (constraints.maxWidth - padding * 2 - gap * (columns - 1)) / columns;
                return SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(padding, padding, padding, 96),
                  child: Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [for (final s in servers) SizedBox(width: cardWidth, child: ServerCard(server: s))],
                  ),
                );
              }),
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.phone_android, size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('No Husk servers yet', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text(
              'Add a phone running Husk by its IP address, or scan your network to find it.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Wrap(spacing: 12, runSpacing: 12, alignment: WrapAlignment.center, children: [
              FilledButton.icon(onPressed: () => context.push('/servers/new'), icon: const Icon(Icons.add), label: const Text('Add server')),
              OutlinedButton.icon(onPressed: () => context.push('/servers/scan'), icon: const Icon(Icons.wifi_find), label: const Text('Scan network')),
            ]),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: Implement the router, app and `main`**

`lib/core/router.dart`:
```dart
import 'package:go_router/go_router.dart';

import '../features/dashboard/dashboard_screen.dart';

GoRouter createRouter() => GoRouter(
      routes: [
        GoRoute(path: '/', builder: (context, state) => const DashboardScreen()),
      ],
    );
```

`lib/app.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/providers.dart';
import 'core/router.dart';
import 'features/settings/settings_controller.dart';

class HuskConfigApp extends ConsumerStatefulWidget {
  const HuskConfigApp({super.key});

  @override
  ConsumerState<HuskConfigApp> createState() => _HuskConfigAppState();
}

class _HuskConfigAppState extends ConsumerState<HuskConfigApp> {
  late final GoRouter _router = createRouter();
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Polling and streams pause while the app is hidden; `inactive` (desktop
    // window unfocused) still counts as foreground.
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) => ref
          .read(appForegroundProvider.notifier)
          .set(state == AppLifecycleState.resumed || state == AppLifecycleState.inactive),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(settingsProvider.select((s) => s.themeMode));
    return MaterialApp.router(
      title: 'Husk Config',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      routerConfig: _router,
    );
  }
}

ThemeData _theme(Brightness brightness) => ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal, brightness: brightness),
      useMaterial3: true,
    );
```

`lib/main.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(ProviderScope(
    // Riverpod 3 retries failing providers by default; an offline phone
    // should show "Offline", not trigger a retry storm.
    retry: (_, _) => null,
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    child: const HuskConfigApp(),
  ));
}
```

- [ ] **Step 7: Run tests and analyze**

Run: `flutter test && flutter analyze`
Expected: `All tests passed!` and `No issues found!`

- [ ] **Step 8: Smoke-run against the test phone**

Run `flutter run -d macos`. The empty dashboard appears and the console shows no errors. Quit with `q`. (Adding the test phone comes in Task 14.)

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat: add app shell, router and live server dashboard

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_018vGW2sL6yV3eTZKrrtJar3"
```

---

### Task 14: Add/Edit server form and token request dialog

**Files:**
- Create: `lib/features/servers/server_form_screen.dart`, `lib/features/servers/token_request_dialog.dart`
- Modify: `lib/core/router.dart`, `lib/features/dashboard/server_card.dart`
- Test: `test/features/servers/server_form_screen_test.dart`, `test/features/servers/token_request_dialog_test.dart`

**Interfaces:**
- Consumes:
  - `IpValidator` (Task 3)
  - `HuskApi.healthz/info` (Tasks 5–6)
  - `TokenRequestFlow`, `TokenFlowState` subtypes (Task 10)
  - `serversProvider`, `serverByIdProvider`, `settingsProvider` (Task 12)
  - `confirm` (Task 13)
- Produces:
  - `class ServerFormScreen({String? serverId, String? initialHost, int? initialPort})`
  - `class TokenRequestDialog({required TokenRequestFlow flow})`: pops with the token `String` on approval, `null` otherwise
  - `Future<void> requestTokenForServer(BuildContext context, WidgetRef ref, String serverId)`
  - routes `/servers/new?host=&port=` and `/servers/:id/edit`
  - dashboard card menu item **Request token**

- [ ] **Step 1: Write failing tests**

`test/features/servers/server_form_screen_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:huskconfig/features/servers/server_form_screen.dart';

import '../../support/fixtures.dart';
import '../../support/memory_repos.dart';
import '../../support/test_app.dart';

void main() {
  late MemoryServerRepository repo;

  Future<void> pumpForm(WidgetTester tester, {String? serverId}) async {
    final router = GoRouter(initialLocation: '/form', routes: [
      GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('home'))),
      GoRoute(path: '/form', builder: (_, _) => ServerFormScreen(serverId: serverId)),
    ]);
    await tester.pumpWidget(testScope(serverRepo: repo, child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  setUp(() => repo = MemoryServerRepository());

  testWidgets('rejects a hostname', (tester) async {
    await pumpForm(tester);
    await tester.enterText(field('IP address'), 'phone.local');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Husk only accepts IP addresses (e.g. 192.168.0.106)'), findsOneWidget);
    expect(repo.saved, isEmpty);
  });

  testWidgets('rejects an invalid port', (tester) async {
    await pumpForm(tester);
    await tester.enterText(field('IP address'), '192.168.0.106');
    await tester.enterText(field('Port'), '70000');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Port must be 1–65535'), findsOneWidget);
  });

  testWidgets('saves a new server with a trimmed host and default port', (tester) async {
    await pumpForm(tester);
    await tester.enterText(field('Name'), 'Kitchen');
    await tester.enterText(field('IP address'), ' 192.168.0.106 ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(repo.saved.single.host, '192.168.0.106');
    expect(repo.saved.single.port, 8090);
    expect(repo.saved.single.name, 'Kitchen');
    expect(repo.saved.single.token, isNull);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('name defaults to the host when left empty', (tester) async {
    await pumpForm(tester);
    await tester.enterText(field('IP address'), '10.0.0.9');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(repo.saved.single.name, '10.0.0.9');
  });

  testWidgets('edit pre-fills the fields and keeps the id', (tester) async {
    repo = MemoryServerRepository([server1]);
    await pumpForm(tester, serverId: server1.id);
    expect(find.text('Edit server'), findsOneWidget);
    expect(find.text('192.168.0.106'), findsOneWidget);
    await tester.enterText(field('Name'), 'Renamed');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(repo.saved.single.id, server1.id);
    expect(repo.saved.single.name, 'Renamed');
  });

  testWidgets('a duplicate address asks before saving', (tester) async {
    repo = MemoryServerRepository([server1]);
    await pumpForm(tester);
    await tester.enterText(field('IP address'), '192.168.0.106');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Duplicate address'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repo.saved, hasLength(1));
  });
}
```

`test/features/servers/token_request_dialog_test.dart`:
```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/api/husk_exception.dart';
import 'package:huskconfig/core/api/models/tools_models.dart';
import 'package:huskconfig/core/api/token_request_flow.dart';
import 'package:huskconfig/features/servers/token_request_dialog.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/mocks.dart';

void main() {
  late MockHuskApi api;
  String? result;

  setUp(() {
    api = MockHuskApi();
    result = null;
    when(() => api.requestToken(client: any(named: 'client')))
        .thenAnswer((_) async => const TokenRequest(id: 'r', expiresIn: 120));
  });

  Future<void> open(WidgetTester tester, {Delay? delay}) async {
    final flow = TokenRequestFlow(api: api, clientName: 'Husk Config', delay: delay ?? (_) async {});
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await showDialog<String>(context: context, builder: (_) => TokenRequestDialog(flow: flow)),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('returns the token when approved', (tester) async {
    when(() => api.tokenStatus('r')).thenAnswer((_) async => const TokenStatus(state: TokenState.approved, token: 'tok'));
    await open(tester);
    expect(result, 'tok');
    expect(find.byType(TokenRequestDialog), findsNothing);
  });

  testWidgets('shows the approval prompt while pending and cancels cleanly', (tester) async {
    when(() => api.tokenStatus('r')).thenAnswer((_) async => const TokenStatus(state: TokenState.pending));
    await open(tester, delay: (_) => Completer<void>().future); // poll never fires
    expect(find.text('Approve the request on your phone.'), findsOneWidget);
    expect(find.textContaining('Expires in'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.byType(TokenRequestDialog), findsNothing);
  });

  testWidgets('explains a denial', (tester) async {
    when(() => api.tokenStatus('r')).thenAnswer((_) async => const TokenStatus(state: TokenState.denied));
    await open(tester);
    expect(find.text('The request was denied on the phone.'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
  });

  testWidgets('explains disabled notifications (503)', (tester) async {
    when(() => api.requestToken(client: any(named: 'client'))).thenThrow(HttpStatusException(503, ''));
    await open(tester);
    expect(find.textContaining('Notifications are disabled'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/servers`
Expected: FAIL, missing `server_form_screen.dart` / `token_request_dialog.dart`.

- [ ] **Step 3: Implement the token dialog**

`lib/features/servers/token_request_dialog.dart`:
```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/husk_api.dart';
import '../../core/api/token_request_flow.dart';
import '../settings/settings_controller.dart';
import 'servers_controller.dart';

/// Runs a [TokenRequestFlow]; pops with the token on approval.
class TokenRequestDialog extends StatefulWidget {
  const TokenRequestDialog({super.key, required this.flow});

  final TokenRequestFlow flow;

  @override
  State<TokenRequestDialog> createState() => _TokenRequestDialogState();
}

class _TokenRequestDialogState extends State<TokenRequestDialog> {
  late final StreamSubscription<TokenFlowState> _subscription;
  TokenFlowState _state = const TokenFlowRequesting();
  int? _initialSeconds;

  @override
  void initState() {
    super.initState();
    _subscription = widget.flow.run().listen((state) {
      if (!mounted) return;
      if (state is TokenFlowApproved) {
        Navigator.of(context).pop(state.token);
        return;
      }
      setState(() {
        _state = state;
        if (state is TokenFlowPending) _initialSeconds ??= state.secondsLeft;
      });
    });
  }

  @override
  void dispose() {
    widget.flow.cancel();
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Request access token'),
      content: SizedBox(
        width: 360,
        child: switch (_state) {
          TokenFlowRequesting() || TokenFlowApproved() => const Row(children: [
              SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 16),
              Expanded(child: Text('Sending the request to the phone…')),
            ]),
          TokenFlowPending(:final secondsLeft) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Approve the request on your phone.'),
                const SizedBox(height: 4),
                Text('Look for the notification "${widget.flow.clientName} asks for the access token".',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 16),
                LinearProgressIndicator(value: secondsLeft / (_initialSeconds ?? secondsLeft)),
                const SizedBox(height: 4),
                Text('Expires in ${secondsLeft}s'),
              ],
            ),
          TokenFlowDenied() => const Text('The request was denied on the phone.'),
          TokenFlowExpired() => const Text('The request expired before it was approved.'),
          TokenFlowFailed(:final message) => Text(message),
        },
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(_state.isTerminal ? 'Close' : 'Cancel')),
      ],
    );
  }
}

/// Requests a token for a saved server and stores it on approval.
/// /token/request is unauthenticated, so the current token is not sent.
Future<void> requestTokenForServer(BuildContext context, WidgetRef ref, String serverId) async {
  final server = ref.read(serverByIdProvider(serverId));
  if (server == null) return;
  final api = HuskApi(baseUrl: server.baseUrl);
  final token = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => TokenRequestDialog(
      flow: TokenRequestFlow(api: api, clientName: ref.read(settingsProvider).tokenClientName),
    ),
  );
  api.close();
  if (token == null) return;
  await ref.read(serversProvider.notifier).setToken(serverId, token);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Token saved.')));
  }
}
```

- [ ] **Step 4: Implement the form**

`lib/features/servers/server_form_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/husk_api.dart';
import '../../core/api/husk_exception.dart';
import '../../core/api/token_request_flow.dart';
import '../../core/net/ip_validator.dart';
import '../../core/storage/server_config.dart';
import '../../shared/widgets/confirm_dialog.dart';
import '../settings/settings_controller.dart';
import 'servers_controller.dart';
import 'token_request_dialog.dart';

class ServerFormScreen extends ConsumerStatefulWidget {
  const ServerFormScreen({super.key, this.serverId, this.initialHost, this.initialPort});

  final String? serverId;
  final String? initialHost;
  final int? initialPort;

  @override
  ConsumerState<ServerFormScreen> createState() => _ServerFormScreenState();
}

class _ServerFormScreenState extends ConsumerState<ServerFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _token;
  bool _showToken = false;
  bool _testing = false;
  bool _testOk = false;
  String? _testResult;
  String? _detectedName;

  ServerConfig? get _existing => widget.serverId == null ? null : ref.read(serversProvider.notifier).byId(widget.serverId!);

  @override
  void initState() {
    super.initState();
    final s = _existing;
    _name = TextEditingController(text: s?.name ?? '');
    _host = TextEditingController(text: s?.host ?? widget.initialHost ?? '');
    _port = TextEditingController(text: '${s?.port ?? widget.initialPort ?? ServerConfig.defaultPort}');
    _token = TextEditingController(text: s?.token ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _port.dispose();
    _token.dispose();
    super.dispose();
  }

  String? _validateHost(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return "Enter the phone's IP address";
    if (!IpValidator.isIpLiteral(text)) return 'Husk only accepts IP addresses (e.g. 192.168.0.106)';
    return null;
  }

  String? _validatePort(String? value) =>
      IpValidator.isValidPort(int.tryParse(value?.trim() ?? '')) ? null : 'Port must be 1–65535';

  String get _hostValue => IpValidator.normalizeHost(_host.text);
  int get _portValue => int.parse(_port.text.trim());

  /// A client for the address currently in the form, or null if it is invalid.
  HuskApi? _apiFromFields({required bool withToken}) {
    if (!(_formKey.currentState?.validate() ?? false)) return null;
    return HuskApi(baseUrl: IpValidator.baseUrl(_hostValue, _portValue), token: withToken ? _token.text.trim() : null);
  }

  Future<void> _test() async {
    final api = _apiFromFields(withToken: true);
    if (api == null) return;
    setState(() {
      _testing = true;
      _testResult = null;
    });
    String result;
    var ok = false;
    try {
      if (!await api.healthz()) throw const DeviceErrorException('This address answered, but it is not a Husk server.');
      final info = await api.info();
      _detectedName = info.displayName;
      result = 'Connected: ${info.displayName}, Android ${info.androidRelease}, Husk ${info.appVersionName}';
      ok = true;
    } on HuskException catch (e) {
      result = e.message;
    } finally {
      api.close();
    }
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testOk = ok;
      _testResult = result;
    });
  }

  Future<void> _requestToken() async {
    final api = _apiFromFields(withToken: false);
    if (api == null) return;
    final token = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => TokenRequestDialog(
        flow: TokenRequestFlow(api: api, clientName: ref.read(settingsProvider).tokenClientName),
      ),
    );
    api.close();
    if (token != null && mounted) setState(() => _token.text = token);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final host = _hostValue;
    final port = _portValue;
    final token = _token.text.trim();
    final controller = ref.read(serversProvider.notifier);
    if (controller.isDuplicate(host, port, exceptId: widget.serverId)) {
      final ok = await confirm(
        context,
        title: 'Duplicate address',
        message: 'A server with ${IpValidator.authority(host, port)} is already saved. Save anyway?',
        confirmLabel: 'Save anyway',
      );
      if (!ok) return;
    }
    final typedName = _name.text.trim();
    final name = typedName.isNotEmpty ? typedName : (_detectedName ?? host);
    final existing = _existing;
    if (existing == null) {
      await controller.add(name: name, host: host, port: port, token: token);
    } else {
      await controller.update(existing.copyWith(name: name, host: host, port: port, token: token, clearToken: token.isEmpty));
    }
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.serverId == null ? 'Add server' : 'Edit server')),
      body: Form(
        key: _formKey,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    helperText: 'Optional. Defaults to the phone model after a successful test.',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _host,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: 'IP address', hintText: '192.168.0.106'),
                  validator: _validateHost,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _port,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Port'),
                  validator: _validatePort,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _token,
                  obscureText: !_showToken,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'Token (optional)',
                    helperText: 'Only needed if a token is set on the phone.',
                    suffixIcon: IconButton(
                      tooltip: _showToken ? 'Hide token' : 'Show token',
                      icon: Icon(_showToken ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _showToken = !_showToken),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Wrap(spacing: 12, runSpacing: 12, children: [
                  OutlinedButton.icon(
                    onPressed: _testing ? null : _test,
                    icon: _testing
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.network_check),
                    label: const Text('Test connection'),
                  ),
                  OutlinedButton.icon(onPressed: _requestToken, icon: const Icon(Icons.key), label: const Text('Request token')),
                  FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save), label: const Text('Save')),
                ]),
                if (_testResult != null) ...[
                  const SizedBox(height: 16),
                  Text(_testResult!, style: TextStyle(color: _testOk ? scheme.primary : scheme.error)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Add routes and the card menu item**

`lib/core/router.dart`. Replace the file with:
```dart
import 'package:go_router/go_router.dart';

import '../features/dashboard/dashboard_screen.dart';
import '../features/servers/server_form_screen.dart';

GoRouter createRouter() => GoRouter(
      routes: [
        GoRoute(path: '/', builder: (context, state) => const DashboardScreen()),
        GoRoute(
          path: '/servers/new',
          builder: (context, state) => ServerFormScreen(
            initialHost: state.uri.queryParameters['host'],
            initialPort: int.tryParse(state.uri.queryParameters['port'] ?? ''),
          ),
        ),
        GoRoute(
          path: '/servers/:id/edit',
          builder: (context, state) => ServerFormScreen(serverId: state.pathParameters['id']),
        ),
      ],
    );
```

In `lib/features/dashboard/server_card.dart`:
- Add the import `import '../servers/token_request_dialog.dart';`.
- Change the enum to `enum _CardAction { edit, requestToken, delete }`.
- Add the menu item between Edit and Delete:
  ```dart
  PopupMenuItem(value: _CardAction.requestToken, child: Text('Request token')),
  ```
- Add this case to `_onAction`:
  ```dart
      case _CardAction.requestToken:
        await requestTokenForServer(context, ref, server.id);
  ```

- [ ] **Step 6: Run tests and analyze**

Run: `flutter test && flutter analyze`
Expected: `All tests passed!` and `No issues found!`

- [ ] **Step 7: Manual check against the test phone**

Run `flutter run -d macos`:
1. Click **Add server**.
2. Enter IP `192.168.0.106`.
3. Click **Test connection**. Expect `Connected: samsung SM-A750F, Android 10, Husk 1.4`.
4. Click **Save**. The dashboard card turns online with battery and service chips.

Do **not** click Request token against this phone. It has no token, so approving would set one (see Global Constraints).

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: add server form with connection test and token request dialog

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_018vGW2sL6yV3eTZKrrtJar3"
```

---

### Task 15: LAN scan screen

**Files:**
- Create: `lib/features/servers/scan_screen.dart`
- Modify: `lib/core/router.dart`
- Test: `test/features/servers/scan_screen_test.dart`

**Interfaces:**
- Consumes:
  - `LanScanner`, `ScanFound`, `ScanProgress` (Task 11)
  - `IpValidator` (Task 3)
  - `HuskApi.info` (Task 6)
  - `serversProvider` (Task 12)
- Produces:
  - `final lanScannerProvider = Provider<LanScanner>`
  - `final wifiIpProvider = FutureProvider.autoDispose<String?>`
  - `final scanDeviceNameProvider = FutureProvider.autoDispose.family<String, ({String host, int port})>`
  - `class ScanScreen`
  - route `/servers/scan`

- [ ] **Step 1: Write failing tests**

`test/features/servers/scan_screen_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/net/lan_scanner.dart';
import 'package:huskconfig/features/servers/scan_screen.dart';

import '../../support/fixtures.dart';
import '../../support/test_app.dart';

void main() {
  Future<void> pump(WidgetTester tester, {String? wifiIp}) async {
    await tester.pumpWidget(testScope(
      servers: [server1],
      overrides: [
        lanScannerProvider.overrideWithValue(LanScanner(probe: (host, port) async => host.endsWith('.106') || host.endsWith('.7'))),
        wifiIpProvider.overrideWith((ref) async => wifiIp),
        scanDeviceNameProvider.overrideWith((ref, target) async => 'samsung SM-A750F'),
      ],
      child: const MaterialApp(home: ScanScreen()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('prefills the subnet and lists found devices, marking saved ones', (tester) async {
    await pump(tester, wifiIp: '192.168.0.20');
    expect(find.widgetWithText(TextField, '192.168.0'), findsOneWidget);
    await tester.tap(find.text('Start scan'));
    await tester.pumpAndSettle();
    expect(find.text('192.168.0.106'), findsOneWidget);
    expect(find.text('192.168.0.7'), findsOneWidget);
    expect(find.text('samsung SM-A750F'), findsNWidgets(2));
    expect(find.text('Saved'), findsOneWidget);
    expect(find.text('Checked 253 of 253'), findsOneWidget);
  });

  testWidgets('without a Wi-Fi address asks for a subnet', (tester) async {
    await pump(tester);
    expect(find.textContaining('Could not detect'), findsOneWidget);
    await tester.tap(find.text('Start scan'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a subnet like 192.168.0 and a valid port.'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/servers/scan_screen_test.dart`
Expected: FAIL, missing `scan_screen.dart`.

- [ ] **Step 3: Implement**

`lib/features/servers/scan_screen.dart`:
```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:network_info_plus/network_info_plus.dart';

import '../../core/api/husk_api.dart';
import '../../core/api/husk_exception.dart';
import '../../core/net/ip_validator.dart';
import '../../core/net/lan_scanner.dart';
import '../../core/storage/server_config.dart';
import 'servers_controller.dart';

final lanScannerProvider = Provider<LanScanner>((ref) => LanScanner());

/// This device's Wi-Fi IPv4, or null when unavailable (desktop on ethernet, VPN only…).
final wifiIpProvider = FutureProvider.autoDispose<String?>((ref) async {
  try {
    return await NetworkInfo().getWifiIP();
  } catch (_) {
    return null; // Treated as "unknown"; the user types the subnet instead.
  }
});

/// Model name of a found device; works only when no token is required.
final scanDeviceNameProvider = FutureProvider.autoDispose.family<String, ({String host, int port})>((ref, target) async {
  final api = HuskApi(
    baseUrl: IpValidator.baseUrl(target.host, target.port),
    connectTimeout: const Duration(seconds: 2),
    receiveTimeout: const Duration(seconds: 3),
  );
  ref.onDispose(api.close);
  try {
    return (await api.info()).displayName;
  } on UnauthorizedException {
    return 'Token required';
  } on HuskException {
    return 'Husk device';
  }
});

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final _prefix = TextEditingController();
  final _port = TextEditingController(text: '${ServerConfig.defaultPort}');
  final _found = <String>[];
  StreamSubscription<ScanEvent>? _subscription;
  String? _ownIp;
  String? _error;
  bool _running = false;
  int _done = 0;
  int _total = 0;
  int _scanPort = ServerConfig.defaultPort;

  @override
  void initState() {
    super.initState();
    ref.listenManual(wifiIpProvider, (previous, next) {
      final ip = next.value;
      final prefix = LanScanner.prefixOf(ip);
      setState(() => _ownIp = ip);
      if (prefix != null && _prefix.text.isEmpty) _prefix.text = prefix;
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _prefix.dispose();
    _port.dispose();
    super.dispose();
  }

  void _start() {
    final prefix = _prefix.text.trim();
    final port = int.tryParse(_port.text.trim());
    if (!LanScanner.isValidPrefix(prefix) || !IpValidator.isValidPort(port)) {
      setState(() => _error = 'Enter a subnet like 192.168.0 and a valid port.');
      return;
    }
    _subscription?.cancel();
    setState(() {
      _found.clear();
      _done = 0;
      _total = 0;
      _error = null;
      _running = true;
      _scanPort = port!;
    });
    _subscription = ref.read(lanScannerProvider).scan(prefix: prefix, port: port!, excludeHost: _ownIp).listen(
      (event) => setState(() {
        switch (event) {
          case ScanFound(:final host):
            _found.add(host);
          case ScanProgress(:final done, :final total):
            _done = done;
            _total = total;
        }
      }),
      onDone: () {
        if (mounted) setState(() => _running = false);
      },
    );
  }

  void _stop() {
    _subscription?.cancel();
    setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Scan network')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('Looks for Husk on every address of a /24 subnet by calling /healthz.'),
              const SizedBox(height: 16),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: TextField(
                    controller: _prefix,
                    decoration: InputDecoration(
                      labelText: 'Subnet',
                      hintText: '192.168.0',
                      helperText: _ownIp == null
                          ? 'Could not detect a Wi-Fi address. Type your subnet.'
                          : 'This device: $_ownIp',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 110,
                  child: TextField(controller: _port, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Port')),
                ),
              ]),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: _running ? _stop : _start,
                  icon: Icon(_running ? Icons.stop : Icons.search),
                  label: Text(_running ? 'Stop' : 'Start scan'),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
              if (_total > 0) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(value: _done / _total),
                const SizedBox(height: 4),
                Text('Checked $_done of $_total', style: theme.textTheme.bodySmall),
              ],
              if (!_running && _total > 0 && _found.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Text('No Husk devices found. Check the subnet and port, and that Husk is running on the phone.'),
                ),
              for (final host in _found) _FoundTile(host: host, port: _scanPort),
            ],
          ),
        ),
      ),
    );
  }
}

class _FoundTile extends ConsumerWidget {
  const _FoundTile({required this.host, required this.port});

  final String host;
  final int port;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(scanDeviceNameProvider((host: host, port: port)));
    final saved = ref.watch(serversProvider).any((s) => s.host == host && s.port == port);
    return ListTile(
      leading: const Icon(Icons.phone_android),
      title: Text(host),
      subtitle: Text(name.value ?? 'Identifying…'),
      trailing: saved ? const Chip(label: Text('Saved')) : const Icon(Icons.chevron_right),
      onTap: () => context.push(Uri(path: '/servers/new', queryParameters: {'host': host, 'port': '$port'}).toString()),
    );
  }
}
```

- [ ] **Step 4: Add the route**

In `lib/core/router.dart`, add the import `import '../features/servers/scan_screen.dart';`, then add this route after the `/servers/new` route:
```dart
        GoRoute(path: '/servers/scan', builder: (context, state) => const ScanScreen()),
```

- [ ] **Step 5: Run tests and analyze**

Run: `flutter test && flutter analyze`
Expected: `All tests passed!` and `No issues found!`

- [ ] **Step 6: Manual check**

Run `flutter run -d macos`, open **Scan network**, check the subnet is `192.168.0`, and click **Start scan**. Expect `192.168.0.106` with `samsung SM-A750F` and a `Saved` chip if you saved it in Task 14.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: add LAN scan screen

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_018vGW2sL6yV3eTZKrrtJar3"
```

---

### Task 16: Settings screen

**Files:**
- Create: `lib/features/settings/settings_screen.dart`
- Modify: `lib/core/router.dart`
- Test: `test/features/settings/settings_screen_test.dart`

**Interfaces:**
- Consumes:
  - `settingsProvider`, `serversProvider` (Task 12)
  - `AppSettings.pollIntervalOptions`, `AppSettings.isValidClientName`, `ScreenMode` (Task 3)
  - `confirmDeleteServer` (Task 13)
- Produces:
  - `final appVersionProvider = FutureProvider<String>`
  - `class SettingsScreen`
  - route `/settings`

- [ ] **Step 1: Write failing tests**

`test/features/settings/settings_screen_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/storage/app_settings.dart';
import 'package:huskconfig/features/settings/settings_screen.dart';

import '../../support/fixtures.dart';
import '../../support/memory_repos.dart';
import '../../support/test_app.dart';

void main() {
  late MemorySettingsRepository repo;

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(testScope(
      servers: [server1],
      settingsRepo: repo,
      overrides: [appVersionProvider.overrideWith((ref) async => '1.0.0 (1)')],
      child: const MaterialApp(home: SettingsScreen()),
    ));
    await tester.pumpAndSettle();
  }

  setUp(() => repo = MemorySettingsRepository());

  testWidgets('theme selection is saved', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(repo.saved.themeMode, ThemeMode.dark);
  });

  testWidgets('polling interval can be turned off', (tester) async {
    await pump(tester);
    await tester.tap(find.text('10 s'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Off').last);
    await tester.pumpAndSettle();
    expect(repo.saved.pollIntervalSeconds, 0);
  });

  testWidgets('default screen mode is saved', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Web control'));
    await tester.pumpAndSettle();
    expect(repo.saved.defaultScreenMode, ScreenMode.webview);
  });

  testWidgets('invalid client names are rejected, valid ones saved', (tester) async {
    await pump(tester);
    final field = find.widgetWithText(TextFormField, 'Token client name');
    await tester.enterText(field, 'bad/name');
    await tester.pumpAndSettle();
    expect(find.text('Use letters, digits, space, dot, underscore or dash (max 32).'), findsOneWidget);
    expect(repo.saved.tokenClientName, 'Husk Config');
    await tester.enterText(field, 'My Mac');
    await tester.pumpAndSettle();
    expect(repo.saved.tokenClientName, 'My Mac');
  });

  testWidgets('lists servers and shows the app version', (tester) async {
    await pump(tester);
    expect(find.text('Kitchen phone'), findsOneWidget);
    expect(find.text('1.0.0 (1)'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/settings/settings_screen_test.dart`
Expected: FAIL, missing `settings_screen.dart`.

- [ ] **Step 3: Implement**

`lib/features/settings/settings_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/storage/app_settings.dart';
import '../servers/server_actions.dart';
import '../servers/servers_controller.dart';
import 'settings_controller.dart';

final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return '${info.version} (${info.buildNumber})';
});

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final servers = ref.watch(serversProvider);
    final controller = ref.read(settingsProvider.notifier);
    final version = ref.watch(appVersionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const _Header('Appearance'),
              SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(value: ThemeMode.system, label: Text('System'), icon: Icon(Icons.brightness_auto)),
                  ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode)),
                  ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode)),
                ],
                selected: {settings.themeMode},
                onSelectionChanged: (v) => controller.update((s) => s.copyWith(themeMode: v.first)),
              ),
              const _Header('Live status'),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Polling interval'),
                subtitle: const Text('How often the dashboard and status cards refresh while visible.'),
                trailing: DropdownButton<int>(
                  value: settings.pollIntervalSeconds,
                  items: [
                    for (final seconds in AppSettings.pollIntervalOptions)
                      DropdownMenuItem(value: seconds, child: Text(seconds == 0 ? 'Off' : '$seconds s')),
                  ],
                  onChanged: (v) {
                    if (v != null) controller.update((s) => s.copyWith(pollIntervalSeconds: v));
                  },
                ),
              ),
              const _Header('Screen view'),
              const Text('Default mode when opening the Screen tab.'),
              const SizedBox(height: 8),
              SegmentedButton<ScreenMode>(
                segments: const [
                  ButtonSegment(value: ScreenMode.mjpeg, label: Text('MJPEG')),
                  ButtonSegment(value: ScreenMode.h264, label: Text('H.264')),
                  ButtonSegment(value: ScreenMode.webview, label: Text('Web control')),
                ],
                selected: {settings.defaultScreenMode},
                onSelectionChanged: (v) => controller.update((s) => s.copyWith(defaultScreenMode: v.first)),
              ),
              const _Header('Access token'),
              _ClientNameField(
                initialValue: settings.tokenClientName,
                onValid: (name) => controller.update((s) => s.copyWith(tokenClientName: name)),
              ),
              const _Header('Servers'),
              for (final server in servers)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(server.name),
                  subtitle: Text(server.address),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit), onPressed: () => context.push('/servers/${server.id}/edit')),
                    IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete), onPressed: () => confirmDeleteServer(context, ref, server)),
                  ]),
                ),
              Wrap(spacing: 12, runSpacing: 8, children: [
                OutlinedButton.icon(onPressed: () => context.push('/servers/new'), icon: const Icon(Icons.add), label: const Text('Add server')),
                OutlinedButton.icon(onPressed: () => context.push('/servers/scan'), icon: const Icon(Icons.wifi_find), label: const Text('Scan network')),
              ]),
              const _Header('About'),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Husk Config'),
                subtitle: Text(version.value ?? '…'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}

class _ClientNameField extends StatelessWidget {
  const _ClientNameField({required this.initialValue, required this.onValid});

  final String initialValue;
  final ValueChanged<String> onValid;

  @override
  Widget build(BuildContext context) => TextFormField(
        initialValue: initialValue,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        decoration: const InputDecoration(
          labelText: 'Token client name',
          helperText: 'Shown in the approval notification on the phone.',
        ),
        validator: (v) => AppSettings.isValidClientName(v ?? '') ? null : 'Use letters, digits, space, dot, underscore or dash (max 32).',
        onChanged: (v) {
          if (AppSettings.isValidClientName(v)) onValid(v);
        },
      );
}
```

- [ ] **Step 4: Add the route**

In `lib/core/router.dart`, add the import `import '../features/settings/settings_screen.dart';` and this route:
```dart
        GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
```

- [ ] **Step 5: Run tests and analyze**

Run: `flutter test && flutter analyze`
Expected: `All tests passed!` and `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add settings screen

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_018vGW2sL6yV3eTZKrrtJar3"
```

---

### Task 17: Device shell and Overview tab (status & hardware)

**Files:**
- Create:
  - `lib/shared/widgets/section_card.dart`, `lib/shared/run_command.dart`
  - `lib/features/device/overview_providers.dart`, `lib/features/device/device_shell.dart`, `lib/features/device/overview_tab.dart`, `lib/features/device/status_cards.dart`, `lib/features/device/controls_card.dart`, `lib/features/device/sensors_card.dart`
  - `test/support/overview_stubs.dart`
- Modify: `lib/core/router.dart`
- Test: `test/features/device/overview_tab_test.dart`, `test/features/device/device_shell_test.dart`

**Interfaces:**
- Consumes:
  - `apiProvider`, `serversProvider`, `serverByIdProvider`, `pollIntervalProvider`, `pollEvery` (Task 12)
  - `serverStatusProvider`, `StatusDot`, `describeError` (Task 13)
  - all `HuskApi` getters and setters (Tasks 6–7)
  - `TextResult` (Task 5)
- Produces:
  - `class SectionCard({required String title, required Widget child, IconData? icon, Widget? trailing})`
  - `class AsyncSection<T>({required AsyncValue<T> value, required Widget Function(T) builder, VoidCallback? onRetry})`
  - `class InfoRow(String label, String value)`
  - `Future<TextResult?> runCommand(BuildContext context, Future<TextResult> Function() action, {String? success, String? Function(String reply)? hint})`
  - **Providers** (all autoDispose, family keyed by server id):
    - streams: `flagsProvider` (`Flags`), `batteryProvider` (`BatteryInfo`)
    - futures: `deviceInfoProvider`, `connectivityProvider`, `displayInfoProvider`, `locationProvider`, `volumeProvider`, `ringerProvider`, `brightnessProvider`, `sensorsProvider`, `displaysProvider`
  - `void refreshOverview(WidgetRef ref, String serverId)`
  - `enum DeviceTab { overview, camera, screen, tools }`
  - `class DeviceShell({required String serverId, required DeviceTab tab})`
  - `class OverviewTab(String serverId)`
  - `GoRouter createRouter({String initialLocation = '/'})`, plus route `/device/:id/:tab`
  - test helper `void stubOverview(MockHuskApi api)`

- [ ] **Step 1: Write the overview stubs used by several widget tests**

`test/support/overview_stubs.dart`:
```dart
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
```

- [ ] **Step 2: Write failing tests**

`test/features/device/overview_tab_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/storage/app_settings.dart';
import 'package:huskconfig/features/device/overview_tab.dart';
import 'package:huskconfig/features/servers/api_provider.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/fixtures.dart';
import '../../support/mocks.dart';
import '../../support/overview_stubs.dart';
import '../../support/test_app.dart';

void main() {
  late MockHuskApi api;

  setUp(() {
    api = MockHuskApi();
    stubOverview(api);
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(testScope(
      servers: [server1],
      settings: const AppSettings(pollIntervalSeconds: 0),
      overrides: [apiProvider.overrideWith((ref, id) => api)],
      child: const MaterialApp(home: Scaffold(body: OverviewTab(serverId: 's1'))),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('shows device, battery, connectivity and services', (tester) async {
    await pump(tester);
    expect(find.text('samsung SM-A750F'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('wifi'), findsOneWidget);
    expect(find.text('1080 × 2112'), findsWidgets);
    expect(find.text('Front'), findsOneWidget); // selected camera from /flags
  });

  testWidgets('a plain-text ERR from /location is shown, not a crash', (tester) async {
    await pump(tester);
    expect(find.textContaining('no-fix'), findsOneWidget);
  });

  testWidgets('wake and torch call the phone', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Wake screen'));
    await tester.pumpAndSettle();
    verify(() => api.wake()).called(1);
    expect(find.text('Screen woken for about 2 minutes'), findsOneWidget);
    await tester.tap(find.widgetWithText(SwitchListTile, 'Torch'));
    await tester.pumpAndSettle();
    verify(() => api.torch(on: true)).called(1);
  });
}
```

`test/features/device/device_shell_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/router.dart';
import 'package:huskconfig/core/storage/app_settings.dart';
import 'package:huskconfig/features/servers/api_provider.dart';

import '../../support/fixtures.dart';
import '../../support/mocks.dart';
import '../../support/overview_stubs.dart';
import '../../support/test_app.dart';

void main() {
  late MockHuskApi api;

  setUp(() {
    api = MockHuskApi();
    stubOverview(api);
  });

  Future<void> pump(WidgetTester tester, {required double width, String location = '/device/s1/overview'}) async {
    tester.view.physicalSize = Size(width, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(testScope(
      servers: [server1],
      settings: const AppSettings(pollIntervalSeconds: 0),
      overrides: [apiProvider.overrideWith((ref, id) => api)],
      child: MaterialApp.router(routerConfig: createRouter(initialLocation: location)),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('wide layout uses a navigation rail', (tester) async {
    await pump(tester, width: 1200);
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Kitchen phone'), findsWidgets);
  });

  testWidgets('narrow layout uses a bottom navigation bar', (tester) async {
    await pump(tester, width: 400);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('an unknown server id explains itself', (tester) async {
    await pump(tester, width: 800, location: '/device/nope/overview');
    expect(find.text('This server no longer exists.'), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `flutter test test/features/device`
Expected: FAIL, missing `overview_tab.dart`, `createRouter(initialLocation:)`, etc.

- [ ] **Step 4: Implement shared card widgets and `runCommand`**

`lib/shared/widgets/section_card.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../error_text.dart';

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.child, this.icon, this.trailing});

  final String title;
  final Widget child;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
                Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
                ?trailing,
              ]),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      );
}

/// Data (possibly stale while refreshing), an error line with Retry, or a loader.
class AsyncSection<T> extends StatelessWidget {
  const AsyncSection({super.key, required this.value, required this.builder, this.onRetry});

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final data = value.value;
    final error = value.error;
    if (data == null && error == null) {
      return const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: LinearProgressIndicator());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (data != null) builder(data),
        if (error != null)
          Row(children: [
            Expanded(child: Text(describeError(error), style: TextStyle(color: Theme.of(context).colorScheme.error))),
            if (onRetry != null) TextButton(onPressed: onRetry, child: const Text('Retry')),
          ]),
      ],
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 130,
            child: Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          Expanded(child: SelectableText(value)),
        ]),
      );
}
```
(`?trailing` is a Dart 3.8+ null-aware collection element; Dart 3.12 supports it.)

`lib/shared/run_command.dart`:
```dart
import 'package:flutter/material.dart';

import '../core/api/husk_exception.dart';
import '../core/api/text_result.dart';

/// Runs a device command and reports the outcome in a SnackBar. `ERR …`
/// replies and thrown errors use the error colour; [hint] may add advice for
/// a specific reply. Returns the reply, or null when the call failed.
Future<TextResult?> runCommand(
  BuildContext context,
  Future<TextResult> Function() action, {
  String? success,
  String? Function(String reply)? hint,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final errorColor = Theme.of(context).colorScheme.error;
  try {
    final result = await action();
    final extra = hint?.call(result.text);
    final text = result.isErr ? result.text : (success ?? (result.text.isEmpty ? 'Done' : result.text));
    messenger.showSnackBar(SnackBar(
      content: Text(extra == null ? text : '$text\n$extra'),
      backgroundColor: result.isErr ? errorColor : null,
    ));
    return result;
  } on HuskException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message), backgroundColor: errorColor));
    return null;
  }
}
```

- [ ] **Step 5: Implement the overview providers**

`lib/features/device/overview_providers.dart`:
```dart
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
```

- [ ] **Step 6: Implement the status cards**

`lib/features/device/status_cards.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/widgets/section_card.dart';
import 'overview_providers.dart';

String _yesNo(bool v) => v ? 'Yes' : 'No';
String _orDash(String? v) => v == null || v.isEmpty ? '—' : v;

class DeviceCard extends ConsumerWidget {
  const DeviceCard({super.key, required this.serverId});

  final String serverId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SectionCard(
        title: 'Device',
        icon: Icons.phone_android,
        child: AsyncSection(
          value: ref.watch(deviceInfoProvider(serverId)),
          onRetry: () => ref.invalidate(deviceInfoProvider(serverId)),
          builder: (i) => Column(children: [
            InfoRow('Model', i.displayName),
            InfoRow('Android', '${i.androidRelease} (SDK ${i.sdkInt ?? '?'})'),
            InfoRow('Husk', '${i.appVersionName} (${i.appVersionCode})'),
            InfoRow('Screen', '${i.screenWidth ?? '?'} × ${i.screenHeight ?? '?'}'),
            InfoRow('Local IP', _orDash(i.localIp)),
            InfoRow('Tailscale IP', _orDash(i.tailscaleIp)),
            InfoRow('Camera', _yesNo(i.hasCamera)),
            InfoRow('DeX capable', _yesNo(i.dexCapable)),
          ]),
        ),
      );
}

class ServicesCard extends ConsumerWidget {
  const ServicesCard({super.key, required this.serverId});

  final String serverId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SectionCard(
        title: 'Services',
        icon: Icons.miscellaneous_services,
        child: AsyncSection(
          value: ref.watch(flagsProvider(serverId)),
          onRetry: () => ref.invalidate(flagsProvider(serverId)),
          builder: (f) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 6, runSpacing: 6, children: [
              _FlagChip('Accessibility', f.a11y),
              _FlagChip('Camera active', f.camera),
              _FlagChip('Screen sharing', f.screen),
              _FlagChip('Motion alarm', f.motion),
              _FlagChip('ntfy topic set', f.ntfy),
              _FlagChip('Battery optimisation off', f.batteryOptIgnored),
              _FlagChip('DeX reconnect', f.dexReconnect),
            ]),
            const SizedBox(height: 8),
            InfoRow('Selected camera', f.front ? 'Front' : 'Back'),
            if (f.lastNtfy.isNotEmpty) InfoRow('Last push', f.lastNtfy),
            const SizedBox(height: 4),
            Text(
              'Camera inactive is normal: it starts on demand and closes a few seconds after the last viewer.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ]),
        ),
      );
}

class _FlagChip extends StatelessWidget {
  const _FlagChip(this.label, this.on);

  final String label;
  final bool on;

  @override
  Widget build(BuildContext context) => Chip(
        visualDensity: VisualDensity.compact,
        avatar: Icon(on ? Icons.check_circle : Icons.cancel_outlined, size: 18, color: on ? Colors.green : null),
        label: Text(label),
      );
}

class BatteryCard extends ConsumerWidget {
  const BatteryCard({super.key, required this.serverId});

  final String serverId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SectionCard(
        title: 'Battery',
        icon: Icons.battery_full,
        child: AsyncSection(
          value: ref.watch(batteryProvider(serverId)),
          onRetry: () => ref.invalidate(batteryProvider(serverId)),
          builder: (b) => Column(children: [
            InfoRow('Level', b.level == null ? '—' : '${b.level}%'),
            InfoRow('Charging', _yesNo(b.charging)),
            InfoRow('Status', _orDash(b.status)),
            InfoRow('Health', _orDash(b.health)),
            InfoRow('Plugged', _orDash(b.plugged)),
            InfoRow('Temperature', b.temperatureC == null ? '—' : '${b.temperatureC!.toStringAsFixed(1)} °C'),
            InfoRow('Voltage', b.voltageMv == null ? '—' : '${b.voltageMv} mV'),
            InfoRow('Technology', _orDash(b.technology)),
          ]),
        ),
      );
}

class ConnectivityCard extends ConsumerWidget {
  const ConnectivityCard({super.key, required this.serverId});

  final String serverId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SectionCard(
        title: 'Connectivity',
        icon: Icons.wifi,
        child: AsyncSection(
          value: ref.watch(connectivityProvider(serverId)),
          onRetry: () => ref.invalidate(connectivityProvider(serverId)),
          builder: (c) => Column(children: [
            InfoRow('Type', c.type),
            InfoRow('Connected', _yesNo(c.connected)),
            InfoRow('Metered', _yesNo(c.metered)),
            InfoRow('Validated', _yesNo(c.validated)),
          ]),
        ),
      );
}

class DisplayCard extends ConsumerWidget {
  const DisplayCard({super.key, required this.serverId});

  final String serverId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SectionCard(
        title: 'Display',
        icon: Icons.aspect_ratio,
        child: AsyncSection(
          value: ref.watch(displayInfoProvider(serverId)),
          onRetry: () => ref.invalidate(displayInfoProvider(serverId)),
          builder: (d) => Column(children: [
            InfoRow('Resolution', '${d.width} × ${d.height}'),
            InfoRow('Density', '${d.densityDpi ?? '?'} dpi (${d.density?.toStringAsFixed(2) ?? '?'}×)'),
            InfoRow('Refresh rate', d.refreshHz == null ? '—' : '${d.refreshHz!.toStringAsFixed(0)} Hz'),
            InfoRow('Rotation', '${d.rotation}'),
          ]),
        ),
      );
}

class LocationCard extends ConsumerWidget {
  const LocationCard({super.key, required this.serverId});

  final String serverId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SectionCard(
        title: 'Location',
        icon: Icons.place,
        child: AsyncSection(
          value: ref.watch(locationProvider(serverId)),
          onRetry: () => ref.invalidate(locationProvider(serverId)),
          builder: (l) {
            final lat = l.lat, lon = l.lon;
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              InfoRow('Position', lat == null || lon == null ? '—' : '${lat.toStringAsFixed(6)}, ${lon.toStringAsFixed(6)}'),
              InfoRow('Accuracy', l.accuracyM == null ? '—' : '±${l.accuracyM!.toStringAsFixed(0)} m'),
              InfoRow('Altitude', l.altitude == null ? '—' : '${l.altitude!.toStringAsFixed(0)} m'),
              InfoRow('Time', l.time == null ? '—' : l.time!.toLocal().toString().substring(0, 19)),
              InfoRow('Provider', _orDash(l.provider)),
              if (lat != null && lon != null)
                TextButton.icon(
                  onPressed: () => launchUrl(Uri.parse('https://maps.google.com/?q=$lat,$lon')),
                  icon: const Icon(Icons.map),
                  label: const Text('Open in maps'),
                ),
            ]);
          },
        ),
      );
}
```

- [ ] **Step 7: Implement the quick controls card**

`lib/features/device/controls_card.dart`:
```dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/run_command.dart';
import '../../shared/widgets/section_card.dart';
import '../servers/api_provider.dart';
import 'overview_providers.dart';

String? _brightnessHint(String reply) =>
    reply.contains('WRITE_SETTINGS') ? 'Allow "Modify system settings" for Husk on the phone.' : null;

class ControlsCard extends ConsumerStatefulWidget {
  const ControlsCard({super.key, required this.serverId});

  final String serverId;

  @override
  ConsumerState<ControlsCard> createState() => _ControlsCardState();
}

class _ControlsCardState extends ConsumerState<ControlsCard> {
  final _vibrateMs = TextEditingController(text: '300');
  bool _torchOn = false;
  double? _brightnessDrag;
  final Map<String, double> _volumeDrag = {};

  @override
  void dispose() {
    _vibrateMs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.serverId;
    final api = ref.watch(apiProvider(id));
    final label = Theme.of(context).textTheme.labelLarge;

    return SectionCard(
      title: 'Quick controls',
      icon: Icons.tune,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Torch'),
          value: _torchOn,
          onChanged: (on) async {
            final result = await runCommand(context, () => api.torch(on: on));
            if (mounted && result != null && !result.isErr) setState(() => _torchOn = on);
          },
        ),
        Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(
            width: 120,
            child: TextField(
              controller: _vibrateMs,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Vibrate (ms)', isDense: true),
            ),
          ),
          OutlinedButton.icon(
            onPressed: () {
              final ms = (int.tryParse(_vibrateMs.text.trim()) ?? 300).clamp(1, 10000);
              runCommand(context, () => api.vibrate(ms: ms));
            },
            icon: const Icon(Icons.vibration),
            label: const Text('Vibrate'),
          ),
          OutlinedButton.icon(
            onPressed: () => runCommand(context, api.wake, success: 'Screen woken for about 2 minutes'),
            icon: const Icon(Icons.light_mode),
            label: const Text('Wake screen'),
          ),
        ]),
        const Divider(height: 32),
        Text('Brightness', style: label),
        AsyncSection(
          value: ref.watch(brightnessProvider(id)),
          onRetry: () => ref.invalidate(brightnessProvider(id)),
          builder: (b) {
            final max = math.max(b.max, 1).toDouble();
            final value = (_brightnessDrag ?? b.level.toDouble()).clamp(0.0, max);
            return Row(children: [
              Expanded(
                child: Slider(
                  value: value,
                  max: max,
                  divisions: max.toInt(),
                  label: '${value.round()}',
                  onChanged: (v) => setState(() => _brightnessDrag = v),
                  onChangeEnd: (v) async {
                    await runCommand(context, () => api.setBrightness(v.round()), hint: _brightnessHint);
                    if (!mounted) return;
                    setState(() => _brightnessDrag = null);
                    ref.invalidate(brightnessProvider(id));
                  },
                ),
              ),
              if (b.auto) const Chip(label: Text('Auto'), visualDensity: VisualDensity.compact),
            ]);
          },
        ),
        const SizedBox(height: 8),
        Text('Ringer', style: label),
        const SizedBox(height: 4),
        AsyncSection(
          value: ref.watch(ringerProvider(id)),
          onRetry: () => ref.invalidate(ringerProvider(id)),
          builder: (mode) => SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'normal', label: Text('Normal')),
              ButtonSegment(value: 'vibrate', label: Text('Vibrate')),
              ButtonSegment(value: 'silent', label: Text('Silent')),
            ],
            selected: {if (const {'normal', 'vibrate', 'silent'}.contains(mode)) mode},
            emptySelectionAllowed: true,
            onSelectionChanged: (v) async {
              if (v.isEmpty) return;
              await runCommand(context, () => api.setRinger(v.first));
              if (mounted) ref.invalidate(ringerProvider(id));
            },
          ),
        ),
        Text('Silent and vibrate may need Do Not Disturb access for Husk on the phone.',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        Text('Volume', style: label),
        AsyncSection(
          value: ref.watch(volumeProvider(id)),
          onRetry: () => ref.invalidate(volumeProvider(id)),
          builder: (streams) => Column(children: [
            for (final MapEntry(key: stream, value: level) in streams.entries)
              Row(children: [
                SizedBox(width: 100, child: Text(stream)),
                Expanded(
                  child: Slider(
                    value: (_volumeDrag[stream] ?? level.level.toDouble()).clamp(0.0, math.max(level.max, 1).toDouble()),
                    max: math.max(level.max, 1).toDouble(),
                    divisions: math.max(level.max, 1),
                    onChanged: (v) => setState(() => _volumeDrag[stream] = v),
                    onChangeEnd: (v) async {
                      await runCommand(context, () => api.setVolume(stream, v.round()));
                      if (!mounted) return;
                      setState(() => _volumeDrag.remove(stream));
                      ref.invalidate(volumeProvider(id));
                    },
                  ),
                ),
                SizedBox(width: 48, child: Text('${(_volumeDrag[stream] ?? level.level).round()}/${level.max}')),
              ]),
          ]),
        ),
      ]),
    );
  }
}
```

- [ ] **Step 8: Implement the sensors and mic cards**

`lib/features/device/sensors_card.dart`:
```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/husk_api.dart';
import '../../core/api/husk_exception.dart';
import '../../core/api/models/hardware_models.dart';
import '../../shared/widgets/section_card.dart';
import '../servers/api_provider.dart';
import 'overview_providers.dart';

class SensorsCard extends ConsumerStatefulWidget {
  const SensorsCard({super.key, required this.serverId});

  final String serverId;

  @override
  ConsumerState<SensorsCard> createState() => _SensorsCardState();
}

class _SensorsCardState extends ConsumerState<SensorsCard> {
  String? _type;
  SensorReading? _reading;
  String? _error;
  bool _live = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _read(HuskApi api, String type) async {
    try {
      final reading = await api.sensor(type);
      if (mounted && type == _type) setState(() => (_reading, _error) = (reading, null));
    } on HuskException catch (e) {
      if (mounted && type == _type) setState(() => (_reading, _error) = (null, e.message));
    }
  }

  void _select(HuskApi api, String type) {
    setState(() => (_type, _reading, _error) = (type, null, null));
    _read(api, type);
  }

  void _setLive(HuskApi api, bool live) {
    _timer?.cancel();
    setState(() => _live = live);
    final type = _type;
    if (live && type != null) _timer = Timer.periodic(const Duration(seconds: 1), (_) => _read(api, _type ?? type));
  }

  @override
  Widget build(BuildContext context) {
    final api = ref.watch(apiProvider(widget.serverId));
    final reading = _reading;
    return SectionCard(
      title: 'Sensors',
      icon: Icons.sensors,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final type in sensorTypes)
            ChoiceChip(label: Text(type), selected: _type == type, onSelected: (_) => _select(api, type)),
        ]),
        if (_type != null) ...[
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: Text(reading != null
                  ? '${reading.sensor}: ${reading.values.map((v) => v.toStringAsFixed(2)).join(', ')}'
                  : (_error ?? 'Reading…')),
            ),
            const Text('Live'),
            Switch(value: _live, onChanged: (v) => _setLive(api, v)),
          ]),
        ],
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('All sensors'),
          children: [
            AsyncSection(
              value: ref.watch(sensorsProvider(widget.serverId)),
              onRetry: () => ref.invalidate(sensorsProvider(widget.serverId)),
              builder: (list) => Column(children: [
                for (final s in list)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(s.name),
                    subtitle: Text('${s.vendor} · type ${s.type ?? '?'} · ${s.power ?? '?'} mA · max ${s.max ?? '?'}'),
                  ),
              ]),
            ),
          ],
        ),
      ]),
    );
  }
}

class MicCard extends ConsumerStatefulWidget {
  const MicCard({super.key, required this.serverId});

  final String serverId;

  @override
  ConsumerState<MicCard> createState() => _MicCardState();
}

class _MicCardState extends ConsumerState<MicCard> {
  MicLevel? _level;
  String? _error;
  bool _live = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _sample(HuskApi api) async {
    try {
      final level = await api.mic();
      if (mounted) setState(() => (_level, _error) = (level, null));
    } on HuskException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _setLive(HuskApi api, bool live) {
    _timer?.cancel();
    setState(() => _live = live);
    if (live) _timer = Timer.periodic(const Duration(seconds: 1), (_) => _sample(api));
  }

  @override
  Widget build(BuildContext context) {
    final api = ref.watch(apiProvider(widget.serverId));
    final level = _level;
    return SectionCard(
      title: 'Microphone level',
      icon: Icons.mic,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        const Text('Live'),
        Switch(value: _live, onChanged: (v) => _setLive(api, v)),
      ]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        LinearProgressIndicator(value: level?.fraction ?? 0),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Text(_error ?? (level == null ? 'No sample yet. Audio is never recorded.' : '${level.amplitude} / ${level.max}'))),
          OutlinedButton(onPressed: () => _sample(api), child: const Text('Sample')),
        ]),
      ]),
    );
  }
}
```

- [ ] **Step 9: Implement the overview tab and the device shell**

`lib/features/device/overview_tab.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'controls_card.dart';
import 'overview_providers.dart';
import 'sensors_card.dart';
import 'status_cards.dart';

class OverviewTab extends ConsumerWidget {
  const OverviewTab({super.key, required this.serverId});

  final String serverId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = <Widget>[
      DeviceCard(serverId: serverId),
      ServicesCard(serverId: serverId),
      ControlsCard(serverId: serverId),
      BatteryCard(serverId: serverId),
      ConnectivityCard(serverId: serverId),
      DisplayCard(serverId: serverId),
      LocationCard(serverId: serverId),
      SensorsCard(serverId: serverId),
      MicCard(serverId: serverId),
    ];
    return RefreshIndicator(
      onRefresh: () async => refreshOverview(ref, serverId),
      child: LayoutBuilder(builder: (context, constraints) {
        const gap = 12.0, padding = 16.0;
        final columns = (constraints.maxWidth / 420).floor().clamp(1, 3);
        final width = (constraints.maxWidth - padding * 2 - gap * (columns - 1)) / columns;
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(padding),
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            TextButton.icon(
              onPressed: () => refreshOverview(ref, serverId),
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
            Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [for (final card in cards) SizedBox(width: width, child: card)],
            ),
          ]),
        );
      }),
    );
  }
}
```

`lib/features/device/device_shell.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets/status_dot.dart';
import '../dashboard/server_status.dart';
import '../servers/servers_controller.dart';
import 'overview_tab.dart';

enum DeviceTab { overview, camera, screen, tools }

class DeviceShell extends ConsumerStatefulWidget {
  const DeviceShell({super.key, required this.serverId, required this.tab});

  static DeviceTab parseTab(String? name) => DeviceTab.values.asNameMap()[name] ?? DeviceTab.overview;

  final String serverId;
  final DeviceTab tab;

  @override
  ConsumerState<DeviceShell> createState() => _DeviceShellState();
}

class _DeviceShellState extends ConsumerState<DeviceShell> {
  static const _destinations = [
    (DeviceTab.overview, 'Overview', Icons.dashboard_outlined),
    (DeviceTab.camera, 'Camera', Icons.videocam_outlined),
    (DeviceTab.screen, 'Screen', Icons.smartphone),
    (DeviceTab.tools, 'Tools', Icons.build_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _touch();
  }

  @override
  void didUpdateWidget(DeviceShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.serverId != widget.serverId) _touch();
  }

  void _touch() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(serversProvider.notifier).touch(widget.serverId);
      });

  void _go(int index) => context.go('/device/${widget.serverId}/${DeviceTab.values[index].name}');

  Widget _body() => switch (widget.tab) {
        DeviceTab.overview => OverviewTab(serverId: widget.serverId),
        DeviceTab.camera => const _TabPlaceholder('Camera'),
        DeviceTab.screen => const _TabPlaceholder('Screen'),
        DeviceTab.tools => const _TabPlaceholder('Tools'),
      };

  @override
  Widget build(BuildContext context) {
    final server = ref.watch(serverByIdProvider(widget.serverId));
    if (server == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('This server no longer exists.'),
            TextButton(onPressed: () => context.go('/'), child: const Text('Back to dashboard')),
          ]),
        ),
      );
    }
    final servers = ref.watch(serversProvider);
    final status = ref.watch(serverStatusProvider(server.id));
    final dot = status.value?.dot ?? (status.hasError ? DotState.offline : DotState.unknown);
    final wide = MediaQuery.sizeOf(context).width >= 600;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(tooltip: 'All servers', icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/')),
        title: Row(children: [
          StatusDot(dot),
          const SizedBox(width: 8),
          Flexible(
            child: DropdownButton<String>(
              value: server.id,
              underline: const SizedBox.shrink(),
              isExpanded: true,
              items: [
                for (final s in servers)
                  DropdownMenuItem(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (id) {
                if (id != null) context.go('/device/$id/${widget.tab.name}');
              },
            ),
          ),
        ]),
      ),
      body: wide
          ? Row(children: [
              NavigationRail(
                selectedIndex: widget.tab.index,
                labelType: NavigationRailLabelType.all,
                onDestinationSelected: _go,
                destinations: [
                  for (final (_, label, icon) in _destinations) NavigationRailDestination(icon: Icon(icon), label: Text(label)),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: _body()),
            ])
          : _body(),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: widget.tab.index,
              onDestinationSelected: _go,
              destinations: [
                for (final (_, label, icon) in _destinations) NavigationDestination(icon: Icon(icon), label: label),
              ],
            ),
    );
  }
}

/// Stand-in for tabs implemented in Tasks 18, 19 and 21.
class _TabPlaceholder extends StatelessWidget {
  const _TabPlaceholder(this.name);

  final String name;

  @override
  Widget build(BuildContext context) => Center(child: Text('$name is not available yet.'));
}
```

- [ ] **Step 10: Add the device route and the `initialLocation` parameter**

In `lib/core/router.dart`:
- Add the import `import '../features/device/device_shell.dart';`.
- Change the signature to `GoRouter createRouter({String initialLocation = '/'}) => GoRouter(`.
- Add `initialLocation: initialLocation,` as the first argument of `GoRouter(`.
- Add this route:
  ```dart
          GoRoute(
            path: '/device/:id/:tab',
            builder: (context, state) => DeviceShell(
              serverId: state.pathParameters['id']!,
              tab: DeviceShell.parseTab(state.pathParameters['tab']),
            ),
          ),
  ```

- [ ] **Step 11: Run tests and analyze**

Run: `flutter test && flutter analyze`
Expected: `All tests passed!` and `No issues found!`

- [ ] **Step 12: Manual check against the test phone**

Run `flutter run -d macos` and open the saved phone. The Overview shows:
- Device: `samsung SM-A750F`, Android 10, Husk 1.4
- Services chips
- Battery with real values
- Location: the `ERR no-fix …` message (or a position, if the phone has a fix)

Test the controls:
- **Wake screen** makes the phone's screen turn on.
- **Vibrate** with 300 makes the phone vibrate.
- Moving the brightness slider changes brightness, or shows the WRITE_SETTINGS hint.

Do not flip the ringer away from what the user had without asking. If you test it, restore `silent` afterwards; that was the phone's mode on 2026-10-07.

- [ ] **Step 13: Commit**

```bash
git add -A
git commit -m "feat: add device shell and overview with status and hardware controls

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_018vGW2sL6yV3eTZKrrtJar3"
```

---

### Task 18: MJPEG view and Camera tab

**Files:**
- Create: `lib/shared/widgets/mjpeg_view.dart`, `lib/shared/save_image.dart`, `lib/features/camera/snapshot.dart`, `lib/features/camera/camera_tab.dart`
- Modify: `lib/features/device/device_shell.dart`
- Test: `test/features/camera/snapshot_test.dart`, `test/shared/mjpeg_view_test.dart`, `test/features/camera/camera_tab_test.dart`

**Interfaces:**
- Consumes:
  - `HuskApi.openMultipart`, `snapshot`, `setCamera` (Tasks 5, 7)
  - `MjpegParser` (Task 8)
  - `appForegroundProvider`, `apiProvider` (Task 12)
  - `flagsProvider` (Task 17)
  - `describeError` (Task 13)
- Produces:
  - `class MjpegView({required HuskApi api, required String path, BoxFit fit = BoxFit.contain, bool showFps = true})`
  - `Future<void> saveImage(BuildContext context, Uint8List bytes, String fileName)`
  - `Future<Uint8List> fetchWithWarmup(Future<Uint8List> Function() fetch, {Duration wait = const Duration(seconds: 1)})`
  - `class CameraTab(String serverId)`

- [ ] **Step 1: Write failing tests**

`test/features/camera/snapshot_test.dart`:
```dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/api/husk_exception.dart';
import 'package:huskconfig/features/camera/snapshot.dart';

void main() {
  final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]);

  test('retries once after a 503 while the lazy camera wakes up', () async {
    var calls = 0;
    final bytes = await fetchWithWarmup(() async {
      if (++calls == 1) throw HttpStatusException(503, 'no frame yet');
      return jpeg;
    }, wait: Duration.zero);
    expect(bytes, jpeg);
    expect(calls, 2);
  });

  test('does not retry other errors', () async {
    var calls = 0;
    await expectLater(
      fetchWithWarmup(() async {
        calls++;
        throw HttpStatusException(500, 'boom');
      }, wait: Duration.zero),
      throwsA(isA<HttpStatusException>()),
    );
    expect(calls, 1);
  });

  test('gives up after the second 503', () async {
    await expectLater(
      fetchWithWarmup(() async => throw HttpStatusException(503, ''), wait: Duration.zero),
      throwsA(isA<HttpStatusException>().having((e) => e.statusCode, 'statusCode', 503)),
    );
  });
}
```

`test/shared/mjpeg_view_test.dart`:
```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/api/husk_exception.dart';
import 'package:huskconfig/shared/widgets/mjpeg_view.dart';
import 'package:mocktail/mocktail.dart';

import '../support/mocks.dart';

void main() {
  late MockHuskApi api;

  setUpAll(() => registerFallbackValue(CancelToken()));
  setUp(() => api = MockHuskApi());

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(ProviderScope(
        retry: (_, _) => null,
        child: MaterialApp(home: MjpegView(api: api, path: '/stream')),
      ));

  testWidgets('shows Connecting while waiting for the first frame', (tester) async {
    when(() => api.openMultipart('/stream', cancelToken: any(named: 'cancelToken'))).thenAnswer((_) async =>
        (contentType: 'multipart/x-mixed-replace; boundary=rigframe', stream: StreamController<Uint8List>().stream));
    await pump(tester);
    await tester.pump();
    expect(find.text('Connecting…'), findsOneWidget);
  });

  testWidgets('a failed connection schedules a reconnect with backoff', (tester) async {
    when(() => api.openMultipart('/stream', cancelToken: any(named: 'cancelToken')))
        .thenThrow(const OfflineException("Can't reach 10.0.0.5:8090"));
    await pump(tester);
    await tester.pump();
    expect(find.text("Can't reach 10.0.0.5:8090. Reconnecting in 1s…"), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    verify(() => api.openMultipart('/stream', cancelToken: any(named: 'cancelToken'))).called(2);
    expect(find.text("Can't reach 10.0.0.5:8090. Reconnecting in 2s…"), findsOneWidget);
  });
}
```

`test/features/camera/camera_tab_test.dart`:
```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/api/husk_exception.dart';
import 'package:huskconfig/core/api/text_result.dart';
import 'package:huskconfig/core/storage/app_settings.dart';
import 'package:huskconfig/features/camera/camera_tab.dart';
import 'package:huskconfig/features/servers/api_provider.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/fixtures.dart';
import '../../support/mocks.dart';
import '../../support/overview_stubs.dart';
import '../../support/test_app.dart';

void main() {
  late MockHuskApi api;

  setUpAll(() => registerFallbackValue(CancelToken()));

  setUp(() {
    api = MockHuskApi();
    stubOverview(api);
    when(() => api.openMultipart(any(), cancelToken: any(named: 'cancelToken'))).thenAnswer((_) async =>
        (contentType: 'multipart/x-mixed-replace; boundary=rigframe', stream: StreamController<Uint8List>().stream));
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(testScope(
      servers: [server1],
      settings: const AppSettings(pollIntervalSeconds: 0),
      overrides: [apiProvider.overrideWith((ref, id) => api)],
      child: const MaterialApp(home: Scaffold(body: CameraTab(serverId: 's1'))),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('switching side sends /set?front=0', (tester) async {
    when(() => api.setCamera(front: false)).thenAnswer((_) async => const TextResult('ok'));
    await pump(tester);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    verify(() => api.setCamera(front: false)).called(1);
  });

  testWidgets('a 409 explains the camera side does not exist', (tester) async {
    when(() => api.setCamera(front: false)).thenThrow(HttpStatusException(409, 'no such camera'));
    await pump(tester);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('This camera side does not exist on the device.'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/camera test/shared`
Expected: FAIL, missing files.

- [ ] **Step 3: Implement `fetchWithWarmup` and `saveImage`**

`lib/features/camera/snapshot.dart`:
```dart
import 'dart:typed_data';

import '../../core/api/husk_exception.dart';

/// The lazy camera answers 503 until it has a frame; the first call wakes it,
/// so one retry after [wait] is enough.
Future<Uint8List> fetchWithWarmup(Future<Uint8List> Function() fetch, {Duration wait = const Duration(seconds: 1)}) async {
  try {
    return await fetch();
  } on HttpStatusException catch (e) {
    if (e.statusCode != 503) rethrow;
    await Future<void>.delayed(wait);
    return fetch();
  }
}
```

`lib/shared/save_image.dart`:
```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

/// Desktop: native save dialog. Mobile: share sheet (Save to Photos/Files…).
Future<void> saveImage(BuildContext context, Uint8List bytes, String fileName) async {
  final messenger = ScaffoldMessenger.of(context);
  final box = context.findRenderObject() as RenderBox?;
  final file = XFile.fromData(bytes, mimeType: 'image/jpeg', name: fileName);
  try {
    if (Platform.isAndroid || Platform.isIOS) {
      await SharePlus.instance.share(ShareParams(
        files: [file],
        // Required on iPad, where the share sheet is a popover.
        sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      ));
      return;
    }
    final location = await getSaveLocation(
      suggestedName: fileName,
      acceptedTypeGroups: const [XTypeGroup(label: 'JPEG image', extensions: ['jpg', 'jpeg'])],
    );
    if (location == null) return;
    await file.saveTo(location.path);
    messenger.showSnackBar(SnackBar(content: Text('Saved to ${location.path}')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Could not save the image: $e')));
  }
}
```

- [ ] **Step 4: Implement `MjpegView`**

`lib/shared/widgets/mjpeg_view.dart`:
```dart
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/husk_api.dart';
import '../../core/api/husk_exception.dart';
import '../../core/providers.dart';
import '../../core/stream/mjpeg_stream.dart';

/// Plays a Husk MJPEG stream (/stream or /screen). Reconnects with backoff
/// (1, 2, 4, 8, 10 s), drops frames that arrive while one is still decoding,
/// and disconnects while the app is in the background or the widget is gone.
class MjpegView extends ConsumerStatefulWidget {
  const MjpegView({super.key, required this.api, required this.path, this.fit = BoxFit.contain, this.showFps = true});

  final HuskApi api;
  final String path;
  final BoxFit fit;
  final bool showFps;

  @override
  ConsumerState<MjpegView> createState() => _MjpegViewState();
}

class _MjpegViewState extends ConsumerState<MjpegView> {
  ui.Image? _image;
  StreamSubscription<Uint8List>? _subscription;
  CancelToken? _cancelToken;
  Timer? _retryTimer;
  Timer? _fpsTimer;
  int _attempt = 0;
  int _generation = 0;
  String? _status = 'Connecting…';
  bool _decoding = false;
  Uint8List? _pending;
  int _framesThisSecond = 0;
  int _fps = 0;

  @override
  void initState() {
    super.initState();
    _connect();
    if (widget.showFps) {
      _fpsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        final fps = _framesThisSecond;
        _framesThisSecond = 0;
        if (mounted && fps != _fps) setState(() => _fps = fps);
      });
    }
  }

  @override
  void didUpdateWidget(MjpegView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api != widget.api || oldWidget.path != widget.path) {
      _disconnect();
      _attempt = 0;
      _connect();
    }
  }

  @override
  void dispose() {
    _disconnect();
    _fpsTimer?.cancel();
    _image?.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final generation = ++_generation;
    _cancelToken = CancelToken();
    try {
      final response = await widget.api.openMultipart(widget.path, cancelToken: _cancelToken);
      if (!mounted || generation != _generation) return;
      final boundary = MjpegParser.boundaryFrom(response.contentType);
      if (boundary == null) throw const DeviceErrorException('The phone did not send an MJPEG stream');
      _subscription = response.stream.transform(MjpegParser(boundary)).listen(
            (frame) => _onFrame(frame, generation),
            onError: (Object _) => _scheduleReconnect(generation, 'Connection lost'),
            onDone: () => _scheduleReconnect(generation, 'Stream ended'),
            cancelOnError: true,
          );
    } on HuskException catch (e) {
      _scheduleReconnect(generation, e.message);
    }
  }

  void _disconnect() {
    _generation++;
    _retryTimer?.cancel();
    _subscription?.cancel();
    _subscription = null;
    _cancelToken?.cancel();
    _cancelToken = null;
  }

  void _scheduleReconnect(int generation, String reason) {
    if (!mounted || generation != _generation) return;
    _subscription?.cancel();
    _subscription = null;
    final seconds = math.min(10, 1 << math.min(_attempt, 4));
    _attempt++;
    setState(() => _status = '$reason. Reconnecting in ${seconds}s…');
    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(seconds: seconds), () {
      if (mounted && generation == _generation) _connect();
    });
  }

  void _onFrame(Uint8List bytes, int generation) {
    if (generation != _generation) return;
    _attempt = 0;
    _framesThisSecond++;
    if (_decoding) {
      _pending = bytes; // Keep only the newest frame while decoding.
      return;
    }
    _decode(bytes);
  }

  Future<void> _decode(Uint8List bytes) async {
    _decoding = true;
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      final old = _image;
      setState(() {
        _image = frame.image;
        _status = null;
      });
      old?.dispose();
    } catch (_) {
      // A corrupt frame is skipped; the next one replaces it.
    } finally {
      _decoding = false;
      final next = _pending;
      _pending = null;
      if (next != null && mounted) _decode(next);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(appForegroundProvider, (previous, foreground) {
      if (foreground) {
        _attempt = 0;
        _disconnect();
        _connect();
        setState(() => _status = 'Connecting…');
      } else {
        _disconnect();
        setState(() => _status = 'Paused');
      }
    });
    final status = _status;
    return ColoredBox(
      color: Colors.black,
      child: Stack(fit: StackFit.expand, children: [
        if (_image != null) RawImage(image: _image, fit: widget.fit),
        if (status != null)
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
              child: Text(status, style: const TextStyle(color: Colors.white)),
            ),
          ),
        if (widget.showFps && _image != null)
          Positioned(
            left: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              color: Colors.black54,
              child: Text('$_fps fps', style: const TextStyle(color: Colors.white, fontSize: 11)),
            ),
          ),
      ]),
    );
  }
}
```

- [ ] **Step 5: Implement the Camera tab**

`lib/features/camera/camera_tab.dart`:
```dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/husk_api.dart';
import '../../core/api/husk_exception.dart';
import '../../shared/save_image.dart';
import '../../shared/widgets/mjpeg_view.dart';
import '../device/overview_providers.dart';
import '../servers/api_provider.dart';
import 'snapshot.dart';

class CameraTab extends ConsumerStatefulWidget {
  const CameraTab({super.key, required this.serverId});

  final String serverId;

  @override
  ConsumerState<CameraTab> createState() => _CameraTabState();
}

class _CameraTabState extends ConsumerState<CameraTab> {
  int? _rotation;
  bool _flip = false;
  int? _fps;
  bool _busy = false;

  void _snack(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    ));
  }

  Future<void> _setCamera(HuskApi api, {bool? front, int? rotation, bool? flip, int? fps}) async {
    try {
      final result = await api.setCamera(front: front, rotation: rotation, flip: flip, fps: fps);
      if (result.isErr) _snack(result.text, error: true);
    } on HttpStatusException catch (e) {
      _snack(e.statusCode == 409 ? 'This camera side does not exist on the device.' : e.message, error: true);
    } on HuskException catch (e) {
      _snack(e.message, error: true);
    }
    if (mounted) ref.invalidate(flagsProvider(widget.serverId));
  }

  Future<void> _snapshot(HuskApi api) async {
    setState(() => _busy = true);
    try {
      final bytes = await fetchWithWarmup(api.snapshot);
      if (mounted) await _showSnapshot(bytes);
    } on HuskException catch (e) {
      _snack(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showSnapshot(Uint8List bytes) => showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Flexible(child: InteractiveViewer(child: Image.memory(bytes))),
            OverflowBar(children: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
              Builder(
                builder: (buttonContext) => FilledButton.icon(
                  onPressed: () => saveImage(buttonContext, bytes, 'husk-snapshot-${DateTime.now().millisecondsSinceEpoch}.jpg'),
                  icon: const Icon(Icons.save_alt),
                  label: const Text('Save'),
                ),
              ),
            ]),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final api = ref.watch(apiProvider(widget.serverId));
    final front = ref.watch(flagsProvider(widget.serverId)).value?.front;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final textTheme = Theme.of(context).textTheme;

    final controls = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      FilledButton.icon(
        onPressed: _busy ? null : () => _snapshot(api),
        icon: const Icon(Icons.photo_camera),
        label: const Text('Snapshot'),
      ),
      const SizedBox(height: 16),
      Text('Camera side', style: textTheme.labelLarge),
      const SizedBox(height: 4),
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: false, label: Text('Back')),
          ButtonSegment(value: true, label: Text('Front')),
        ],
        selected: {?front},
        emptySelectionAllowed: true,
        onSelectionChanged: (v) {
          if (v.isNotEmpty) _setCamera(api, front: v.first);
        },
      ),
      const SizedBox(height: 16),
      Text('Rotation', style: textTheme.labelLarge),
      const SizedBox(height: 4),
      SegmentedButton<int>(
        segments: const [
          for (final degrees in [0, 90, 180, 270]) ButtonSegment(value: degrees, label: Text('$degrees°')),
        ],
        selected: {?_rotation},
        emptySelectionAllowed: true,
        onSelectionChanged: (v) {
          if (v.isEmpty) return;
          setState(() => _rotation = v.first);
          _setCamera(api, rotation: v.first);
        },
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Mirror horizontally'),
        value: _flip,
        onChanged: (v) {
          setState(() => _flip = v);
          _setCamera(api, flip: v);
        },
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Frame rate cap'),
        trailing: DropdownButton<int>(
          value: _fps,
          hint: const Text('Default'),
          items: [for (final f in [1, 5, 10, 15, 30]) DropdownMenuItem(value: f, child: Text('$f fps'))],
          onChanged: (v) {
            if (v == null) return;
            setState(() => _fps = v);
            _setCamera(api, fps: v);
          },
        ),
      ),
      Text(
        'The phone starts the camera on demand and closes it about 4 s after the last viewer.',
        style: textTheme.bodySmall,
      ),
    ]);

    final view = MjpegView(api: api, path: '/stream');
    if (wide) {
      return Row(children: [
        Expanded(child: view),
        SizedBox(width: 340, child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: controls)),
      ]);
    }
    return Column(children: [
      Expanded(flex: 3, child: view),
      Expanded(flex: 2, child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: controls)),
    ]);
  }
}
```
(`{?front}` is a null-aware set element: an empty set when `front` is null.)

- [ ] **Step 6: Wire the tab into the shell**

In `lib/features/device/device_shell.dart`:
- Add the import `import '../camera/camera_tab.dart';`.
- Replace `DeviceTab.camera => const _TabPlaceholder('Camera'),` with:
  ```dart
          DeviceTab.camera => CameraTab(serverId: widget.serverId),
  ```

- [ ] **Step 7: Run tests and analyze**

Run: `flutter test && flutter analyze`
Expected: `All tests passed!` and `No issues found!`

- [ ] **Step 8: Manual check against the test phone**

In `flutter run -d macos`, open the Camera tab:
1. The live stream appears with an fps readout.
2. **Snapshot** opens the image. **Save** opens a save dialog and writes a `.jpg`.
3. Switching Back/Front changes the stream after a moment.
4. Leaving the tab stops the stream. After about 4 s, `/flags` shows `"camera":false` (check with `curl -s http://192.168.0.106:8090/flags`).

Restore the camera side to **Front** afterwards (its state on 2026-10-07).

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat: add MJPEG view and camera tab with snapshot and camera settings

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_018vGW2sL6yV3eTZKrrtJar3"
```

---

### Task 19: Screen tab: MJPEG mode, gesture mapping, nav bar and keyboard

**Files:**
- Create: `lib/features/screen/screen_mode.dart`, `lib/features/screen/input_queue.dart`, `lib/features/screen/gesture_layer.dart`, `lib/features/screen/input_controls.dart`, `lib/features/screen/screen_tab.dart`
- Modify: `lib/features/device/device_shell.dart`
- Test: `test/features/screen/screen_mode_test.dart`, `test/features/screen/input_queue_test.dart`, `test/features/screen/gesture_layer_test.dart`, `test/features/screen/screen_tab_test.dart`

**Interfaces:**
- Consumes:
  - `CoordinateMapper` (Task 9)
  - `HuskApi.tap/swipe/key/scroll/typeText/wake/screenshot/setCamera` (Task 7)
  - `MjpegView`, `saveImage` (Task 18)
  - `flagsProvider`, `displayInfoProvider`, `displaysProvider`, `runCommand` (Task 17)
  - `settingsProvider` (Task 12)
  - `NavKey`, `TextResult`, `DeviceErrorException`
- Produces:
  - `final sessionScreenModeProvider = NotifierProvider<SessionScreenMode, ScreenMode?>` (`set(ScreenMode)`)
  - `Set<ScreenMode> availableScreenModes()`: returns `{ScreenMode.mjpeg}` in this task; Task 20 changes the signature
  - `ScreenMode effectiveScreenMode({required ScreenMode? session, required ScreenMode defaultMode, required Set<ScreenMode> available})`
  - `class InputQueue({required void Function(Object error) onError})` with `void add(Future<Object?> Function() action)` and `Future<void> get idle`
  - `typedef DevicePoint = ({int x, int y});`
  - `class GestureLayer({required Size deviceSize, required Widget child, required onTap, required onLongPress, required onSwipe, required onScroll, required onKey})`
  - `class NavBar({required void Function(NavKey) onKey, required VoidCallback onWake})`
  - `class KeyboardPanel({required void Function(String) onSendText, required VoidCallback onEnter})`
  - `class ScreenTab(String serverId)`

- [ ] **Step 1: Write failing tests**

`test/features/screen/screen_mode_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/storage/app_settings.dart';
import 'package:huskconfig/features/screen/screen_mode.dart';

void main() {
  test('session choice wins over the default when available', () {
    expect(
      effectiveScreenMode(session: ScreenMode.webview, defaultMode: ScreenMode.mjpeg, available: {ScreenMode.mjpeg, ScreenMode.webview}),
      ScreenMode.webview,
    );
  });

  test('falls back to the default, then to MJPEG when unavailable', () {
    expect(effectiveScreenMode(session: null, defaultMode: ScreenMode.webview, available: {ScreenMode.mjpeg, ScreenMode.webview}), ScreenMode.webview);
    expect(effectiveScreenMode(session: ScreenMode.h264, defaultMode: ScreenMode.h264, available: {ScreenMode.mjpeg}), ScreenMode.mjpeg);
  });
}
```

`test/features/screen/input_queue_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/api/husk_exception.dart';
import 'package:huskconfig/core/api/text_result.dart';
import 'package:huskconfig/features/screen/input_queue.dart';

void main() {
  test('runs actions one at a time, in order', () async {
    final log = <String>[];
    final queue = InputQueue(onError: (_) {});
    queue.add(() async {
      log.add('a-start');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      log.add('a-end');
      return null;
    });
    queue.add(() async {
      log.add('b');
      return null;
    });
    await queue.idle;
    expect(log, ['a-start', 'a-end', 'b']);
  });

  test('reports thrown errors and ERR replies, and keeps going', () async {
    final errors = <String>[];
    var ran = false;
    final queue = InputQueue(onError: (e) => errors.add('$e'));
    queue.add(() async => throw const OfflineException('down'));
    queue.add(() async => const TextResult('ERR cancelled'));
    queue.add(() async {
      ran = true;
      return const TextResult('OK');
    });
    await queue.idle;
    expect(errors, ['down', 'ERR cancelled']);
    expect(ran, isTrue);
  });
}
```

`test/features/screen/gesture_layer_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/api/models/tools_models.dart';
import 'package:huskconfig/features/screen/gesture_layer.dart';

void main() {
  final taps = <DevicePoint>[];
  final longPresses = <DevicePoint>[];
  final swipes = <(DevicePoint, DevicePoint, Duration)>[];
  final keys = <NavKey>[];

  setUp(() {
    taps.clear();
    longPresses.clear();
    swipes.clear();
    keys.clear();
  });

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(MaterialApp(
        home: Center(
          child: SizedBox(
            width: 400,
            height: 400,
            child: GestureLayer(
              deviceSize: const Size(1080, 2112),
              onTap: taps.add,
              onLongPress: longPresses.add,
              onSwipe: (a, b, d) => swipes.add((a, b, d)),
              onScroll: (_) {},
              onKey: keys.add,
              child: const ColoredBox(color: Colors.black),
            ),
          ),
        ),
      ));

  testWidgets('tap in the centre maps to the device centre', (tester) async {
    await pump(tester);
    await tester.tap(find.byType(GestureLayer));
    await tester.pumpAndSettle();
    expect(taps, [(x: 540, y: 1056)]);
  });

  testWidgets('taps in the letterbox bars are ignored', (tester) async {
    await pump(tester);
    final topLeft = tester.getTopLeft(find.byType(GestureLayer));
    await tester.tapAt(topLeft + const Offset(10, 200));
    await tester.pumpAndSettle();
    expect(taps, isEmpty);
  });

  testWidgets('long press maps to a long tap', (tester) async {
    await pump(tester);
    await tester.longPress(find.byType(GestureLayer));
    await tester.pumpAndSettle();
    expect(longPresses, [(x: 540, y: 1056)]);
  });

  testWidgets('a drag becomes a swipe from the start point', (tester) async {
    await pump(tester);
    await tester.drag(find.byType(GestureLayer), const Offset(0, -100));
    await tester.pumpAndSettle();
    expect(swipes, hasLength(1));
    final (from, to, duration) = swipes.single;
    expect(from, (x: 540, y: 1056));
    expect(to.x, 540);
    expect(to.y, lessThan(1056));
    expect(duration.inMilliseconds, inInclusiveRange(100, 2000));
  });

  testWidgets('Escape maps to Back once the view has focus', (tester) async {
    await pump(tester);
    await tester.tap(find.byType(GestureLayer));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(keys, [NavKey.back]);
  });
}
```

`test/features/screen/screen_tab_test.dart`:
```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/api/models/tools_models.dart';
import 'package:huskconfig/core/api/text_result.dart';
import 'package:huskconfig/core/storage/app_settings.dart';
import 'package:huskconfig/features/screen/gesture_layer.dart';
import 'package:huskconfig/features/screen/screen_tab.dart';
import 'package:huskconfig/features/servers/api_provider.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/fixtures.dart';
import '../../support/mocks.dart';
import '../../support/overview_stubs.dart';
import '../../support/test_app.dart';

void main() {
  late MockHuskApi api;

  setUpAll(() => registerFallbackValue(CancelToken()));

  Future<void> pump(WidgetTester tester, {required bool screenSharing}) async {
    api = MockHuskApi();
    stubOverview(api, screenSharing: screenSharing);
    when(() => api.openMultipart(any(), cancelToken: any(named: 'cancelToken'))).thenAnswer((_) async =>
        (contentType: 'multipart/x-mixed-replace; boundary=rigframe', stream: StreamController<Uint8List>().stream));
    when(() => api.tap(any(), any(), display: any(named: 'display'), ms: any(named: 'ms')))
        .thenAnswer((_) async => const TextResult('OK'));
    when(() => api.key(any())).thenAnswer((_) async => const TextResult('OK'));
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(testScope(
      servers: [server1],
      settings: const AppSettings(pollIntervalSeconds: 0),
      overrides: [apiProvider.overrideWith((ref, id) => api)],
      child: const MaterialApp(home: Scaffold(body: ScreenTab(serverId: 's1'))),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('explains when screen sharing is off', (tester) async {
    await pump(tester, screenSharing: false);
    expect(find.text('Screen sharing is off. Enable it in the Husk app on the phone.'), findsOneWidget);
    expect(find.byType(GestureLayer), findsNothing);
  });

  testWidgets('a tap on the screen view taps the phone', (tester) async {
    await pump(tester, screenSharing: true);
    await tester.tap(find.byType(GestureLayer));
    await tester.pumpAndSettle();
    verify(() => api.tap(540, 1056, display: 0)).called(1);
  });

  testWidgets('nav bar Home sends /key?k=home', (tester) async {
    await pump(tester, screenSharing: true);
    await tester.tap(find.byTooltip('Home'));
    await tester.pumpAndSettle();
    verify(() => api.key(NavKey.home)).called(1);
  });

  testWidgets('ERR cancelled suggests waking the screen', (tester) async {
    await pump(tester, screenSharing: true);
    when(() => api.key(NavKey.back)).thenAnswer((_) async => const TextResult('ERR cancelled'));
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Screen may be off — press Wake.'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/screen`
Expected: FAIL, missing files.

- [ ] **Step 3: Implement screen mode, input queue and gesture layer**

`lib/features/screen/screen_mode.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/app_settings.dart';

/// Mode picked in the Screen tab during this app session (null = settings default).
class SessionScreenMode extends Notifier<ScreenMode?> {
  @override
  ScreenMode? build() => null;

  void set(ScreenMode mode) => state = mode;
}

final sessionScreenModeProvider = NotifierProvider<SessionScreenMode, ScreenMode?>(SessionScreenMode.new);

/// Modes this build can show. H.264 and Web control are added in Task 20.
Set<ScreenMode> availableScreenModes() => {ScreenMode.mjpeg};

ScreenMode effectiveScreenMode({
  required ScreenMode? session,
  required ScreenMode defaultMode,
  required Set<ScreenMode> available,
}) {
  final mode = session ?? defaultMode;
  return available.contains(mode) ? mode : ScreenMode.mjpeg;
}
```

`lib/features/screen/input_queue.dart`:
```dart
import '../../core/api/husk_exception.dart';
import '../../core/api/text_result.dart';

/// Sends input commands strictly one after another without blocking the UI.
/// Failures (thrown or `ERR …` replies) go to [onError]; the queue keeps going.
class InputQueue {
  InputQueue({required this.onError});

  final void Function(Object error) onError;
  Future<void> _tail = Future.value();

  Future<void> get idle => _tail;

  void add(Future<Object?> Function() action) {
    _tail = _tail.then((_) async {
      try {
        final result = await action();
        if (result is TextResult && result.isErr) onError(DeviceErrorException(result.text));
      } catch (error) {
        onError(error);
      }
    });
  }
}
```

`lib/features/screen/gesture_layer.dart`:
```dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/models/tools_models.dart';
import 'coordinate_mapper.dart';

typedef DevicePoint = ({int x, int y});

/// Turns taps, long presses, drags, wheel scrolls and Esc/Enter on top of a
/// letterboxed phone image into device-pixel input events.
class GestureLayer extends StatefulWidget {
  const GestureLayer({
    super.key,
    required this.deviceSize,
    required this.child,
    required this.onTap,
    required this.onLongPress,
    required this.onSwipe,
    required this.onScroll,
    required this.onKey,
  });

  final Size deviceSize;
  final Widget child;
  final void Function(DevicePoint point) onTap;
  final void Function(DevicePoint point) onLongPress;
  final void Function(DevicePoint from, DevicePoint to, Duration duration) onSwipe;
  final void Function(bool forward) onScroll;
  final void Function(NavKey key) onKey;

  @override
  State<GestureLayer> createState() => _GestureLayerState();
}

class _GestureLayerState extends State<GestureLayer> {
  final _focus = FocusNode(debugLabel: 'phone screen');
  Offset? _panStart;
  Offset? _panLast;
  DateTime? _panStartedAt;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onKey(NavKey.back);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      widget.onKey(NavKey.enter);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
        final mapper = CoordinateMapper(viewSize: constraints.biggest, deviceSize: widget.deviceSize);
        return Focus(
          focusNode: _focus,
          onKeyEvent: _onKey,
          child: Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) widget.onScroll(event.scrollDelta.dy > 0);
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => _focus.requestFocus(),
              onTapUp: (details) {
                final point = mapper.toDevice(details.localPosition);
                if (point != null) widget.onTap(point);
              },
              onLongPressStart: (details) {
                final point = mapper.toDevice(details.localPosition);
                if (point != null) widget.onLongPress(point);
              },
              onPanStart: (details) {
                _panStart = details.localPosition;
                _panLast = details.localPosition;
                _panStartedAt = DateTime.now();
              },
              onPanUpdate: (details) => _panLast = details.localPosition,
              onPanEnd: (_) {
                final start = _panStart, end = _panLast, startedAt = _panStartedAt;
                _panStart = null;
                if (start == null || end == null || startedAt == null) return;
                final from = mapper.toDevice(start);
                final to = mapper.toDeviceClamped(end);
                if (from == null || to == null) return;
                final ms = DateTime.now().difference(startedAt).inMilliseconds.clamp(100, 2000);
                widget.onSwipe(from, to, Duration(milliseconds: ms));
              },
              child: widget.child,
            ),
          ),
        );
      });
}
```

- [ ] **Step 4: Implement the nav bar and keyboard panel**

`lib/features/screen/input_controls.dart`:
```dart
import 'package:flutter/material.dart';

import '../../core/api/models/tools_models.dart';

class NavBar extends StatelessWidget {
  const NavBar({super.key, required this.onKey, required this.onWake});

  final void Function(NavKey key) onKey;
  final VoidCallback onWake;

  @override
  Widget build(BuildContext context) => Wrap(alignment: WrapAlignment.center, spacing: 4, children: [
        IconButton(tooltip: 'Back', icon: const Icon(Icons.arrow_back), onPressed: () => onKey(NavKey.back)),
        IconButton(tooltip: 'Home', icon: const Icon(Icons.circle_outlined), onPressed: () => onKey(NavKey.home)),
        IconButton(tooltip: 'Recents', icon: const Icon(Icons.crop_square), onPressed: () => onKey(NavKey.recents)),
        IconButton(tooltip: 'Notifications', icon: const Icon(Icons.notifications_none), onPressed: () => onKey(NavKey.notifications)),
        IconButton(tooltip: 'Wake screen', icon: const Icon(Icons.power_settings_new), onPressed: onWake),
      ]);
}

class KeyboardPanel extends StatefulWidget {
  const KeyboardPanel({super.key, required this.onSendText, required this.onEnter});

  final void Function(String text) onSendText;
  final VoidCallback onEnter;

  @override
  State<KeyboardPanel> createState() => _KeyboardPanelState();
}

class _KeyboardPanelState extends State<KeyboardPanel> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _send() {
    if (_text.text.isEmpty) return;
    widget.onSendText(_text.text);
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _text,
              decoration: const InputDecoration(
                labelText: 'Text for the focused field',
                helperText: "Replaces the field's whole content.",
                isDense: true,
              ),
              onSubmitted: (_) => _send(),
            ),
          ),
          IconButton(tooltip: 'Send text', icon: const Icon(Icons.send), onPressed: _send),
          OutlinedButton(onPressed: widget.onEnter, child: const Text('Enter')),
        ]),
      );
}
```

- [ ] **Step 5: Implement the Screen tab**

`lib/features/screen/screen_tab.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/husk_api.dart';
import '../../core/api/husk_exception.dart';
import '../../core/api/models/hardware_models.dart';
import '../../core/api/models/tools_models.dart';
import '../../core/storage/app_settings.dart';
import '../../shared/error_text.dart';
import '../../shared/run_command.dart';
import '../../shared/save_image.dart';
import '../../shared/widgets/mjpeg_view.dart';
import '../device/overview_providers.dart';
import '../servers/api_provider.dart';
import '../settings/settings_controller.dart';
import 'gesture_layer.dart';
import 'input_controls.dart';
import 'input_queue.dart';
import 'screen_mode.dart';

String _modeLabel(ScreenMode mode) => switch (mode) {
      ScreenMode.mjpeg => 'MJPEG',
      ScreenMode.h264 => 'H.264',
      ScreenMode.webview => 'Web control',
    };

class ScreenTab extends ConsumerStatefulWidget {
  const ScreenTab({super.key, required this.serverId});

  final String serverId;

  @override
  ConsumerState<ScreenTab> createState() => _ScreenTabState();
}

class _ScreenTabState extends ConsumerState<ScreenTab> {
  late final InputQueue _queue = InputQueue(onError: _showInputError);
  int _display = 0;
  bool _fullscreenOpen = false;

  void _showInputError(Object error) {
    if (!mounted) return;
    final message = describeError(error);
    final hint = message.contains('cancelled') ? ' Screen may be off — press Wake.' : '';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$message$hint')));
  }

  void _snack(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Widget _interactive(HuskApi api, Size deviceSize, Widget child) => GestureLayer(
        deviceSize: deviceSize,
        onTap: (p) => _queue.add(() => api.tap(p.x, p.y, display: _display)),
        onLongPress: (p) => _queue.add(() => api.tap(p.x, p.y, display: _display, ms: 600)),
        onSwipe: (a, b, d) => _queue.add(() => api.swipe(a.x, a.y, b.x, b.y, display: _display, ms: d.inMilliseconds)),
        onScroll: (forward) => _queue.add(() => api.scroll(display: _display, forward: forward)),
        onKey: (key) => _queue.add(() => api.key(key)),
        child: child,
      );

  /// The live view for [mode]. [display] is the phone's pixel size from /display.
  Widget _modeView(ScreenMode mode, HuskApi api, AsyncValue<DisplayInfo> display) {
    final info = display.value;
    if (info == null) {
      final error = display.error;
      return Center(child: error == null ? const CircularProgressIndicator() : Text(describeError(error)));
    }
    final deviceSize = Size(info.width.toDouble(), info.height.toDouble());
    return switch (mode) {
      ScreenMode.mjpeg || ScreenMode.h264 || ScreenMode.webview => _interactive(api, deviceSize, MjpegView(api: api, path: '/screen')),
    };
  }

  Widget _controls(HuskApi api) => Column(mainAxisSize: MainAxisSize.min, children: [
        NavBar(onKey: (k) => _queue.add(() => api.key(k)), onWake: () => _queue.add(api.wake)),
        KeyboardPanel(
          onSendText: (t) => _queue.add(() => api.typeText(t)),
          onEnter: () => _queue.add(() => api.key(NavKey.enter)),
        ),
      ]);

  Future<void> _screenshot(HuskApi api) async {
    try {
      final bytes = await api.screenshot();
      if (mounted) await saveImage(context, bytes, 'husk-screen-${DateTime.now().millisecondsSinceEpoch}.jpg');
    } on HttpStatusException catch (e) {
      _snack(e.statusCode == 503 ? 'Screen sharing is off on the phone.' : e.message);
    } on HuskException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _quality(HuskApi api) async {
    var quality = 70.0, fps = 15.0;
    final apply = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Screen stream quality'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('JPEG quality: ${quality.round()} (lower = less lag)'),
            Slider(value: quality, min: 1, max: 100, divisions: 99, onChanged: (v) => setDialogState(() => quality = v)),
            Text('Frames per second: ${fps.round()}'),
            Slider(value: fps, min: 1, max: 30, divisions: 29, onChanged: (v) => setDialogState(() => fps = v)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Apply')),
          ],
        ),
      ),
    );
    if (apply == true && mounted) {
      await runCommand(
        context,
        () => api.setCamera(screenQuality: quality.round(), screenFps: fps.round()),
        success: 'Stream quality updated',
      );
    }
  }

  Future<void> _openFullscreen(ScreenMode mode, HuskApi api, AsyncValue<DisplayInfo> display) async {
    setState(() => _fullscreenOpen = true); // Avoid two streams while the route is on top.
    await Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (context) => Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(children: [
            Positioned.fill(child: _modeView(mode, api, display)),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton.filledTonal(
                tooltip: 'Exit fullscreen',
                icon: const Icon(Icons.fullscreen_exit),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ]),
        ),
        bottomNavigationBar: mode == ScreenMode.webview ? null : Material(child: _controls(api)),
      ),
    ));
    if (mounted) setState(() => _fullscreenOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.serverId;
    final api = ref.watch(apiProvider(id));
    final flags = ref.watch(flagsProvider(id));
    final display = ref.watch(displayInfoProvider(id));
    final displays = ref.watch(displaysProvider(id)).value ?? const [DisplayEntry(id: 0, raw: '0')];
    final available = availableScreenModes();
    final mode = effectiveScreenMode(
      session: ref.watch(sessionScreenModeProvider),
      defaultMode: ref.watch(settingsProvider.select((s) => s.defaultScreenMode)),
      available: available,
    );
    final displayIds = {for (final d in displays) d.id, _display};

    final Widget body;
    if (_fullscreenOpen) {
      body = const Center(child: Text('Showing fullscreen'));
    } else if (flags.value?.screen == false) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.screen_share_outlined, size: 48),
            const SizedBox(height: 12),
            const Text('Screen sharing is off. Enable it in the Husk app on the phone.', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: () => ref.invalidate(flagsProvider(id)), child: const Text('Retry')),
          ]),
        ),
      );
    } else if (flags.value == null) {
      body = Center(child: flags.hasError ? Text(describeError(flags.error!)) : const CircularProgressIndicator());
    } else {
      body = _modeView(mode, api, display);
    }

    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(8),
        child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (available.length > 1)
            SegmentedButton<ScreenMode>(
              segments: [for (final m in available) ButtonSegment(value: m, label: Text(_modeLabel(m)))],
              selected: {mode},
              onSelectionChanged: (v) => ref.read(sessionScreenModeProvider.notifier).set(v.first),
            ),
          DropdownButton<int>(
            value: _display,
            items: [
              for (final d in displayIds) DropdownMenuItem(value: d, child: Text(d == 0 ? 'Phone (display 0)' : 'Display $d')),
            ],
            onChanged: (v) => setState(() => _display = v ?? 0),
          ),
          IconButton(tooltip: 'Screenshot', icon: const Icon(Icons.screenshot_monitor), onPressed: () => _screenshot(api)),
          IconButton(tooltip: 'Stream quality', icon: const Icon(Icons.high_quality), onPressed: () => _quality(api)),
          IconButton(
            tooltip: 'Fullscreen',
            icon: const Icon(Icons.fullscreen),
            onPressed: () => _openFullscreen(mode, api, display),
          ),
        ]),
      ),
      Expanded(child: body),
      if (mode != ScreenMode.webview) _controls(api),
    ]);
  }
}
```
The `_modeView` switch maps every mode to MJPEG for now. Task 20 gives H.264 and Web control their own views.

- [ ] **Step 6: Wire the tab into the shell**

In `lib/features/device/device_shell.dart`:
- Add the import `import '../screen/screen_tab.dart';`.
- Replace `DeviceTab.screen => const _TabPlaceholder('Screen'),` with:
  ```dart
          DeviceTab.screen => ScreenTab(serverId: widget.serverId),
  ```

- [ ] **Step 7: Run tests and analyze**

Run: `flutter test && flutter analyze`
Expected: `All tests passed!` and `No issues found!`

- [ ] **Step 8: Manual check against the test phone**

Screen sharing must be on (see Task 2, Step 1). In `flutter run -d macos`, open the Screen tab:
1. The phone screen streams.
2. Clicking an app icon opens it on the phone.
3. Dragging up scrolls a list.
4. The mouse wheel scrolls.
5. Back, Home and Recents work.
6. Esc goes back after clicking the view.
7. Focus a search field on the phone, type `hello` and click **Send text**. It appears; **Enter** submits.
8. **Screenshot** saves a JPEG.
9. Quality changes apply.
10. Fullscreen opens and closes.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat: add screen tab with MJPEG view, gesture mapping and input controls

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_018vGW2sL6yV3eTZKrrtJar3"
```

---

### Task 20: Screen tab: H.264 and Web control modes

**Files:**
- Create: `lib/features/screen/h264_view.dart`, `lib/features/screen/web_control_view.dart`
- Modify: `lib/features/screen/screen_mode.dart`, `lib/features/screen/screen_tab.dart`
- Test: `test/features/screen/screen_mode_test.dart` (extend)

**Interfaces:**
- Consumes:
  - the spike findings `H264_PLATFORMS` and `CATCH_UP_SEEK` from `docs/superpowers/spikes/2026-10-07-h264-media-kit.md` (Task 2)
  - `HuskApi.uri` (Task 5)
  - `GestureLayer` (Task 19)
- Produces:
  - `const Set<TargetPlatform> h264Platforms`
  - `const bool h264CatchUpSeek`
  - `Set<ScreenMode> availableScreenModes({required bool h264Supported, required bool h264Failed})`: replaces the Task 19 signature
  - `class H264View({required Uri uri, required ValueChanged<String> onFailed, bool catchUpSeek})`
  - `class WebControlView({required HuskApi api})`

- [ ] **Step 1: Extend the mode test (failing)**

Append to `test/features/screen/screen_mode_test.dart`, inside `main()`:
```dart
  test('availableScreenModes hides H.264 when unsupported or after a failure', () {
    expect(availableScreenModes(h264Supported: true, h264Failed: false), {ScreenMode.mjpeg, ScreenMode.h264, ScreenMode.webview});
    expect(availableScreenModes(h264Supported: false, h264Failed: false), {ScreenMode.mjpeg, ScreenMode.webview});
    expect(availableScreenModes(h264Supported: true, h264Failed: true), {ScreenMode.mjpeg, ScreenMode.webview});
  });
```

Run: `flutter test test/features/screen/screen_mode_test.dart`
Expected: FAIL, `No named parameter with the name 'h264Supported'`.

- [ ] **Step 2: Update `screen_mode.dart` from the spike findings**

Open `docs/superpowers/spikes/2026-10-07-h264-media-kit.md` and read the `H264_PLATFORMS:` and `CATCH_UP_SEEK:` lines.

In `lib/features/screen/screen_mode.dart`:
- Add `import 'package:flutter/foundation.dart';`.
- Replace the `availableScreenModes` function with the block below. Put exactly the spike's platforms in `h264Platforms`; for example, if the spike says `macos,android`, use `{TargetPlatform.macOS, TargetPlatform.android}`.
```dart
/// Platforms where H.264 /screen.mp4 passed the 2026-10-07 spike.
const Set<TargetPlatform> h264Platforms = {TargetPlatform.macOS, TargetPlatform.android};

/// Whether H264View seeks to the live edge when it falls >2 s behind (spike: CATCH_UP_SEEK).
const bool h264CatchUpSeek = true;

Set<ScreenMode> availableScreenModes({required bool h264Supported, required bool h264Failed}) => {
      ScreenMode.mjpeg,
      if (h264Supported && !h264Failed) ScreenMode.h264,
      ScreenMode.webview,
    };
```

If the spike found **no** platform working, set `h264Platforms = {}`. H.264 then never appears, and the setting falls back to MJPEG through `effectiveScreenMode`.

- [ ] **Step 3: Implement the H.264 view**

`lib/features/screen/h264_view.dart`:
```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Plays Husk's live fMP4 /screen.mp4 with mpv's low-latency settings.
/// Calls [onFailed] on any player error so the tab can fall back to MJPEG.
class H264View extends StatefulWidget {
  const H264View({super.key, required this.uri, required this.onFailed, this.catchUpSeek = true});

  final Uri uri;
  final ValueChanged<String> onFailed;
  final bool catchUpSeek;

  @override
  State<H264View> createState() => _H264ViewState();
}

class _H264ViewState extends State<H264View> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);
  StreamSubscription<String>? _errors;
  Timer? _watchdog;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final native = _player.platform;
    if (native is NativePlayer) {
      await native.setProperty('profile', 'low-latency');
      await native.setProperty('cache', 'no');
      await native.setProperty('untimed', 'yes');
    }
    // mpv errors may echo the URL; strip it so the token never reaches the UI.
    _errors = _player.stream.error.listen((e) => widget.onFailed(e.replaceAll(widget.uri.toString(), '/screen.mp4')));
    await _player.open(Media(widget.uri.toString()));
    if (widget.catchUpSeek) {
      _watchdog = Timer.periodic(const Duration(seconds: 2), (_) {
        final state = _player.state;
        if (state.buffer - state.position > const Duration(seconds: 2)) _player.seek(state.buffer);
      });
    }
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    _errors?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Video(controller: _controller, controls: NoVideoControls, fit: BoxFit.contain, fill: Colors.black);
}
```

- [ ] **Step 4: Implement the Web control view**

`lib/features/screen/web_control_view.dart`:
```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/husk_api.dart';

/// Husk's own /control (MJPEG) or /controlhw (H.264) page in a WebView.
/// The page is loaded from the phone's IP, so Husk's same-site checks pass.
class WebControlView extends StatefulWidget {
  const WebControlView({super.key, required this.api});

  final HuskApi api;

  @override
  State<WebControlView> createState() => _WebControlViewState();
}

class _WebControlViewState extends State<WebControlView> {
  bool _hardware = false;
  String? _error;
  bool? _webViewAvailable;

  @override
  void initState() {
    super.initState();
    if (defaultTargetPlatform == TargetPlatform.windows) {
      WebViewEnvironment.getAvailableVersion().then((version) {
        if (mounted) setState(() => _webViewAvailable = version != null);
      });
    } else {
      _webViewAvailable = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_webViewAvailable) {
      case null:
        return const Center(child: CircularProgressIndicator());
      case false:
        return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Web control needs the Microsoft Edge WebView2 runtime.'),
            TextButton(
              onPressed: () => launchUrl(Uri.parse('https://developer.microsoft.com/microsoft-edge/webview2/')),
              child: const Text('Get WebView2'),
            ),
          ]),
        );
      case true:
        break;
    }
    final url = widget.api.uri(_hardware ? '/controlhw' : '/control').toString();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('MJPEG page')),
            ButtonSegment(value: true, label: Text('H.264 page')),
          ],
          selected: {_hardware},
          onSelectionChanged: (v) => setState(() {
            _hardware = v.first;
            _error = null;
          }),
        ),
      ),
      if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      Expanded(
        child: InAppWebView(
          key: ValueKey(url),
          initialUrlRequest: URLRequest(url: WebUri(url)),
          initialSettings: InAppWebViewSettings(mediaPlaybackRequiresUserGesture: false, allowsInlineMediaPlayback: true),
          onReceivedError: (controller, request, error) {
            if (request.isForMainFrame != false && mounted) {
              setState(() => _error = 'Could not load the control page: ${error.description}');
            }
          },
        ),
      ),
    ]);
  }
}
```

- [ ] **Step 5: Use the new views in the Screen tab**

In `lib/features/screen/screen_tab.dart`:
- Add these imports:
  ```dart
  import 'package:flutter/foundation.dart';
  import 'h264_view.dart';
  import 'web_control_view.dart';
  ```
- Add a field to `_ScreenTabState`:
  ```dart
  bool _h264Failed = false;
  ```
- Replace the `switch` in `_modeView` with:
  ```dart
      return switch (mode) {
        ScreenMode.mjpeg => _interactive(api, deviceSize, MjpegView(api: api, path: '/screen')),
        ScreenMode.h264 => _interactive(
            api,
            deviceSize,
            H264View(
              uri: api.uri('/screen.mp4'),
              catchUpSeek: h264CatchUpSeek,
              onFailed: (message) {
                if (!mounted || _h264Failed) return;
                setState(() => _h264Failed = true);
                _snack('H.264 not supported on this platform — using MJPEG ($message)');
              },
            ),
          ),
        ScreenMode.webview => WebControlView(api: api),
      };
  ```
- In `build`, replace `final available = availableScreenModes();` with:
  ```dart
      final available = availableScreenModes(
        h264Supported: h264Platforms.contains(defaultTargetPlatform),
        h264Failed: _h264Failed,
      );
  ```
- Web control needs no display size. Move the `ScreenMode.webview` case above the `display.value == null` check. Add this as the **first** statement of `_modeView`:
  ```dart
      if (mode == ScreenMode.webview) return WebControlView(api: api);
  ```

- [ ] **Step 6: Run tests and analyze**

Run: `flutter test && flutter analyze`
Expected: `All tests passed!` and `No issues found!`

- [ ] **Step 7: Manual check on every platform you can run**

With screen sharing on, run `flutter run -d macos` (and `-d <android-id>` if attached):
1. Switch the Screen tab to **H.264**. Video plays with noticeably lower lag than MJPEG, and tapping still works.
2. On a platform outside `h264Platforms`, the H.264 segment is absent.
3. Switch to **Web control**. Husk's control page loads and its own clicks work. Toggling **H.264 page** loads `/controlhw`.
4. Set Settings → Default mode to Web control, reopen the Screen tab, and check it starts in Web control.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: add H.264 and web control screen modes

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_018vGW2sL6yV3eTZKrrtJar3"
```

---

### Task 21: Tools tab: Inspect and Launch

**Files:**
- Create: `lib/shared/widgets/result_box.dart`, `lib/features/tools/tools_tab.dart`, `lib/features/tools/inspect_tool.dart`, `lib/features/tools/launch_tool.dart`
- Modify: `lib/features/device/device_shell.dart`
- Test: `test/features/tools/inspect_tool_test.dart`, `test/features/tools/launch_tool_test.dart`

**Interfaces:**
- Consumes:
  - `HuskApi.find/exists/getText/click/dump/scroll/tap/launch` (Tasks 5, 7)
  - `apiProvider` (Task 12)
- Produces:
  - `class ResultBox(String text, {bool isError = false})`
  - `enum ToolPage` with `label`/`icon`; values `inspect` and `launch` (Task 22 adds more)
  - `class ToolsTab(String serverId)`, `class InspectTool(String serverId)`, `class LaunchTool(String serverId)`

- [ ] **Step 1: Write failing tests**

`test/features/tools/inspect_tool_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/api/text_result.dart';
import 'package:huskconfig/features/servers/api_provider.dart';
import 'package:huskconfig/features/tools/inspect_tool.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/fixtures.dart';
import '../../support/mocks.dart';
import '../../support/test_app.dart';

void main() {
  late MockHuskApi api;

  setUp(() => api = MockHuskApi());

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(testScope(
      servers: [server1],
      overrides: [apiProvider.overrideWith((ref, id) => api)],
      child: const MaterialApp(home: Scaffold(body: InspectTool(serverId: 's1'))),
    ));
  }

  testWidgets('asks for a pattern first', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Find'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a regular expression to match text or content descriptions.'), findsOneWidget);
  });

  testWidgets('Find shows the centre and Tap here taps it', (tester) async {
    when(() => api.find('Settings', display: 0)).thenAnswer((_) async => (x: 540, y: 1056));
    when(() => api.tap(540, 1056, display: 0)).thenAnswer((_) async => const TextResult('OK'));
    await pump(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Pattern (regex)'), 'Settings');
    await tester.tap(find.text('Find'));
    await tester.pumpAndSettle();
    expect(find.text('Found at 540, 1056'), findsOneWidget);
    await tester.tap(find.text('Tap here'));
    await tester.pumpAndSettle();
    verify(() => api.tap(540, 1056, display: 0)).called(1);
  });

  testWidgets('Exists reports no match', (tester) async {
    when(() => api.exists('Nope', display: 0)).thenAnswer((_) async => false);
    await pump(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Pattern (regex)'), 'Nope');
    await tester.tap(find.text('Exists'));
    await tester.pumpAndSettle();
    expect(find.text('No matching element'), findsOneWidget);
  });

  testWidgets('Dump shows a filterable tree', (tester) async {
    when(() => api.dump(display: 0)).thenAnswer((_) async => 'Settings [0,0][100,100]\nWi-Fi [0,100][100,200]');
    await pump(tester);
    await tester.tap(find.text('Dump'));
    await tester.pumpAndSettle();
    expect(find.text('Dumped 2 lines'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Filter lines'), 'wi-fi');
    await tester.pumpAndSettle();
    expect(find.text('Wi-Fi [0,100][100,200]'), findsOneWidget);
  });
}
```

`test/features/tools/launch_tool_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/api/text_result.dart';
import 'package:huskconfig/features/servers/api_provider.dart';
import 'package:huskconfig/features/tools/launch_tool.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/fixtures.dart';
import '../../support/mocks.dart';
import '../../support/test_app.dart';

void main() {
  testWidgets('a preset fills the action and Launch sends it', (tester) async {
    final api = MockHuskApi();
    when(() => api.launch(action: 'android.settings.WIFI_SETTINGS', data: null, package: null, display: 0))
        .thenAnswer((_) async => const TextResult('OK'));
    await tester.pumpWidget(testScope(
      servers: [server1],
      overrides: [apiProvider.overrideWith((ref, id) => api)],
      child: const MaterialApp(home: Scaffold(body: LaunchTool(serverId: 's1'))),
    ));
    await tester.tap(find.text('Wi-Fi settings'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'android.settings.WIFI_SETTINGS'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Launch'));
    await tester.pumpAndSettle();
    verify(() => api.launch(action: 'android.settings.WIFI_SETTINGS', data: null, package: null, display: 0)).called(1);
    expect(find.text('OK'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/tools`
Expected: FAIL, missing files.

- [ ] **Step 3: Implement `ResultBox`**

`lib/shared/widgets/result_box.dart`:
```dart
import 'package:flutter/material.dart';

/// Monospace, selectable output of a device command.
class ResultBox extends StatelessWidget {
  const ResultBox(this.text, {super.key, this.isError = false});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isError ? scheme.errorContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectableText(
        text,
        style: TextStyle(fontFamily: 'monospace', color: isError ? scheme.onErrorContainer : null),
      ),
    );
  }
}
```

- [ ] **Step 4: Implement the Inspect tool**

`lib/features/tools/inspect_tool.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/husk_exception.dart';
import '../../shared/widgets/result_box.dart';
import '../servers/api_provider.dart';

class InspectTool extends ConsumerStatefulWidget {
  const InspectTool({super.key, required this.serverId});

  final String serverId;

  @override
  ConsumerState<InspectTool> createState() => _InspectToolState();
}

class _InspectToolState extends ConsumerState<InspectTool> {
  final _match = TextEditingController();
  final _display = TextEditingController(text: '0');
  final _filter = TextEditingController();
  String? _result;
  bool _resultIsError = false;
  ({int x, int y})? _found;
  String? _dump;
  bool _busy = false;

  int get _d => int.tryParse(_display.text.trim()) ?? 0;
  String get _m => _match.text.trim();

  @override
  void dispose() {
    _match.dispose();
    _display.dispose();
    _filter.dispose();
    super.dispose();
  }

  Future<void> _run(Future<String> Function() action, {bool needsPattern = true}) async {
    if (needsPattern && _m.isEmpty) {
      setState(() {
        _result = 'Enter a regular expression to match text or content descriptions.';
        _resultIsError = true;
      });
      return;
    }
    setState(() {
      _busy = true;
      _found = null;
    });
    try {
      final text = await action();
      if (mounted) setState(() => (_result, _resultIsError) = (text, text.startsWith('ERR')));
    } on HuskException catch (e) {
      if (mounted) setState(() => (_result, _resultIsError) = (e.message, true));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = ref.watch(apiProvider(widget.serverId));
    final dump = _dump;
    final filter = _filter.text.trim().toLowerCase();
    final dumpLines = dump == null
        ? const <String>[]
        : [for (final line in dump.split('\n')) if (filter.isEmpty || line.toLowerCase().contains(filter)) line];

    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        Expanded(
          child: TextField(
            controller: _match,
            decoration: const InputDecoration(labelText: 'Pattern (regex)', hintText: 'Wi-?Fi|WLAN'),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 90,
          child: TextField(controller: _display, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Display')),
        ),
      ]),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton(
          onPressed: _busy
              ? null
              : () => _run(() async {
                    final point = await api.find(_m, display: _d);
                    _found = point;
                    return point == null ? 'No match' : 'Found at ${point.x}, ${point.y}';
                  }),
          child: const Text('Find'),
        ),
        OutlinedButton(
          onPressed: _busy ? null : () => _run(() async => await api.exists(_m, display: _d) ? 'Yes, a matching element exists' : 'No matching element'),
          child: const Text('Exists'),
        ),
        OutlinedButton(
          onPressed: _busy ? null : () => _run(() async => await api.getText(_m, display: _d) ?? 'No match'),
          child: const Text('Get text'),
        ),
        OutlinedButton(
          onPressed: _busy ? null : () => _run(() async => (await api.click(_m, display: _d)).text),
          child: const Text('Click'),
        ),
        OutlinedButton(
          onPressed: _busy
              ? null
              : () => _run(needsPattern: false, () async {
                    final tree = await api.dump(display: _d);
                    setState(() => _dump = tree);
                    return 'Dumped ${tree.split('\n').length} lines';
                  }),
          child: const Text('Dump'),
        ),
        OutlinedButton(
          onPressed: _busy ? null : () => _run(needsPattern: false, () async => (await api.scroll(display: _d)).text),
          child: const Text('Scroll forward'),
        ),
        OutlinedButton(
          onPressed: _busy ? null : () => _run(needsPattern: false, () async => (await api.scroll(display: _d, forward: false)).text),
          child: const Text('Scroll back'),
        ),
      ]),
      if (_result != null) ...[
        const SizedBox(height: 16),
        ResultBox(_result!, isError: _resultIsError),
      ],
      if (_found case final point?) ...[
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonal(
            onPressed: () => _run(needsPattern: false, () async => (await api.tap(point.x, point.y, display: _d)).text),
            child: const Text('Tap here'),
          ),
        ),
      ],
      if (dump != null) ...[
        const SizedBox(height: 24),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _filter,
              decoration: const InputDecoration(labelText: 'Filter lines', prefixIcon: Icon(Icons.filter_list)),
              onChanged: (_) => setState(() {}),
            ),
          ),
          IconButton(
            tooltip: 'Copy dump',
            icon: const Icon(Icons.copy),
            onPressed: () => Clipboard.setData(ClipboardData(text: dump)),
          ),
        ]),
        const SizedBox(height: 8),
        Container(
          constraints: const BoxConstraints(maxHeight: 480),
          decoration: BoxDecoration(border: Border.all(color: Theme.of(context).dividerColor), borderRadius: BorderRadius.circular(8)),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(8),
            children: [for (final line in dumpLines) Text(line, style: const TextStyle(fontFamily: 'monospace', fontSize: 12))],
          ),
        ),
      ],
    ]);
  }
}
```

- [ ] **Step 5: Implement the Launch tool**

`lib/features/tools/launch_tool.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/husk_exception.dart';
import '../../shared/widgets/result_box.dart';
import '../servers/api_provider.dart';

const _presets = [
  (label: 'Settings', action: 'android.settings.SETTINGS', data: ''),
  (label: 'Wi-Fi settings', action: 'android.settings.WIFI_SETTINGS', data: ''),
  (label: 'Developer options', action: 'android.settings.APPLICATION_DEVELOPMENT_SETTINGS', data: ''),
  (label: 'Open URL', action: 'android.intent.action.VIEW', data: 'https://'),
];

class LaunchTool extends ConsumerStatefulWidget {
  const LaunchTool({super.key, required this.serverId});

  final String serverId;

  @override
  ConsumerState<LaunchTool> createState() => _LaunchToolState();
}

class _LaunchToolState extends ConsumerState<LaunchTool> {
  final _action = TextEditingController();
  final _data = TextEditingController();
  final _package = TextEditingController();
  final _display = TextEditingController(text: '0');
  String? _result;
  bool _isError = false;

  @override
  void dispose() {
    for (final c in [_action, _data, _package, _display]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _orNull(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  @override
  Widget build(BuildContext context) {
    final api = ref.watch(apiProvider(widget.serverId));
    return ListView(padding: const EdgeInsets.all(16), children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final p in _presets)
          ActionChip(
            label: Text(p.label),
            onPressed: () => setState(() {
              _action.text = p.action;
              _data.text = p.data;
            }),
          ),
      ]),
      const SizedBox(height: 12),
      TextField(controller: _action, decoration: const InputDecoration(labelText: 'Intent action', hintText: 'android.settings.SETTINGS')),
      TextField(controller: _data, decoration: const InputDecoration(labelText: 'Data URI (optional)')),
      TextField(controller: _package, decoration: const InputDecoration(labelText: 'Target package (optional)')),
      SizedBox(
        width: 120,
        child: TextField(controller: _display, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Display')),
      ),
      const SizedBox(height: 16),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          icon: const Icon(Icons.open_in_new),
          label: const Text('Launch'),
          onPressed: () async {
            final action = _action.text.trim();
            if (action.isEmpty) {
              setState(() => (_result, _isError) = ('Enter an intent action.', true));
              return;
            }
            try {
              final r = await api.launch(
                action: action,
                data: _orNull(_data),
                package: _orNull(_package),
                display: int.tryParse(_display.text.trim()) ?? 0,
              );
              if (mounted) setState(() => (_result, _isError) = (r.text, r.isErr));
            } on HuskException catch (e) {
              if (mounted) setState(() => (_result, _isError) = (e.message, true));
            }
          },
        ),
      ),
      if (_result != null) ...[const SizedBox(height: 16), ResultBox(_result!, isError: _isError)],
    ]);
  }
}
```

- [ ] **Step 6: Implement the Tools tab and wire it in**

`lib/features/tools/tools_tab.dart`:
```dart
import 'package:flutter/material.dart';

import 'inspect_tool.dart';
import 'launch_tool.dart';

enum ToolPage {
  inspect('Inspect', Icons.manage_search),
  launch('Launch', Icons.open_in_new);

  const ToolPage(this.label, this.icon);

  final String label;
  final IconData icon;
}

class ToolsTab extends StatefulWidget {
  const ToolsTab({super.key, required this.serverId});

  final String serverId;

  @override
  State<ToolsTab> createState() => _ToolsTabState();
}

class _ToolsTabState extends State<ToolsTab> {
  ToolPage _selected = ToolPage.inspect;

  Widget _page(ToolPage page) => switch (page) {
        ToolPage.inspect => InspectTool(serverId: widget.serverId),
        ToolPage.launch => LaunchTool(serverId: widget.serverId),
      };

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
        if (constraints.maxWidth >= 840) {
          return Row(children: [
            SizedBox(
              width: 220,
              child: ListView(children: [
                for (final page in ToolPage.values)
                  ListTile(
                    leading: Icon(page.icon),
                    title: Text(page.label),
                    selected: page == _selected,
                    onTap: () => setState(() => _selected = page),
                  ),
              ]),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: _page(_selected)),
          ]);
        }
        return ListView(children: [
          for (final page in ToolPage.values)
            ListTile(
              leading: Icon(page.icon),
              title: Text(page.label),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => Scaffold(appBar: AppBar(title: Text(page.label)), body: _page(page)),
              )),
            ),
        ]);
      });
}
```

In `lib/features/device/device_shell.dart`:
- Add the import `import '../tools/tools_tab.dart';`.
- Replace `DeviceTab.tools => const _TabPlaceholder('Tools'),` with `DeviceTab.tools => ToolsTab(serverId: widget.serverId),`.
- Delete the now-unused `_TabPlaceholder` class.

- [ ] **Step 7: Run tests and analyze**

Run: `flutter test && flutter analyze`
Expected: `All tests passed!` and `No issues found!`

- [ ] **Step 8: Manual check against the test phone**

On the Tools tab:
1. Inspect: **Dump** shows the accessibility tree. Find `Settings` (or a visible label) and **Tap here** opens it.
2. Launch: the **Settings** preset opens Settings on the phone.
3. Press Home afterwards.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat: add tools tab with inspect and launch

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_018vGW2sL6yV3eTZKrrtJar3"
```

---

### Task 22: Tools: Motion alarm, Management, RPC console, Access token

**Files:**
- Create: `lib/features/tools/tools_providers.dart`, `lib/features/tools/motion_tool.dart`, `lib/features/tools/management_tool.dart`, `lib/features/tools/rpc_tool.dart`, `lib/features/tools/token_tool.dart`
- Modify: `lib/features/tools/tools_tab.dart`
- Test: `test/features/tools/motion_tool_test.dart`, `test/features/tools/management_tool_test.dart`, `test/features/tools/rpc_tool_test.dart`, `test/features/tools/token_tool_test.dart`

**Interfaces:**
- Consumes:
  - `HuskApi.motion/setMotion/events/wd/pair/devOptions/rpc/setToken` (Tasks 6–7)
  - `isValidNewToken`, `generateToken` (Task 10)
  - `confirm` (Task 13)
  - `requestTokenForServer` (Task 14)
  - `serversProvider`, `serverByIdProvider`, `apiProvider` (Task 12)
  - `SectionCard`, `AsyncSection`, `InfoRow` (Task 17)
  - `ResultBox` (Task 21)
- Produces:
  - `motionProvider`, `eventsProvider` (autoDispose family futures)
  - `final rpcConfirmedProvider = NotifierProvider<RpcConfirmed, bool>` (session-scoped; `confirm()`)
  - `MotionTool`, `ManagementTool`, `RpcTool`, `TokenTool`
  - `ToolPage` values `motion`, `management`, `rpc`, `token`

- [ ] **Step 1: Write failing tests**

`test/features/tools/motion_tool_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/api/models/tools_models.dart';
import 'package:huskconfig/features/servers/api_provider.dart';
import 'package:huskconfig/features/tools/motion_tool.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/fixtures.dart';
import '../../support/mocks.dart';
import '../../support/test_app.dart';

void main() {
  late MockHuskApi api;

  setUp(() {
    api = MockHuskApi();
    when(() => api.motion()).thenAnswer((_) async =>
        const MotionConfig(enabled: false, ntfyServer: 'https://ntfy.sh', ntfyTopic: '', sensitivity: 5, lastNtfy: ''));
    when(() => api.events()).thenAnswer((_) async => [MotionEvent(time: DateTime(2026, 10, 7, 12), source: 'camera', change: 12.5)]);
    when(() => api.setMotion(
          enabled: any(named: 'enabled'),
          topic: any(named: 'topic'),
          server: any(named: 'server'),
          sensitivity: any(named: 'sensitivity'),
        )).thenAnswer((_) async {});
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(testScope(
      servers: [server1],
      overrides: [apiProvider.overrideWith((ref, id) => api)],
      child: const MaterialApp(home: Scaffold(body: MotionTool(serverId: 's1'))),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('loads config and events, saves changes', (tester) async {
    await pump(tester);
    expect(find.text('12.5 % change'), findsOneWidget);
    await tester.tap(find.widgetWithText(SwitchListTile, 'Motion alarm'));
    await tester.enterText(find.widgetWithText(TextField, 'ntfy topic'), 'my-topic');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    verify(() => api.setMotion(enabled: true, topic: 'my-topic', server: 'https://ntfy.sh', sensitivity: 5)).called(1);
  });

  testWidgets('rejects a non-https ntfy server', (tester) async {
    await pump(tester);
    await tester.enterText(find.widgetWithText(TextField, 'ntfy server'), 'http://ntfy.local');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Only https:// servers are accepted.'), findsOneWidget);
    verifyNever(() => api.setMotion(
          enabled: any(named: 'enabled'),
          topic: any(named: 'topic'),
          server: any(named: 'server'),
          sensitivity: any(named: 'sensitivity'),
        ));
  });
}
```

`test/features/tools/management_tool_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/api/models/tools_models.dart';
import 'package:huskconfig/features/servers/api_provider.dart';
import 'package:huskconfig/features/tools/management_tool.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/fixtures.dart';
import '../../support/mocks.dart';
import '../../support/test_app.dart';

void main() {
  testWidgets('Wireless Debugging needs confirmation and shows the adb command', (tester) async {
    final api = MockHuskApi();
    when(() => api.wd()).thenAnswer((_) async => const WdInfo(ip: '192.168.0.106', port: 37123, ipport: '192.168.0.106:37123'));
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(testScope(
      servers: [server1],
      overrides: [apiProvider.overrideWith((ref, id) => api)],
      child: const MaterialApp(home: Scaffold(body: ManagementTool(serverId: 's1'))),
    ));

    await tester.tap(find.text('Enable Wireless Debugging'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    verifyNever(() => api.wd());

    await tester.tap(find.text('Enable Wireless Debugging'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Enable'));
    await tester.pumpAndSettle();
    verify(() => api.wd()).called(1);
    expect(find.text('adb connect 192.168.0.106:37123'), findsOneWidget);
  });
}
```

`test/features/tools/rpc_tool_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/features/servers/api_provider.dart';
import 'package:huskconfig/features/tools/rpc_tool.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/fixtures.dart';
import '../../support/mocks.dart';
import '../../support/test_app.dart';

void main() {
  testWidgets('confirms once per session, then sends directly', (tester) async {
    final api = MockHuskApi();
    when(() => api.rpc(any())).thenAnswer((_) async => 'pong');
    await tester.pumpWidget(testScope(
      servers: [server1],
      overrides: [apiProvider.overrideWith((ref, id) => api)],
      child: const MaterialApp(home: Scaffold(body: RpcTool(serverId: 's1'))),
    ));

    final field = find.widgetWithText(TextField, 'Command');
    await tester.enterText(field, 'ping');
    await tester.tap(find.widgetWithText(FilledButton, 'Send'));
    await tester.pumpAndSettle();
    expect(find.text('Send raw commands?'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('pong'), findsOneWidget);

    await tester.enterText(field, 'ping');
    await tester.tap(find.widgetWithText(FilledButton, 'Send'));
    await tester.pumpAndSettle();
    expect(find.text('Send raw commands?'), findsNothing);
    verify(() => api.rpc('ping')).called(2);
  });
}
```

`test/features/tools/token_tool_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/api/husk_exception.dart';
import 'package:huskconfig/features/servers/api_provider.dart';
import 'package:huskconfig/features/tools/token_tool.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/fixtures.dart';
import '../../support/memory_repos.dart';
import '../../support/mocks.dart';
import '../../support/test_app.dart';

void main() {
  late MockHuskApi api;
  late MemoryServerRepository repo;

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(testScope(
      serverRepo: repo,
      overrides: [apiProvider.overrideWith((ref, id) => api)],
      child: const MaterialApp(home: Scaffold(body: TokenTool(serverId: 's1'))),
    ));
  }

  setUp(() {
    api = MockHuskApi();
    repo = MemoryServerRepository([server1.copyWith(token: 'O' * 32)]);
  });

  testWidgets('rejects an invalid new token without calling the phone', (tester) async {
    await pump(tester);
    await tester.enterText(find.widgetWithText(TextField, 'New token'), 'short');
    await tester.tap(find.widgetWithText(FilledButton, 'Change token'));
    await tester.pumpAndSettle();
    expect(find.text('The new token must be 24–128 letters and digits.'), findsOneWidget);
    verifyNever(() => api.setToken(any()));
  });

  testWidgets('a confirmed change updates the phone and the saved token', (tester) async {
    when(() => api.setToken('N' * 32)).thenAnswer((_) async {});
    await pump(tester);
    await tester.enterText(find.widgetWithText(TextField, 'New token'), 'N' * 32);
    await tester.tap(find.widgetWithText(FilledButton, 'Change token'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Change token').last);
    await tester.pumpAndSettle();
    verify(() => api.setToken('N' * 32)).called(1);
    expect(repo.saved.single.token, 'N' * 32);
    expect(find.text('Token changed and saved.'), findsOneWidget);
  });

  testWidgets('409 explains that no token is set', (tester) async {
    when(() => api.setToken(any())).thenThrow(HttpStatusException(409, '{"error":"no token set; use /token/request"}'));
    await pump(tester);
    await tester.enterText(find.widgetWithText(TextField, 'New token'), 'N' * 32);
    await tester.tap(find.widgetWithText(FilledButton, 'Change token'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Change token').last);
    await tester.pumpAndSettle();
    expect(find.text('No token is set on the phone. Use Request token instead.'), findsOneWidget);
    expect(repo.saved.single.token, 'O' * 32);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/tools`
Expected: FAIL, missing files.

- [ ] **Step 3: Implement the providers**

`lib/features/tools/tools_providers.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/models/tools_models.dart';
import '../servers/api_provider.dart';

final motionProvider = FutureProvider.autoDispose.family<MotionConfig, String>((ref, id) => ref.watch(apiProvider(id)).motion());

final eventsProvider = FutureProvider.autoDispose.family<List<MotionEvent>, String>((ref, id) => ref.watch(apiProvider(id)).events());

/// True once the user accepted the raw-command warning in this app session.
class RpcConfirmed extends Notifier<bool> {
  @override
  bool build() => false;

  void confirm() => state = true;
}

final rpcConfirmedProvider = NotifierProvider<RpcConfirmed, bool>(RpcConfirmed.new);
```

- [ ] **Step 4: Implement the Motion tool**

`lib/features/tools/motion_tool.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/husk_exception.dart';
import '../../core/api/models/tools_models.dart';
import '../../shared/widgets/section_card.dart';
import '../servers/api_provider.dart';
import 'tools_providers.dart';

class MotionTool extends ConsumerStatefulWidget {
  const MotionTool({super.key, required this.serverId});

  final String serverId;

  @override
  ConsumerState<MotionTool> createState() => _MotionToolState();
}

class _MotionToolState extends ConsumerState<MotionTool> {
  final _server = TextEditingController();
  final _topic = TextEditingController();
  bool _enabled = false;
  double _sensitivity = 5;
  bool _loaded = false;
  bool _saving = false;
  String? _serverError;

  @override
  void dispose() {
    _server.dispose();
    _topic.dispose();
    super.dispose();
  }

  void _load(MotionConfig config) {
    _loaded = true;
    _enabled = config.enabled;
    _server.text = config.ntfyServer;
    _topic.text = config.ntfyTopic;
    _sensitivity = config.sensitivity.clamp(1, 10).toDouble();
  }

  Future<void> _save() async {
    final server = _server.text.trim();
    if (!server.startsWith('https://')) {
      setState(() => _serverError = 'Only https:// servers are accepted.');
      return;
    }
    setState(() => (_serverError, _saving) = (null, true));
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(apiProvider(widget.serverId)).setMotion(
            enabled: _enabled,
            topic: _topic.text.trim(),
            server: server,
            sensitivity: _sensitivity.round(),
          );
      messenger.showSnackBar(const SnackBar(content: Text('Motion alarm saved')));
      _loaded = false;
      ref.invalidate(motionProvider(widget.serverId));
    } on HuskException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.serverId;
    ref.watch(apiProvider(id));
    final config = ref.watch(motionProvider(id));
    final events = ref.watch(eventsProvider(id));
    final loaded = config.value;
    if (loaded != null && !_loaded) _load(loaded);

    return ListView(padding: const EdgeInsets.all(16), children: [
      SectionCard(
        title: 'Motion alarm',
        icon: Icons.motion_photos_on,
        child: AsyncSection(
          value: config,
          onRetry: () => ref.invalidate(motionProvider(id)),
          builder: (c) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Detects motion in the camera or screen feed and pushes a snapshot through ntfy.'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Motion alarm'),
              value: _enabled,
              onChanged: (v) => setState(() => _enabled = v),
            ),
            TextField(
              controller: _server,
              decoration: InputDecoration(labelText: 'ntfy server', helperText: 'Only https:// is accepted.', errorText: _serverError),
            ),
            TextField(
              controller: _topic,
              decoration: const InputDecoration(labelText: 'ntfy topic', helperText: 'Leave empty to only log events (no push).'),
            ),
            const SizedBox(height: 12),
            Text('Sensitivity: ${_sensitivity.round()} (10 = most sensitive)'),
            Slider(value: _sensitivity, min: 1, max: 10, divisions: 9, onChanged: (v) => setState(() => _sensitivity = v)),
            if (c.lastNtfy.isNotEmpty) InfoRow('Last push', c.lastNtfy),
            const SizedBox(height: 8),
            FilledButton(onPressed: _saving ? null : _save, child: const Text('Save')),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      SectionCard(
        title: 'Recent events',
        icon: Icons.history,
        trailing: IconButton(tooltip: 'Refresh events', icon: const Icon(Icons.refresh), onPressed: () => ref.invalidate(eventsProvider(id))),
        child: AsyncSection(
          value: events,
          onRetry: () => ref.invalidate(eventsProvider(id)),
          builder: (list) => list.isEmpty
              ? const Text('No motion events yet.')
              : Column(children: [
                  for (final e in list)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(e.source == 'camera' ? Icons.videocam : Icons.smartphone),
                      title: Text('${e.change.toStringAsFixed(1)} % change'),
                      subtitle: Text('${e.source} · ${e.time.toLocal().toString().substring(0, 19)}'),
                    ),
                ]),
        ),
      ),
    ]);
  }
}
```

- [ ] **Step 5: Implement the Management tool**

`lib/features/tools/management_tool.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/husk_exception.dart';
import '../../shared/widgets/confirm_dialog.dart';
import '../../shared/widgets/result_box.dart';
import '../../shared/widgets/section_card.dart';
import '../servers/api_provider.dart';

class ManagementTool extends ConsumerStatefulWidget {
  const ManagementTool({super.key, required this.serverId});

  final String serverId;

  @override
  ConsumerState<ManagementTool> createState() => _ManagementToolState();
}

class _ManagementToolState extends ConsumerState<ManagementTool> {
  Widget? _wdResult;
  Widget? _pairResult;
  Widget? _devResult;
  bool _probeOnly = true;

  Future<Widget> _guard(Future<Widget> Function() action) async {
    try {
      return await action();
    } on HuskException catch (e) {
      return ResultBox(e.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = ref.watch(apiProvider(widget.serverId));
    return ListView(padding: const EdgeInsets.all(16), children: [
      SectionCard(
        title: 'Wireless Debugging',
        icon: Icons.adb,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text("Re-enables Wireless Debugging through the phone's Settings and returns its address (Android 11+)."),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () async {
              final ok = await confirm(
                context,
                title: 'Enable Wireless Debugging?',
                message: "Husk will open Settings on the phone and toggle Wireless Debugging with accessibility. The phone's screen will change while this runs.",
                confirmLabel: 'Enable',
              );
              if (!ok) return;
              final result = await _guard(() async {
                final wd = await api.wd();
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  InfoRow('Address', wd.ipport),
                  _CopyCommand('adb connect ${wd.ipport}'),
                ]);
              });
              if (mounted) setState(() => _wdResult = result);
            },
            child: const Text('Enable Wireless Debugging'),
          ),
          ?_wdResult,
        ]),
      ),
      const SizedBox(height: 12),
      SectionCard(
        title: 'Pair',
        icon: Icons.link,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Starts Wireless Debugging pairing and returns the pairing address and code (Android 11+).'),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () async {
              final ok = await confirm(
                context,
                title: 'Start pairing?',
                message: 'Husk will open the Wireless Debugging pairing dialog on the phone.',
                confirmLabel: 'Start',
              );
              if (!ok) return;
              final result = await _guard(() async {
                final pair = await api.pair();
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  InfoRow('Address', pair.addr),
                  InfoRow('Code', pair.code),
                  _CopyCommand('adb pair ${pair.addr} ${pair.code}'),
                ]);
              });
              if (mounted) setState(() => _pairResult = result);
            },
            child: const Text('Start pairing'),
          ),
          ?_pairResult,
        ]),
      ),
      const SizedBox(height: 12),
      SectionCard(
        title: 'Developer options',
        icon: Icons.developer_mode,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text("Probe only (navigate, don't tap Build number)"),
            value: _probeOnly,
            onChanged: (v) => setState(() => _probeOnly = v ?? true),
          ),
          OutlinedButton(
            onPressed: () async {
              final probe = _probeOnly;
              final ok = await confirm(
                context,
                title: probe ? 'Check Developer options?' : 'Unlock Developer options?',
                message: probe
                    ? 'Husk will open Settings › About phone on the phone.'
                    : 'Husk will open Settings › About phone and tap Build number until Developer options are enabled.',
                confirmLabel: probe ? 'Check' : 'Unlock',
              );
              if (!ok) return;
              final result = await _guard(() async {
                final r = await api.devOptions(probe: probe);
                return ResultBox(r.text, isError: r.isErr);
              });
              if (mounted) setState(() => _devResult = result);
            },
            child: const Text('Run'),
          ),
          ?_devResult,
        ]),
      ),
    ]);
  }
}

class _CopyCommand extends StatelessWidget {
  const _CopyCommand(this.command);

  final String command;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: SelectableText(command, style: const TextStyle(fontFamily: 'monospace'))),
        IconButton(
          tooltip: 'Copy',
          icon: const Icon(Icons.copy),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: command));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
          },
        ),
      ]);
}
```

- [ ] **Step 6: Implement the RPC console**

`lib/features/tools/rpc_tool.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/husk_exception.dart';
import '../../shared/widgets/confirm_dialog.dart';
import '../servers/api_provider.dart';
import 'tools_providers.dart';

/// Vocabulary of the a11y engine on port 8127 (from the API description).
const _vocabulary = [
  ('ping', 'Check that the engine is alive'),
  ('displays', 'List displays'),
  ('rotation 0', 'rotation D'),
  ('tap 540 1000 0', 'tap X Y D [ms]'),
  ('swipe 540 1500 540 500 0 300', 'swipe X1 Y1 X2 Y2 D [ms]'),
  ('dump 0', 'dump D: accessibility tree'),
  ('find 0 Settings', 'find|click|state|gettext D <regex>'),
  ('launch 0 android.settings.SETTINGS', 'launch D <action> [data] [pkg]'),
  ('scroll 0', 'scroll D [b]'),
  ('global home', 'global <name>'),
  ('devoptions probe', 'devoptions [probe]'),
  ('text hello', 'text <string>'),
  ('enter', 'Press Enter in the focused field'),
  ('wake', 'Wake the screen'),
];

class RpcTool extends ConsumerStatefulWidget {
  const RpcTool({super.key, required this.serverId});

  final String serverId;

  @override
  ConsumerState<RpcTool> createState() => _RpcToolState();
}

class _RpcToolState extends ConsumerState<RpcTool> {
  final _command = TextEditingController();
  final _history = <({String command, String reply, bool isError})>[];
  bool _busy = false;

  @override
  void dispose() {
    _command.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final command = _command.text.trim();
    if (command.isEmpty) return;
    if (!ref.read(rpcConfirmedProvider)) {
      final ok = await confirm(
        context,
        title: 'Send raw commands?',
        message: "Raw commands go straight to Husk's accessibility engine and can tap, type and launch anything on the phone.",
      );
      if (!ok) return;
      ref.read(rpcConfirmedProvider.notifier).confirm();
    }
    setState(() => _busy = true);
    ({String command, String reply, bool isError}) entry;
    try {
      final reply = await ref.read(apiProvider(widget.serverId)).rpc(command);
      entry = (command: command, reply: reply.trim(), isError: reply.trim().startsWith('ERR'));
    } on HuskException catch (e) {
      entry = (command: command, reply: e.message, isError: true);
    }
    if (!mounted) return;
    setState(() {
      _history.insert(0, entry);
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(apiProvider(widget.serverId));
    final scheme = Theme.of(context).colorScheme;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        Expanded(
          child: TextField(
            controller: _command,
            style: const TextStyle(fontFamily: 'monospace'),
            decoration: const InputDecoration(labelText: 'Command', hintText: 'ping'),
            onSubmitted: (_) => _send(),
          ),
        ),
        const SizedBox(width: 12),
        FilledButton(onPressed: _busy ? null : _send, child: const Text('Send')),
      ]),
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: const Text('Command reference'),
        children: [
          for (final (syntax, description) in _vocabulary)
            ListTile(
              dense: true,
              title: Text(syntax, style: const TextStyle(fontFamily: 'monospace')),
              subtitle: Text(description),
              onTap: () => _command.text = syntax,
            ),
        ],
      ),
      for (final entry in _history)
        Card(
          child: ListTile(
            title: Text('> ${entry.command}', style: const TextStyle(fontFamily: 'monospace')),
            subtitle: SelectableText(
              entry.reply,
              style: TextStyle(fontFamily: 'monospace', color: entry.isError ? scheme.error : null),
            ),
          ),
        ),
    ]);
  }
}
```

- [ ] **Step 7: Implement the Token tool**

`lib/features/tools/token_tool.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/husk_exception.dart';
import '../../core/api/token_rules.dart';
import '../../shared/widgets/confirm_dialog.dart';
import '../../shared/widgets/result_box.dart';
import '../../shared/widgets/section_card.dart';
import '../servers/api_provider.dart';
import '../servers/servers_controller.dart';
import '../servers/token_request_dialog.dart';

class TokenTool extends ConsumerStatefulWidget {
  const TokenTool({super.key, required this.serverId});

  final String serverId;

  @override
  ConsumerState<TokenTool> createState() => _TokenToolState();
}

class _TokenToolState extends ConsumerState<TokenTool> {
  final _newToken = TextEditingController();
  bool _show = false;
  String? _message;
  bool _isError = false;

  @override
  void dispose() {
    _newToken.dispose();
    super.dispose();
  }

  void _report(String message, {bool error = false}) => setState(() => (_message, _isError) = (message, error));

  Future<void> _change() async {
    final token = _newToken.text.trim();
    if (!isValidNewToken(token)) {
      _report('The new token must be 24–128 letters and digits.', error: true);
      return;
    }
    final ok = await confirm(
      context,
      title: "Change the phone's token?",
      message: 'Every client using the old token, including other apps, loses access until it is updated.',
      confirmLabel: 'Change token',
    );
    if (!ok) return;
    final api = ref.read(apiProvider(widget.serverId));
    try {
      await api.setToken(token);
      await ref.read(serversProvider.notifier).setToken(widget.serverId, token);
      _newToken.clear();
      if (mounted) _report('Token changed and saved.');
    } on HttpStatusException catch (e) {
      if (!mounted) return;
      _report(
        switch (e.statusCode) {
          409 => 'No token is set on the phone. Use Request token instead.',
          400 => 'The phone rejected the new token: ${e.message}',
          _ => e.message,
        },
        error: true,
      );
    } on UnauthorizedException {
      if (mounted) _report('The current token is invalid. Request a new one first.', error: true);
    } on HuskException catch (e) {
      if (mounted) _report(e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final server = ref.watch(serverByIdProvider(widget.serverId));
    ref.watch(apiProvider(widget.serverId));
    if (server == null) return const SizedBox.shrink();
    return ListView(padding: const EdgeInsets.all(16), children: [
      SectionCard(
        title: 'Current token',
        icon: Icons.key,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(server.hasToken
              ? 'A token is saved for this server (${server.token!.length} characters).'
              : 'No token saved. The phone may not have one set.'),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => requestTokenForServer(context, ref, widget.serverId),
            icon: const Icon(Icons.key),
            label: const Text('Request token'),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      SectionCard(
        title: 'Change token',
        icon: Icons.autorenew,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Sets a new token on the phone. Requires the current token and takes effect immediately.'),
          TextField(
            controller: _newToken,
            obscureText: !_show,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'New token',
              helperText: '24–128 letters and digits.',
              suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  tooltip: _show ? 'Hide' : 'Show',
                  icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _show = !_show),
                ),
                IconButton(
                  tooltip: 'Generate',
                  icon: const Icon(Icons.casino),
                  onPressed: () => setState(() => _newToken.text = generateToken()),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: _change, child: const Text('Change token')),
          if (_message != null) ...[const SizedBox(height: 12), ResultBox(_message!, isError: _isError)],
        ]),
      ),
    ]);
  }
}
```

- [ ] **Step 8: Register the new tool pages**

In `lib/features/tools/tools_tab.dart`, add these imports:
```dart
import 'management_tool.dart';
import 'motion_tool.dart';
import 'rpc_tool.dart';
import 'token_tool.dart';
```

Replace the enum values with:
```dart
  inspect('Inspect', Icons.manage_search),
  launch('Launch', Icons.open_in_new),
  motion('Motion alarm', Icons.motion_photos_on),
  management('Management', Icons.adb),
  rpc('RPC console', Icons.terminal),
  token('Access token', Icons.key);
```

Extend `_page`:
```dart
        ToolPage.motion => MotionTool(serverId: widget.serverId),
        ToolPage.management => ManagementTool(serverId: widget.serverId),
        ToolPage.rpc => RpcTool(serverId: widget.serverId),
        ToolPage.token => TokenTool(serverId: widget.serverId),
```

- [ ] **Step 9: Run tests and analyze**

Run: `flutter test && flutter analyze`
Expected: `All tests passed!` and `No issues found!`

- [ ] **Step 10: Manual check (read-only parts only)**

Against the test phone:
1. Motion alarm loads `enabled: false, https://ntfy.sh, sensitivity 5`. Do **not** save changes unless the user agrees.
2. The events list shows "No motion events yet."
3. RPC console: `ping` → `pong` (or the engine's reply), after the one-time confirmation.
4. Do **not** run Management actions or Change token here; they are in the user-approved checklist (Task 23).

- [ ] **Step 11: Commit**

```bash
git add -A
git commit -m "feat: add motion, management, RPC and token tools

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_018vGW2sL6yV3eTZKrrtJar3"
```

---

### Task 23: Final verification, manual checklist and README

**Files:**
- Create: `docs/manual-test-checklist.md`, `README.md` (replace the `flutter create` one)

**Interfaces:**
- Consumes: the whole app.
- Produces: a filled-in checklist with results, and run instructions.

- [ ] **Step 1: Run the full automated suite and builds**

Run:
```bash
flutter analyze && flutter test && flutter build macos --debug && flutter build apk --debug && flutter build ios --simulator --debug
```
Expected:
- `No issues found!`
- `All tests passed!`
- three `✓ Built …` lines

The Windows build needs a Windows machine (`flutter build windows`). Note it as **not run** if none is available.

- [ ] **Step 2: Write `README.md`**

```markdown
# Husk Config

Personal cross-platform manager (iOS, Android, Windows, macOS) for phones running
[Husk](https://xplat.co/husk). Talks directly to each phone's Husk HTTP API (default
port 8090) over LAN or Tailscale. All data is stored locally on this device.

## Run

    flutter pub get
    flutter run -d macos        # or: -d windows, an Android device id, an iOS device/simulator

## Add a phone

1. Open the Husk app on the phone and note its IP (the dashboard card shows it once added).
2. In Husk Config: **Add server** → IP address (IP only, Husk rejects hostnames) → port 8090 → **Test connection** → **Save**.
   Or use **Scan network** to find phones on your /24 subnet.
3. If the phone has a token, paste it, or use **Request token** and approve the notification on the phone.

## Features

- Dashboard of all phones with live status (polling interval in Settings).
- Overview: device, services, battery, connectivity, display, location, torch, vibrate, wake, brightness, ringer, volume, sensors, mic level.
- Camera: live MJPEG, snapshot, front/back, rotation, mirror, fps.
- Screen: live view with tap/swipe/scroll, Back/Home/Recents, text input. Modes: MJPEG, H.264 (where supported), Husk's web control page.
- Tools: inspect (find/click/dump), launch intents, motion alarm and events, Wireless Debugging/pair/developer options, raw RPC console, token change.

## Notes

- Screen view and web control need screen sharing enabled in the Husk app.
- Tokens are stored in plain text in this app's local preferences.
- Design spec: `docs/superpowers/specs/2026-10-07-husk-config-app-design.md`.
```

- [ ] **Step 3: Write `docs/manual-test-checklist.md`**

```markdown
# Manual test checklist: Husk Config

Device under test: `192.168.0.106:8090` (SM-A750F, Android 10, Husk 1.4).
Fill each line with ✅ / ❌ / n/a and a note. Platforms: macOS · Android · iOS · Windows.

## Safe (read-only or easily reverted)
- [ ] Launch with no servers shows the empty dashboard (Add server / Scan network)
- [ ] Add server by IP; a hostname is rejected; Test connection shows the model
- [ ] LAN scan finds 192.168.0.106 and marks it Saved
- [ ] Dashboard card shows online, battery, services; switching phone Wi-Fi off turns it Offline within one poll interval
- [ ] App in background pauses polling (no requests in phone log); resumes on return
- [ ] Settings: theme, polling interval (Off stops auto refresh), default screen mode, client name
- [ ] Overview cards load; Location shows the phone's ERR message or a position
- [ ] Wake, vibrate, torch on/off work
- [ ] Brightness slider (or WRITE_SETTINGS hint); restore previous level
- [ ] Camera stream + snapshot + save; front/back switch (restore Front)
- [ ] Screen (screen sharing on): MJPEG view, tap, swipe, wheel scroll, Back/Home/Recents, Esc, text + Enter
- [ ] Landscape: rotate the phone, check taps still land where clicked
- [ ] Screen: H.264 mode (on platforms in `h264Platforms`), fallback message elsewhere
- [ ] Screen: Web control loads /control and /controlhw
- [ ] Screenshot saves; stream quality applies; fullscreen opens/closes
- [ ] Tools: Inspect dump/find/tap here; Launch Settings preset
- [ ] Tools: Motion config and events load (no save)
- [ ] Tools: RPC `ping` after one-time confirmation

## Changes phone state: ONLY with the user's explicit OK
- [ ] Request token (this SETS a token on a phone that has none; record it)
- [ ] Change token (requires a token to exist)
- [ ] Motion alarm save (restore enabled=false, topic empty afterwards)
- [ ] Wireless Debugging (/wd), Pair (/pair), Developer options probe (/devoptions?probe=1)
- [ ] Ringer mode change (restore `silent`)
```

- [ ] **Step 4: Execute the checklist**

Run `flutter run -d macos` (plus Android if available) and go through every **Safe** item, recording results in the file.

For the second section, **ask the user** before each item and run only the ones they approve. Record "skipped (not approved)" for the rest.

- [ ] **Step 5: Commit**

```bash
git add README.md docs/manual-test-checklist.md
git commit -m "docs: add README and manual test checklist with results

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_018vGW2sL6yV3eTZKrrtJar3"
```

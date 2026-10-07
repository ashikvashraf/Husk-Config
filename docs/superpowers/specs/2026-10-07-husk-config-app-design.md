# Husk Config — Design Spec

- **Date:** 2026-10-07
- **Status:** Approved in brainstorming; pending written-spec review
- **Source API:** `husk-openapi-json.json` (Husk Device API 1.4)
- **Test device:** `http://192.168.0.106:8090` (Samsung SM-A750F, Android 10, Husk 1.4, no token configured)

## 1. Purpose and scope

A **personal** cross-platform management app for controlling and monitoring the user's own Android phones running the Husk app (https://xplat.co/husk). It talks directly to each phone's Husk HTTP API over LAN or Tailscale.

**Platforms:** iOS, Android, Windows, macOS. Dev builds only (no store signing).

**v1 covers all API areas:** status & hardware, camera, screen view + remote control, advanced tools (inspection, launch, motion alarm, Wireless Debugging/pair/devoptions, raw RPC, token management).

**Out of scope for v1:** cloud/back-end sync, store signing and metadata, localization (English only), saved snapshot/command history, cached device data, in-app push notifications.

## 2. Decisions

| Topic | Decision |
|---|---|
| App name / bundle id | "Husk Config" / `com.ava.huskconfig` (`flutter create --org com.ava --project-name huskconfig`) |
| State management | Riverpod (`flutter_riverpod`) |
| Routing | `go_router` |
| HTTP | `dio`, hand-written typed client (approach A) |
| Storage | Plain local: `shared_preferences` JSON behind repository interfaces. Tokens stored in plain text (user choice). |
| UI | Material 3, light/dark/system; adaptive: NavigationRail on desktop/tablet, bottom NavigationBar on phone |
| Language | English only, no i18n setup |
| Launch screen | Dashboard of all saved servers with live status |
| Adding servers | Manual entry + LAN /24 scan |
| Token | Manual field + phone-approval request flow |
| Screen view | Three switchable modes: native MJPEG, H.264 via `media_kit`, Husk web control page via `flutter_inappwebview` |
| Confirmations | Only for `/devoptions`, `/wd`, `/pair`, `/token/set`, `/rpc` (first use per session) |

## 3. API facts that shape the design

- All endpoints are `GET` with query parameters. Token is the `token` query parameter, required only if the device has one configured. `/healthz`, `/`, `/token/request`, `/token/status` never need it.
- The server requires the `Host` header to be an **IP literal** (or localhost); hostnames are rejected. The app therefore only accepts IP addresses.
- Default port 8090; servers are plain HTTP.
- Many accessibility endpoints return `text/plain` with `OK`, `NONE`, or `ERR …` bodies under HTTP 200. These are results, not transport errors.
- Camera and screen streams are MJPEG (`multipart/x-mixed-replace`); `/screen.mp4` is live fragmented MP4 (H.264).
- `/snapshot` returns 503 until the lazy camera has a frame; `/screen.jpg` returns 503 if screen sharing is off.
- Token request: `/token/request` → `{id, expires_in:120}` (429 if another request is pending, 503 if notifications are disabled); poll `/token/status?id=` → `pending | denied | expired | approved{token}`. The token is delivered exactly once.
- `/token/set?new=` requires the current token; 401 invalid token, 409 no token set, 400 invalid `new` (alphanumeric, 24–128 chars).

### 3.1 Observed on the test device (2026-10-07)

- `/location` → `ERR no-fix (no known position; is location turned on?)` as `text/plain`, HTTP 200.
- `/display` → `rotation` is a **string** (`"0"`); `refreshHz` is a double.
- `/displays` → plain text `0:0` (one `id:state` line per display).
- `/volume` read → `{"media":{"level":0,"max":15},…,"call":{"level":4,"max":5}}`; `/sensors` → array of `{name,type(int),vendor,power,max}`.
- `/token/set` without a token → HTTP 409 `{"error":"no token set; use /token/request"}`; unknown path → HTTP 404 `not found`.
- `/stream` → `multipart/x-mixed-replace; boundary=rigframe`, parts are `--rigframe\r\nContent-Type: image/jpeg\r\nContent-Length: N\r\n\r\n<jpeg>`; HTTP/1.0, `Connection: close`.

## 4. Architecture

```
UI (screens/widgets)        ← Material 3 adaptive shell
  ↓ watches
Riverpod providers           ← per-feature controllers (AsyncNotifier / StreamProvider)
  ↓ calls
Services                     ← HuskApi (dio), MjpegStream, LanScanner, TokenRequestFlow
  ↓ uses
Storage                      ← ServerRepository, SettingsRepository (shared_preferences JSON)
```

Dependencies point downward only. The UI never calls `dio` directly.

### 4.1 Folder layout (`lib/`)

```
main.dart, app.dart                  # ProviderScope, MaterialApp.router, theme, MediaKit.ensureInitialized()
core/
  api/husk_api.dart                  # one method per endpoint, token injection, error mapping
  api/husk_exception.dart            # sealed: Offline, Unauthorized, HttpStatusError(code, body), DeviceError(message)
  api/models/                        # DeviceInfo, Flags, Battery, Connectivity, DisplayInfo, Location,
                                     # MicLevel, Sensor, SensorReading, Volumes, MotionConfig,
                                     # MotionEvent, WdInfo, PairInfo, TokenRequest, TokenStatus
  stream/mjpeg_stream.dart           # multipart/x-mixed-replace parser → Stream<Uint8List>
  net/lan_scanner.dart               # /24 probe of :port/healthz
  net/ip_validator.dart              # IP literal validation + base URL building
  storage/server_repository.dart
  storage/settings_repository.dart
  router.dart
features/
  dashboard/
  servers/        # add/edit form, scan screen, token request dialog
  device/         # device shell + Overview tab (status & hardware)
  camera/
  screen/         # mjpeg_mode, h264_mode, webview_mode, gesture layer, coordinate mapper
  tools/          # inspect, launch, motion, management, rpc, token
  settings/
shared/widgets/   # StatusDot, BatteryIndicator, ServiceChip, ConfirmDialog, ResultBox, MjpegView, SectionCard
```

### 4.2 Packages

`flutter_riverpod`, `go_router`, `dio`, `shared_preferences`, `uuid`, `media_kit`, `media_kit_video`, `media_kit_libs_video`, `flutter_inappwebview`, `network_info_plus`, `file_selector` (desktop save), `share_plus` (mobile share), `url_launcher` (open maps), `package_info_plus` (About version). Dev: `flutter_test`, `mocktail`, and a small hand-written fake `HttpClientAdapter` for dio tests (no extra mock-adapter package).

### 4.3 Data model (persisted)

```dart
ServerConfig {
  String id;            // uuid v4
  String name;
  String host;          // IPv4 or IPv6 literal, no brackets stored
  int port;             // default 8090
  String? token;        // plain text
  DateTime createdAt;
  DateTime? lastUsedAt;
}
// baseUrl = 'http://$host:$port', IPv6 → 'http://[$host]:$port'

AppSettings {
  ThemeMode themeMode;          // default system
  int pollIntervalSeconds;      // 0 = off; options 5/10/30/60; default 10
  ScreenMode defaultScreenMode; // mjpeg | h264 | webview; default mjpeg
  String tokenClientName;       // default "Husk Config"; [A-Za-z0-9 ._-], ≤32 chars
}
```

Stored as JSON under the `servers.v1` and `settings.v1` keys in `shared_preferences`. `ServerRepository` / `SettingsRepository` are abstract interfaces, so the storage backend can be swapped later.

### 4.4 Error handling

- `HuskApi` throws a `HuskException`:
  - `Offline`: connection refused or timeout; connect timeout 3 s, receive timeout 10 s for non-stream calls.
  - `Unauthorized`: 401.
  - `HttpStatusError(code, body)`: any other non-2xx status; the message is taken from a JSON `{"error": …}` body when present.
  - `DeviceError(message)`: a JSON endpoint answered plain text such as `ERR no-fix …` under HTTP 200 (observed live on `/location`).
- Plain-text `ERR …` / `NONE` responses are returned as a `TextResult` (raw string plus `isOk` / `isNone` / `isErr` helpers) and displayed, not thrown.
- UI messages:
  - 401: "Token missing or invalid. Edit the server or request a token."
  - Offline: "Can't reach <ip:port>."
- Every card or section loads and fails independently; one failing endpoint never blanks a page.
- Tokens are never logged; dio logging, if enabled in debug, redacts the `token` parameter.

## 5. Features

### 5.1 Dashboard (route `/`, launch screen)

- Responsive grid of server cards: 1 column on phone, 2–4 on desktop. Each card shows:
  - name and `ip:port`
  - status dot: online / offline / unauthorized
  - model and Android version
  - battery % with a charging icon
  - service chips (a11y, camera, screen)
  - "last seen" time
- `serverStatusProvider(serverId)` polls `/info` every `pollIntervalSeconds` while the dashboard is visible and the app is in the foreground (uses `AppLifecycleListener`). Pull-to-refresh and a refresh button force a poll. Interval 0 = manual only.
- Tap a card to open the device view. The card menu has Edit, Request token, and Delete (with confirmation).
- A FAB **Add server** opens the add flow.
- With no servers, a centered empty state offers **Add server** and **Scan network**.

### 5.2 Add / Edit server (routes `/servers/new`, `/servers/:id/edit`)

- Fields:
  - **Name:** optional; defaults to the device model after a successful test, else the IP.
  - **IP:** IPv4/IPv6 literal. A hostname shows the error "Husk only accepts IP addresses".
  - **Port:** 1–65535, default 8090.
  - **Token:** optional, with show/hide.
- **Test connection:** `/healthz`, then `/info` with the token. Shows the model, Android version, and Husk app version, or the exact error.
- **Request token:** opens the token request dialog (5.3).
- Saving a duplicate `host:port` shows a warning (user can still save).
- Can be prefilled from a scan result (query parameters).

### 5.3 Token request flow

1. `GET /token/request?client=<tokenClientName>`. Do not send `new`; the phone generates a token when it has none.
2. Dialog: "Approve on your phone…" with a 120 s countdown (from `expires_in`) and Cancel.
3. Poll `/token/status?id=` every 2 s:
   - `approved`: fill the token field (if called from the dashboard or Tools, save directly to the server) and close the dialog.
   - `denied`: show "Denied on the phone".
   - `expired`: show "Request expired".
4. Request errors:
   - 429: "Another request is pending on the phone."
   - 503: "Notifications are disabled on the phone."

Implemented as a `TokenRequestFlow` state machine (idle → requesting → pending(remaining) → approved / denied / expired / error) with an injectable clock and delay, so it is unit-testable.

### 5.4 LAN scan (route `/servers/scan`)

- `network_info_plus` provides the Wi-Fi IPv4. Scan its /24 (`.1`–`.254`, excluding self) on the scan port (default 8090, editable).
- `GET /healthz` with a 1 s timeout, about 32 probes at a time. A host matches if the body trimmed equals `ok`.
- Results stream into a list with a progress bar.
- For each match, try `/info` without a token to show the model; on 401, show "token required".
- Hosts that are already saved are labelled "Saved".
- Tap a result to open the Add form prefilled with IP and port.
- If no Wi-Fi IP is available (some desktops, VPN-only), let the user type a subnet prefix like `192.168.0`.

### 5.5 Settings (route `/settings`)

- Theme: system / light / dark.
- Dashboard polling interval: 5 / 10 / 30 / 60 s / off.
- Default screen view mode.
- Token client name, validated: `[A-Za-z0-9 ._-]`, ≤32 chars.
- **Manage servers:** list with edit, delete, add (reuses the 5.2 screens).
- About: app version.

### 5.6 Device shell (route `/device/:id/{overview|camera|screen|tools}`)

- Tabs: **Overview · Camera · Screen · Tools**. NavigationRail on wide layouts, bottom NavigationBar on narrow.
- App bar: server name, status dot, back to the dashboard, and a server switcher dropdown.
- Opening a device updates `lastUsedAt`.

### 5.7 Overview tab (status & hardware)

Cards (each loads independently; all load in parallel when the tab opens; pull-to-refresh refreshes all; flags and battery auto-refresh at the poll interval):

- **Device** (`/info`): app package and version, manufacturer/model, Android release and SDK, screen size, local IP, Tailscale IP (or "—"), DeX capable, has camera.
- **Services** (`/flags`): chips for a11y, camera, selected side (`front`), screen, motion, ntfy, batteryOptIgnored, dexReconnect; `lastNtfy` text. Note: "camera off = idle, not broken".
- **Battery** (`/battery`): level, charging, status, health, plugged, temperature °C, voltage mV, technology.
- **Connectivity** (`/connectivity`): connected, type, metered, validated.
- **Display** (`/display`): width × height, densityDpi, density, refresh Hz, rotation.
- **Location** (`/location`): lat/lon, accuracy, altitude, time, provider, and an "Open in maps" link via `url_launcher`. An `ERR` reply (e.g. `ERR no-fix (no known position; is location turned on?)`) is shown verbatim, since the phone's message names the actual cause.
- **Quick controls:**
  - Torch: switch, `/torch?on=1|0`; shows the error if the camera is busy.
  - Vibrate: ms field (1–10000, default 300) and a button, `/vibrate?ms=`.
  - Wake: `/wake`.
  - Brightness: slider 0–255 plus an auto indicator; read from `/brightness`, set on slider release with `/brightness?level=`. A `needs WRITE_SETTINGS` reply shows a hint.
  - Ringer: segmented normal / vibrate / silent, `/ringer?mode=`, with a hint that silent and vibrate may need DND access.
  - Volume: one slider per stream returned by `/volume` (level/max); set with `/volume?stream=&level=` on release.
- **Sensors:**
  - `/sensors` list.
  - A "Read" action per sensor type (accelerometer, gyroscope, magnetic, light, proximity, pressure, gravity, linear, rotation, temperature, humidity, stepcounter) → `/sensor?type=`, showing values. Optional 1 s auto-refresh toggle.
- **Mic level:** `/mic` sample button showing amplitude/max as a meter; optional 1 s live toggle.

### 5.8 Camera tab

- `MjpegView` on `/stream`:
  - FPS readout and a connecting/reconnecting overlay.
  - Exponential reconnect backoff (1 s → max 10 s).
  - The stream is cancelled when the tab is not visible or the app is backgrounded.
- **Snapshot:** `/snapshot`. On 503, retry once after 1 s. Shows the full image with **Save** (desktop: `file_selector` save dialog; mobile: `share_plus`).
- **Camera settings** (each change sends `/set`):
  - Side: front/back → `front=1|0`. On 409, show "This camera side doesn't exist on the device". The current side is read from `/flags.front`.
  - Rotation: 0 / 90 / 180 / 270 → `rot`.
  - Horizontal flip → `flip=1|0`.
  - FPS cap → `fps`.

### 5.9 Screen tab

**Toolbar:**
- Mode switcher: MJPEG / H.264 / Web control. The default comes from settings; the choice is remembered for the app session.
- Display picker from `/displays` (sets `d`).
- Fullscreen toggle.
- Screenshot (`/screen.jpg` → save/share).
- Quality: `sq` 1–100 and `sfps` 1–30 via `/set`.

**Before streaming:** read `/flags.screen`. If false, show the banner "Screen sharing is off. Enable it in the Husk app on the phone" with Retry.

**Controls** (MJPEG and H.264 modes):
- **Nav bar:** Back, Home, Recents, Notifications (`/key?k=back|home|recents|notifications`), Wake (`/wake`).
- **Keyboard panel:** text field with "Send text" (`/text?t=`; replaces the field's whole content, newlines stripped) and "Enter" (`/key?k=enter`). The `ERR ime-needs-api30` reply shows a hint.

**Gesture layer** (shared by MJPEG and H.264):
- Device size comes from `/display` (rotation-aware width/height).
- The video is rendered with `BoxFit.contain`. `CoordinateMapper` converts a local position to device pixels: `devX = (localX − offX) / renderedW × deviceW`, and the same for Y. Points in letterbox bars are ignored.
- Gesture → endpoint:
  - Tap: `/tap?x&y&d`.
  - Long-press: `/tap` with `ms=600`.
  - Drag: `/swipe?x1&y1&x2&y2&d&ms=<duration clamped 100–2000>`.
  - Mouse wheel: `/scroll?d&dir=fwd|back`.
  - Desktop keys while focused: Esc → back, Enter → enter.
- Input calls are fire-and-forget through a small serial queue. A failure shows a snackbar; `ERR cancelled` adds the hint "Screen may be off — press Wake".

**Mode details:**
- **MJPEG:** `MjpegView` on `/screen`, with the same reconnect and lifecycle rules as the camera.
- **H.264:** a `media_kit` `Player` opens `http://host:port/screen.mp4?token=…` with mpv low-latency options (`profile=low-latency`, `cache=no`, `untimed=yes`), rendered via `Video` with the gesture layer on top.
  - **This is the highest-risk item.** It is validated by an early spike against the test phone.
  - If it fails on a platform (error, or latency drifting > ~2 s), the mode shows "H.264 not supported on this platform — using MJPEG" and falls back.
- **Web control:** `flutter_inappwebview` loads `/control?token=…`, with a toggle to `/controlhw`. The app's nav bar, keyboard panel, and gesture layer are hidden in this mode. Windows requires the WebView2 runtime (present on Windows 10/11).

### 5.10 Tools tab

List on phone, master–detail on desktop.

- **Inspect:**
  - Regex field and display id; buttons:
    - Find (`/find` → "x y" or NONE, with "Tap here")
    - Exists (`/exists` → yes/no)
    - Get text (`/gettext`)
    - Click (`/click`)
  - Dump (`/dump`): monospace, searchable, copyable.
  - Scroll fwd/back (`/scroll`).
- **Launch:**
  - Fields: action, data, pkg, d.
  - Presets: `android.settings.SETTINGS`, `android.settings.WIFI_SETTINGS`, `android.settings.APPLICATION_DEVELOPMENT_SETTINGS`, and Open URL (`android.intent.action.VIEW` + data).
  - Raw result shown.
- **Motion alarm:**
  - Load `/motion`.
  - Form: enabled, ntfy server (https only, validated), topic (empty = log only), sensitivity. Save → `/motion?on&topic&server&sensitivity`.
  - Events list from `/events`: time, source, change %; refresh button. Shows `lastNtfy`.
- **Management** (each behind a ConfirmDialog):
  - `/wd`: `ip:port`, plus a copy button for `adb connect <ipport>`.
  - `/pair`: addr and code, plus a copy button for `adb pair <addr> <code>`.
  - `/devoptions`: with a "probe only" checkbox (`probe=1`).
- **RPC console:**
  - `/rpc?cmd=`; ConfirmDialog on first use per session.
  - Vocabulary cheat-sheet: `ping`, `displays`, `rotation D`, `tap X Y D [ms]`, `swipe X1 Y1 X2 Y2 D [ms]`, `dump D`, `find|click|state|gettext D <regex>`, `launch D <action> [data] [pkg]`, `scroll D [b]`, `global <name>`, `devoptions [probe]`, `text <string>`, `enter`, `wake`.
  - Scrollback in memory only.
- **Access token:**
  - **Change token:** `/token/set?new=`.
    - "Generate" button creates a 32-char alphanumeric token; client-side validation for 24–128 alphanumeric.
    - Behind a ConfirmDialog.
    - On success, update the stored token.
    - 409: "No token set — use Request token". 401: "Current token invalid".
  - **Request token:** the flow in 5.3.

All query parameters are passed via dio `queryParameters` (URL-encoded).

## 6. Platform configuration

- **Scaffold:** `flutter create --org com.ava --project-name huskconfig --platforms ios,android,windows,macos .`
- Display name "Husk Config" in all platform manifests.
- **Android:**
  - Permissions: `INTERNET` and `ACCESS_WIFI_STATE`.
  - `network_security_config.xml` with cleartext permitted.
  - `minSdk` raised as required by `media_kit` / `flutter_inappwebview`.
- **iOS:**
  - `NSAppTransportSecurity`: `NSAllowsLocalNetworking` = true and `NSAllowsArbitraryLoads` = true (Tailscale 100.x addresses are not "local").
  - `NSLocalNetworkUsageDescription`.
  - Location-when-in-use description, only if `network_info_plus` requires it for Wi-Fi IP.
- **macOS:**
  - `com.apple.security.network.client` and `com.apple.security.files.user-selected.read-write` (snapshot save dialog) in both `DebugProfile.entitlements` and `Release.entitlements`.
  - The same ATS keys as iOS.
- **Windows:** no special configuration; the WebView2 runtime is assumed.

## 7. Testing

**Unit tests** (TDD for logic units):
- `IpValidator` and base URL building: IPv4, IPv6 with brackets, rejects hostnames, port range.
- `ServerRepository` / `SettingsRepository` with `SharedPreferences.setMockInitialValues`.
- `HuskApi` with a fake dio adapter:
  - token injection (present/absent; never on `/healthz` and `/token/*`)
  - 401 → `Unauthorized`
  - 409 / 429 / 503 → `HttpStatusError`
  - timeouts → `Offline`
  - model parsing from real JSON samples captured from the test phone (`/info`, `/flags` already captured)
- `MjpegStream` parser: multipart fixtures, including frames split across chunks, multiple frames per chunk, and missing Content-Length.
- `CoordinateMapper`: letterboxing on both axes, out-of-bounds rejection, scale.
- `TokenRequestFlow`: fake clock covering approved / denied / expired / 429 / 503 / cancel.
- `LanScanner`: fake prober covering subnet derivation, concurrency, and match criteria.

**Widget tests:**
- Dashboard: empty state, online / offline / unauthorized cards.
- Add-server form validation.
- Token request dialog states.

**Manual integration checklist** against `192.168.0.106:8090`:
- Run on macOS and Android at minimum; iOS and Windows when devices are available.
- Cover:
  - every tab
  - LAN scan finds the phone
  - all three screen modes
  - camera stream, snapshot, and side switch
- State-changing management calls (`/devoptions`, `/wd`, `/pair`, `/token/set`) and `/token/request` (which would **set** a token on the currently token-less test phone) run only with the user's explicit OK.

## 8. Risks

| Risk | Mitigation |
|---|---|
| H.264 live fMP4 via media_kit may not play or may build latency | Early spike task; per-platform fallback to MJPEG with a message |
| MJPEG decode cost at high fps on low-end devices | `sfps`/`sq` controls; decode with `gaplessPlayback` `Image.memory`; drop frames if the previous one is still decoding |
| LAN scan blocked (iOS local network permission, desktop firewalls) | Permission string; manual subnet entry; manual add always available |
| WebView2 missing on older Windows | Error message with a link to install WebView2; other modes still work |
| Plain-text token storage | Explicit user choice for v1; the repository interface allows moving to secure storage later |

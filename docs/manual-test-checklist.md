# Manual test checklist: Husk Config

Status: PARTIALLY EXECUTED on macOS (2026-10-07), automated through `integration_test` on the real app and the real phone `192.168.0.106:8090` (screen sharing on). Not executed on Android, iOS or Windows. Items marked [x] passed on the real app against the real phone; every other item is FAIL, BLOCKED or NOT RUN, with the reason on its line. Items that need a human at the phone are listed under "Human-only items still open". The "Changes phone state" section was not approved and was not run.

Counts (27 integration items): 19 PASS, 4 FAIL (S10, S11, T20b, T20c), 2 BLOCKED (S12, S16), 2 NOT RUN (S15, S14-click).

## How the real-device run works
- Test files: `integration_test/device/NN_*_test.dart`, shared harness `integration_test/device/support/device_harness.dart`. Run with `flutter test integration_test/device/<file> -d macos`.
- The harness wraps the real network in a counting adapter and blocks every phone-changing request that is not on the approved list (`adapter.blocked` was empty in every reported run).
- Snapshots go to `build/device_checks/<file>/` (not committed). Evidence below is the `CHECK <id> ...` line each test prints.
- Phone state: the phone is on a SECURE lock screen (One UI keyguard, `/dump` shows only the Samsung Wallet hint, `/screen.jpg` shows black when swiped). Anything that needs a phone UI to react (Settings list, launcher) is blocked until a human unlocks it.

## Automated results (Task 23 Step 1, this machine, Xcode 27.0)
| Check | Result |
|---|---|
| `flutter analyze` | No issues found |
| `flutter test` | All tests passed (+200) |
| `flutter build macos --debug` | Built `build/macos/Build/Products/Debug/Husk Config.app` |
| `flutter build apk --debug` | Built `build/app/outputs/flutter-apk/app-debug.apk` |
| `flutter build ios --simulator --debug` | Built `build/ios/iphonesimulator/Runner.app` (iOS deployment target raised to 15.0). Build only: not launched on iOS. |
| `flutter build windows` | not run (no Windows machine) |
| Android on a device | not run (no adb device attached) |
| Real-device checklist on macOS | see below: 19 PASS, 4 FAIL, 2 BLOCKED, 2 NOT RUN |

Device under test: `192.168.0.106:8090` (samsung SM-A750F, Android 10, Husk 1.4). Platforms: macOS (run) · Android · iOS · Windows (not run).

## Safe (read-only or easily reverted)
Each line: the integration test file and test id, one line of evidence, and the earlier automated (fakes) test for reference.

- [x] Launch with no servers shows the empty dashboard (Add server / Scan network)
  - Real: PASS. `integration_test/device/01_servers_test.dart` "S01". Evidence: shows "No Husk servers yet" with Add server and Scan network, no 'Server actions' menu, 0 requests to the phone.
  - Fakes: `test/app_test.dart`.
- [x] Add server by IP; a hostname is rejected; Test connection shows the model
  - Real: PASS. `01_servers_test.dart` "S02". Evidence: `phone.local` rejected on Save and Test connection ("Husk only accepts IP addresses"); 192.168.0.106:8090 accepted; Test connection showed "Connected: samsung SM-A750F, Android 10, Husk 1.4" (equals /info); empty Name saved as card "samsung SM-A750F".
  - Fakes: `test/features/servers/server_form_screen_test.dart`.
- [x] LAN scan finds 192.168.0.106 and marks it Saved
  - Real: PASS. `01_servers_test.dart` "S03". Evidence: scan of 192.168.0.0/24 found .106, subtitle "samsung SM-A750F", 'Saved' chip, "Checked 253 of 253" in about 11 s; Wi-Fi IP auto-detected (192.168.0.123).
  - Fakes: `test/features/servers/scan_screen_test.dart`.
- [x] Dashboard card shows online, battery, services; an unreachable server turns Offline
  - Real: PASS. `01_servers_test.dart` "S04". Evidence: card Online, 100% and charging icon match /info, service chips match /info (a11y true, camera false, screen true); second server 192.0.2.1:8090 shows Offline "Can't reach 192.0.2.1:8090".
  - Not covered: real phone Wi-Fi-off timing (human-only, see below). An unreachable second server stands in for it.
  - Fakes: `test/features/dashboard/dashboard_test.dart`.
- [x] App in background pauses polling (no requests in phone log); resumes on return
  - Real: PASS. `integration_test/device/02_settings_polling_test.dart` "S05". Evidence: interval 5 s: foreground /info=3 in 12 s, hidden /info=0 in 12 s, after resume /info=3 in 12 s (counted by the adapter). Lifecycle sequence is resumed->inactive->hidden->inactive->resumed.
  - Fakes: `test/features/settings/settings_controller_test.dart`, `test/features/dashboard/server_status_test.dart`.
- [x] Settings: theme, polling interval (Off stops auto refresh), default screen mode, client name
  - Real: PASS. `02_settings_polling_test.dart` "S06". Evidence: Dark gives ThemeMode.dark and Brightness.dark; Off gives 0 /info in 12 s; `bad/name!` rejected; prefs `settings.v1` restored after relaunch (themeMode dark, pollIntervalSeconds 0, defaultScreenMode h264, tokenClientName "Husk Test_1.2").
  - Note: settings were left as the test last wrote them (theme dark, polling Off, default mode H.264); phoneRestored=false for this section, the app prefs of the test sandbox only.
  - Fakes: `test/features/settings/settings_screen_test.dart`, `test/core/polling_test.dart`.
- [x] Overview cards load; Location shows the phone's ERR message or a position
  - Real: PASS. `integration_test/device/03_overview_test.dart` "S07". Evidence: model, Android "10 (SDK 29)", battery 100% (probe 100), display 1080x2112, connectivity wifi equal the probe GETs; Location shows the phone's ERR "no-fix (no known position; is location turned on?)" verbatim with Retry.
  - Fakes: `test/features/device/overview_tab_test.dart`.
- [x] Wake, vibrate, torch on/off work
  - Real: PASS. `03_overview_test.dart` "S08". Evidence: "Screen woken for about 2 minutes", "OK (300ms)", torch "OK (on)" then "OK (off)"; exactly one /wake, one /vibrate?ms=300, /torch params ['1','0']; torch ends OFF.
  - Fakes: `test/features/device/overview_tab_test.dart` (vibrate had no fake test).
- [x] Brightness slider (or WRITE_SETTINGS hint); restore previous level
  - Real: PASS. `03_overview_test.dart` "S09". Evidence: level 85 -> 125 confirmed by GET /brightness, restored to exactly 85 ("OK (85/255)"). The WRITE_SETTINGS hint path was not exercised (the phone never showed it).
  - Note: in the first run, setting a level turned auto brightness OFF (auto before=true, after=false) and the test did not re-enable it. The phone's auto brightness may still be off.
  - Fakes: none.
- [x] Sensors: light reading shows values; Mic Sample shows an amplitude (extra check)
  - Real: PASS. `03_overview_test.dart` "S09b". Evidence: "CM36658 Light: 11.00" equals the probe; mic "0 / 32767" equals the probe; Live switches untouched.
- [ ] Camera stream + snapshot + save; front/back switch (restore Front)
  - Real: FAIL (intermittent product bug, see "Product bugs found"). `integration_test/device/04_camera_test.dart` "S10". Evidence: stream decodes frames at 8-9 fps and Snapshot dialog opens with Image + Save (Save not pressed); Back applies within 43-174 ms; but Front after Back failed in 2 of 4 conclusive runs (`/flags.front` stayed false 15 s after `/set?front=1` succeeded; in the passing run it took 15.8 s to read true).
  - Not covered: Snapshot Save (native dialog, human-only).
  - Fakes: `test/features/camera/camera_tab_test.dart`, `snapshot_test.dart`, `test/shared/mjpeg_view_test.dart`.
- [ ] Screen (screen sharing on): MJPEG view, tap, swipe, wheel scroll, Back/Home/Recents, Esc, text + Enter
  - Real: FAIL (product bug) and mostly NOT RUN. `integration_test/device/05_screen_test.dart` "S11". Evidence: frame is 720x1480 (aspect 0.4865) but /display is 1080x2112 (0.5114), a 4.9% mismatch (limit 3%); the other 11 sub-steps (Settings, tap, nav Back, swipe, wheel, Esc, Recents, Home, text, Enter, cleanup) did not run because the phone is on a secure lock screen.
  - Fakes: `test/features/screen/screen_tab_test.dart`, `gesture_layer_test.dart`, `input_queue_test.dart`.
- [ ] Landscape: rotate the phone, check taps still land where clicked
  - Real: BLOCKED (human step). `05_screen_test.dart` "S12". Evidence: `/display` rotation=0, 1080x2112 (portrait); physical rotation cannot be automated.
  - Fakes: `test/features/screen/coordinate_mapper_test.dart`, `screen_tab_test.dart`.
- [x] Screen: H.264 mode (on platforms in `h264Platforms`), fallback message elsewhere
  - Real: PASS on macOS only. `integration_test/device/06_h264_web_test.dart` "S13" and "S13 spike". Evidence: H.264 segment offered, selected, H264View alive 30.08 s with no "using MJPEG" snackbar; spike: real stream 720x1480, position 1.14 -> 19.93 s over 20 s. The video texture is blank in PNGs, so playback is judged by `onFailed` never firing plus the spike. Forced-error fallback: see (c) below.
  - Not covered: platforms outside `h264Platforms` (Android, iOS, Windows not run).
  - Fakes: `test/features/screen/screen_mode_test.dart`, `screen_tab_test.dart`.
- [x] Screen: Web control loads /control and /controlhw
  - Real: PASS. `06_h264_web_test.dart` "S14". Evidence: WebControlView with InAppWebView rendered; /control: onLoadStop, no error callbacks, title "Husk control", 1 img; /controlhw: title "Husk control (HW)", 1 video. HTTP 200 is inferred (no error callback; WebKit gave no status).
  - NOT RUN: "S14-click", page-internal clicks inside /control (test gap, not driven).
- [ ] Screenshot saves; stream quality applies; fullscreen opens/closes
  - Real: fullscreen PASS, Screenshot and Stream quality NOT RUN.
  - Fullscreen: `05_screen_test.dart` "S11b". Evidence: placeholder "Showing fullscreen" and Exit fullscreen button while open, one MjpegView / one new /screen request, tab streams again after exit.
  - Screenshot/Stream quality: `05_screen_test.dart` "S15". Evidence: only `GET /screen.jpg` was checked (200, image/jpeg, FFD8FF, decodes to 720x1480). Neither the app's Screenshot button nor the save path ran. The Screenshot save could be automated by faking `FileSelectorPlatform.instance` (reads /screen.jpg only, writes a temp file); not done. Stream quality is skipped on purpose: `/set sq,sfps` cannot be read back, so it cannot be restored.
  - Fakes: none.
- [ ] Tools: Inspect dump/find/tap here; Launch Settings preset
  - Real: BLOCKED. `integration_test/device/07_tools_test.dart` "S16". Evidence: after /wake + Home, /dump had one node ("Swipe up with two fingers or double tap to open Samsung Wallet."); the secure keyguard hides the launcher. Unlock the phone and rerun.
  - Fakes: `test/features/tools/inspect_tool_test.dart`, `launch_tool_test.dart`.
- [x] Tools: Motion config and events load (no save)
  - Real: PASS. `07_tools_test.dart` "S17". Evidence: enabled=false, server https://ntfy.sh, empty topic, sensitivity 5 equal GET /motion; "No motion events yet" equals GET /events; Save not pressed, every /motion request had no parameters.
  - Fakes: `test/features/tools/motion_tool_test.dart`.
- [x] Tools: RPC `ping` after one-time confirmation
  - Real: PASS. `07_tools_test.dart` "S18". Evidence: "Send raw commands?" dialog once, reply "PONG", second ping sent with no dialog, /rpc=0 before Continue and 2 after, both cmd=ping.
  - Fakes: `test/features/tools/rpc_tool_test.dart`.

### Task 20 Step 7: Screen H.264 and Web control (real run on macOS)
All tests in `integration_test/device/06_h264_web_test.dart`.
- [ ] (a) H.264 mode plays /screen.mp4 on macOS, and on Android if a device is attached. Lag is visibly lower than MJPEG; add a rough latency estimate by tapping on the phone. Running about 60 s shows no drift.
  - PARTIAL, not ticked. Plays on macOS: PASS ("S13": 30.08 s, no fallback; "S13 spike": position +18.79 s over 20.0 s wall). Not done: 60 s run, lag comparison against MJPEG and tap-based latency (human-only), Android (no device).
- [ ] (b) Taps, swipes and scrolls over the H.264 Video widget reach the phone at the right coordinates.
  - FAIL (product bug). "T20b". Evidence: target 540,1110 (/info 1080x2220 space) but the app sent `/tap x=540 y=1056` (54 px off vertically, tolerance 3); GestureLayer uses the /display size 1080x2112 while the video draws the 1080x2220 frame. Swipes and scrolls not run. Even with correct coordinates the phone reaction would be BLOCKED by the keyguard.
- [ ] (c) On a platform outside h264Platforms, or on a display other than 0, the H.264 segment is absent. A forced player error shows the 'using MJPEG' snack and falls back.
  - FAIL (product bug) for the display != 0 half, PASS for the forced-error half. "T20c" and "T20c-fallback". Evidence: the picker only offers `Phone (display 0)` although the phone reports `/displays` = `0:0,2:0,13:0` (one comma-separated line); `DisplayEntry.parseList` splits on newlines only, so display 2/13 can never be picked. Forced error: a standalone H264View on closed port 127.0.0.1:1 called `onFailed` once with "Failed to open /screen.mp4." (no phone traffic). Platform outside `h264Platforms`: not run.
- [ ] (d) Web control loads /control, the page's own clicks work, and toggling 'H.264 page' loads /controlhw.
  - PARTIAL, not ticked. "S14" PASS for /control and /controlhw loading and the H.264 page segment. NOT RUN: the page's own clicks ("S14-click" is a test gap).
- [x] (e) Set Settings -> Default mode to Web control, then reopen the Screen tab. It opens in Web control.
  - PASS. "T20e". Evidence: after selecting Web control the Screen tab opened with selected=[webview], WebControlView present, MjpegView and H264View absent.
- [x] (f) Re-run the plan's Task 2 GUI spike against the phone and update docs/superpowers/spikes/2026-10-07-h264-media-kit.md. If Android or macOS fails on the real stream, change h264Platforms in lib/features/screen/screen_mode.dart and the pinned test in test/features/screen/screen_mode_test.dart to match.
  - PASS on macOS. "S13 spike". Evidence: real stream 720x1480, position 1.14 -> 19.93 s, buffer-minus-position never above 0 (min -0.118). Numbers recorded in the spike doc. `h264Platforms` was NOT changed. Android not run.

### Final review fixes
- [ ] (g) Screen tab: rotate the phone while MJPEG (and H.264) is showing. Taps and swipes still land where clicked after the frame turns.
  - NOT RUN (human-only: physical rotation). Fakes: `screen_tab_test.dart` "a rotated frame re-reads /display and maps taps with the rotated size".
- [ ] (h) H.264: leave the phone screen static for 10 s or more. H.264 must not fall back. Then throttle the network (or load the phone) until the view lags more than 2 s; it falls back with "H.264 not supported on this platform — using MJPEG (latency drifted past 2 s)".
  - NOT RUN (human-only: network throttling). The static-screen half is partly seen in S13 (30 s, no fallback, locked static screen). Fakes: `latency_drift_test.dart`.
- [x] (i) Tools on the wide layout: open Motion alarm on one server, then switch server in the app bar. The tool list resets and Motion alarm shows the second server's settings.
  - Real: PASS. `07_tools_test.dart` "T20i". Evidence: after switching to the unreachable server the tool list reset to Inspect, no Sensitivity text from the phone, and Motion alarm showed "Can't reach 192.0.2.1:8090" with Retry. Fakes: `device_shell_test.dart`.

**Merge gate:** the Safe section was run on macOS against `192.168.0.106:8090` (19 of 27 items PASS), but 4 items FAIL with product bugs (below) and the human-only items are open. Fix or explicitly accept the product bugs and the open items before merging.

## Human-only items still open
- S04 real Wi-Fi-off timing on the phone
- S12 / (g) physical rotation of the phone
- T20a subjective lag comparison and end-to-end latency by tapping the phone
- (h) network throttling to force >2 s H.264 lag
- S15 native save dialogs for Screenshot / Snapshot
- Section "Changes phone state: ONLY with the user's explicit OK" (token request/change, motion save, /wd, /pair, /devoptions, ringer) - not approved, not run

Also blocked by the phone's secure lock screen until a human unlocks it: S11 sub-steps, S16, S14 page clicks, and the phone-side reaction in T20b.

## Product bugs found
1. S10 Camera Back -> Front is unreliable (intermittent).
   - Expected: after Back then Front on the Camera tab, `GET /flags` shows front=false then front=true, the video switches each time, and the UI ends on Front.
   - Actual: when Front is pressed 1-3 s after Back, the phone answers `/set?front=1` with success but `/flags.front` stays false for 15 s or more (attempts 1 and 5), or about 15.8 s (attempt 6); attempt 3 took 1.4 s. No error is shown. Also the tab refetches /flags right after /set, can get the old value, and shows the previous side until the next 10 s poll (UI showed Back while the stream showed the front camera). The frames after Back looked identical to the front view, so the video may not switch at all. Could be phone-side (Husk 1.4 camera restart) or the app needing to confirm or retry; `lib/` was not changed.
2. S11 Click-to-phone mapping uses the wrong device size on the Screen tab (MJPEG).
   - Expected: clicks map with the same size as the streamed frame, the real screen 1080x2220 (`/info` screen, the /tap pixel space).
   - Actual: `GestureLayer` / `CoordinateMapper` get `deviceSize` from `/display` = 1080x2112 (excludes the 108 px nav bar) while the frame is 720x1480 (= 1080x2220) drawn with BoxFit.contain. y is scaled by 2112/2220 (about 100 px too high near the bottom), x is slightly off at the edges, and the nav bar strip cannot be reached.
3. T20b Same root cause for H.264 taps.
   - Expected: a click at a point of the phone image sends `/tap` at that phone pixel (centre = 540,1110).
   - Actual: the app sent `/tap x=540 y=1056` (54 px off, growing to about 108 px at the nav bar). Code: `lib/features/screen/screen_tab.dart` `_modeView` / `_interactive` pass `/display` width/height as `deviceSize`.
4. T20c `/displays` parsing does not match the phone's wire format.
   - Expected: the Screen tab picker offers every display the phone reports (0, 2, 13), and H.264 is hidden on any display other than 0.
   - Actual: the phone returns `/displays` as one comma-separated line (`0:0,2:0,13:0`); `DisplayEntry.parseList` (`lib/core/api/models/hardware_models.dart`) splits on newlines only, so the picker shows only display 0 (e.g. DeX display 2 is never offered). The unit fixture in `test/core/api/husk_api_models_test.dart` uses newlines, which hid it. The ids 2 and 13 grow across runs, so they may be short-lived virtual displays created by Husk.

## Changes phone state: ONLY with the user's explicit OK
Not approved, not run. Nothing on the phone was changed by these items.
- [ ] not run (not approved): Request token (this SETS a token on a phone that has none; record it)
- [ ] not run (not approved): Change token (requires a token to exist)
- [ ] not run (not approved): Motion alarm save (restore enabled=false, topic empty afterwards)
- [ ] not run (not approved): Wireless Debugging (/wd), Pair (/pair), Developer options probe (/devoptions?probe=1)
- [ ] not run (not approved): Ringer mode change (restore `silent`)

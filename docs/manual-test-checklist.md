# Manual test checklist: Husk Config

Status: INCOMPLETE. The interactive checklist below was NOT executed. It needs a human, the phone and a GUI session (`flutter run`), and no human or adb device was available to the automated run. No manual item below is a pass. Safe items additionally carry an automated (fakes) result from a headless test run, which is a proxy only. (The earlier commit message "with results" overstated this; there are no manual results yet.)

## Automated results (Task 23 Step 1, this machine, Xcode 27.0)
| Check | Result |
|---|---|
| `flutter analyze` | No issues found |
| `flutter test` | All tests passed (+200) |
| `flutter build macos --debug` | Built `build/macos/Build/Products/Debug/Husk Config.app` |
| `flutter build apk --debug` | Built `build/app/outputs/flutter-apk/app-debug.apk` |
| `flutter build ios --simulator --debug` | Built `build/ios/iphonesimulator/Runner.app` (after raising the iOS deployment target to 15.0 in `ios/Podfile` and `ios/Runner.xcodeproj`). Build only: no iOS simulator runtime is installed, so the app was not launched on iOS. |
| `flutter build windows` | not run (no Windows machine) |
| Android on a device | not run (no adb device attached) |

Device under test: `192.168.0.106:8090` (SM-A750F, Android 10, Husk 1.4).
Fill each line with ✅ / ❌ / n/a and a note. Platforms: macOS · Android · iOS · Windows.

## Safe (read-only or easily reverted)
Each line has two results. **Automated (fakes)** was executed in this fix round: the widget/unit test named in the line, run headless against fake HTTP adapters (no real phone contacted), command `flutter test --reporter expanded <dirs>` -> `+92: All tests passed!`. **Manual (phone/GUI)** is the real checklist item and was NOT run (needs a human, a GUI session and the phone), so every box stays unchecked. An automated pass is a proxy and does not tick the manual box.

- [ ] Launch with no servers shows the empty dashboard (Add server / Scan network)
  - Automated (fakes): pass, `test/app_test.dart` "boots to the empty dashboard with add and scan actions". Manual: not run.
- [ ] Add server by IP; a hostname is rejected; Test connection shows the model
  - Automated (fakes): pass, `test/features/servers/server_form_screen_test.dart` (rejects a hostname, rejects an invalid port, saves with trimmed host). Test connection model display has no widget test. Manual: not run.
- [ ] LAN scan finds 192.168.0.106 and marks it Saved
  - Automated (fakes): pass, `test/features/servers/scan_screen_test.dart` (lists found devices, marks saved ones; fake scanner, no real scan). Manual: not run.
- [ ] Dashboard card shows online, battery, services; switching phone Wi-Fi off turns it Offline within one poll interval
  - Automated (fakes): pass, `test/features/dashboard/dashboard_test.dart` (online card, offline card with reason, unauthorized card). Real Wi-Fi-off timing is not covered. Manual: not run.
- [ ] App in background pauses polling (no requests in phone log); resumes on return
  - Automated (fakes): pass, `test/features/settings/settings_controller_test.dart` (pollIntervalProvider follows foreground) and `test/features/dashboard/server_status_test.dart` (polling pauses under a covering route and resumes). The phone request log is not covered. Manual: not run.
- [ ] Settings: theme, polling interval (Off stops auto refresh), default screen mode, client name
  - Automated (fakes): pass, `test/features/settings/settings_screen_test.dart` (theme, polling off, default mode, client name validation) and `test/core/polling_test.dart`. Manual: not run.
- [ ] Overview cards load; Location shows the phone's ERR message or a position
  - Automated (fakes): pass, `test/features/device/overview_tab_test.dart` (cards, plain-text ERR from /location). Manual: not run.
- [ ] Wake, vibrate, torch on/off work
  - Automated (fakes): pass, `test/features/device/overview_tab_test.dart` "wake and torch call the phone" (fake adapter; vibrate has no test). Manual: not run.
- [ ] Brightness slider (or WRITE_SETTINGS hint); restore previous level
  - Automated (fakes): no test. Manual: not run.
- [ ] Camera stream + snapshot + save; front/back switch (restore Front)
  - Automated (fakes): pass, `test/features/camera/camera_tab_test.dart` (side switch, 409, reconnect), `test/features/camera/snapshot_test.dart` (503 retry), `test/shared/mjpeg_view_test.dart`. Real stream and save are not covered. Manual: not run.
- [ ] Screen (screen sharing on): MJPEG view, tap, swipe, wheel scroll, Back/Home/Recents, Esc, text + Enter
  - Automated (fakes): pass, `test/features/screen/screen_tab_test.dart`, `gesture_layer_test.dart` (tap, long press, swipe, Esc), `input_queue_test.dart`. Wheel scroll and a live stream are not covered. Manual: not run.
- [ ] Landscape: rotate the phone, check taps still land where clicked
  - Automated (fakes): pass, `test/features/screen/coordinate_mapper_test.dart` (landscape device in a tall view) and `screen_tab_test.dart` (taps map with the display size). Real rotation is not covered. Manual: not run.
- [ ] Screen: H.264 mode (on platforms in `h264Platforms`), fallback message elsewhere
  - Automated (fakes): pass, `test/features/screen/screen_mode_test.dart` and `screen_tab_test.dart` (H.264 offered for display 0 only). Real playback is covered by the Task 20 Step 7 items below. Manual: not run.
- [ ] Screen: Web control loads /control and /controlhw
  - Automated (fakes): no test (needs a webview). Manual: not run.
- [ ] Screenshot saves; stream quality applies; fullscreen opens/closes
  - Automated (fakes): no test. Manual: not run.
- [ ] Tools: Inspect dump/find/tap here; Launch Settings preset
  - Automated (fakes): pass, `test/features/tools/inspect_tool_test.dart` and `launch_tool_test.dart`. Manual: not run.
- [ ] Tools: Motion config and events load (no save)
  - Automated (fakes): pass, `test/features/tools/motion_tool_test.dart` (the fake test also exercises save; the manual item must not save). Manual: not run.
- [ ] Tools: RPC `ping` after one-time confirmation
  - Automated (fakes): pass, `test/features/tools/rpc_tool_test.dart` "confirms once per session, then sends directly". Manual: not run.

### Task 20 Step 7 (pending, R4): Screen H.264 and Web control
Not executed (agent, R4). Never mark these passed without a human run.
- [ ] Task 20 Step 7 (pending, R4) (a): H.264 mode plays /screen.mp4 on macOS, and on Android if a device is attached. Lag is visibly lower than MJPEG; add a rough latency estimate by tapping on the phone. Running about 60 s shows no drift.
- [ ] Task 20 Step 7 (pending, R4) (b): Taps, swipes and scrolls over the H.264 Video widget reach the phone at the right coordinates.
- [ ] Task 20 Step 7 (pending, R4) (c): On a platform outside h264Platforms, or on a display other than 0, the H.264 segment is absent. A forced player error shows the 'using MJPEG' snack and falls back.
- [ ] Task 20 Step 7 (pending, R4) (d): Web control loads /control, the page's own clicks work, and toggling 'H.264 page' loads /controlhw.
- [ ] Task 20 Step 7 (pending, R4) (e): Set Settings -> Default mode to Web control, then reopen the Screen tab. It opens in Web control.
- [ ] Task 20 Step 7 (pending, R4) (f): Re-run the plan's Task 2 GUI spike against the phone and update docs/superpowers/spikes/2026-10-07-h264-media-kit.md. If Android or macOS fails on the real stream, change h264Platforms in lib/features/screen/screen_mode.dart and the pinned test in test/features/screen/screen_mode_test.dart to match.

## Changes phone state: ONLY with the user's explicit OK
No user was available to approve any of these, so none was run and nothing on the phone was changed.
- [ ] skipped (not approved): Request token (this SETS a token on a phone that has none; record it)
- [ ] skipped (not approved): Change token (requires a token to exist)
- [ ] skipped (not approved): Motion alarm save (restore enabled=false, topic empty afterwards)
- [ ] skipped (not approved): Wireless Debugging (/wd), Pair (/pair), Developer options probe (/devoptions?probe=1)
- [ ] skipped (not approved): Ringer mode change (restore `silent`)

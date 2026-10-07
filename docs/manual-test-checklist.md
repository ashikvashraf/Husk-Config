# Manual test checklist: Husk Config

Status: INCOMPLETE. The interactive checklist below was NOT executed. It needs a human, the phone and a GUI session (`flutter run`), and no human or adb device was available to the automated run. Every item is recorded as `not run` and no result below is a pass. (The earlier commit message "with results" overstated this; there are no manual results yet.)

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
- [ ] not run (needs human/GUI/phone): Launch with no servers shows the empty dashboard (Add server / Scan network)
- [ ] not run (needs human/GUI/phone): Add server by IP; a hostname is rejected; Test connection shows the model
- [ ] not run (needs human/GUI/phone): LAN scan finds 192.168.0.106 and marks it Saved
- [ ] not run (needs human/GUI/phone): Dashboard card shows online, battery, services; switching phone Wi-Fi off turns it Offline within one poll interval
- [ ] not run (needs human/GUI/phone): App in background pauses polling (no requests in phone log); resumes on return
- [ ] not run (needs human/GUI/phone): Settings: theme, polling interval (Off stops auto refresh), default screen mode, client name
- [ ] not run (needs human/GUI/phone): Overview cards load; Location shows the phone's ERR message or a position
- [ ] not run (needs human/GUI/phone): Wake, vibrate, torch on/off work
- [ ] not run (needs human/GUI/phone): Brightness slider (or WRITE_SETTINGS hint); restore previous level
- [ ] not run (needs human/GUI/phone): Camera stream + snapshot + save; front/back switch (restore Front)
- [ ] not run (needs human/GUI/phone): Screen (screen sharing on): MJPEG view, tap, swipe, wheel scroll, Back/Home/Recents, Esc, text + Enter
- [ ] not run (needs human/GUI/phone): Landscape: rotate the phone, check taps still land where clicked
- [ ] not run (needs human/GUI/phone): Screen: H.264 mode (on platforms in `h264Platforms`), fallback message elsewhere
- [ ] not run (needs human/GUI/phone): Screen: Web control loads /control and /controlhw
- [ ] not run (needs human/GUI/phone): Screenshot saves; stream quality applies; fullscreen opens/closes
- [ ] not run (needs human/GUI/phone): Tools: Inspect dump/find/tap here; Launch Settings preset
- [ ] not run (needs human/GUI/phone): Tools: Motion config and events load (no save)
- [ ] not run (needs human/GUI/phone): Tools: RPC `ping` after one-time confirmation

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

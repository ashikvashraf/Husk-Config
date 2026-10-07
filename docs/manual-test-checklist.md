# Manual test checklist: Husk Config

Status: not yet executed (needs a human, the phone and a GUI)

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

### Task 20 Step 7 (pending, R4): Screen H.264 and Web control
Not executed (agent, R4). Never mark these passed without a human run.
- [ ] Task 20 Step 7 (pending, R4) (a): H.264 mode plays /screen.mp4 on macOS, and on Android if a device is attached. Lag is visibly lower than MJPEG; add a rough latency estimate by tapping on the phone. Running about 60 s shows no drift.
- [ ] Task 20 Step 7 (pending, R4) (b): Taps, swipes and scrolls over the H.264 Video widget reach the phone at the right coordinates.
- [ ] Task 20 Step 7 (pending, R4) (c): On a platform outside h264Platforms, or on a display other than 0, the H.264 segment is absent. A forced player error shows the 'using MJPEG' snack and falls back.
- [ ] Task 20 Step 7 (pending, R4) (d): Web control loads /control, the page's own clicks work, and toggling 'H.264 page' loads /controlhw.
- [ ] Task 20 Step 7 (pending, R4) (e): Set Settings -> Default mode to Web control, then reopen the Screen tab. It opens in Web control.
- [ ] Task 20 Step 7 (pending, R4) (f): Re-run the plan's Task 2 GUI spike against the phone and update docs/superpowers/spikes/2026-10-07-h264-media-kit.md. If Android or macOS fails on the real stream, change h264Platforms in lib/features/screen/screen_mode.dart and the pinned test in test/features/screen/screen_mode_test.dart to match.

## Changes phone state: ONLY with the user's explicit OK
- [ ] Request token (this SETS a token on a phone that has none; record it)
- [ ] Change token (requires a token to exist)
- [ ] Motion alarm save (restore enabled=false, topic empty afterwards)
- [ ] Wireless Debugging (/wd), Pair (/pair), Developer options probe (/devoptions?probe=1)
- [ ] Ringer mode change (restore `silent`)

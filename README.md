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

# Releasing Husk Config

Release builds are produced by GitHub Actions (`.github/workflows/release.yml`) for
**Android, macOS and Windows**. iOS is not built by CI.

The workflow runs in this order:

1. **Analyze and test** (Ubuntu): `flutter pub get`, `flutter analyze`, `flutter test`. If any of them fail, nothing is built.
2. **Builds** run in parallel: Android (Ubuntu, Java 17), macOS (macOS runner), Windows (Windows runner).
   All use Flutter 3.44.8 stable, pinned in the workflow's `FLUTTER_VERSION`.
3. **Publish GitHub Release**: only for tag pushes. It collects all artifacts, writes `SHA256SUMS.txt` and creates the release.

## Cut a release

1. Bump `version:` in `pubspec.yaml`, e.g. `version: 1.2.0+1`. Only the `1.2.0` part matters; CI replaces the build number.
2. Commit and push to `main`.
3. Tag the commit and push the tag:

   ```sh
   git tag v1.2.0
   git push origin v1.2.0
   ```

4. Watch the run under **Actions > Release**. When it finishes, the release is at
   `https://github.com/ashikvashraf/Husk-Config/releases/tag/v1.2.0` with generated notes and install instructions.

Details:

- **Version name** comes from the tag without the leading `v` (`v1.2.0` → `1.2.0`). The workflow warns if it
  differs from `pubspec.yaml` but builds anyway. Tags must look like `vX.Y.Z` or `vX.Y.Z-suffix`.
- **Build number** is the workflow run number (`github.run_number`), so it always increases. That keeps
  Android `versionCode` monotonic.
- **Pre-releases**: a tag containing a hyphen (e.g. `v1.3.0-beta.1`) is published as a pre-release. Android and
  Windows keep the full version (`1.3.0-beta.1`). macOS only allows digits and dots in the bundle version, so the macOS
  build is versioned `1.3.0` (the suffix is dropped) and the build number tells builds apart. File names keep the full
  version on every platform.
- **Re-running** for an existing tag (re-run the workflow, or a release you created by hand) does not fail.
  It re-uploads the assets with `--clobber` and leaves the existing notes alone. If that release is still a draft,
  the workflow publishes it. Exception: if the repository has *immutable releases* enabled, assets on a published
  release cannot be replaced.

## Manual builds (no release)

**Actions > Release > Run workflow** on any branch builds all three platforms with the version from
`pubspec.yaml` and the run number as build number. The files are attached to the run as workflow artifacts
(`husk-config-android`, `husk-config-macos`, `husk-config-windows`), kept for 14 days. Nothing is published.

## Artifacts

| File | What it is |
| --- | --- |
| `Husk-Config-<version>-android.apk` | Universal APK (arm, arm64, x64) for sideloading. |
| `Husk-Config-<version>-android.aab` | Android App Bundle for Google Play. Only useful if release-signed (see below). |
| `Husk-Config-<version>-macos.zip` | `Husk Config.app`, zipped with `ditto` so the bundle and its symlinks survive. Unzip by double-clicking. |
| `Husk-Config-<version>-windows-x64.zip` | Folder with `huskconfig.exe`, its DLLs (Flutter, plugins, libmpv, MSVC runtime) and `data/`. Keep the files together. |
| `SHA256SUMS.txt` | SHA-256 of each file above (release only). Check with `shasum -a 256 -c SHA256SUMS.txt` (macOS/Linux) or `Get-FileHash .\<file> -Algorithm SHA256` (Windows PowerShell). |

## Android release signing (optional, recommended)

Without signing secrets, the APK and AAB are signed with a **debug key**, and the run shows a warning (the release
notes say so too). Every GitHub runner generates a **new, throwaway** debug key, so no two debug-signed CI builds can
update each other: users must uninstall the previous version first and lose the app's data, every time. Google Play
rejects debug-signed bundles, and a properly signed APK will not install over a debug-signed one either.
**Set the four secrets below before publishing releases other people install.**

### 1. Create an upload keystore (once)

```sh
keytool -genkeypair -v \
  -keystore husk-config-upload.jks \
  -storetype JKS -keyalg RSA -keysize 4096 -validity 10000 \
  -alias husk-config
```

`keytool` comes with any JDK (Android Studio has one in `Android Studio.app/Contents/jbr/Contents/Home/bin`).
Keep the `.jks` file and both passwords somewhere safe, such as a password manager. If you lose them, you cannot
publish updates that install over existing ones. Never commit the keystore: `*.jks`, `*.keystore` and
`key.properties` are git-ignored.

### 2. Add the repository secrets

In **GitHub > Settings > Secrets and variables > Actions > New repository secret**, add:

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | The keystore, base64-encoded (see below). |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore (store) password. |
| `ANDROID_KEY_ALIAS` | Key alias, e.g. `husk-config`. |
| `ANDROID_KEY_PASSWORD` | Key password (same as the store password if you did not set a separate one). |

Encode the keystore:

```sh
# macOS: copies the single-line base64 to the clipboard
base64 -i husk-config-upload.jks | pbcopy

# Linux
base64 -w 0 husk-config-upload.jks
```

With the GitHub CLI you can set it directly: `base64 -i husk-config-upload.jks | gh secret set ANDROID_KEYSTORE_BASE64`.

All four secrets must be set. If any is missing, the build falls back to the debug key and warns.
CI decodes the keystore into the runner's temp directory (outside the repo) and passes it to Gradle through
`ANDROID_KEYSTORE_PATH` / `ANDROID_KEYSTORE_PASSWORD` / `ANDROID_KEY_ALIAS` / `ANDROID_KEY_PASSWORD`
environment variables, only for the build step. The keystore is deleted when the job ends.

### Local release-signed builds

Create `android/key.properties` (git-ignored):

```properties
storeFile=/absolute/path/to/husk-config-upload.jks
storePassword=...
keyAlias=husk-config
keyPassword=...
```

`android/app/build.gradle.kts` uses, in order: the four environment variables, then `key.properties`, then the
debug key. A relative `storeFile` is resolved against `android/app/`.

For Google Play, enroll in Play App Signing and use this keystore as the **upload key**.

## Known limits

- **iOS is not built.**
- **macOS is not notarized or Developer ID signed.** The app is ad-hoc signed (Flutter's default), so Gatekeeper
  blocks the first launch. On **macOS 15 and later**, try to open it once, then go to *System Settings > Privacy &
  Security* and click **Open Anyway**. On macOS 12-14, right-click the app > **Open**. Alternatively, remove the
  quarantine flag: `xattr -dr com.apple.quarantine "/Applications/Husk Config.app"`.
  macOS also asks for **Local Network** access, which the app needs to reach phones.
  To remove the warning later, you need a paid Apple Developer account: import a *Developer ID Application* certificate
  into the runner keychain, sign with hardened runtime, submit with `xcrun notarytool`, and `xcrun stapler staple`
  the app before zipping. None of that is set up yet.
- **Windows is unsigned.** SmartScreen shows "Windows protected your PC": choose **More info > Run anyway**. The app
  needs the Microsoft Edge **WebView2 Runtime** for the web control screen. It is preinstalled on Windows 11 and most
  Windows 10 PCs, and otherwise available from Microsoft. There is no installer; it is a portable zip.
- **Android is debug-signed** unless the four secrets above are set.
- Builds use the Visual Studio and Android SDK of the GitHub-hosted runner images (`ubuntu-24.04`, `windows-2025`).
  The macOS job selects Xcode **26.6** on `macos-26` (`XCODE_VERSION` in `release.yml`); if the image no longer has it,
  the job warns and uses the image default. Local builds use Xcode 27.
- The Android job installs the NDK version Flutter pins before building, if the runner does not already have it.

## Troubleshooting

- **A download fails** (pub, Gradle, CocoaPods/Swift packages, NuGet, libmpv): runs fetch these from the internet.
  Use **Re-run failed jobs**; a tag release re-run uploads with `--clobber`.
- **Windows app does not start on a clean PC**: the packaging step copies the MSVC runtime DLLs and, when the exe
  needs it, `WebView2Loader.dll` next to `huskconfig.exe`. The run log of the *Package and check release folder* step
  lists what was copied. Test a new Windows build once on a PC without Visual Studio.
- **macOS video (Camera/Screen H.264) fails in a CI build but works locally**: compare the `Frameworks` folder inside
  the two `Husk Config.app` bundles; the media_kit libmpv frameworks must be present in the CI build.
- **`flutter analyze` fails the first job**: infos count as failures. Fix the reported lint, then push again.

## Optional hardening

- Add a **tag ruleset** (Settings > Rules) that restricts who can create `v*` tags, since a tag push publishes a release.
- Move the four Android secrets into a GitHub **Environment** (e.g. `release`) with required reviewers, and add
  `environment: release` to the Android job, so signing keys are only used after approval.

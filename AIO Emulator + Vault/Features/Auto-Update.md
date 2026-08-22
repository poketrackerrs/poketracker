---
tags: [poketracker, feature, updates]
---
# Auto-Update

The app self-updates from **GitHub Releases** by polling a JSON manifest. Service: `update_service.dart` + the `update_installer` facade ([[Services]]); UI: `updates_screen.dart` ([[Screens]]).

## The manifest
- URL constant `kUpdateManifestUrl` (in `config.dart`): `https://raw.githubusercontent.com/poketrackerrs/poketracker/main/update.json`.
- Shape: `version`, `notes`, `windows_url`, `android_url`.
- Fetched with a **cache-buster query param + no-cache headers** to defeat the ~5-min raw-CDN cache (15s timeout).

## Check → download → install
1. `checkForUpdate()` → `UpdateCheckResult` (`update?`, `currentVersion`, `error?`, `hasUpdate`). `_isNewer` compares dot-separated numeric versions; `_urlForPlatform` picks the Windows or Android URL.
2. `downloadAndInstall(url, onProgress)` (conditional-import facade):
   - **Windows** (`update_installer_io.dart`) — streams the installer to a temp file, `Process.start(..., detached)`, then **`exit(0)`** (the app quits so the installer can replace it).
   - **Android** — streams the APK, then invokes `installApk` on the `poketracker/installer` channel (see [[Native Android Layer]]), which fires the system package installer.
   - **Web** (`update_installer_stub.dart`) — throws `UnsupportedError`.

> [!note] Why the updates screen "ends" on Windows
> Because Windows calls `exit(0)` right after launching the installer, any code after the `await` in `updates_screen.dart` runs **only on Android**. The Windows app is already gone.

## Releasing a new version
See [[Build and Release]] for the full loop (bump `pubspec.yaml` → edit `update.json` → build both → `gh release create` with asset names **exactly** `PokeTracker-Setup.exe` and `PokeTracker.apk`).

---
Related: [[Services]] · [[Native Android Layer]] · [[Build and Release]]

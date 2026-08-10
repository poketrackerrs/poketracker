---
tags: [poketracker, architecture, android, native]
---
# Native Android Layer

`android/app/src/main/kotlin/.../MainActivity.kt` — `MainActivity : FlutterActivity` registers **three `MethodChannel`s** in `configureFlutterEngine`. These are the only native code paths; Windows uses `dart:io` directly.

## `poketracker/installer` → [[Auto-Update]]
- **`installApk(path)`** — wraps the downloaded APK in a `FileProvider` URI (`$packageName.fileprovider`), fires `ACTION_VIEW` with mime `application/vnd.android.package-archive` + read/new-task flags to trigger the system installer.
- Dart caller: `update_installer_io.dart`.

## `poketracker/emulators` → [[Emulator Launching]]
- **`installedPackages(packages)`** — filters the candidate list via `packageManager.getPackageInfo` (returns which are installed).
- **`launchRom(package, path)`** — tries to hand the ROM to the emulator via a `FileProvider` `ACTION_VIEW` intent (mimes `application/octet-stream` then `*/*`, `setPackage(pkg)`). If nothing resolves, it opens the emulator's own launch intent and **returns false** → surfaces as `LaunchOutcome.handoffFailed`.
- Dart caller: `emulator_service.dart`.

## `poketracker/storage` → [[ROM Library and Downloads]] (Lemuroid sync)
- **`hasAllFilesAccess()`** — `Environment.isExternalStorageManager` on API ≥ R, else true.
- **`requestAllFilesAccess()`** — opens `ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION` (falls back to the general list).
- **`externalStorageDir()`** — the shared-storage root used to mirror ROMs for Lemuroid.
- Dart caller: `lemuroid_sync.dart`.

## Supporting manifest (`AndroidManifest.xml`)
- **Permissions:** `INTERNET`, `REQUEST_INSTALL_PACKAGES`, `MANAGE_EXTERNAL_STORAGE`, legacy `WRITE`/`READ_EXTERNAL_STORAGE`.
- **`FileProvider`** authority `${applicationId}.fileprovider` → `@xml/file_paths` (exposes cache / files / external-cache / external-files roots). ROMs must be **staged into `cache/roms/`** before hand-off because `getApplicationDocumentsDirectory()` (`app_flutter`) isn't covered by `file_paths.xml`. See [[Emulator Launching]] and [[Gotchas]].
- **`<queries>`** block declares emulator package ids for launch/detection.

> [!warning] Known asymmetries
> - `<queries>` lists `io.mgba.android.emulator` and `com.dsemu.drastic`, which are **not** in the Dart `kEmulators.androidPackages` (leftover/asymmetry).
> - `MANAGE_EXTERNAL_STORAGE` is intentional for this sideloaded personal build but would **block a Play Store listing**.
> See [[Gotchas]] · [[Constraints and Legal]].

---
Related: [[Architecture Overview]] · [[Services]] · [[Emulator Launching]] · [[Auto-Update]]

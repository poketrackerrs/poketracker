---
tags: [poketracker, architecture, services]
---
# Services

`lib/services/` — all I/O: disk, network, platform channels, and binary parsing. Every service is owned by [[AppState]].

## `storage_service.dart`
Persists all progress as **one JSON blob**.
- Key `poketracker_progress_v1`; `load()` / `save(Map<String, GameProgress>)` via `shared_preferences`.

## `library_service.dart` → [[ROM Library and Downloads]]
Manages the on-device ROM library folder and downloads user-supplied files (esp. Google Drive) into it. **Ships with no sources** (see [[Constraints and Legal]]).
- `libraryDir()` → `Documents/PokeTracker/Games`; `gameDir(id)` → `Games/<id>/`; `fileForGame`, `deleteForGame`.
- `loadDriveFolders()` — reads user `drive_folders.json`, else falls back to the **bundled `assets/config/drive_folders.json`**.
- `importDriveFolderTree(link)` — scrapes a public Drive `embeddedfolderview`, matches subfolder names to game ids (alias map `{arceus→legends-arceus, z-a→legends-z-a}`).
- `download(gameId, url, onProgress, {nameHint})` — streams to disk; handles Drive's large-file HTML confirm gate (`_normalizeDrive`, `_driveRetryUri` with confirm-token/uuid extraction), content-disposition + extension resolution, filename sanitizing.

## `emulator_service.dart` → [[Emulator Launching]]
Detects installed emulators and launches them.
- **`class DetectedEmulator`** — `Emulator emu`, `String? path`; `installed => path != null`.
- Channel `poketracker/emulators`.
- `detectAll()` — Android queries installed packages via the channel ("path" = package id); desktop resolves each `exeName` via `_find` (manual pref → PATH `where`/`which` → registry App Paths → common dirs / winget / scoop / choco / Steam → registry Uninstall `InstallLocation`).
- **`launch(emulatorPath, [romPath]) → bool`** — Android stages the ROM into cache (`_stageForShare`) then invokes `launchRom`; desktop `Process.start(..., mode: detached)`.

## `save_service.dart` → [[Save Auto-Tracker]]
Parses emulator save files into `SaveData`. Reads only unencrypted, documented fields; reports uncertainty via `notes`.
- `parse(bytes, {generation, versionId})` dispatches to `_parseGen1` … `_parseGen5`; throws `SaveParseException` for unsupported gens.
- Hardcoded **English-ROM** offsets per gen (Bulbapedia-sourced, documented inline). Confidence varies wildly by gen — see [[Save Auto-Tracker]] and [[Gotchas]].

## `pokedex_service.dart` → [[Pokedex]]
Fetches Pokédex data from PokéAPI, caching raw responses in `shared_preferences` (keys `pokecache:<url>`, **never expire**) + an in-memory `_memCache`.
- `_base = 'https://pokeapi.co/api/v2'`; `nationalDexCount = 1025`.
- `loadIndex`, `loadAllVarieties` (forms ≥ 10000), `loadGameDex(versionGroup)`, `loadObtainability(...)`, `fetchDetail(id)`, `fetchForm(formId)`, `_evolutionChain` (recursive).

## `lemuroid_sync.dart` (Android only)
Mirrors downloaded ROMs into a shared folder laid out for Lemuroid's scanner (`<shared>/PokeTracker/<platform>/<file>`), since Lemuroid can't launch-into or read app-private storage.
- Channel `poketracker/storage`. `platformFolder(gen)` → `gb`/`gbc`/`gba`/`nds`. `hasAccess`, `requestAccess` (all-files-access), `mirror`, `syncAll`.

## `update_service.dart` + installer facade → [[Auto-Update]]
- `update_service.dart` — `checkForUpdate()` GETs [[Architecture Overview|kUpdateManifestUrl]] with a cache-buster + no-cache headers; `_isNewer` compares dot-separated numeric versions. Types `UpdateInfo`, `UpdateCheckResult`.
- `update_installer.dart` — conditional-import facade exporting `downloadAndInstall(url, onProgress)`:
  - `update_installer_io.dart` — streams to a temp file; **Windows** `Process.start` detached then `exit(0)`; **Android** invokes `installApk` on `poketracker/installer`.
  - `update_installer_stub.dart` — throws `UnsupportedError` (web preview).

## Dependency list (`pubspec.yaml`)
`provider` · `shared_preferences` · `http` · `package_info_plus` · `path_provider` · `cached_network_image` · `url_launcher` · `audioplayers` · `model_viewer_plus` · `webview_windows` · `webview_flutter` · `cupertino_icons`.
Dev: `flutter_test`, `flutter_lints`, `flutter_launcher_icons`, `flutter_native_splash`.

---
Related: [[Architecture Overview]] · [[AppState]] · [[Native Android Layer]]

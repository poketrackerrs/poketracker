---
tags: [poketracker, feature, library, roms]
---
# ROM Library and Downloads

Manages the on-device ROM library folder and downloads the user's **own** files (typically from Google Drive) into it. Service: `library_service.dart` ([[Services]]); Android mirroring: `lemuroid_sync.dart`.

> [!warning] Personal-use boundary
> The app ships with **no ROM sources of its own** and must never become a ROM distribution pipeline. Users supply their own Drive links to their own legally-dumped ROMs. See [[Constraints and Legal]].

## Library layout
- `libraryDir()` → `Documents/PokeTracker/Games` (created on first use).
- `gameDir(id)` → `Games/<id>/`; `fileForGame(id)` returns the first file in that subfolder.
- On Windows and Android the ROM lives in the same documents dir — **don't relocate it** (the Android launch path stages a copy into cache instead; see [[Emulator Launching]]).

## Drive sources
- `loadDriveFolders()` — reads a user `drive_folders.json`, else falls back to the **bundled `assets/config/drive_folders.json`** and persists it.
- `importDriveFolderTree(linkOrId)` — scrapes a public Drive `embeddedfolderview` HTML page, matches subfolder names to game ids (alias map `{arceus→legends-arceus, z-a→legends-z-a}`), writes the id→folder map, returns the count matched.
- `resolveDriveFile(folderId)` — finds the current file (id + name) in a public folder via the same HTML view.
- `_driveFolderId(input)` — parses `/folders/ID`, `?id=`, or a raw id.

## Downloading (`download`)
Streams a URL to disk with progress. Handles:
- Google Drive's **large-file HTML confirm gate** (`_isHtml`, `_normalizeDrive`, `_driveRetryUri` extracts the confirm-token / uuid).
- content-disposition + extension resolution (`_extensionFrom`) and filename sanitizing.
- `sourceUrl` / `setSourceUrl` per game (pref `romsrc:<id>`).

`AppState.downloadGame(gameId)` wires progress into `_downloadProgress`; on Android it fire-and-forgets `LemuroidSyncService.mirror`.

## Lemuroid mirroring (Android only)
Lemuroid can't launch-into or read app-private storage, so ROMs are **mirrored** into a shared folder its scanner can see:
- Layout `<externalStorageDir>/PokeTracker/<platform>/<file>` where `platformFolder(gen)` → `gb`/`gbc`/`gba`/`nds` (null for Gen 6+).
- Needs **all-files access** (`hasAccess`/`requestAccess` via the `poketracker/storage` channel — see [[Native Android Layer]]). `mirror` copies one ROM (skips if a same-size file exists); `syncAll` mirrors everything.

---
Related: [[Services]] · [[Emulator Launching]] · [[Native Android Layer]] · [[Constraints and Legal]]

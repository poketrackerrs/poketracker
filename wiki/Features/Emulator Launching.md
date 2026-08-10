---
tags: [poketracker, feature, emulators]
---
# Emulator Launching

The **Play** button hands a game's ROM to an installed emulator. Logic spans [[AppState]] (`tryLaunchGame`), `EmulatorService` ([[Services]]), and the `poketracker/emulators` channel ([[Native Android Layer]]).

## Decision flow
1. `AppState.emulatorForGame(Game)` picks an emulator: **null** for Gen ≥ 8 and Let's Go (no supported emulator); otherwise the **first installed, `launchable` emulator** whose `generations` includes the game's gen. Library-only apps (e.g. Lemuroid, `launchable:false`) are skipped.
2. `tryLaunchGame(Game) → LaunchOutcome` rescans emulators if needed, launches, and maps the result to `launched` / `handoffFailed` / `noEmulator` (each → a distinct snackbar).

## Detection (`EmulatorService.detectAll`)
- **Android:** queries `installedPackages` via the channel; a detected emulator's "path" is actually its **package id**, not a filesystem path.
- **Desktop (`_find`, in order):** manual pref (`emupath:<name>`) → PATH (`where`/`which`) → registry **App Paths** (HKLM / WOW6432Node / HKCU) → common dirs (Program Files, LOCALAPPDATA, winget/scoop/choco shims, Steam common, Desktop/Downloads) incl. `hints` → registry **Uninstall** `InstallLocation`.

## Launch (`EmulatorService.launch`)
- **Android:** stages the ROM into `cache/roms/` (`_stageForShare`) then invokes `launchRom(package, path)`. Staging is required because `getApplicationDocumentsDirectory()` (`app_flutter`) isn't covered by the `FileProvider` `file_paths.xml`.
- **Desktop:** `Process.start(emulatorPath, [romPath], mode: detached)`.

## Verified Android behavior (Android 13 / Galaxy A51)
| Emulator | Package | Result |
|---|---|---|
| **My Boy! Lite** (GBA) | `com.fastemulator.gbafree` | ✅ accepts hand-off — recommended |
| **My OldBoy! Lite** (GB/GBC) | `com.fastemulator.gbcfree` | ✅ accepts hand-off — recommended |
| melonDS (DS) | `me.magnum.melonds` | ✅ accepts |
| RetroArch | — | ⚠️ accepts intents, but Play build too old to install on modern Android |
| **Pizza Boy** | — | ❌ library-only, ignores the ROM → `handoffFailed` |
| **Lemuroid** | — | ❌ library-only (`launchable:false`) → use the folder-sync flow instead |
| mGBA (Android) | `io.mgba.android.emulator` | ❌ no official Play app (404) — desktop only |

> [!warning] Lesson (don't relearn it)
> Before recommending any store app, verify the package **exists** in the store **and** that it accepts external ROM intents. Two wrong guesses (RetroArch Plus, mGBA-on-Play) came from skipping this. See [[Gotchas]].

For Lemuroid, ROMs are mirrored into a shared folder instead — see [[ROM Library and Downloads]] and `lemuroid_sync.dart` in [[Services]]. The full emulator list is in [[Emulators Catalog]].

---
Related: [[AppState]] · [[Services]] · [[Native Android Layer]] · [[Emulators Catalog]]

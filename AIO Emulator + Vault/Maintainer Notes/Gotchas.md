---
tags: [poketracker, maintainer, gotchas]
---
# Gotchas

Hard-won lessons, sharp edges, and incomplete work. Skim this before touching an unfamiliar area.

## Save parsing ([[Save Auto-Tracker]])
- Offsets assume **English ROMs** — other regions/revisions silently misread. Confirm against a real save per game.
- Confidence varies by gen: Gen 1 solid; Gen 2 Johto-only; Gen 3 no badges/party (encrypted); **Gen 4 only trainer+playtime**; **Gen 5 nothing** (notes only).
- Gen 3/4/5 party mons are **encrypted** (need PKM decryption) — not attempted.
- `_findSaveFile` guesses by extension next to the ROM; no per-emulator save-path knowledge.

## Emulator launching ([[Emulator Launching]])
- **Verify before recommending.** A package must (a) exist in the store and (b) accept external ROM intents. Two wrong guesses (RetroArch Plus, mGBA-on-Play) came from skipping this.
- **Pizza Boy** and **Lemuroid** are library-only in practice → `handoffFailed`. Lemuroid is `launchable:false`; use the folder-sync flow.
- On **Android**, a "detected emulator path" is actually a **package id**, not a filesystem path.
- ROMs must be **staged into `cache/roms/`** before hand-off — `getApplicationDocumentsDirectory()` (`app_flutter`) isn't covered by the `FileProvider` `file_paths.xml`, so `getUriForFile` throws otherwise. Don't relocate ROM storage (Windows shares the documents dir).
- `emulatorForGame` returns null for **Gen ≥ 8 and Let's Go** → those games never show Play.

## Box/spine art ([[Box Art System]])
- The 3D-box spine is **flipped** (`Transform.flip`) because the ±90° face rotation shows the mirrored back; the flat shelf `GameSpine` is **not** flipped. Getting this wrong mirrors the spine text.
- DS/3DS spine layouts still need real measurement where wraps exist; most Gen 7+ games have **no wrap** → they use the front-cover + generated-spine fallback.

## Windows specifics
- **3D model viewing needs the WebView2 runtime** and spins up a **local loopback `HttpServer`** per view ([[Console Mode and Launch Animation]]); `.glb` models exist only for the Game Boy family.
- Self-update calls **`exit(0)`** after launching the installer — the app quits, so code after the `await` in `updates_screen.dart` runs only on Android ([[Auto-Update]]).
- A running `poketracker.exe` **locks the build output** — kill it before `flutter build windows` ([[Build and Release]]).

## Data / ID mismatches ([[Data Layer]])
- `kGameVersionGroups` keys (`rby`, `pla`, `lza`) do **not** match `kGames` ids (`red`, `legends-arceus`, `legends-z-a`). Unknown groups → empty `GameDex`.
- `region_theme.dart` has no color for **Lumiose City** (Legends Z-A) → falls back to accent.
- `assets/games/` has **39** covers vs **38** catalog entries — a stray `green` cover (and a `green` key in `drive_folders.json`) matches no `kGames.id`.
- Android `<queries>` lists `io.mgba.android.emulator` + `com.dsemu.drastic`, not in `kEmulators` ([[Native Android Layer]]).

## Caching
- PokéAPI responses are cached in `shared_preferences` **forever**, keyed by URL — stale data persists until prefs are cleared ([[Pokedex]]).

## Toolchain (this machine)
- Android SDK is at **`C:\dev\Android`**, not `C:\Android` (drive-root blocked). Update `build_both.ps1` before a release ([[Machine Setup]]).
- No inline `TODO`/`FIXME` markers exist — incomplete work is expressed via doc comments and user-facing "notes" strings instead.

---
Related: [[Constraints and Legal]] · [[Save Auto-Tracker]] · [[Emulator Launching]] · [[Machine Setup]]

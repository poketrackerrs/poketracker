---
tags: [poketracker, architecture, ui]
---
# Screens

`lib/screens/` — the UI surfaces. All read [[AppState]] via `provider`.

## `home_screen.dart` — the root
`AppBar` (Emulators + Check-for-updates actions) over a 3-tab `NavigationBar`/`IndexedStack`: **Games · Pokédex · Settings**.
- `_GamesTab` — `_OverallCard` (avg [[Box Art System|completion ring]] + started/caught/badges), a `_ModeToggle` (**Consoles** vs **List**), then either `_ConsoleGrid` (→ [[Console Mode and Launch Animation]]) or a per-gen list of `_GameTile`s.
- `_GameTile` — box art, meta chips, completion ring, `_DownloadControl` (download progress → Play via `tryLaunchGame` with per-`LaunchOutcome` snackbars → reveal in folder, or a download button).

## `game_screen.dart` — per-game detail
A 4-tab controller (**Badges · Pokédex · Team · Shiny**) with a "Sync from save file" AppBar action (→ [[Save Auto-Tracker]]).
- `_GameHeader` — tappable 3D box popout (`GameBoxArt`), meta chips, completion ring.
- `_MilestonesTab` — `_BadgeDisc`s + `_MilestoneRow`s → `setMilestone`.
- `_DexTab` (stateful) — loads the game's regional dex + alternate forms (filtered by intro gen), caught filter (all/caught/missing), obtainability chips, caught checkboxes.
- `_TeamTab` — up to 6 members with an edit sheet.
- `_ShinyTab` — hunts with **odds math** (`_shinyRate`, cumulative probability), counters, caught toggle.
- Save-sync flow: `_startSaveSync` → `_locateSave` → `_SaveSyncDialog` (dex/badges/team checkboxes → `applySaveData`).

## `console_shelf_screen.dart` → [[Console Mode and Launch Animation]]
A console's games as cartridge **spines** on a wooden shelf; tap to inspect, Play runs the launch animation then hands off to the emulator. Includes the `_LaunchSequence` `AnimationController` (3200ms) and the `.glb` "Cartridge 3D" viewer.

## `launch3d.dart` → [[Console Mode and Launch Animation]]
Pre-rendered **frame-based** Game Boy launch animation. `showLaunch3D(...)`; `_frameCount = 68` (`assets/launch/f00.png`…`f67.png`), precached before playing (2500ms). Plays `sfx/insert.wav` + `sfx/poweron.wav`.

## `cartridge_viewer.dart`
Cross-platform `.glb` viewer. `showModelViewerDialog(...)`; `ModelView` uses `model_viewer_plus` on mobile and `_WindowsModelView` on Windows — which spins up a **local loopback `HttpServer`** serving the `.glb` + bundled `model-viewer.min.js` into a `webview_windows` (WebView2) instance. See [[Gotchas]].

## `pokedex_list_screen.dart` → [[Pokedex]]
National-dex grid (Pokédex tab). Gen chips, search (name/number), Forms toggle, caught check from `allCaughtSpecies`. Opens `PokemonDetailScreen`.

## `pokemon_detail_screen.dart` → [[Pokedex]]
Full species detail: type-colored header, form switcher, infobox, stats (bars vs **hexagon radar**), type defenses, evolution line, per-gen dex entries, and a moves section with gen dropdown + method chips.

## `emulators_screen.dart`
Lists detected emulators (rescans on open). `_EmulatorCard` — status, systems/note, **Open** (installed) or **Get** + **Locate…** (manual path → `setEmulatorPath`). See [[Emulator Launching]].

## `settings_screen.dart`
Sections: **Appearance** (theme, accent swatches, region-tint), **Emulators** (per-platform store links), **Game downloads** (Drive-link import; Android-only Lemuroid sync), **Library** (folder path, refresh/open), **Updates**, **About** (`PackageInfo` version).

## `updates_screen.dart` → [[Auto-Update]]
Checks the manifest on open; shows current version, an update card with notes, a download progress bar, and `downloadAndInstall`. On Windows the app **exits** before returning.

---
Related: [[Architecture Overview]] · [[AppState]] · [[Box Art System]]

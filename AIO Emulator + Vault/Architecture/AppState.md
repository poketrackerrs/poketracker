---
tags: [poketracker, architecture, state]
---
# AppState

`lib/state/app_state.dart` — the **central `ChangeNotifier`** and single source of truth. It owns every [[Services|service]], holds all progress + UI state, and persists on every change. The UI ([[Screens]]) reads it via `provider`.

> [!note] Owned services (private finals)
> `StorageService` · `LibraryService` · `EmulatorService` · `SaveService` · `PokedexService` · `LemuroidSyncService` — see [[Services]].

## `LaunchOutcome` enum (top-level)
Returned by `tryLaunchGame` and mapped to user-facing snackbars:
- `launched` — emulator opened **and** loaded the ROM
- `handoffFailed` — emulator opened but wouldn't auto-load the ROM (e.g. library-only apps)
- `noEmulator` — no installed, launchable emulator for this game

## Main fields

| Field | Meaning |
|---|---|
| `Map<String, GameProgress> _progress` | per-game progress, keyed by game id (see [[Models]]) |
| `List<DetectedEmulator> _detectedEmulators` | detected emulators (getter `detectedEmulators`) |
| `Map<String,String> _driveFolders` | gameId → Google Drive folder id |
| `Map<String,String?> _installed` | gameId → ROM file path (or null) |
| `Map<String,double> _downloadProgress` | gameId → 0..1 |
| `String _libraryPath` | ROM library folder |
| `ThemeMode _themeMode` · `Color _accent` | theme; `defaultAccent = 0xFFEE1515` (Poké Ball red) |
| `bool _regionTint` (true) · `bool _consoleMode` (true) | UI prefs |

## Key methods

- **Lifecycle:** `init()` — loads saved progress, restores prefs (`thememode`, `accent`, `regiontint`, `consolemode`), loads the library, sets `_loaded`, notifies.
- **Setters** (persist + notify): `setThemeMode`, `setAccent`, `setRegionTint`, `setConsoleMode`.
- **Dashboard stats** (getters): `startedCount`, `totalCaught` (base species only, `id < 10000`), `allCaughtSpecies` (union set), `totalBadges` (milestones whose key contains "Badge").
- **Emulators / launching** → see [[Emulator Launching]]:
  - `emulatorForGame(Game)` — null for Gen ≥ 8 and Let's Go; else first installed **launchable** emulator whose `generations` includes the game's gen.
  - `canLaunch`, `launchGame`, `emulatorNameFor`, and **`tryLaunchGame(Game) → LaunchOutcome`** (rescans, launches, maps result).
- **Library / downloads** → see [[ROM Library and Downloads]]: `refreshInstalled`, `isInstalled`, `canDownload`, `downloadGame` (Drive, with progress; Android also mirrors to Lemuroid), `deleteGameFile`, `openLibraryFolder`, `revealGameFile`, plus Lemuroid passthroughs.
- **Save auto-tracker** → see [[Save Auto-Tracker]]: `savePath`/`setSavePath`, `_findSaveFile` (ROM-adjacent by extension), `scanSave(Game)`, `applySaveData(...)` (merges caught species — **never removes** — sets badges, replaces team).
- **Progress mutators** (each → `_persist()`): `setMilestone`, `setDexSeen`, `setDexCaught`, `setCaught`/`isCaught`/`caughtCount`, team (`addTeamMember` cap 6, `updateTeamMember`, `removeTeamMember`), shiny (`addShinyHunt`, `updateShinyHunt`, `removeShinyHunt`).
- **`completion(Game) → double`** — average of the milestone fraction and the dex fraction (dex uses per-species base count `id < 10000`, else falls back to manual `dexCaught`).

> [!tip] The "never remove caught" rule
> `applySaveData` **unions** caught species from a save into existing progress — a save scan can only *add*, never wipe manual edits. This is the safety net that makes the [[Save Auto-Tracker]] non-destructive.

---
Related: [[Architecture Overview]] · [[Services]] · [[Models]] · [[Screens]]

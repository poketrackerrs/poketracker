---
tags: [poketracker, reference, glossary]
---
# Glossary

Terms, IDs, and constants used across the app.

## Core types
- **[[AppState]]** — the single `ChangeNotifier` holding all state and owning the services.
- **`Game`** — a catalog entry (id, region, gen, milestones…). See [[Models]] / [[Games Catalog]].
- **`GameProgress`** — the persisted per-game record (milestones, dex, team, shinies).
- **`SaveData`** — the parsed output of a [[Save Auto-Tracker|save-file scan]].
- **`DetectedEmulator`** — an `Emulator` + a resolved `path` (or package id on Android).
- **`GameDex` / `PokemonDetail`** — [[Pokedex]] view models from PokéAPI.

## Enums
- **`LaunchOutcome`** — `launched` · `handoffFailed` · `noEmulator` (result of `tryLaunchGame`).
- **`GameCategory`** — `mainline` · `legends`.
- **`BoxPlatform`** — `gb` · `gbc` · `gba` · `ds` · `n3ds` · `nswitch` (drives the [[Box Art System]]).
- **`ObtainKind`** — `wild` · `partial` · `none` · `unknown` (Pokédex obtainability).

## IDs & keys
- **game `id`** — e.g. `red`, `legends-arceus`. Used for `assets/games/<id>.png`, the library folder `Games/<id>/`, and prefs like `savepath:<id>`, `romsrc:<id>`, `emupath:<name>`.
- **`versionGroup`** — PokéAPI version-group slug (e.g. `red-blue`), used by [[Pokedex]].
- **form ids ≥ 10000** — alternate forms; stored but **excluded** from completion math.
- **base species `id < 10000`** — counts toward `totalCaught` / completion.

## Persistence keys (`shared_preferences`)
- `poketracker_progress_v1` — the whole progress JSON blob.
- `thememode`, `accent`, `regiontint`, `consolemode` — UI prefs.
- `pokecache:<url>` — cached PokéAPI responses (**never expire**).
- `savepath:<id>`, `romsrc:<id>`, `emupath:<name>` — per-item paths/sources.

## Constants worth knowing
- `defaultAccent = 0xFFEE1515` (Poké Ball red).
- `nationalDexCount = 1025`; PokéAPI base `https://pokeapi.co/api/v2`.
- `kUpdateManifestUrl` → `raw.githubusercontent.com/poketrackerrs/poketracker/main/update.json`.
- Launch animation: **68** frames (`f00`–`f67`); box hinge sequence 3200ms; frame sequence 2500ms.

## Method channels (Android)
- `poketracker/installer` · `poketracker/emulators` · `poketracker/storage` — see [[Native Android Layer]].

---
Related: [[Home]] · [[Architecture Overview]]

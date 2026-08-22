---
tags: [poketracker, architecture, data]
---
# Data Layer

`lib/data/` holds the app's **static catalogs** — the games, the emulators, the PokéAPI lookup maps, and the region/accent colors. These are `const` and consumed almost everywhere.

## `games_data.dart`
The full catalog of mainline + Legends games and the shared milestone lists.
- Private `const` milestone lists per region: `_kanto`, `_johto`, `_hoenn`, `_sinnoh`, `_unovaBW`, `_unovaB2W2`, `_kalos`, `_alola`, `_galar`, `_paldea`, `_hisui`, `_za`. Each is an ordered `List<String>` of labels (badges end with **"Badge"**; also "Elite Four", "Champion", etc.).
- **`const List<Game> kGames`** — **39 entries**, Gen 1 → Gen 9, including remakes and Legends (Arceus, Z-A). Each carries `id, title, generation, region, releaseYear, category, milestones, dexTotal, versionGroup, version`.
- `gamesByGeneration() → Map<int, List<Game>>`.

See the full list in [[Games Catalog]]. The `Game` model is in [[Models]].

## `emulators.dart`
The catalog of detectable emulators.
- **`class Emulator`** — `name, systems, generations (List<int>), exeNames, hints, androidPackages, downloadUrl, note, launchable (default true)`.
  - `launchable: false` = **library-only** app that can't be handed a ROM via intent/CLI (e.g. Lemuroid).
- **`const List<Emulator> kEmulators`** — mGBA, My OldBoy!, My Boy!, melonDS, DeSmuME, Azahar (Citra/Lime3DS), Lemuroid (`launchable:false`), Pizza Boy, RetroArch.

Full breakdown in [[Emulators Catalog]]; detection/launch logic in [[Emulator Launching]].

## `pokeapi_maps.dart`
Lookup maps between PokéAPI names and generations, plus display helpers.
- `kVersionToGen` — PokéAPI "version" → gen.
- `kVersionGroupToGen` — "version group" → gen.
- `kGameVersionGroups` — abbreviated ids (`rby`, `gsc`, …, `lza`) → version groups.
- `prettifyName(slug)`, `kStatLabels` (canonical stat order → display), `kLearnMethodLabels`.

> [!warning] ID mismatch
> The keys in `kGameVersionGroups` (`rby`, `pla`, `lza`, …) do **not** match `kGames` ids (`red`, `legends-arceus`, `legends-z-a`). The comment flags that `lza` may not exist in PokéAPI. Unknown groups are handled by returning an empty `GameDex`. See [[Gotchas]].

## `region_theme.dart`
Region and accent colors.
- `kRegionColors` — 10 regions (Kanto red `0xFFEE1515` … Hisui `0xFF3E8E7E`).
- `regionColor(region, fallback)` — falls back to the accent when a region is missing (e.g. Legends Z-A's **Lumiose City** has no entry). See [[Gotchas]].
- `kAccentChoices` — the 6 accent swatches offered in [[Screens|Settings]].

---
Related: [[Architecture Overview]] · [[Models]] · [[Games Catalog]] · [[Emulators Catalog]]

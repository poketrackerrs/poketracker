---
tags: [poketracker, feature, pokedex, pokeapi]
---
# Pokedex

A full **PokéAPI-backed** species browser plus per-game regional dexes. Backed by `PokedexService` ([[Services]]), models in `pokedex_models.dart` ([[Models]]), UI in `pokedex_list_screen.dart` + `pokemon_detail_screen.dart` ([[Screens]]).

## Data source & caching
- Base `https://pokeapi.co/api/v2`; national dex count **1025**.
- Every raw response is cached in `shared_preferences` (key `pokecache:<url>`) **with no expiry**, plus an in-memory `_memCache`. Requests time out at 20s.

> [!warning] Cache never expires
> PokéAPI reads are cached forever, keyed by URL. Stale data persists until the pref store is cleared. See [[Gotchas]].

## Key service methods
- `loadIndex()` — id → name in one request.
- `loadAllVarieties()` / `loadFormsByBase()` — base species + forms (**form ids ≥ 10000**; excluded from completion math).
- `loadGameDex(versionGroup) → GameDex` — resolves the regional dex(es) + versions; returns an **empty `GameDex`** if the version group isn't in PokéAPI (e.g. an unreleased game like Legends Z-A — see the ID-mismatch note in [[Data Layer]]).
- `loadObtainability(speciesId, gameVersions) → ObtainInfo` — from `/pokemon/{id}/encounters` → `wild` / `partial` / `none` / `unknown`.
- `fetchDetail(id) → PokemonDetail` and `fetchForm(formId) → FormOverride` via `_buildCore` (types, stats, moves, abilities + effect text, past types, matchups, art). `_evolutionChain` walks the chain recursively.

## National-dex grid (`pokedex_list_screen.dart`)
Gen chips (via `_genRanges`), name/number search, a Forms toggle, and a caught check sourced from `AppState.allCaughtSpecies`. Sprites via `cached_network_image`. Taps open the detail screen.

## Species detail (`pokemon_detail_screen.dart`)
- Type-colored header (`_typeColors`, 18 types), optional `generation` scoping, `initialFormId`.
- Sections: **form switcher**, **infobox** (height/weight/abilities/catch rate/gender/egg groups/growth/friendship), **stats** (bars *or* a **hexagon radar** `_StatHexPainter`), **type defenses** (weak/resist/immune via `_mult`), **evolution line**, **per-gen dex entries**, and a **moves section** (gen dropdown + method chips). Forms are fetched on demand (`_selectForm` → `FormOverride`).
- `PokemonDetail.typesForGeneration(gen)` applies historical `pastTypes` so older gens show period-correct typing.

---
Related: [[Services]] · [[Models]] · [[Screens]] · [[Data Layer]]

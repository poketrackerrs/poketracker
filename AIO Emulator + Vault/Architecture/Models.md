---
tags: [poketracker, architecture, models]
---
# Models

`lib/models/` — plain, mostly-immutable data classes. The progress/save/game models are `shared_preferences`-serializable (`toJson`/`fromJson`); the Pokédex models are PokéAPI-derived view models.

## `game.dart`
- **`class Game`** (immutable) — `id, title, generation, region, releaseYear, category, milestones, dexTotal, versionGroup, version`. Getter `boxArtAsset => 'assets/games/$id.png'` (see [[Box Art System]]).
- **`enum GameCategory { mainline, legends }`** + `GameCategoryLabel` extension (`.label`).

The catalog of `Game` instances lives in [[Data Layer]] / [[Games Catalog]].

## `progress.dart` — the persisted progress model
- **`class GameProgress`** — `gameId`, `Map<String,bool> milestones`, `int dexSeen`, `int dexCaught`, `Set<int> caughtSpecies`, `List<TeamMember> team`, `List<ShinyHunt> shinyHunts`. `toJson`/`fromJson`.
- **`class TeamMember`** — `species, nickname, level` (default 1).
- **`class ShinyHunt`** — `species, method` (default 'Random encounter'), `count, caught`.

This is what [[AppState]] holds per game and what [[Services|StorageService]] serializes.

## `save_models.dart` — the [[Save Auto-Tracker]] output
- **`class SaveData`** — `generation, versionId, caughtDex (Set<int>), seenCount, badgeCount?, team, trainerName?, trainerId?, money?, playTime?, notes`. Getters `caughtCount`, `playTimeText`.
- **`class SaveTeamMon`** — `dexId?, level, nickname?, name?` (name resolved from the dex index later).
- **`class SaveParseException implements Exception`** — `message`.

## `pokedex_models.dart` — PokéAPI view models
Consumed by [[Pokedex]] and its [[Services|PokedexService]].
- `PokemonSummary` (`spriteUrl`/`artworkUrl` from PokéAPI sprite CDN).
- `GameSpecies`, `GameDex` (species + versions).
- `enum ObtainKind { wild, partial, none, unknown }`, `ObtainInfo`.
- `MoveEntry`, `AbilityInfo`, `PastType`, `EvoStage` (with `condition`), `PokemonForm`, `FormOverride`.
- **`PokemonDetail`** — full species data incl. Bulbapedia-style infobox fields (height, weight, genus, captureRate, genderRate, eggGroups, baseHappiness, growthRate, forms). Methods: `copyWithForm(FormOverride)`, `genderText`, **`typesForGeneration(gen)`** (applies `pastTypes`), `artworkUrl`, `statTotal`, `moveGenerations`.

---
Related: [[Architecture Overview]] · [[AppState]] · [[Save Auto-Tracker]] · [[Pokedex]]

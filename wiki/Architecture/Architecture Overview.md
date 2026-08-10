---
tags: [poketracker, architecture, moc]
---
# Architecture Overview

PokeTracker is a single-`ChangeNotifier` Flutter app. All state lives in [[AppState]], which owns the [[Services]]; the UI ([[Screens]]) reads from `AppState` via `provider` and calls its mutators, which persist and notify.

```
        ┌─────────────────────────────────────────────┐
        │                   Screens                    │  ← provider.watch(AppState)
        │   Home · Game · Pokédex · ConsoleShelf · …   │
        └───────────────┬─────────────────────────────┘
                        │ read state / call mutators
        ┌───────────────▼─────────────────────────────┐
        │                  AppState                    │  ← the ChangeNotifier
        │  progress · installed · emulators · theme    │
        └───┬───────┬───────┬───────┬───────┬──────────┘
            │       │       │       │       │  owns services
        ┌───▼──┐ ┌──▼───┐ ┌─▼────┐ ┌▼─────┐ ┌▼────────┐
        │Storage│ │Library│ │Emul │ │Save │ │Pokedex …│    → see [[Services]]
        └───┬──┘ └──┬───┘ └─┬────┘ └┬─────┘ └┬────────┘
            │       │       │       │        │
   shared_prefs   disk   MethodChannels   PokéAPI / Drive
                          → [[Native Android Layer]]
```

## The layers

| Layer | Folder | Note | Responsibility |
|---|---|---|---|
| **Entry & config** | `lib/main.dart`, `lib/config.dart` | below | App root, theming, update-URL constant |
| **State** | `lib/state/` | [[AppState]] | Single source of truth; owns services; persists progress |
| **Data** | `lib/data/` | [[Data Layer]] | Static catalogs (games, emulators, PokéAPI maps, region colors) |
| **Models** | `lib/models/` | [[Models]] | Plain immutable/serializable data classes |
| **Services** | `lib/services/` | [[Services]] | I/O: disk, network, platform channels, parsing |
| **Screens** | `lib/screens/` | [[Screens]] | The UI surfaces |
| **Widgets** | `lib/widgets/` | [[Box Art System]] | Reusable widgets, esp. the 3D art system |
| **Native** | `android/.../MainActivity.kt` | [[Native Android Layer]] | Kotlin method channels |

## Entry & config

- **`lib/main.dart`** — `main()` wraps `PokeTrackerApp` in `ChangeNotifierProvider(create: (_) => AppState()..init())`. `PokeTrackerApp` reads `AppState.accent` + `AppState.themeMode` and builds a Material 3 theme via `_buildTheme(seed, brightness)` (`ColorScheme.fromSeed`, custom dark surfaces `0xFF0F1013` / cards `0xFF1B1D22` / app bar `0xFF15171B`, nav bar height 66). `home: HomeScreen`.
- **`lib/config.dart`** — one constant: `kUpdateManifestUrl` → `raw.githubusercontent.com/poketrackerrs/poketracker/main/update.json`. Consumed by [[Auto-Update]].

## Key data-flow patterns

- **Persist-and-notify.** Every mutator on [[AppState]] ends in `_persist()` (notify + `StorageService.save`) or a pref write + `notifyListeners()`. The whole progress map serializes to **one JSON blob** (`poketracker_progress_v1`).
- **Conditional imports for platform code.** [[Auto-Update]] uses `update_installer.dart` → `_io.dart` (dart:io) vs `_stub.dart` (web).
- **MethodChannels for native.** Three channels bridge to Kotlin — see [[Native Android Layer]].
- **Cache-forever network reads.** [[Pokedex]] caches PokéAPI responses in `shared_preferences` keyed by URL with no expiry.

---
Related: [[Home]] · [[Overview]] · [[AppState]]

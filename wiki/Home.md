---
tags: [poketracker, moc, home]
---
# 🔴 PokeTracker — Project Wiki

**PokeTracker** is a personal, cross-platform **Flutter** app for tracking progress across the mainline Pokémon games (Gen 1–9) plus Legends (Arceus, Z-A) — badges/milestones, Pokédex caught/seen, teams, and shiny hunts — with a built-in PokéAPI Pokédex, a save-file auto-tracker, a ROM library/downloader, and a 3D **"console mode"** that launches games in installed emulators.

> [!info] At a glance
> Package `poketracker` · version **1.0.46+47** · **Flutter 3.44.9 / Dart 3.12.2**
> App id `com.baygroupusa.poketracker` · State via `provider` (single [[AppState]]) · Persistence via `shared_preferences`
> Targets: **Windows** (`.exe` installer) + **Android** (`.apk`), iOS via CI. Auto-updates from GitHub Releases.

---

## 🚀 Start here
- [[Overview]] — what it is, who it's for, and the **hard constraints**
- [[Architecture Overview]] — the layers and how data flows
- [[Machine Setup]] — **this laptop's** verified toolchain paths ⚙️
- [[Build and Release]] — how to build and ship

## 🏗 Architecture
- [[AppState]] — the single source of truth (`ChangeNotifier`)
- [[Data Layer]] — the game/emulator/PokéAPI catalogs
- [[Models]] — plain data classes
- [[Services]] — library, emulators, saves, Pokédex, updates
- [[Screens]] — the UI surfaces
- [[Box Art System]] — the constructed 3D box/spine art
- [[Native Android Layer]] — the three Kotlin method channels

## ✨ Features
- [[Save Auto-Tracker]] — read progress straight from emulator save files
- [[Emulator Launching]] — hand a ROM to an installed emulator
- [[Pokedex]] — full PokéAPI-backed species browser
- [[Console Mode and Launch Animation]] — the 3D shelf + launch sequence
- [[Auto-Update]] — self-update from GitHub Releases
- [[ROM Library and Downloads]] — the on-device library + Drive downloader

## 📚 Reference
- [[Games Catalog]] — the 39 games and their milestones
- [[Emulators Catalog]] — which emulators are supported and how
- [[Glossary]] — terms and IDs used across the app

## 🛠 Maintainer notes
- [[Gotchas]] — hard-won lessons, sharp edges, incomplete features
- [[Constraints and Legal]] — personal-use rules and the ROM/copyright boundary

---
> [!tip] Using this vault
> Open the `wiki/` folder as an Obsidian vault (**Open folder as vault**). Everything is plain Markdown with `[[wikilinks]]` — no plugins required. Try the **graph view** to see how the notes connect.

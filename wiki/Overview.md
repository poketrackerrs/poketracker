---
tags: [poketracker, overview]
---
# Overview

**PokeTracker** is the owner's **personal** cross-platform Flutter app for tracking progress across the mainline Pokémon games (Gen 1–9) and the Legends titles (Arceus, Z-A).

It combines several tools in one app:

| Capability | Where it lives |
|---|---|
| Progress tracking (badges, dex, teams, shinies) | [[AppState]] + [[Models]] + [[Screens]] |
| Built-in Pokédex (PokéAPI) | [[Pokedex]] |
| Save-file auto-tracker | [[Save Auto-Tracker]] |
| ROM library + Google Drive downloader | [[ROM Library and Downloads]] |
| Emulator detection + launching | [[Emulator Launching]] |
| 3D box art + "console mode" launch animation | [[Box Art System]] · [[Console Mode and Launch Animation]] |
| Self-update from GitHub Releases | [[Auto-Update]] |

**Targets:** Windows (`.exe` installer) and Android (`.apk`). iOS builds via CI (unsigned, sideloaded). See [[Build and Release]].

---

## Who it's for & the hard constraints

> [!warning] Read before doing anything "helpful"
> These constraints are non-negotiable and shape every design decision. See [[Constraints and Legal]] for the full detail.

- **Personal use only.** The owner has repeatedly said this "will never be distributed to anyone other than myself." The public GitHub repo exists only so they can build/sync between their own devices.
- **Never build a ROM downloader / distribution pipeline.** ROM *downloading* has been declined multiple times. The app only manages the user's **own** legally-dumped ROMs (they supply their own source URLs / Drive links).
- **Box art is a private-use fair-use call.** Covers/wraps/models are committed because the repo is never distributed. If it's ever repackaged for distribution, the covers are copyrighted — revisit then.
- **Never commit built binaries** (`*.apk`, `*.aab`, `*-Setup.exe`). They're regenerable and large; release binaries go **only** as GitHub Release assets.

---

## Tech stack

- **Framework:** Flutter (Material 3), Dart `^3.12.2`
- **State:** `provider` — a single [[AppState]] `ChangeNotifier`
- **Persistence:** `shared_preferences` (one progress JSON blob + individual prefs)
- **Networking:** `http` (PokéAPI, Google Drive scraping, update manifest)
- **Media/3D:** `audioplayers`, `model_viewer_plus`, `webview_windows`, `cached_network_image`

See [[Services]] for the full dependency list and responsibilities.

---
Related: [[Home]] · [[Architecture Overview]]

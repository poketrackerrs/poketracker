---
tags: [poketracker, architecture, ui, 3d]
---
# Box Art System

`lib/widgets/` — the reusable widgets, dominated by a hand-rolled **3D box/spine art** system that renders each game as a real, drag-to-spin 3D box. This is one of the app's signature visuals.

## `game_box_art.dart` — the core 3D box
- **`enum BoxPlatform { gb, gbc, gba, ds, n3ds, nswitch }`**; `platformForGame(Game)` maps generation (+ Let's Go → Switch) to a platform.
- **`class GameBoxArt`** (stateful) — renders a game's box in 3D:
  - If `assets/games/wraps/<id>.png` exists → textures **front / spine / back** panels of the full box wrap onto the faces.
  - Otherwise → front cover image + a **generated spine** + a per-gen gradient fallback (`genGradients`).
  - **Manual 3D pipeline:** builds 6 faces (center, outward normal, local rotation, child); `_tz` transforms z for **back-face culling** + far→near depth sorting; a `Transform` with perspective (`setEntry(3,2,0.0009)`) applies `rotateX(pitch)` / `rotateY(yaw)`.
  - `interactive: true` enables **drag-to-spin** (`onPanUpdate`, clamped yaw/pitch).
- **`class WrapLayout`** — fractional `back`/`spine`/`front` panels of a wrap image (left→right) + `spineSplit` (fraction of the printed spine occupied by the console banner). Per-platform `const` layouts: `_gbWrap`, `_gbcWrap`, `_gbaWrap`, `_dsWrap`, `_n3dsWrap` (Switch has none → fallback).
- **`class GameSpine`** (stateful) — the recomposed spine as a **flat vertical strip** for the shelf (see [[Console Mode and Launch Animation]]); falls back to a tinted strip + short title.

> [!note] Why the spine gets flipped on the 3D box but not the shelf
> On the 3D box, the ±90° face rotation shows the **mirrored** back of the spine texture, so `_wrapSpineFace` applies a horizontal `Transform.flip` and recomposes the console banner to the bottom + title on top. The flat `GameSpine` (shelf) faces the viewer directly, so it is **not** flipped. Getting this wrong mirrors the spine text. See [[Gotchas]].

## `console_art.dart`
Stylized **vector** consoles + cartridges (no bitmaps).
- `ConsoleArt` — per-platform painted console with a `glow` (0..1 screen light); the Game Boy can show a photo (`assets/models/gameboy_icon.png`) or the constructed `GameBoy3D`.
- `_ConsolePainter` draws `_handheld` (GB/GBC), `_gba`, `_clamshell` (DS/3DS), `_switch`.
- `CartridgeArt` + `_CartPainter` — console-shaped cartridge art used in the launch animation.
- `kConsoleNames`, `kConsoleOrder` — shelf order.

## `gameboy_3d.dart`
**`class GameBoy3D`** (stateful) — a constructed 3D DMG-01 (extruded slab): painted front (`_GameBoyFront`: LCD glow, D-pad, A/B, wordmark, speaker grille), back (`_GameBoyBack`: cartridge slot, label plate, screws, battery ridges), top edge, gradient sides. Same perspective + back-face-culling technique as `GameBoxArt`. Rotation can be **driven externally** (`yaw`/`pitch`) for the launch animation or dragged when `interactive`.

## `completion_ring.dart`
**`CompletionRing`** — the circular percent ring used across [[Screens]] (`value 0..1`, color, size, stroke; `_RingPainter` draws an arc from −π/2).

## Asset inventory
- `assets/games/` — **39** front covers (one per game id)
- `assets/games/wraps/` — **21** full box wraps (Gen 1–6 subset; note `blue.png` but no `green.png`, and most DS/3DS-era games have no wrap → fallback)
- `assets/games/dielines/` — 1 working file (gitignored)
- `assets/models/` — `gameboy_cartridge.glb`, `gameboy_classic.glb`, `gameboy_icon.png`
- `assets/launch/` — `cart.png` + **68** launch frames
- `assets/sfx/` — `insert.wav`, `poweron.wav`
- `assets/web/model-viewer.min.js` — offline model-viewer for Windows

---
Related: [[Screens]] · [[Console Mode and Launch Animation]] · [[Games Catalog]]

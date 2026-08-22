---
tags: [poketracker, feature, ui, 3d]
---
# Console Mode and Launch Animation

"Console mode" (default on, `AppState.consoleMode`) presents games as a shelf of consoles → cartridge spines, and plays a **3D launch animation** before handing the ROM to an emulator. Built on the [[Box Art System]].

## Console shelf (`console_shelf_screen.dart`)
- Reached from `_ConsoleGrid` on the [[Screens|home screen]] — games grouped by `BoxPlatform`.
- `_shelf` — horizontal `GameSpine` strips on a wooden-gradient shelf; the selected spine raises.
- `_selectedPanel` — box popout (`GameBoxArt`), Play / Download / Details, and **"Cartridge 3D"** (`showModelViewerDialog` → the `.glb` viewer; Game Boy family only).
- `_runLaunch` — Game Boy games use `showLaunch3D`; others use the `_LaunchSequence` dialog. Both map `LaunchOutcome` to snackbars (see [[Emulator Launching]]).

## `_LaunchSequence` (in-widget animation)
Stateful `AnimationController`, **3200ms**: the box hinges open, the cartridge ejects and rises into the console, the console rotates back→front and powers on. Plays `sfx/insert.wav` and `sfx/poweron.wav` at timeline thresholds.

## Frame-based Game Boy launch (`launch3d.dart`)
- `showLaunch3D(context, {game, onLaunch})`; `_frameCount = 68` → `assets/launch/f00.png`…`f67.png`.
- **Precaches** `cart.png`, the box art, and all 68 frames before playing (2500ms). Documented timeline: box opens → cart lifts → crossfade to the 3D frames → insertion/turn → power-on flash. Same two SFX.

## `.glb` model viewer (`cartridge_viewer.dart`)
- `showModelViewerDialog(context, {src, title})`.
- Mobile → `model_viewer_plus`; **Windows → `_WindowsModelView`**, which starts a **local loopback `HttpServer`** serving the `.glb` + bundled `assets/web/model-viewer.min.js` into a `webview_windows` (WebView2) instance.
- Only the Game Boy family has models (`gameboy_cartridge.glb`, `gameboy_classic.glb`).

> [!warning] Windows requirement
> 3D model viewing on Windows needs the **WebView2 runtime**; a missing runtime shows an error message instead of the model. See [[Gotchas]].

---
Related: [[Box Art System]] · [[Screens]] · [[Emulator Launching]]

---
tags: [poketracker, planning, emulator, research]
---
# Built-in Emulator — Feasibility (GBA + DS)

Goal: play the user's **own** GBA (Gen 3) and DS (Gen 4–5) ROMs **inside** PokeTracker, instead of handing them off to an external app ([[Emulator Launching]]). Scope: Android 13 (primary — the owner's Galaxy A51) + Windows desktop. Researched 2026-08-10.

> [!summary] Verdict
> **Feasible, but a real project — not a weekend.** The right architecture is a **single libretro frontend** embedding `mgba_libretro` (GBA) and `melonDS DS` (DS) through one C ABI. It's an **Android‑first** effort (Flutter's Android texture path is mature; Windows' is the hard half). The biggest risk is that **nobody has published a mature "libretro core in a Flutter `Texture`" integration** — this is novel plumbing, mostly borrowed from LibretroDroid + irondash.

> [!success] Phase 0 spike — PROVEN on Windows (2026-08-10)
> Built a throwaway Flutter Windows app (`C:\dev\poketracker_emu_spike`) that loads the prebuilt `mgba_libretro.dll` via `dart:ffi`, registers the libretro callbacks, and runs a ROM.
> - **Pokémon Ruby boots and runs** in-window at a steady **~63 fps** (240×160, RGB565).
> - Video **and** audio callbacks both fire, frame-locked (`video==audio` counters).
> - No native C++ written — the prebuilt core + hand-written FFI bindings were enough.
> The novel-integration risk is retired for Windows. Frame display used the simple `RawImage` path (decode `ui.Image` per frame); the fast `Texture` path, audio playback, and input are the known next steps. **Android port (swap `.dll`→`.so`) is the remaining unknown to confirm.**

## Recommended architecture

One libretro host, cores loaded at runtime as separate `.so`/`.dll`:

```
Flutter UI (Dart)  ──FFI/method channel──▶  native C++ libretro frontend (own thread)
   Texture widget  ◀───frame───────────────  retro_run() → video_refresh → texture
   touch buttons   ───input state──────────▶  input_poll / input_state
   audio out       ◀───int16 batch──────────  audio_sample_batch → Oboe / WASAPI
```

- **Core loop runs in native C++ on its own thread** — never the Dart UI isolate. `retro_run()` blocks a full frame and fires synchronous, value-returning callbacks; Dart's async `NativeCallable.listener` can't serve those, so the hot callbacks (video/audio/input) stay in C++. Dart only drives load/start/stop/savestate/input.
- **Video → Flutter `Texture`**: Android uses `SurfaceProducer`/`SurfaceTextureEntry` (GPU, smooth 60fps). Windows uses the **pixel-buffer texture** (CPU upload — trivial at 240×160 / 256×384); escalate to ANGLE→D3D11 shared-handle only if shaders (CRT/LCD) are wanted.
- **Audio (~48kHz int16)**: Android **Oboe** (AAudio on API 27+, so fine on Android 13); Windows WASAPI/XAudio2 or cross-platform `flutter_soloud`. **Audio-driven sync + resampler** (the emulator is the clock).
- **Input**: RetroPad IDs via `input_state`; on-screen touch buttons + optional gamepad; DS bottom-screen touch → `RETRO_DEVICE_POINTER`.

## Cores + licensing

| System | Core | License | Notes |
|---|---|---|---|
| GBA | **mGBA** (`mgba_libretro`) | **MPL‑2.0** (friendly) | Most accurate GBA emu; BIOS optional (HLE). |
| DS | **melonDS DS** (`melondsds_libretro`) | **GPLv3** | Most accurate/active DS emu; the legacy `melonds_libretro` is obsolete. |
| DS (alt) | DeSmuME | GPLv2 | Avoid — GPLv2/GPLv3 mixing risk; less accurate. |
| — | `libretro.h` API | **MIT** | The frontend/glue itself carries no copyleft. |

- **The DS cores are GPL, so the public repo must go GPLv3.** Bundling a GPL core into the published combined app makes the whole published work GPLv3 — fine for a personal open project, but the app code then can't be proprietary. mGBA's MPL is friendlier but doesn't change the DS side (no permissive DS core exists). **Standardize the repo on GPLv3; pick `melonDS DS` as the one DS core.**
- **BIOS/firmware**: never bundle Nintendo files — user supplies them. GBA runs BIOS-free; DS games direct-boot without BIOS but real `bios7/9.bin` + `firmware.bin` improve compatibility (and are required for DSi). Same "your own dumps" model as [[Constraints and Legal]].
- **Distribution**: GPL ✗ Apple App Store; Google Play is iffy; **sideload / F-Droid are clean**. The owner already sideloads a personal build on Android 13, so this is moot. Ship cores as separate modules, not static-linked.

## Prior art (the risk signal)

No mature "**libretro core embedded in-process in a Flutter Texture**" project exists. You'd combine three references:
- **LibretroDroid** ([Swordfish90/LibretroDroid](https://github.com/Swordfish90/LibretroDroid)) — the C++ libretro frontend that powers Lemuroid: `core.cpp`, `video.cpp`+renderers+shaders, `audio.cpp`+Oboe+resamplers, `fpssync.cpp`, `input.cpp`, JNI bridge, savestates. **The closest blueprint** (minus Flutter). Phase 1 could even wrap it directly.
- **irondash** ([irondash/irondash](https://github.com/irondash/irondash)) — cross-platform Flutter external-texture infra (`irondash_texture`, `BoxedPixelData`, `SendableTexture` mark-from-any-thread). The reusable video path.
- **flutter_soloud** ([alnitak/flutter_soloud](https://github.com/alnitak/flutter_soloud)) — low-latency PCM streaming over FFI, Windows+Android.
- **NESd** ([jpjonte/NESd](https://github.com/jpjonte/NESd)) — a full pure-Dart emulator running on Windows *and* Android; good Flutter emulation-loop reference (no native core).
- **Freegosy** launches *external* RetroArch (not embedded) — UI/library patterns only.

## Hard parts, ranked

1. **Windows external-texture path** — GPU-surface is finicky (direct `ID3D11Texture2D` fails; needs DXGI shared handle + EGL/FBO; [flutter#121046](https://github.com/flutter/flutter/issues/121046) closed unresolved). Mitigation: **use the pixel-buffer path** — the upload at GBA/DS resolutions is negligible.
2. **Threading + the FFI callback model** — keep `retro_run` + hot callbacks in C++; expose only control to Dart. Thread-safe frame handoff to the texture is the core engineering.
3. **A/V sync / frame pacing** — reconcile ~59.7–60fps + audio clock with Flutter's vsync without underruns/judder (audio-driven + resampler, per LibretroDroid).
4. **DS specifics** — dual screens from one framebuffer, `RETRO_DEVICE_POINTER` touch, heavier CPU, BIOS handling.
5. **Savestates + lifecycle** — `retro_serialize`/`unserialize`, SaveRAM, ROM load paths.
6. **Build matrix** — NDK/CMake ABI splits (Android), DLL bundling + MSVC (Windows), reproducible core builds.

## Phased plan

- **Phase 0 — spike (days).** Build `mgba_libretro` for arm64‑v8a, `DynamicLibrary.open` it via `dart:ffi`, load a ROM, run headless, confirm the video/audio callbacks fire. De-risks the novel part before any UI.
- **Phase 1 — Android GBA (Gen 3).** LibretroDroid-style native frontend → `SurfaceProducer` texture + Oboe audio + touch controls. In-app play for GBA on the Android 13 device. Reuse, don't reinvent.
- **Phase 2 — DS (Gen 4–5).** Add `melonDS DS`; dual-screen layout + pointer touch + user BIOS handling.
- **Phase 3 — Windows parity.** Pixel-buffer `Texture` + WASAPI/`flutter_soloud`.
- **Phase 4 — polish.** Savestates, fast-forward, per-game input maps, optional shaders.

## How it fits the app

Replaces the external hand-off ([[Emulator Launching]]) for Gen 3–5 with in-app play: the [[Console Mode and Launch Animation|launch animation]] (console + cartridge insert) flows straight into the built-in emulator screen instead of an `ACTION_VIEW` intent. Keep external launch as a fallback. Still only the user's own ROMs — no change to [[Constraints and Legal]], no downloader.

## Android 13 notes
- Oboe → AAudio (API 27+) — supported.
- `SurfaceProducer` texture API available.
- Scoped storage already handled (ROMs staged to cache; `MANAGE_EXTERNAL_STORAGE` in the manifest — see [[Native Android Layer]]). Cores ship in `jniLibs` per ABI.
- Sideloaded personal build → the GPL/store tension doesn't apply.

---
Related: [[Emulator Launching]] · [[Emulators Catalog]] · [[Constraints and Legal]] · [[Home]]

# PokeTracker — agent handoff & project guide

This file auto-loads for Claude Code. It's the primary context for anyone
(agent or human) picking up this project — especially on a **freshly-copied
machine** where the previous machine's `~/.claude` memory does not travel.

---

## What this is

**PokeTracker** is the owner's **personal** cross-platform Flutter app for tracking
progress across the mainline Pokémon games (Gen 1–9) plus Legends (Arceus, Z-A):
badges/milestones, Pokédex caught/seen, teams, shiny hunts, plus a built-in
Pokédex (PokeAPI), a save-file auto-tracker, and a visual "console mode" that
launches games in installed emulators.

Targets: **Windows** (`.exe` installer) and **Android** (`.apk`). iOS builds via
CI (unsigned, sideloaded). It auto-updates from GitHub Releases.

### Hard constraints (read before doing anything "helpful")
- **Personal use only.** The owner has said repeatedly this "will never be
  distributed to anyone other than myself." The public GitHub repo exists only so
  they can build/sync between their own devices.
- **Never build a ROM downloader / distribution pipeline.** ROM *downloading* has
  been declined multiple times. The app only manages the user's **own** legally
  dumped ROMs (they supply their own source URLs / Drive links). Box-art covers
  are the owner's own fair-use call for a private build.
- **Never commit built binaries** (`*.apk`, `*.aab`, `*-Setup.exe`) — regenerable
  and large; `.gitignore` excludes them. Release binaries go **only** as GitHub
  Release assets, never into the repo tree.
- **Box art IS committed.** The repo is private-use (never distributed), so the
  covers/wraps/models/launch-frames (58 covers, 21 wraps, 3 `.glb`, 69 frames) are
  all tracked. Only `assets/games/dielines/*` (intermediate working files) are
  gitignored. **A plain `git clone` gives the complete, buildable project** — no
  separate asset transfer needed. (If this repo is ever repackaged for
  distribution, the covers are copyrighted — revisit then.)

---

## Machine setup (✅ installed + verified on THIS PC 2026-08-10 — paths below are live)

As of 2026-08-10 this machine is a fully set-up build box: both `flutter build windows
--release` and `flutter build apk --release` succeed and `flutter doctor` is all green.
When moving to a *new* machine, re-verify each path below.

Flutter's Windows build **breaks on paths with spaces**, so the project must live
at a space-free path (`C:\PokeTracker`). Do not move it under `C:\Poke Project`.

Toolchain (all installed here unless noted):
- **Flutter SDK** — `C:\dev\flutter\bin` (on PATH). Flutter 3.44.9 / Dart 3.12.2. `flutter --version`.
- **Windows build**: Visual Studio 2022 **Build Tools** 17.14.37 + "Desktop development with
  C++" (Windows 10 SDK 10.0.26100) at
  `C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools`. **Developer Mode is ON**
  (required for Flutter plugin symlinks — `ms-settings:developers`).
- **Inno Setup 6** (Windows installer) — `%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe` (v6.7.3).
- **Android**: JDK 17 at `C:\Program Files\Microsoft\jdk-17.0.20.8-hotspot` + Android SDK at
  **`C:\dev\Android`** (⚠ NOT `C:\Android` — the drive-root path is blocked by a harness safety
  guard, so nest SDK dirs under `C:\dev\`). Platforms android-35 & android-36, build-tools 35.0.0
  & 36.0.0, platform-tools r37, cmake 3.22.1. Persistent env vars `ANDROID_HOME` /
  `ANDROID_SDK_ROOT` = `C:\dev\Android`, `JAVA_HOME` = the JDK above. Licenses accepted via
  `sdkmanager --licenses` with piped `y` (worked here); writing the license *files* under
  `<sdk>\licenses` also works. `compileSdk` is pinned to 36 in `android/app/build.gradle.kts`.
- **GitHub CLI** (`gh`) — `C:\Program Files\GitHub CLI\gh.exe` (v2.97.0). ✅ **Authed** as
  `poketrackerrs` (keyring; `repo` + `workflow` scopes) — `gh release create` works. Not on
  PATH in bash; call by full path or from PowerShell.
- Python (for asset tooling: pygltflib, Pillow, trimesh, pyglet<2, scipy) — **not yet installed
  here**; only needed to compress `.glb` models and crop/measure covers. No Node.js in this project.

---

## Release workflow (the core operational loop)

Every shippable change follows this. Bump → build → release; the app then
self-updates.

1. **Bump version** in `pubspec.yaml` (`version: 1.0.X+Y`; Android needs the `+Y`
   build number to increase every release).
2. **Edit `update.json`** — set `version` (must exceed installed) + `notes`. This is
   the manifest the app polls at
   `raw.githubusercontent.com/poketrackerrs/poketracker/main/update.json`
   (`kUpdateManifestUrl` in `lib/config.dart`). A cache-buster query defeats the
   ~5-min raw CDN cache.
3. **Commit + push** to `main` (repo is at the project root; on git-bash use
   `git -C <projectroot>`). End commit messages with the Co-Authored-By line.
4. **Kill the running app** before building on Windows — the launched `poketracker.exe`
   locks the build output (`Stop-Process -Name poketracker -Force`).
5. **Build both**: `flutter build windows --release` → compile the Inno installer
   (`installer/poketracker.iss` → `dist/PokeTracker-Setup.exe`); and
   `flutter build apk --release` → copy to `dist/PokeTracker.apk`. The combined
   script `build_both.ps1` (below) does both; its paths are set for THIS PC
   (re-verify Flutter/SDK/JDK paths on a new machine).
6. **Release**: `gh release create vX.Y.Z dist\PokeTracker-Setup.exe dist\PokeTracker.apk
   --title "vX.Y.Z" --notes "..."`. Asset names MUST be exactly `PokeTracker-Setup.exe`
   and `PokeTracker.apk` (the manifest points at `releases/latest/download/<name>`).
   PowerShell mangles complex `--notes`/`--jq` strings — use `--notes-file` and pipe
   `gh ... --json` through `ConvertFrom-Json` instead of `--jq`.

`build_both.ps1` (recreate under a scratch dir; **paths below are set for THIS PC — re-verify on a new machine**):
```powershell
$env:Path = 'C:\dev\flutter\bin;' + $env:Path      # <- Flutter bin
$env:ANDROID_HOME = 'C:\dev\Android'; $env:ANDROID_SDK_ROOT = 'C:\dev\Android'
$jdk = (Get-ChildItem "C:\Program Files\Microsoft\jdk-*" -Directory | Select -First 1).FullName
if ($jdk) { $env:JAVA_HOME = $jdk }
Set-Location C:\PokeTracker
New-Item -ItemType Directory -Force C:\PokeTracker\dist | Out-Null
flutter build windows --release
& "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe" "C:\PokeTracker\installer\poketracker.iss"
flutter build apk --release
Copy-Item build\app\outputs\flutter-apk\app-release.apk dist\PokeTracker.apk -Force
```
For a **cover-less public build** (if the owner ever wants covers out of the
distributed binary) see `scratchpad/release_build.ps1` history — it moves
`assets/games` covers to a temp backup, builds, then restores them in a `finally`.
Currently the owner ships **with** covers (personal use).

---

## Architecture map (`lib/`)

- `main.dart` — app root, bottom nav (Games | Pokédex | Settings), theme wiring.
- `config.dart` — `kUpdateManifestUrl`.
- `state/app_state.dart` — the `ChangeNotifier` (provider). Holds progress,
  library/installed ROMs, emulator detection, downloads, theme/accent, launch. Key:
  `tryLaunchGame` → `LaunchOutcome` enum (`launched` / `handoffFailed` / `noEmulator`);
  `emulatorForGame` (skips `launchable:false` emulators); Lemuroid folder sync.
- `data/` — `games_data.dart` (~38 individual games with `versionGroup`/`version`),
  `emulators.dart` (catalog), `pokeapi_maps.dart`, `region_theme.dart`.
- `services/` — `library_service.dart` (downloads, Drive links, per-game
  `Games/<id>/` subfolders), `emulator_service.dart` (detect + launch + **ROM
  cache-staging**), `save_service.dart` (save parsing), `pokedex_service.dart`
  (PokeAPI + caching), `lemuroid_sync.dart`, `update_installer*.dart`.
- `models/` — `game.dart`, `progress.dart`, `save_models.dart`.
- `screens/` — `home_screen.dart` (Games: console grid + list), `console_shelf_screen.dart`
  (console → spines → launch), `launch3d.dart` (pre-rendered launch animation),
  `cartridge_viewer.dart` (3D model dialogs), `game_screen.dart`, `settings_screen.dart`,
  `emulators_screen.dart`, `pokemon_detail_screen.dart`, `pokedex_list_screen.dart`,
  `updates_screen.dart`.
- `widgets/` — `game_box_art.dart` (constructed + wrap-textured 3D boxes, **`GameSpine`**,
  `WrapLayout`s), `console_art.dart`, `gameboy_3d.dart`.
- Native: `android/app/src/main/kotlin/.../MainActivity.kt` (channels
  `poketracker/installer`, `poketracker/emulators`, `poketracker/storage`),
  `AndroidManifest.xml` (`<queries>` per emulator package + FileProvider).

Assets (`pubspec.yaml`): `assets/games/` (covers), `wraps/`, `models/` (`.glb` +
rendered icon), `web/model-viewer.min.js` (offline), `launch/` (f00..f67 launch
frames), `sfx/`, `config/`.

---

## Platform + feature notes

- **Box/spine art**: `game_box_art.dart` textures a full box wrap (`assets/games/wraps/<id>.png`,
  layout `[back|spine|front]`) onto a constructed 3D box; games without a wrap fall
  back to front-cover + generated spine. Spine layouts are calibrated per console:
  `_gbWrap` (GB), `_gbcWrap`, `_gbaWrap` (spine ≈0.4729–0.5271, `spineSplit` 0.281 —
  banner recomposed to the bottom), `_dsWrap`, `_n3dsWrap`. The spine texture is
  flipped (`Transform.flip`) on the 3D box because the ±90° face rotation shows the
  mirrored back; the flat `GameSpine` (shelf) is NOT flipped. DS/3DS spine layouts
  still need real measurement when wraps exist.
- **Android emulator launching** — see the dedicated section below; there are real
  gotchas here.
- **Save auto-tracker** (v1.0.5): Sync button per game → finds `.sav`/`.dsv` → preview
  → non-destructive apply. Gen 1–3 caught-dex parse; Gen 4 trainer/playtime only;
  Gen 5 recognized only. Byte offsets from Bulbapedia still need a real save each to
  confirm; Gen 3/4/5 party is encrypted (needs PKM decryption).
- **Forms/regional variants**: shipped across detail switcher, global grid, per-game
  dex, team/shiny. Form ids ≥10000 are stored but excluded from completion.
- **iOS**: `.github/workflows/ios.yml` builds an unsigned IPA on a macOS runner
  (sideload with AltStore/Sideloadly). CI build lacks local covers. No iOS auto-update.

---

## Built-in emulator (mGBA + melonDS) — Windows & Android

The **Play** button runs games *inside the app* (no external handoff) on Windows and
Android for Gen 1–5. `screens/emulator_screen.dart` drives a libretro core over
`dart:ffi` (`services/gba_emulator.dart`, core-agnostic despite the name; bindings in
`services/libretro.dart`). Cores ship bundled: **mGBA** (`mgba_libretro`, MPL-2.0)
for GB/GBC/GBA; **melonDS DS** (`melondsds_libretro`, **GPLv3** → the distributed
build is GPLv3; attribution in `assets/cores/LICENSE-melondsds.txt`) for Nintendo DS.
Core is picked by generation (`gen ≥ 4 → melonDS`). Cores live in
`assets/cores/*.dll` (Windows, copied out at runtime) and
`android/app/src/main/jniLibs/{arm64-v8a,x86_64}/*.so` (`useLegacyPackaging = true`
in `build.gradle.kts`). Features: remappable keyboard + gamepad
(`services/emulator_controls.dart`), flutter_soloud audio, **time-boxed**
fast-forward (a fixed step count freezes on the heavy DS core — see `_startLoop`),
fullscreen, and battery-save write-back to the same `.sav` the auto-tracker reads.

**DS encrypted-ROM / BIOS gotcha** (full details in the `ds-emulator-bios` memory):
melonDS's built-in FreeBIOS direct-boots **decrypted** DS ROMs, but **encrypted**
retail dumps need real DS BIOS — `bios7.bin` (16 KB), `bios9.bin` (4 KB),
`firmware.bin` (128/256 KB) — placed in the core system dir (`<AppSupport>/cores`).
The user imports them via **Settings → Built-in DS player → Nintendo DS BIOS**
(`screens/ds_bios_screen.dart` + `services/emulator_bios.dart`, using
**`file_selector`** — `file_picker` won't compile under Flutter 3.44's Built-in
Kotlin). When all three exist AND are correctly sized, `init()` flips melonDS to
`sysfile_mode=native` + `boot_mode=direct` (set via the `gVarOverrides` →
GET_VARIABLE mechanism, which also hides the touch cursor with
`melonds_show_cursor=disabled`), so encrypted ROMs decrypt and run — verified with
Diamond. BIOS files are copyrighted: never committed, never shipped. Note:
`boot9.bin`/`boot11.bin` (64 KB) are **3DS** bootroms — unrelated to DS BIOS.

**Nintendo 3DS (Windows only, NOT built-in emulation):** Gen 6–7 still plays in a
desktop emulator (Azahar) — there is no built-in 3DS core (it needs GPU/HW-render
which the software-framebuffer FFI player can't do). What the app *does* do is
**deliver the user's private 3DS files to their PC**: Settings → Nintendo 3DS →
**Link 3DS firmware folder** (paste a *direct* Drive folder link — `k3dsFolderKey`
in `drive_folders.json`, set via `set3dsFolderFromLink`), then **Fetch 3DS files
from Drive** downloads every CIA into `Documents/PokeTracker/3DS Firmware`
(`fetch3dsUpdates` in `library_service.dart`; a nested `updates/` subfolder is
kept). "Open 3DS folder" lands on the `updates/` subfolder when it has files.
The user then installs the CIAs in Azahar. The firmware set is ~137 system-title
CIAs (~224 MB) named by hex Title ID — copyrighted, kept in the user's Drive,
never bundled/shipped (same rule as BIOS). To play a game you usually don't need
the firmware at all; the shared font `0004009B0001400x` is the only piece that
commonly matters.

---

## Android emulator launching (hard-won — don't relearn it)

The Play button hands a ROM to an emulator via `ACTION_VIEW` + a FileProvider
`content://` URI (Kotlin `launchRom`).

- **ROMs are stored in `getApplicationDocumentsDirectory()`** = Android `app_flutter`,
  which `res/xml/file_paths.xml` does **not** cover → `getUriForFile` threw and every
  launch silently failed. Fix (in `emulator_service.dart`): **stage a copy into
  `cache/roms/`** (covered by `<cache-path>`) before launching. Don't relocate ROM
  storage — Windows uses the same documents dir.
- **Which emulators accept a handed-off ROM (verified on Android 13 / Galaxy A51):**
  - ✅ **My Boy! Lite** (`com.fastemulator.gbafree`, GBA) and **My OldBoy! Lite**
    (`com.fastemulator.gbcfree`, GB/GBC) — the recommended launchers.
  - ✅ melonDS (`me.magnum.melonds`, DS). RetroArch accepts intents but its Play build
    is too old to install on modern Android.
  - ❌ **Pizza Boy** and **Lemuroid** — library-only; they ignore the ROM and open to
    their own browser (`LaunchOutcome.handoffFailed`). Lemuroid is `launchable:false`;
    for Lemuroid there's a "Sync games to Lemuroid folder" flow (MANAGE_EXTERNAL_STORAGE
    → mirror ROMs into `/storage/emulated/0/PokeTracker/{gb,gbc,gba,nds}/`).
  - ❌ **mGBA** has NO official Play app (`io.mgba.android.emulator` = 404) — desktop only.
- **Lesson:** before recommending any store app, verify the package **exists** in the
  store AND that it accepts external ROM intents. Two wrong guesses (RetroArch Plus,
  mGBA-on-Play) came from skipping this.

---

## Working conventions

- **Preview visual changes before shipping.** The owner said "give me previews before
  you ship." For UI/design changes, render a mockup (Python/Pillow render or an
  artifact) and get a yes *before* building/releasing. Functional bug fixes they
  asked for can ship directly. (Rendering candidate spine/shelf layouts as PNGs to
  confirm has worked well.)
- The owner iterates fast and tests on-device between releases — small, frequent
  releases are expected.
- Windows/PowerShell is the primary shell; a bash tool is also available (use
  `git -C <path>` there since cwd can reset).
- Repo: `github.com/poketrackerrs/poketracker`, branch `main`.

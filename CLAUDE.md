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
- **Never commit built binaries** (`*.apk`, `*.aab`, `*-Setup.exe`) — they bundle
  copyrighted covers and the repo is public. `.gitignore` excludes them plus
  `assets/games/*.png|jpg`, `wraps/`, `dielines/`. Covers/wraps/models live
  **locally only** and are gitignored — they DO travel when you copy the project
  folder, but a fresh `git clone` will lack them (the app falls back to styled
  cards). Release binaries go **only** as GitHub Release assets.

---

## Machine setup (⚠ paths below are the OLD PC — verify/reinstall on this one)

Flutter's Windows build **breaks on paths with spaces**, so the project must live
at a space-free path (was `C:\PokeTracker`). Do not move it under `C:\Poke Project`.

Toolchain the build expects (install if missing on this machine):
- **Flutter SDK** — was `C:\dev\flutter\bin` (on PATH). `flutter --version`.
- **Windows build**: Visual Studio 2022 + "Desktop development with C++" workload;
  Developer Mode on.
- **Inno Setup 6** (Windows installer) — was `%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe`.
- **Android**: JDK 17 (was `C:\Program Files\Microsoft\jdk-17*`) + Android SDK (was
  `C:\Android`, platforms android-35 & android-36, build-tools 35 & 36). Accept
  licenses by writing the license *files* under `<sdk>\licenses` (piped `y` didn't
  work). `compileSdk` is pinned to 36 in `android/app/build.gradle.kts`.
- **GitHub CLI** (`gh`) — was `C:\Program Files\GitHub CLI\gh.exe`, authed as
  `poketrackerrs`. Not on PATH in bash; call by full path or from PowerShell.
- Python (for asset tooling: pygltflib, Pillow, trimesh, pyglet<2, scipy) — used to
  compress `.glb` models and crop/measure covers. No Node.js in this project.

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
   script `build_both.ps1` (below) does both; note it hard-codes the old machine's
   Flutter/SDK/JDK paths — adjust them.
6. **Release**: `gh release create vX.Y.Z dist\PokeTracker-Setup.exe dist\PokeTracker.apk
   --title "vX.Y.Z" --notes "..."`. Asset names MUST be exactly `PokeTracker-Setup.exe`
   and `PokeTracker.apk` (the manifest points at `releases/latest/download/<name>`).
   PowerShell mangles complex `--notes`/`--jq` strings — use `--notes-file` and pipe
   `gh ... --json` through `ConvertFrom-Json` instead of `--jq`.

`build_both.ps1` (recreate under a scratch dir; **fix the paths for this machine**):
```powershell
$env:Path = 'C:\dev\flutter\bin;' + $env:Path      # <- Flutter bin
$env:ANDROID_HOME = 'C:\Android'; $env:ANDROID_SDK_ROOT = 'C:\Android'
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

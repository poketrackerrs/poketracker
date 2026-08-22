---
tags: [poketracker, build, setup, machine]
---
# Machine Setup

> [!success] This laptop is a **verified** PokeTracker build machine
> Set up and confirmed on **2026-08-10**. Both `flutter build windows --release` and `flutter build apk --release` succeed (`flutter doctor` → *No issues found*). These paths **supersede** the "OLD PC" paths in `CLAUDE.md`.

Flutter's Windows build **breaks on paths with spaces**, so the project lives at a space-free path: **`C:\PokeTracker`**.

## Installed toolchain (this machine)

| Tool | Version | Location |
|---|---|---|
| **Flutter SDK** | 3.44.9 (stable) | `C:\dev\flutter` |
| **Dart** | 3.12.2 | (bundled with Flutter) |
| **Android SDK** | platforms 35 & 36, build-tools 35.0.0 & 36.0.0, platform-tools r37, cmake 3.22.1 | **`C:\dev\Android`** |
| **JDK** | Microsoft OpenJDK 17.0.20.8 | `C:\Program Files\Microsoft\jdk-17.0.20.8-hotspot` |
| **Visual Studio Build Tools 2022** | 17.14.37 + Desktop C++ + Win10 SDK 10.0.26100 | `C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools` |
| **Inno Setup 6** | 6.7.3 | `%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe` |
| **GitHub CLI** | 2.97.0 — ✅ authed as `poketrackerrs` | `C:\Program Files\GitHub CLI\gh.exe` |
| **Git** | (system) | `C:\Program Files\Git` |

> [!warning] Android SDK is at `C:\dev\Android`, **not** `C:\Android`
> The drive-root `C:\Android` path (as in `CLAUDE.md`'s `build_both.ps1`) is blocked by a safety guard, so the SDK was nested under `C:\dev\Android`. **Update `build_both.ps1`'s `ANDROID_HOME`/`ANDROID_SDK_ROOT` accordingly** before using it. See [[Build and Release]].

## Environment configured
Persistent **User** env vars set: `ANDROID_HOME` and `ANDROID_SDK_ROOT` = `C:\dev\Android`, `JAVA_HOME` = the JDK above. `PATH` gained `C:\dev\flutter\bin` and `C:\dev\Android\platform-tools`. Flutter is pointed at both via `flutter config --android-sdk` and `--jdk-dir`. **Windows Developer Mode is enabled** (required for Flutter plugin symlinks).

## Release tools — installed, one step remains
- **Inno Setup 6** (6.7.3) ✅ — wraps `poketracker.exe` into `PokeTracker-Setup.exe`.
- **GitHub CLI** (2.97.0) ✅ installed and **authenticated** as `poketrackerrs` (keyring; `repo` + `workflow` scopes) — `gh release create` works.

## Still not installed
- **Python** (pygltflib, Pillow, trimesh, pyglet<2, scipy) — only for asset tooling (`.glb` compression, cover cropping); not needed to build or release.

## Fresh-machine setup, from scratch
1. Install **Flutter** → unzip the stable SDK to `C:\dev\flutter`, add `bin` to PATH.
2. Enable **Windows Developer Mode** (`ms-settings:developers`).
3. Install **VS 2022 Build Tools** + "Desktop development with C++" workload.
4. Install **JDK 17**; set `JAVA_HOME`.
5. Install the **Android SDK** command-line tools → `C:\dev\Android\cmdline-tools\latest`; `sdkmanager` the platforms/build-tools/platform-tools; accept licenses; set `ANDROID_HOME`.
6. `git clone https://github.com/poketrackerrs/poketracker.git C:\PokeTracker` → `flutter pub get`.
7. `flutter doctor -v` should be all green.

> [!note] The clone is complete
> A plain `git clone` gives the **full, buildable project** — box art and all assets are committed (only `assets/games/dielines/*` is gitignored). No separate asset transfer needed. See [[Constraints and Legal]].

---
Related: [[Build and Release]] · [[Home]] · [[Overview]]

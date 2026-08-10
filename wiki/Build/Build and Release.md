---
tags: [poketracker, build, release, workflow]
---
# Build and Release

The core operational loop: **bump → build → release**; the app then self-updates (see [[Auto-Update]]). Toolchain paths for this machine are in [[Machine Setup]].

## Quick build commands
```powershell
# from C:\PokeTracker, with C:\dev\flutter\bin on PATH
flutter pub get
flutter build windows --release   # → build\windows\x64\runner\Release\poketracker.exe
flutter build apk --release       # → build\app\outputs\flutter-apk\app-release.apk
```
> [!success] Verified on this machine (2026-08-10)
> Windows build ✅ (~171s) · APK build ✅ 69.5 MB (~367s, auto-installed cmake 3.22.1).

> [!warning] Kill the running app before a Windows build
> A launched `poketracker.exe` locks the build output. `Stop-Process -Name poketracker -Force` first.

## Full release workflow
1. **Bump version** in `pubspec.yaml` (`version: 1.0.X+Y`). Android needs the `+Y` build number to increase **every** release. (Currently `1.0.46+47`.)
2. **Edit `update.json`** — set `version` (must exceed the installed one) + `notes`. This is the manifest the app polls; a cache-buster query defeats the ~5-min raw-CDN cache. See [[Auto-Update]].
3. **Commit + push** to `main` (end commit messages with the `Co-Authored-By` line).
4. **Build both** (see commands above); compile the Windows installer with Inno Setup (`installer/poketracker.iss` → `dist/PokeTracker-Setup.exe`), and copy the APK to `dist/PokeTracker.apk`.
5. **Release:**
   ```powershell
   gh release create vX.Y.Z dist\PokeTracker-Setup.exe dist\PokeTracker.apk `
     --title "vX.Y.Z" --notes-file notes.txt
   ```
   Asset names **must** be exactly `PokeTracker-Setup.exe` and `PokeTracker.apk` (the manifest points at `releases/latest/download/<name>`).

> [!note] PowerShell gotchas
> PowerShell mangles complex `--notes` / `--jq` strings — use `--notes-file`, and pipe `gh ... --json` through `ConvertFrom-Json` instead of `--jq`.

## `build_both.ps1` — fix the paths first
`CLAUDE.md` includes a `build_both.ps1` that hard-codes the **old PC's** paths. On this machine, adjust:
```powershell
$env:Path = 'C:\dev\flutter\bin;' + $env:Path
$env:ANDROID_HOME = 'C:\dev\Android'          # ← was C:\Android
$env:ANDROID_SDK_ROOT = 'C:\dev\Android'      # ← was C:\Android
$env:JAVA_HOME = 'C:\Program Files\Microsoft\jdk-17.0.20.8-hotspot'
```
Then it runs `flutter build windows`, the Inno Setup compile, `flutter build apk`, and copies the APK to `dist\`. **Inno Setup 6.7.3 + `gh` 2.97.0 are installed**, and `gh` is authenticated as `poketrackerrs` — the release step is unblocked. See [[Machine Setup]].

## Never commit
Built binaries (`*.apk`, `*.aab`, `*-Setup.exe`) are regenerable + large and are gitignored. Release binaries go **only** as GitHub Release assets. See [[Constraints and Legal]].

---
Related: [[Machine Setup]] · [[Auto-Update]] · [[Constraints and Legal]]

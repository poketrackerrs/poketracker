---
tags: [poketracker, reference, emulators]
---
# Emulators Catalog

The **9 emulators** in `kEmulators` (`lib/data/emulators.dart`). Detection + launch logic is in [[Emulator Launching]]; the `Emulator` fields are described in [[Data Layer]].

| Name | Systems | Gens | Platform | Android package(s) | Launchable |
|---|---|---|---|---|---|
| **mGBA** | GB · GBC · GBA | 1–3 | Desktop only | — (no official Android) | ✅ |
| **My OldBoy!** | GB · GBC | 1–2 | Android | `com.fastemulator.gbcfree` / `.gbc` | ✅ |
| **My Boy!** | GBA | 3 | Android | `com.fastemulator.gbafree` / `.gba` | ✅ |
| **melonDS** | DS | 4–5 | Desktop + Android | `me.magnum.melonds` | ✅ |
| **DeSmuME** | DS | 4–5 | Desktop | — | ✅ |
| **Azahar** | 3DS | 6–7 | Desktop + Android | `org.azahar.azahar`, `io.github.lime3ds.android`, `org.citra.citra_emu` | ✅ |
| **Lemuroid** | Multi (GB→DS) | 1–5 | Android | `com.swordfish.lemuroid` | ❌ library-only |
| **Pizza Boy (GBA/GBC)** | GB · GBC · GBA | 1–3 | Android | `it.dbtecno.pizzaboygba(pro)`, `…gbc(pro)` | ✅* |
| **RetroArch** | Multi (GB→DS) | 1–5 | Desktop + Android | `com.retroarch`, `com.retroarch.aarch64` | ✅* |

`✅*` = declared launchable, but see the verified-behavior caveats below.

## Field meanings
- `generations` — the Pokémon gens the emulator can play; `AppState.emulatorForGame` matches on this.
- `exeNames` / `hints` — desktop discovery (executable names + install-folder hints).
- `androidPackages` — package ids checked via the `poketracker/emulators` channel.
- `launchable` — if **false**, the Play button must never pick it (it can't receive a ROM). Only **Lemuroid** is `launchable:false`.

## Coverage gaps
- **Gen ≥ 8** (Sword/Shield, BDSP, Legends games, Scarlet/Violet) and **Let's Go**: no emulator → `emulatorForGame` returns null → no Play action. See [[Emulator Launching]].
- **3DS** (Azahar) is catalogued but its real-world ROM hand-off isn't in the verified table below.

## Verified Android behavior (Android 13 / Galaxy A51)
- ✅ **My Boy! Lite** (GBA) + **My OldBoy! Lite** (GB/GBC) — the recommended launchers.
- ✅ **melonDS** (DS).
- ❌ **Pizza Boy** and **Lemuroid** — library-only in practice; ignore the handed-off ROM → `LaunchOutcome.handoffFailed` (Lemuroid uses the folder-sync flow instead).
- ⚠️ **RetroArch** accepts intents but its Play build is too old to install on modern Android.

> [!warning] Verify before recommending
> The catalog's `launchable` flag is a *declaration*; real hand-off support was learned empirically. Always confirm a package **exists** in the store and accepts external ROM intents. See [[Gotchas]].

Related manifest asymmetry: the Android `<queries>` block also lists `io.mgba.android.emulator` and `com.dsemu.drastic`, which aren't in this catalog — see [[Native Android Layer]].

---
Related: [[Data Layer]] · [[Emulator Launching]] · [[Native Android Layer]]

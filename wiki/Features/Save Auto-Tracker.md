---
tags: [poketracker, feature, saves]
---
# Save Auto-Tracker

Reads progress **directly from an emulator save file** and non-destructively merges it into the tracker. Added in v1.0.5. Entry point: the "Sync from save file" action on [[Screens|game_screen.dart]].

## Flow
1. **Locate** — `AppState._findSaveFile` checks a manual path (`savepath:<id>` pref), then files **next to the ROM** with extensions `.sav .srm .sav1 .dsv .sa1 .fla`.
2. **Parse** — `SaveService.parse(bytes, {generation, versionId})` dispatches to `_parseGen1`…`_parseGen5` and returns a `SaveData` (see [[Models]]).
3. **Resolve names** — `AppState.scanSave` fills team member names from the Pokédex index (see [[Pokedex]]).
4. **Preview & apply** — `_SaveSyncDialog` shows checkboxes (dex / badges / team) + parser notes; `applySaveData` **unions** caught species (never removes), sets badges up to the count, replaces the team.

> [!tip] Non-destructive by design
> `applySaveData` can only *add* caught species — see the "never remove" rule in [[AppState]]. A bad or partial parse can't wipe manual progress.

## Per-generation confidence (from the `save_service.dart` header)
| Gen | What's read | Status |
|---|---|---|
| **Gen 1** (RBY) | caught dex, badges, party, playtime, trainer | ✅ most complete |
| **Gen 2** (GSC) | dex, party, badges (**Johto only**) | ⚠️ partial |
| **Gen 3** | caught dex, playtime, trainer | ⚠️ badges + party **TODO** (party encrypted) |
| **Gen 4** | trainer id + playtime only | 🚧 dex/badges/team "being calibrated" |
| **Gen 5** | nothing yet | 🚧 notes only |

## Implementation notes
- Hardcoded **English-ROM** byte offsets (Bulbapedia-sourced, documented inline): e.g. Gen 1 `ownedOfs = 0x25A3`; Gen 3 signature `0x08012025`, block size `0xE000`.
- Helpers: `_countBits`, `_dexFromBitfield`, `_u16`/`_u32`, text codecs `_decodeGen1Text` / `_decodeGen3Text`, and the large `_gen1IndexToDex` map (Gen 1 internal species index → national dex).

> [!warning] Sharp edges
> - Offsets assume **English ROMs** — other regions/revisions may silently misread. Confirm against a real save per game before trusting a gen.
> - Gen 3/4/5 party mons are **encrypted** (need PKM decryption) — not attempted.
> - `_findSaveFile` guesses by extension; there's no per-emulator save-path knowledge.
> See [[Gotchas]].

---
Related: [[AppState]] · [[Services]] · [[Models]] · [[Gotchas]]

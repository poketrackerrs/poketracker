---
tags: [poketracker, reference, games]
---
# Games Catalog

The **38 games** in `kGames` (`lib/data/games_data.dart`), grouped by generation. Each `Game` (see [[Models]]) carries an `id` (used for the box-art asset `assets/games/<id>.png` and the library folder `Games/<id>/`), `region`, `dexTotal`, `versionGroup` (→ PokéAPI, see [[Pokedex]]), and a shared milestone list. Games share milestone lists by region.

| Gen | id | Title | Region | Year | dexTotal | versionGroup |
|---|---|---|---|---|---|---|
| 1 | `red` | Red | Kanto | 1996 | 151 | red-blue |
| 1 | `blue` | Blue | Kanto | 1996 | 151 | red-blue |
| 1 | `yellow` | Yellow | Kanto | 1998 | 151 | yellow |
| 2 | `gold` | Gold | Johto | 1999 | 251 | gold-silver |
| 2 | `silver` | Silver | Johto | 1999 | 251 | gold-silver |
| 2 | `crystal` | Crystal | Johto | 2000 | 251 | crystal |
| 3 | `ruby` | Ruby | Hoenn | 2002 | 386 | ruby-sapphire |
| 3 | `sapphire` | Sapphire | Hoenn | 2002 | 386 | ruby-sapphire |
| 3 | `emerald` | Emerald | Hoenn | 2004 | 386 | emerald |
| 3 | `firered` | FireRed | Kanto | 2004 | 151 | firered-leafgreen |
| 3 | `leafgreen` | LeafGreen | Kanto | 2004 | 151 | firered-leafgreen |
| 4 | `diamond` | Diamond | Sinnoh | 2006 | 493 | diamond-pearl |
| 4 | `pearl` | Pearl | Sinnoh | 2006 | 493 | diamond-pearl |
| 4 | `platinum` | Platinum | Sinnoh | 2008 | 493 | platinum |
| 4 | `heartgold` | HeartGold | Johto | 2009 | 493 | heartgold-soulsilver |
| 4 | `soulsilver` | SoulSilver | Johto | 2009 | 493 | heartgold-soulsilver |
| 5 | `black` | Black | Unova | 2010 | 649 | black-white |
| 5 | `white` | White | Unova | 2010 | 649 | black-white |
| 5 | `black-2` | Black 2 | Unova | 2012 | 649 | black-2-white-2 |
| 5 | `white-2` | White 2 | Unova | 2012 | 649 | black-2-white-2 |
| 6 | `x` | X | Kalos | 2013 | 721 | x-y |
| 6 | `y` | Y | Kalos | 2013 | 721 | x-y |
| 6 | `omega-ruby` | Omega Ruby | Hoenn | 2014 | 721 | omega-ruby-alpha-sapphire |
| 6 | `alpha-sapphire` | Alpha Sapphire | Hoenn | 2014 | 721 | omega-ruby-alpha-sapphire |
| 7 | `sun` | Sun | Alola | 2016 | 807 | sun-moon |
| 7 | `moon` | Moon | Alola | 2016 | 807 | sun-moon |
| 7 | `ultra-sun` | Ultra Sun | Alola | 2017 | 807 | ultra-sun-ultra-moon |
| 7 | `ultra-moon` | Ultra Moon | Alola | 2017 | 807 | ultra-sun-ultra-moon |
| 7 | `lets-go-pikachu` | Let's Go, Pikachu! | Kanto | 2018 | 153 | lets-go-pikachu-lets-go-eevee |
| 7 | `lets-go-eevee` | Let's Go, Eevee! | Kanto | 2018 | 153 | lets-go-pikachu-lets-go-eevee |
| 8 | `sword` | Sword | Galar | 2019 | 400 | sword-shield |
| 8 | `shield` | Shield | Galar | 2019 | 400 | sword-shield |
| 8 | `brilliant-diamond` | Brilliant Diamond | Sinnoh | 2021 | 493 | brilliant-diamond-and-shining-pearl |
| 8 | `shining-pearl` | Shining Pearl | Sinnoh | 2021 | 493 | brilliant-diamond-and-shining-pearl |
| 8 | `legends-arceus` | Legends: Arceus 🏔 | Hisui | 2022 | 242 | legends-arceus |
| 9 | `scarlet` | Scarlet | Paldea | 2022 | 400 | scarlet-violet |
| 9 | `violet` | Violet | Paldea | 2022 | 400 | scarlet-violet |
| 9 | `legends-z-a` | Legends: Z-A 🏙 | Lumiose City | 2025 | 230 | legends-z-a |

🏔🏙 = `GameCategory.legends`; all others are `mainline`.

## Milestone lists (by region)
Shared `const` lists in `games_data.dart`: `_kanto`, `_johto`, `_hoenn`, `_sinnoh`, `_unovaBW`, `_unovaB2W2`, `_kalos`, `_alola` (grand trials), `_galar`, `_paldea` (paths/titans/bases), `_hisui` (nobles), `_za` (Z-A Royale ranks). Milestones ending in **"Badge"** count toward `AppState.totalBadges`.

> [!note] Notes on IDs & assets
> - `assets/games/` contains **39** cover images — one more than the 38 catalog entries (an extra `green` cover with no `kGames` entry; a `green` key also appears in `drive_folders.json`). See [[Gotchas]].
> - `versionGroup` feeds [[Pokedex]]. `legends-z-a` may not exist in PokéAPI yet → an empty `GameDex` is returned gracefully.
> - Which of these can actually **launch** depends on the emulator support in [[Emulators Catalog]] (Gen ≥ 8 and Let's Go have none).

---
Related: [[Data Layer]] · [[Models]] · [[Emulators Catalog]] · [[Pokedex]]

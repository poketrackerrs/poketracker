import '../models/game.dart';

// ---- Shared milestone lists (games in the same region share progression) ----

const _kanto = [
  'Boulder Badge', 'Cascade Badge', 'Thunder Badge', 'Rainbow Badge',
  'Soul Badge', 'Marsh Badge', 'Volcano Badge', 'Earth Badge',
  'Elite Four', 'Champion',
];

const _johto = [
  'Zephyr Badge', 'Hive Badge', 'Plain Badge', 'Fog Badge', 'Storm Badge',
  'Mineral Badge', 'Glacier Badge', 'Rising Badge', 'Elite Four', 'Champion',
  'Kanto Gyms (8 badges)', 'Red at Mt. Silver',
];

const _hoenn = [
  'Stone Badge', 'Knuckle Badge', 'Dynamo Badge', 'Heat Badge',
  'Balance Badge', 'Feather Badge', 'Mind Badge', 'Rain Badge',
  'Elite Four', 'Champion',
];

const _sinnoh = [
  'Coal Badge', 'Forest Badge', 'Cobble Badge', 'Fen Badge', 'Relic Badge',
  'Mine Badge', 'Icicle Badge', 'Beacon Badge', 'Elite Four', 'Champion',
];

const _unovaBW = [
  'Trio Badge', 'Basic Badge', 'Insect Badge', 'Bolt Badge', 'Quake Badge',
  'Jet Badge', 'Freeze Badge', 'Legend Badge', 'Elite Four', 'Champion',
];

const _unovaB2W2 = [
  'Basic Badge', 'Toxic Badge', 'Insect Badge', 'Bolt Badge', 'Quake Badge',
  'Jet Badge', 'Legend Badge', 'Wave Badge', 'Elite Four', 'Champion',
];

const _kalos = [
  'Bug Badge', 'Cliff Badge', 'Rumble Badge', 'Plant Badge', 'Voltage Badge',
  'Fairy Badge', 'Psychic Badge', 'Iceberg Badge', 'Elite Four', 'Champion',
];

const _alola = [
  'Grand Trial: Hala', 'Grand Trial: Olivia', 'Grand Trial: Nanu',
  'Grand Trial: Hapu', 'Elite Four', 'Champion',
];

const _galar = [
  'Grass Badge', 'Water Badge', 'Fire Badge', 'Fighting/Ghost Badge',
  'Fairy Badge', 'Rock/Ice Badge', 'Dark Badge', 'Dragon Badge',
  'Champion Cup', 'Champion Leon',
];

const _paldea = [
  'Victory Road: 8 Gyms', 'Path of Legends: 5 Titans',
  'Starfall Street: 5 Bases', 'The Way Home', 'Champion (Geeta)', 'Area Zero',
];

const _hisui = [
  'Kleavor (Noble)', 'Lilligant (Noble)', 'Arcanine (Noble)',
  'Electrode (Noble)', 'Avalugg (Noble)', 'Complete the Pokedex',
  'Catch Arceus',
];

const _za = [
  'Z-A Royale Rank G', 'Z-A Royale Rank F', 'Z-A Royale Rank E',
  'Z-A Royale Rank D', 'Z-A Royale Rank C', 'Z-A Royale Rank B',
  'Z-A Royale Rank A', 'Z-A Royale Rank Z', 'Complete the Pokedex',
  'Story Complete',
];

/// The full catalog of individual mainline + Legends games.
const List<Game> kGames = [
  // ---------------------------------------------------------------- Gen 1
  Game(id: 'red', title: 'Pokemon Red', generation: 1, region: 'Kanto', releaseYear: 1996, category: GameCategory.mainline, milestones: _kanto, dexTotal: 151, versionGroup: 'red-blue', version: 'red'),
  Game(id: 'blue', title: 'Pokemon Blue', generation: 1, region: 'Kanto', releaseYear: 1996, category: GameCategory.mainline, milestones: _kanto, dexTotal: 151, versionGroup: 'red-blue', version: 'blue'),
  Game(id: 'yellow', title: 'Pokemon Yellow', generation: 1, region: 'Kanto', releaseYear: 1998, category: GameCategory.mainline, milestones: _kanto, dexTotal: 151, versionGroup: 'yellow', version: 'yellow'),

  // ---------------------------------------------------------------- Gen 2
  Game(id: 'gold', title: 'Pokemon Gold', generation: 2, region: 'Johto', releaseYear: 1999, category: GameCategory.mainline, milestones: _johto, dexTotal: 251, versionGroup: 'gold-silver', version: 'gold'),
  Game(id: 'silver', title: 'Pokemon Silver', generation: 2, region: 'Johto', releaseYear: 1999, category: GameCategory.mainline, milestones: _johto, dexTotal: 251, versionGroup: 'gold-silver', version: 'silver'),
  Game(id: 'crystal', title: 'Pokemon Crystal', generation: 2, region: 'Johto', releaseYear: 2000, category: GameCategory.mainline, milestones: _johto, dexTotal: 251, versionGroup: 'crystal', version: 'crystal'),

  // ---------------------------------------------------------------- Gen 3
  Game(id: 'ruby', title: 'Pokemon Ruby', generation: 3, region: 'Hoenn', releaseYear: 2002, category: GameCategory.mainline, milestones: _hoenn, dexTotal: 386, versionGroup: 'ruby-sapphire', version: 'ruby'),
  Game(id: 'sapphire', title: 'Pokemon Sapphire', generation: 3, region: 'Hoenn', releaseYear: 2002, category: GameCategory.mainline, milestones: _hoenn, dexTotal: 386, versionGroup: 'ruby-sapphire', version: 'sapphire'),
  Game(id: 'emerald', title: 'Pokemon Emerald', generation: 3, region: 'Hoenn', releaseYear: 2004, category: GameCategory.mainline, milestones: _hoenn, dexTotal: 386, versionGroup: 'emerald', version: 'emerald'),
  Game(id: 'firered', title: 'Pokemon FireRed', generation: 3, region: 'Kanto', releaseYear: 2004, category: GameCategory.mainline, milestones: _kanto, dexTotal: 151, versionGroup: 'firered-leafgreen', version: 'firered'),
  Game(id: 'leafgreen', title: 'Pokemon LeafGreen', generation: 3, region: 'Kanto', releaseYear: 2004, category: GameCategory.mainline, milestones: _kanto, dexTotal: 151, versionGroup: 'firered-leafgreen', version: 'leafgreen'),

  // ---------------------------------------------------------------- Gen 4
  Game(id: 'diamond', title: 'Pokemon Diamond', generation: 4, region: 'Sinnoh', releaseYear: 2006, category: GameCategory.mainline, milestones: _sinnoh, dexTotal: 493, versionGroup: 'diamond-pearl', version: 'diamond'),
  Game(id: 'pearl', title: 'Pokemon Pearl', generation: 4, region: 'Sinnoh', releaseYear: 2006, category: GameCategory.mainline, milestones: _sinnoh, dexTotal: 493, versionGroup: 'diamond-pearl', version: 'pearl'),
  Game(id: 'platinum', title: 'Pokemon Platinum', generation: 4, region: 'Sinnoh', releaseYear: 2008, category: GameCategory.mainline, milestones: _sinnoh, dexTotal: 493, versionGroup: 'platinum', version: 'platinum'),
  Game(id: 'heartgold', title: 'Pokemon HeartGold', generation: 4, region: 'Johto', releaseYear: 2009, category: GameCategory.mainline, milestones: _johto, dexTotal: 493, versionGroup: 'heartgold-soulsilver', version: 'heartgold'),
  Game(id: 'soulsilver', title: 'Pokemon SoulSilver', generation: 4, region: 'Johto', releaseYear: 2009, category: GameCategory.mainline, milestones: _johto, dexTotal: 493, versionGroup: 'heartgold-soulsilver', version: 'soulsilver'),

  // ---------------------------------------------------------------- Gen 5
  Game(id: 'black', title: 'Pokemon Black', generation: 5, region: 'Unova', releaseYear: 2010, category: GameCategory.mainline, milestones: _unovaBW, dexTotal: 649, versionGroup: 'black-white', version: 'black'),
  Game(id: 'white', title: 'Pokemon White', generation: 5, region: 'Unova', releaseYear: 2010, category: GameCategory.mainline, milestones: _unovaBW, dexTotal: 649, versionGroup: 'black-white', version: 'white'),
  Game(id: 'black-2', title: 'Pokemon Black 2', generation: 5, region: 'Unova', releaseYear: 2012, category: GameCategory.mainline, milestones: _unovaB2W2, dexTotal: 649, versionGroup: 'black-2-white-2', version: 'black-2'),
  Game(id: 'white-2', title: 'Pokemon White 2', generation: 5, region: 'Unova', releaseYear: 2012, category: GameCategory.mainline, milestones: _unovaB2W2, dexTotal: 649, versionGroup: 'black-2-white-2', version: 'white-2'),

  // ---------------------------------------------------------------- Gen 6
  Game(id: 'x', title: 'Pokemon X', generation: 6, region: 'Kalos', releaseYear: 2013, category: GameCategory.mainline, milestones: _kalos, dexTotal: 721, versionGroup: 'x-y', version: 'x'),
  Game(id: 'y', title: 'Pokemon Y', generation: 6, region: 'Kalos', releaseYear: 2013, category: GameCategory.mainline, milestones: _kalos, dexTotal: 721, versionGroup: 'x-y', version: 'y'),
  Game(id: 'omega-ruby', title: 'Pokemon Omega Ruby', generation: 6, region: 'Hoenn', releaseYear: 2014, category: GameCategory.mainline, milestones: _hoenn, dexTotal: 721, versionGroup: 'omega-ruby-alpha-sapphire', version: 'omega-ruby'),
  Game(id: 'alpha-sapphire', title: 'Pokemon Alpha Sapphire', generation: 6, region: 'Hoenn', releaseYear: 2014, category: GameCategory.mainline, milestones: _hoenn, dexTotal: 721, versionGroup: 'omega-ruby-alpha-sapphire', version: 'alpha-sapphire'),

  // ---------------------------------------------------------------- Gen 7
  Game(id: 'sun', title: 'Pokemon Sun', generation: 7, region: 'Alola', releaseYear: 2016, category: GameCategory.mainline, milestones: _alola, dexTotal: 807, versionGroup: 'sun-moon', version: 'sun'),
  Game(id: 'moon', title: 'Pokemon Moon', generation: 7, region: 'Alola', releaseYear: 2016, category: GameCategory.mainline, milestones: _alola, dexTotal: 807, versionGroup: 'sun-moon', version: 'moon'),
  Game(id: 'ultra-sun', title: 'Pokemon Ultra Sun', generation: 7, region: 'Alola', releaseYear: 2017, category: GameCategory.mainline, milestones: _alola, dexTotal: 807, versionGroup: 'ultra-sun-ultra-moon', version: 'ultra-sun'),
  Game(id: 'ultra-moon', title: 'Pokemon Ultra Moon', generation: 7, region: 'Alola', releaseYear: 2017, category: GameCategory.mainline, milestones: _alola, dexTotal: 807, versionGroup: 'ultra-sun-ultra-moon', version: 'ultra-moon'),
  Game(id: 'lets-go-pikachu', title: "Pokemon Let's Go, Pikachu!", generation: 7, region: 'Kanto', releaseYear: 2018, category: GameCategory.mainline, milestones: _kanto, dexTotal: 153, versionGroup: 'lets-go-pikachu-lets-go-eevee', version: 'lets-go-pikachu'),
  Game(id: 'lets-go-eevee', title: "Pokemon Let's Go, Eevee!", generation: 7, region: 'Kanto', releaseYear: 2018, category: GameCategory.mainline, milestones: _kanto, dexTotal: 153, versionGroup: 'lets-go-pikachu-lets-go-eevee', version: 'lets-go-eevee'),

  // ---------------------------------------------------------------- Gen 8
  Game(id: 'sword', title: 'Pokemon Sword', generation: 8, region: 'Galar', releaseYear: 2019, category: GameCategory.mainline, milestones: _galar, dexTotal: 400, versionGroup: 'sword-shield', version: 'sword'),
  Game(id: 'shield', title: 'Pokemon Shield', generation: 8, region: 'Galar', releaseYear: 2019, category: GameCategory.mainline, milestones: _galar, dexTotal: 400, versionGroup: 'sword-shield', version: 'shield'),
  Game(id: 'brilliant-diamond', title: 'Pokemon Brilliant Diamond', generation: 8, region: 'Sinnoh', releaseYear: 2021, category: GameCategory.mainline, milestones: _sinnoh, dexTotal: 493, versionGroup: 'brilliant-diamond-and-shining-pearl', version: 'brilliant-diamond'),
  Game(id: 'shining-pearl', title: 'Pokemon Shining Pearl', generation: 8, region: 'Sinnoh', releaseYear: 2021, category: GameCategory.mainline, milestones: _sinnoh, dexTotal: 493, versionGroup: 'brilliant-diamond-and-shining-pearl', version: 'shining-pearl'),
  Game(id: 'legends-arceus', title: 'Pokemon Legends: Arceus', generation: 8, region: 'Hisui', releaseYear: 2022, category: GameCategory.legends, milestones: _hisui, dexTotal: 242, versionGroup: 'legends-arceus', version: 'legends-arceus'),

  // ---------------------------------------------------------------- Gen 9
  Game(id: 'scarlet', title: 'Pokemon Scarlet', generation: 9, region: 'Paldea', releaseYear: 2022, category: GameCategory.mainline, milestones: _paldea, dexTotal: 400, versionGroup: 'scarlet-violet', version: 'scarlet'),
  Game(id: 'violet', title: 'Pokemon Violet', generation: 9, region: 'Paldea', releaseYear: 2022, category: GameCategory.mainline, milestones: _paldea, dexTotal: 400, versionGroup: 'scarlet-violet', version: 'violet'),
  Game(id: 'legends-z-a', title: 'Pokemon Legends: Z-A', generation: 9, region: 'Lumiose City', releaseYear: 2025, category: GameCategory.legends, milestones: _za, dexTotal: 230, versionGroup: 'legends-z-a', version: 'legends-z-a'),
];

/// Games grouped by generation, in order — handy for the home screen.
Map<int, List<Game>> gamesByGeneration() {
  final map = <int, List<Game>>{};
  for (final g in kGames) {
    map.putIfAbsent(g.generation, () => []).add(g);
  }
  return map;
}

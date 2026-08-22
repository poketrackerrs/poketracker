/// Maps PokeAPI "version" names (used in Pokedex flavor text) to a generation.
const Map<String, int> kVersionToGen = {
  'red': 1, 'blue': 1, 'yellow': 1,
  'gold': 2, 'silver': 2, 'crystal': 2,
  'ruby': 3, 'sapphire': 3, 'emerald': 3, 'firered': 3, 'leafgreen': 3,
  'diamond': 4, 'pearl': 4, 'platinum': 4, 'heartgold': 4, 'soulsilver': 4,
  'black': 5, 'white': 5, 'black-2': 5, 'white-2': 5,
  'x': 6, 'y': 6, 'omega-ruby': 6, 'alpha-sapphire': 6,
  'sun': 7, 'moon': 7, 'ultra-sun': 7, 'ultra-moon': 7,
  'lets-go-pikachu': 7, 'lets-go-eevee': 7,
  'sword': 8, 'shield': 8, 'brilliant-diamond': 8, 'shining-pearl': 8,
  'legends-arceus': 8,
  'scarlet': 9, 'violet': 9,
};

/// Maps PokeAPI "version group" names (used in movepools) to a generation.
const Map<String, int> kVersionGroupToGen = {
  'red-blue': 1, 'yellow': 1,
  'gold-silver': 2, 'crystal': 2,
  'ruby-sapphire': 3, 'emerald': 3, 'firered-leafgreen': 3,
  'diamond-pearl': 4, 'platinum': 4, 'heartgold-soulsilver': 4,
  'black-white': 5, 'black-2-white-2': 5,
  'x-y': 6, 'omega-ruby-alpha-sapphire': 6,
  'sun-moon': 7, 'ultra-sun-ultra-moon': 7,
  'lets-go-pikachu-lets-go-eevee': 7,
  'sword-shield': 8, 'brilliant-diamond-and-shining-pearl': 8,
  'legends-arceus': 8,
  'scarlet-violet': 9,
};

/// Maps each of our game ids to its PokeAPI "version group" name(s).
/// Used to resolve the game's regional Pokedex(es) and its game versions.
const Map<String, List<String>> kGameVersionGroups = {
  'rby': ['red-blue', 'yellow'],
  'gsc': ['gold-silver', 'crystal'],
  'rse': ['ruby-sapphire', 'emerald'],
  'frlg': ['firered-leafgreen'],
  'dppt': ['diamond-pearl', 'platinum'],
  'hgss': ['heartgold-soulsilver'],
  'bw': ['black-white'],
  'b2w2': ['black-2-white-2'],
  'xy': ['x-y'],
  'oras': ['omega-ruby-alpha-sapphire'],
  'sm': ['sun-moon'],
  'usum': ['ultra-sun-ultra-moon'],
  'lgpe': ['lets-go-pikachu-lets-go-eevee'],
  'swsh': ['sword-shield'],
  'bdsp': ['brilliant-diamond-and-shining-pearl'],
  'sv': ['scarlet-violet'],
  'pla': ['legends-arceus'],
  'lza': ['legends-z-a'], // may not exist in PokeAPI yet; handled gracefully
};

/// Turns a PokeAPI slug ("mr-mime", "thunder-punch") into a display name.
String prettifyName(String slug) => slug
    .split('-')
    .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ');

/// Nice labels for the six base stats (in canonical order).
const Map<String, String> kStatLabels = {
  'hp': 'HP',
  'attack': 'Attack',
  'defense': 'Defense',
  'special-attack': 'Sp. Atk',
  'special-defense': 'Sp. Def',
  'speed': 'Speed',
};

/// Learn-method labels.
const Map<String, String> kLearnMethodLabels = {
  'level-up': 'Level',
  'machine': 'TM/HM',
  'egg': 'Egg',
  'tutor': 'Tutor',
};

/// Gen 3 item id → name, for the bag editor. Covers the commonly-edited items
/// (balls, healing, vitamins, battle items, evolution stones, hold items) plus
/// generated berries (133–175) and TMs/HMs (289–346). Unknown ids fall back to
/// "Item #N" via [gen3ItemName]. Ids are the Gen 3 internal item numbers.
const Map<int, String> _named = {
  // Poké Balls
  1: 'Master Ball', 2: 'Ultra Ball', 3: 'Great Ball', 4: 'Poké Ball',
  5: 'Safari Ball', 6: 'Net Ball', 7: 'Dive Ball', 8: 'Nest Ball',
  9: 'Repeat Ball', 10: 'Timer Ball', 11: 'Luxury Ball', 12: 'Premier Ball',
  // Healing
  13: 'Potion', 14: 'Antidote', 15: 'Burn Heal', 16: 'Ice Heal',
  17: 'Awakening', 18: 'Parlyz Heal', 19: 'Full Restore', 20: 'Max Potion',
  21: 'Hyper Potion', 22: 'Super Potion', 23: 'Full Heal', 24: 'Revive',
  25: 'Max Revive', 26: 'Fresh Water', 27: 'Soda Pop', 28: 'Lemonade',
  29: 'Moomoo Milk', 30: 'EnergyPowder', 31: 'Energy Root', 32: 'Heal Powder',
  33: 'Revival Herb', 34: 'Ether', 35: 'Max Ether', 36: 'Elixir',
  37: 'Max Elixir', 38: 'Lava Cookie', 39: 'Blue Flute', 40: 'Yellow Flute',
  41: 'Red Flute', 42: 'Black Flute', 43: 'White Flute', 44: 'Berry Juice',
  45: 'Sacred Ash',
  // Vitamins / stat & PP
  63: 'HP Up', 64: 'Protein', 65: 'Iron', 66: 'Carbos', 67: 'Calcium',
  68: 'Rare Candy', 69: 'PP Up', 70: 'Zinc', 71: 'PP Max',
  // Battle items
  73: 'Guard Spec.', 74: 'Dire Hit', 75: 'X Attack', 76: 'X Defend',
  77: 'X Speed', 78: 'X Accuracy', 79: 'X Special', 80: 'Poké Doll',
  81: 'Fluffy Tail',
  // Field
  83: 'Super Repel', 84: 'Max Repel', 85: 'Escape Rope', 86: 'Repel',
  // Evolution stones
  93: 'Sun Stone', 94: 'Moon Stone', 95: 'Fire Stone', 96: 'Thunderstone',
  97: 'Water Stone', 98: 'Leaf Stone',
  // Valuables
  103: 'TinyMushroom', 104: 'Big Mushroom', 106: 'Pearl', 107: 'Big Pearl',
  108: 'Stardust', 109: 'Star Piece', 110: 'Nugget', 111: 'Heart Scale',
  // Hold items
  179: 'BrightPowder', 180: 'White Herb', 181: 'Macho Brace', 182: 'Exp. Share',
  183: 'Quick Claw', 184: 'Soothe Bell', 185: 'Mental Herb', 186: 'Choice Band',
  187: "King's Rock", 188: 'SilverPowder', 189: 'Amulet Coin', 190: 'Cleanse Tag',
  191: 'Soul Dew', 192: 'DeepSeaTooth', 193: 'DeepSeaScale', 194: 'Smoke Ball',
  195: 'Everstone', 196: 'Focus Band', 197: 'Lucky Egg', 198: 'Scope Lens',
  199: 'Metal Coat', 200: 'Leftovers', 201: 'Dragon Scale', 202: 'Light Ball',
  203: 'Soft Sand', 204: 'Hard Stone', 205: 'Miracle Seed', 206: 'BlackGlasses',
  207: 'Black Belt', 208: 'Magnet', 209: 'Mystic Water', 210: 'Sharp Beak',
  211: 'Poison Barb', 212: 'NeverMeltIce', 213: 'Spell Tag', 214: 'TwistedSpoon',
  215: 'Charcoal', 216: 'Dragon Fang', 217: 'Silk Scarf', 218: 'Up-Grade',
  219: 'Shell Bell', 220: 'Sea Incense', 221: 'Lax Incense', 222: 'Lucky Punch',
  223: 'Metal Powder', 224: 'Thick Club', 225: 'Stick',
};

const List<String> _berries = [
  'Cheri', 'Chesto', 'Pecha', 'Rawst', 'Aspear', 'Leppa', 'Oran', 'Persim',
  'Lum', 'Sitrus', 'Figy', 'Wiki', 'Mago', 'Aguav', 'Iapapa', 'Razz', 'Bluk',
  'Nanab', 'Wepear', 'Pinap', 'Pomeg', 'Kelpsy', 'Qualot', 'Hondew', 'Grepa',
  'Tamato', 'Cornn', 'Magost', 'Rabuta', 'Nomel', 'Spelon', 'Pamtre', 'Watmel',
  'Durin', 'Belue', 'Liechi', 'Ganlon', 'Salac', 'Petaya', 'Apicot', 'Lansat',
  'Starf', 'Enigma',
];

final Map<int, String> kGen3ItemNames = () {
  final m = Map<int, String>.from(_named);
  for (var i = 0; i < _berries.length; i++) {
    m[133 + i] = '${_berries[i]} Berry'; // 133..175
  }
  for (var t = 1; t <= 50; t++) {
    m[288 + t] = 'TM${t.toString().padLeft(2, '0')}'; // 289..338
  }
  for (var h = 1; h <= 8; h++) {
    m[338 + h] = 'HM${h.toString().padLeft(2, '0')}'; // 339..346
  }
  return m;
}();

String gen3ItemName(int id) => kGen3ItemNames[id] ?? 'Item #$id';

// PokeAPI item-sprite slugs for our compressed (no-space) names that PokeAPI
// hyphenates. Everything else derives its slug from the display name.
const Map<int, String> _slugOverrides = {
  30: 'energy-powder', 103: 'tiny-mushroom', 179: 'bright-powder',
  188: 'silver-powder', 192: 'deep-sea-tooth', 193: 'deep-sea-scale',
  206: 'black-glasses', 212: 'never-melt-ice', 214: 'twisted-spoon',
};

/// PokeAPI item sprite URL for a Gen 3 item id, or null when there's no useful
/// per-item sprite (TMs/HMs 289–346 use generic type icons upstream). Callers
/// should show a fallback icon on null or a network error.
String? gen3ItemSprite(int id) {
  if (id >= 289 && id <= 346) return null; // TMs & HMs
  final name = kGen3ItemNames[id];
  if (name == null) return null;
  final slug = _slugOverrides[id] ??
      name
          .toLowerCase()
          .replaceAll('é', 'e')
          .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
          .replaceAll(RegExp(r'^-|-$'), '');
  return 'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/items/$slug.png';
}

/// Items offered in the bag editor's "add" picker (id + name), sorted by name.
List<({int id, String name})> gen3ItemPicker() {
  final out = [for (final e in kGen3ItemNames.entries) (id: e.key, name: e.value)];
  out.sort((a, b) => a.name.compareTo(b.name));
  return out;
}

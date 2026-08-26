/// Curated Gen 3 event Pokémon, based on real English distributions
/// (Bulbapedia). Each carries the distribution's actual OT / Trainer ID / moves
/// / held item, is tagged with the games it applies to, and is built into a
/// structurally valid, self-consistent PK3 with the fateful-encounter flag set.
/// Distribution-RNG-perfect legality isn't claimed (natures were random in the
/// real events; here they're fixed) — these are meant to be obtained and used.
class Gen3Event {
  final String label; // shown in the picker
  final int dex; // National dex number
  final int level;
  final String otName; // distribution OT (≤ 7 chars)
  final int otTid; // OT trainer id
  final int otSid; // OT secret id
  final List<int> moves; // up to 4 move ids (National move numbers)
  final int nature; // 0..24 (fixed; real distros were random)
  final int ball; // Poké Ball id (default 4 = Poké Ball)
  final int heldItem; // Gen 3 item id (0 = none)
  final int metLocation; // met-location id (255 = special/fateful)
  final int metLevel;
  final bool fateful; // fateful-encounter/obedience flag (all real distros set it)
  final String note;

  /// Game families this event was available for: 'rs', 'e', 'frlg'.
  final Set<String> games;

  const Gen3Event({
    required this.label,
    required this.dex,
    required this.level,
    required this.otName,
    required this.otTid,
    required this.otSid,
    required this.moves,
    required this.nature,
    required this.metLevel,
    this.ball = 4,
    this.heldItem = 0,
    this.metLocation = 255,
    this.fateful = true,
    this.note = '',
    this.games = const {'rs', 'e', 'frlg'},
  });
}

/// The game family for a Gen 3 version id (matches the save editor).
String gen3EventFamily(String version) => switch (version) {
      'emerald' => 'e',
      'firered' || 'leafgreen' => 'frlg',
      _ => 'rs',
    };

/// Events available for a specific game version.
List<Gen3Event> gen3EventsFor(String version) {
  final fam = gen3EventFamily(version);
  return [for (final e in kGen3Events) if (e.games.contains(fam)) e];
}

// Move-number shorthands used below.
const _pound = 1, _transform = 144, _confusion = 93, _rest = 156, _wish = 273;
const _recover = 105, _cosmicPower = 322, _psychoBoost = 354, _hyperBeam = 63;
const _slash = 163, _dragonRage = 82, _fireSpin = 83, _thunderbolt = 85;
const _agility = 97, _thunder = 87, _lightScreen = 113, _mindReader = 95;
const _iceBeam = 58, _reflect = 115, _quickAttack = 98, _spark = 84;
const _crunch = 242, _stomp = 23, _flamethrower = 53, _swagger = 207;
const _gust = 16, _auroraBeam = 62, _mist = 54, _mirrorCoat = 243;
const _hydroPump = 56, _rainDance = 240, _swift = 129, _fireBlast = 126;
const _sunnyDay = 241, _mistBall = 296, _psychic = 94, _charm = 204;
const _lusterPurge = 295, _dragonDance = 349;

const int _salacBerry = 170; // berries start at 133; Salac = index 37

/// Verified English Generation III distributions.
const kGen3Events = <Gen3Event>[
  // ---- Mythical gifts (all games) ----
  Gen3Event(
    label: 'Mew (MYSTRY)',
    dex: 151, level: 10, otName: 'MYSTRY', otTid: 6930, otSid: 0,
    moves: [_pound, _transform], nature: 0, metLevel: 10,
    note: 'US MYSTRY Mystery-Mew distribution.',
  ),
  Gen3Event(
    label: 'Mew (Aura)',
    dex: 151, level: 10, otName: 'Aura', otTid: 20078, otSid: 0,
    moves: [_pound, _transform], nature: 0, metLevel: 10,
    note: 'European "Aura" Mew distribution.',
  ),
  Gen3Event(
    label: 'Jirachi (WISHMKR)',
    dex: 385, level: 5, otName: 'WISHMKR', otTid: 20043, otSid: 0,
    moves: [_wish, _confusion, _rest], nature: 3, metLevel: 5,
    heldItem: _salacBerry,
    note: 'Wish-Maker bonus-disc Jirachi.',
  ),
  Gen3Event(
    label: 'Deoxys (SPACE C)',
    dex: 386, level: 70, otName: 'SPACE C', otTid: 10, otSid: 0,
    moves: [_cosmicPower, _recover, _psychoBoost, _hyperBeam],
    nature: 10, metLevel: 70, games: {'e', 'frlg'},
    note: 'US Space Center Deoxys (form follows the game).',
  ),

  // ---- 10th Anniversary (10ANNIV) — OT 10ANNIV, ID 06227, all Lv 70 ----
  Gen3Event(
    label: 'Charizard (10ANNIV)', dex: 6, level: 70, otName: '10ANNIV',
    otTid: 6227, otSid: 0, moves: [_pound, _slash, _dragonRage, _fireSpin],
    nature: 3, metLevel: 70, note: '10th Anniversary distribution.',
  ),
  Gen3Event(
    label: 'Pikachu (10ANNIV)', dex: 25, level: 70, otName: '10ANNIV',
    otTid: 6227, otSid: 0,
    moves: [_thunderbolt, _agility, _thunder, _lightScreen],
    nature: 15, metLevel: 70, note: '10th Anniversary distribution.',
  ),
  Gen3Event(
    label: 'Articuno (10ANNIV)', dex: 144, level: 70, otName: '10ANNIV',
    otTid: 6227, otSid: 0, moves: [_agility, _mindReader, _iceBeam, _reflect],
    nature: 15, metLevel: 70, note: '10th Anniversary distribution.',
  ),
  Gen3Event(
    label: 'Raikou (10ANNIV)', dex: 243, level: 70, otName: '10ANNIV',
    otTid: 6227, otSid: 0, moves: [_quickAttack, _spark, _reflect, _crunch],
    nature: 15, metLevel: 70, note: '10th Anniversary distribution.',
  ),
  Gen3Event(
    label: 'Entei (10ANNIV)', dex: 244, level: 70, otName: '10ANNIV',
    otTid: 6227, otSid: 0, moves: [_fireSpin, _stomp, _flamethrower, _swagger],
    nature: 3, metLevel: 70, note: '10th Anniversary distribution.',
  ),
  Gen3Event(
    label: 'Suicune (10ANNIV)', dex: 245, level: 70, otName: '10ANNIV',
    otTid: 6227, otSid: 0, moves: [_gust, _auroraBeam, _mist, _mirrorCoat],
    nature: 15, metLevel: 70, note: '10th Anniversary distribution.',
  ),
  Gen3Event(
    label: 'Lugia (10ANNIV)', dex: 249, level: 70, otName: '10ANNIV',
    otTid: 6227, otSid: 0, moves: [_recover, _hydroPump, _rainDance, _swift],
    nature: 15, metLevel: 70, note: '10th Anniversary distribution.',
  ),
  Gen3Event(
    label: 'Ho-Oh (10ANNIV)', dex: 250, level: 70, otName: '10ANNIV',
    otTid: 6227, otSid: 0, moves: [_recover, _fireBlast, _sunnyDay, _swift],
    nature: 3, metLevel: 70, note: '10th Anniversary distribution.',
  ),
  Gen3Event(
    label: 'Latias (10ANNIV)', dex: 380, level: 70, otName: '10ANNIV',
    otTid: 6227, otSid: 0, moves: [_mistBall, _psychic, _recover, _charm],
    nature: 15, metLevel: 70, note: '10th Anniversary distribution (female).',
  ),
  Gen3Event(
    label: 'Latios (10ANNIV)', dex: 381, level: 70, otName: '10ANNIV',
    otTid: 6227, otSid: 0, moves: [_lusterPurge, _psychic, _recover, _dragonDance],
    nature: 3, metLevel: 70, note: '10th Anniversary distribution (male).',
  ),
];

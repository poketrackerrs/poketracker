/// Curated Gen 4 (Diamond/Pearl/Platinum, HeartGold/SoulSilver) event Pokémon,
/// based on the real English/US distributions (Serebii Eventdex + Bulbapedia).
/// Each carries the distribution's actual OT / Trainer ID / moves / held item /
/// nature and — most importantly — the EXACT set of games it could be received
/// on, so a Diamond save is never offered a Platinum-only event.
///
/// Built into a structurally valid PK4 (via [Pkx.create]) with the fateful flag
/// set. Distribution-RNG-perfect legality isn't claimed — many events rolled a
/// random PID/nature/IVs on pickup; here IVs are Method-1 correlated (legal and
/// realistic, never a flat 31). Guaranteed-shiny events force shininess by
/// choosing a matching Secret ID (the real cards' SID/PID aren't published).
class Gen4Event {
  final String label; // shown in the picker
  final int dex; // National dex number
  final int level;
  final String otName; // distribution OT (ignored when [ownTrainer])
  final int otTid;
  final int otSid;
  final List<int> moves; // up to 4 National move ids
  final int nature; // 0..24, or -1 for "random" (we pick a realistic one)
  final int ball; // Gen 4 ball id (16 = Cherish, 4 = Poké)
  final int heldItem; // Gen 4 item id (0 = none)
  final int metLevel;
  final bool fateful; // all real Gen 4 events set this
  final bool shiny; // guaranteed-shiny distributions
  final bool ownTrainer; // key-item / egg events: caught by YOU (OT/TID/SID = save)
  final bool isEgg; // received as an egg (built hatched at its listed level)
  final String note;

  /// Receiving games, by version id: 'diamond','pearl','platinum',
  /// 'heartgold','soulsilver'.
  final Set<String> games;

  const Gen4Event({
    required this.label,
    required this.dex,
    required this.level,
    required this.otName,
    required this.otTid,
    required this.moves,
    required this.metLevel,
    required this.games,
    this.otSid = 0,
    this.nature = -1,
    this.ball = 16, // Cherish Ball (most distributions)
    this.heldItem = 0,
    this.fateful = true,
    this.shiny = false,
    this.ownTrainer = false,
    this.isEgg = false,
    this.note = '',
  });
}

/// Events receivable on a specific Gen 4 version.
List<Gen4Event> gen4EventsFor(String version) =>
    [for (final e in kGen4Events) if (e.games.contains(version)) e];

// --- All 5 Gen 4 games / handy game-set shorthands. ---
const _dp = {'diamond', 'pearl'};
const _dppt = {'diamond', 'pearl', 'platinum'};
const _all4 = {'diamond', 'pearl', 'platinum', 'heartgold', 'soulsilver'};

// --- Move-id shorthands (National move numbers). ---
const _judgment = 449, _roarOfTime = 459, _spacialRend = 460, _shadowForce = 467;
const _psychoBoost = 354, _zapCannon = 192, _ironDefense = 334, _extremeSpeed = 245;
const _wish = 273, _confusion = 93, _rest = 156, _dracoMeteor = 434;
const _voltTackle = 344, _charge = 268, _endeavor = 283, _endure = 203;
const _nightmare = 171, _hypnosis = 95, _doubleTeam = 104, _feintAttack = 185;
const _growth = 74, _magicalLeaf = 345, _leechSeed = 73, _synthesis = 235;
const _seedFlare = 465, _aromatherapy = 312, _substitute = 164, _energyBall = 412;
const _protect = 182, _refresh = 287, _lusterPurge = 295, _zenHeadbutt = 428;
const _waterSport = 346, _mistBall = 296, _tailGlow = 294, _bubble = 145;
const _ironHead = 442, _rockSlide = 157, _icyWind = 196, _crushGrip = 462;
const _weatherBall = 311, _auraSphere = 396, _flareBlitz = 394, _crushClaw = 306;
const _howl = 336, _sheerCold = 329, _aquaRing = 392, _airSlash = 403;
const _leafStorm = 437, _recover = 105, _nastyPlot = 417, _healingWish = 361;

// --- Nature-id shorthands. ---
const _adamant = 3, _relaxed = 7, _jolly = 13, _rash = 19;

/// Verified English Generation IV distributions.
const kGen4Events = <Gen4Event>[
  // ---- Cherish-Ball distributions (fixed OT) ----
  Gen4Event(
    label: 'Arceus (TRU)', dex: 493, level: 100, otName: 'TRU', otTid: 11079,
    moves: [_judgment, _roarOfTime, _spacialRend, _shadowForce],
    metLevel: 100, games: _dppt,
    note: '2009 Toys R Us Arceus (D/P/Pt). Random nature; held a Rowap Berry.',
  ),
  Gen4Event(
    label: 'Deoxys (GAMESTP 2008)', dex: 386, level: 50, otName: 'Gamestp',
    otTid: 6218,
    moves: [_psychoBoost, _zapCannon, _ironDefense, _extremeSpeed],
    metLevel: 50, games: _dp,
    note: '2008 GameStop Deoxys (Diamond/Pearl only). Form follows the game.',
  ),
  Gen4Event(
    label: 'Jirachi (GAMESTP 2010)', dex: 385, level: 5, otName: 'GAMESTP',
    otTid: 2270, moves: [_wish, _confusion, _rest, _dracoMeteor],
    metLevel: 5, games: _dppt,
    note: '2010 GameStop Jirachi (D/P/Pt). Held a Liechi Berry.',
  ),
  Gen4Event(
    label: 'Jirachi (SMR2010)', dex: 385, level: 5, otName: 'SMR2010',
    otTid: 6260, moves: [_wish, _confusion, _rest, _dracoMeteor],
    metLevel: 5, games: _all4,
    note: '2010 Wi-Fi Jirachi — all 5 games. Held a Liechi Berry.',
  ),
  Gen4Event(
    label: 'Pichu — shiny (SPR2010)', dex: 172, level: 30, otName: 'SPR2010',
    otTid: 3050, moves: [_voltTackle, _charge, _endeavor, _endure],
    nature: _jolly, metLevel: 30, shiny: true, games: _dppt,
    note: 'Pikachu-colored Pichu (D/P/Pt). Send to HG/SS to unlock the '
        'Spiky-eared Pichu. Jolly, held an Everstone.',
  ),
  Gen4Event(
    label: 'Darkrai (ALAMOS)', dex: 491, level: 50, otName: 'ALAMOS',
    otTid: 5318, moves: [_nightmare, _hypnosis, _roarOfTime, _spacialRend],
    metLevel: 50, games: _dp,
    note: '2008 movie Darkrai (Diamond/Pearl). Held an Enigma Berry.',
  ),
  Gen4Event(
    label: 'Shaymin (TRU)', dex: 492, level: 50, otName: 'TRU', otTid: 2089,
    moves: [_seedFlare, _aromatherapy, _substitute, _energyBall],
    metLevel: 50, games: _dp,
    note: '2009 Toys R Us Shaymin (Diamond/Pearl). Held a Micle Berry.',
  ),
  Gen4Event(
    label: 'Regigigas (TRU)', dex: 486, level: 100, otName: 'TRU', otTid: 3089,
    moves: [_ironHead, _rockSlide, _icyWind, _crushGrip],
    metLevel: 100, games: _dp,
    note: '2009 Toys R Us Regigigas (Diamond/Pearl). Held a Custap Berry.',
  ),
  Gen4Event(
    label: 'Celebi (WIN2011)', dex: 251, level: 50, otName: 'WIN2011',
    otTid: 2211, moves: [_leafStorm, _recover, _nastyPlot, _healingWish],
    metLevel: 50, games: _all4,
    note: '2011 Celebi (all 5 games). Send to B/W to unlock Zorua. '
        'Held a Jaboca Berry.',
  ),

  // ---- Shiny legendary beasts — GAMESTP 2010 (fixed natures, guaranteed shiny) ----
  Gen4Event(
    label: 'Raikou — shiny (GAMESTP)', dex: 243, level: 30, otName: 'GAMESTP',
    otTid: 1031, moves: [_zapCannon, _weatherBall, _auraSphere, _extremeSpeed],
    nature: _rash, metLevel: 30, shiny: true, games: _all4,
    note: 'Shiny Raikou (all 5 games). Send to B/W toward Zoroark. Rash.',
  ),
  Gen4Event(
    label: 'Entei — shiny (GAMESTP)', dex: 244, level: 30, otName: 'GAMESTP',
    otTid: 1171, moves: [_flareBlitz, _crushClaw, _howl, _extremeSpeed],
    nature: _adamant, metLevel: 30, shiny: true, games: _all4,
    note: 'Shiny Entei (all 5 games). Send to B/W toward Zoroark. Adamant.',
  ),
  Gen4Event(
    label: 'Suicune — shiny (GAMESTP)', dex: 245, level: 30, otName: 'GAMESTP',
    otTid: 1311, moves: [_sheerCold, _aquaRing, _airSlash, _extremeSpeed],
    nature: _relaxed, metLevel: 30, shiny: true, games: _all4,
    note: 'Shiny Suicune (all 5 games). Send to B/W toward Zoroark. Relaxed.',
  ),

  // ---- Key-item / egg events — caught by YOU (OT/TID/SID come from your save) ----
  Gen4Event(
    label: 'Shaymin (Oak\'s Letter)', dex: 492, level: 30, otName: '', otTid: 0,
    moves: [_growth, _magicalLeaf, _leechSeed, _synthesis],
    ball: 4, metLevel: 30, ownTrainer: true, games: {'platinum'},
    note: 'Oak\'s Letter → Flower Paradise (Platinum only). Caught as yours.',
  ),
  Gen4Event(
    label: 'Darkrai (Member Card)', dex: 491, level: 50, otName: '', otTid: 0,
    moves: [_doubleTeam, _nightmare, _feintAttack, _hypnosis],
    ball: 4, metLevel: 50, ownTrainer: true, games: {'platinum'},
    note: 'Member Card → Newmoon Island (Platinum only). Caught as yours.',
  ),
  Gen4Event(
    label: 'Latios (Enigma Stone)', dex: 381, level: 40, otName: '', otTid: 0,
    moves: [_protect, _refresh, _lusterPurge, _zenHeadbutt],
    ball: 4, metLevel: 40, ownTrainer: true, games: {'heartgold'},
    note: 'Enigma Stone → Pewter City (HeartGold only). Caught as yours.',
  ),
  Gen4Event(
    label: 'Latias (Enigma Stone)', dex: 380, level: 40, otName: '', otTid: 0,
    moves: [_waterSport, _refresh, _mistBall, _zenHeadbutt],
    ball: 4, metLevel: 40, ownTrainer: true, games: {'soulsilver'},
    note: 'Enigma Stone → Pewter City (SoulSilver only). Caught as yours.',
  ),
  Gen4Event(
    label: 'Manaphy (Ranger Egg)', dex: 490, level: 1, otName: '', otTid: 0,
    moves: [_tailGlow, _bubble, _waterSport], ball: 4, metLevel: 1,
    ownTrainer: true, isEgg: true, games: _all4,
    note: 'Pokémon Ranger Manaphy Egg (all 5 games). Built hatched at Lv 1.',
  ),
];

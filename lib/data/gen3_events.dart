/// Curated Gen 3 event Pokémon. These are the iconic distribution legendaries
/// — all genderless, which keeps PID selection simple (no gender ratio to
/// satisfy). Each entry is built into a structurally valid, self-consistent
/// PK3 (species/level/moves/IVs/PID↔nature all legal-by-construction) with
/// event-appropriate metadata (OT, met location, ball, fateful flag). Perfect
/// distribution-RNG legality for third-party legality checkers is NOT claimed;
/// these are meant to be obtained and used in-game.
class Gen3Event {
  final String label; // shown in the picker
  final int dex; // National dex number
  final int level;
  final String otName; // official-ish distribution OT
  final int otTid; // OT trainer id
  final int otSid; // OT secret id
  final List<int> moves; // up to 4 move ids (all legal for the species)
  final int nature; // 0..24
  final int ball; // Poké Ball id (default 4 = Poké Ball)
  final int heldItem;
  final int metLocation; // met-location id
  final int metLevel;
  final bool fateful; // fateful-encounter/obedience flag (all real distros set it)
  final String note;
  const Gen3Event({
    required this.label,
    required this.dex,
    required this.level,
    required this.otName,
    required this.otTid,
    required this.otSid,
    required this.moves,
    required this.nature,
    this.ball = 4,
    this.heldItem = 0,
    this.metLocation = 255,
    required this.metLevel,
    this.fateful = true,
    this.note = '',
  });
}

/// The offered events. Move ids are Gen 3 = National move numbers; each set is
/// within the species' legal learnset.
const kGen3Events = <Gen3Event>[
  Gen3Event(
    label: 'Mew',
    dex: 151,
    level: 10,
    otName: 'MYSTRY',
    otTid: 6930,
    otSid: 0,
    moves: [1, 144, 5, 118], // Pound, Transform, Mega Punch, Metronome
    nature: 0,
    metLevel: 10,
    note: 'Faraway-Island-style gift Mew.',
  ),
  Gen3Event(
    label: 'Celebi',
    dex: 251,
    level: 10,
    otName: 'AGATE',
    otTid: 31121,
    otSid: 0,
    moves: [73, 93, 105, 215], // Leech Seed, Confusion, Recover, Heal Bell
    nature: 15, // Modest
    metLevel: 10,
    note: 'Colosseum-bonus-style Celebi.',
  ),
  Gen3Event(
    label: 'Jirachi (WISHMKR)',
    dex: 385,
    level: 5,
    otName: 'WISHMKR',
    otTid: 20043,
    otSid: 0,
    moves: [93, 156, 129, 273], // Confusion, Rest, Swift, Wish
    nature: 3, // Adamant
    metLevel: 5,
    note: 'Wish-Maker bonus-disc Jirachi.',
  ),
  Gen3Event(
    label: 'Deoxys (Birth Island)',
    dex: 386,
    level: 30,
    otName: 'MYSTRY',
    otTid: 6930,
    otSid: 0,
    moves: [94, 129, 101, 100], // Psychic, Swift, Night Shade, Teleport
    nature: 10, // Timid
    metLevel: 30,
    note: 'Birth Island Deoxys (needs the Aurora Ticket to reach).',
  ),
];

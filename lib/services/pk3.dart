import 'dart:typed_data';

/// Total EXP needed to be at [level] for a species' growth rate. Growth-rate
/// keys are PokeAPI names. Verified against the known level-100 totals.
int gen3Exp(String growthRate, int level) {
  final n = level.clamp(1, 100);
  final n3 = n * n * n;
  switch (growthRate) {
    case 'fast':
      return 4 * n3 ~/ 5;
    case 'slow':
      return 5 * n3 ~/ 4;
    case 'medium-slow':
      return (6 * n3 ~/ 5) - 15 * n * n + 100 * n - 140;
    case 'slow-then-very-fast': // erratic
      if (n < 50) return n3 * (100 - n) ~/ 50;
      if (n < 68) return n3 * (150 - n) ~/ 100;
      if (n < 98) return n3 * ((1911 - 10 * n) ~/ 3) ~/ 500;
      return n3 * (160 - n) ~/ 100;
    case 'fast-then-very-slow': // fluctuating
      if (n < 15) return n3 * (((n + 1) ~/ 3) + 24) ~/ 50;
      if (n < 36) return n3 * (n + 14) ~/ 50;
      return n3 * ((n ~/ 2) + 32) ~/ 50;
    default: // medium / medium-fast
      return n3;
  }
}

/// The level for a given total [exp] under [growthRate] — the highest level
/// whose EXP threshold is still ≤ exp. Boxed Pokémon store no level byte, so it
/// is derived from EXP this way.
int gen3LevelFromExp(String growthRate, int exp) {
  var lvl = 1;
  for (var l = 2; l <= 100; l++) {
    if (gen3Exp(growthRate, l) <= exp) {
      lvl = l;
    } else {
      break;
    }
  }
  return lvl;
}

/// Gen 3 Poké Balls, indexed by ball id (0 = none/unknown).
const kGen3Balls = [
  '—', 'Master', 'Ultra', 'Great', 'Poké', 'Safari', 'Net', 'Dive', 'Nest',
  'Repeat', 'Timer', 'Luxury', 'Premier',
];

/// Gen 3 language codes → name (6 = Korean, unused in the Western games).
const kGen3Languages = {1: 'JPN', 2: 'ENG', 3: 'FRE', 4: 'ITA', 5: 'GER', 7: 'SPA'};

/// The 25 Gen 3 natures, in PID%25 order.
const kNatures = [
  'Hardy', 'Lonely', 'Brave', 'Adamant', 'Naughty', 'Bold', 'Docile',
  'Relaxed', 'Impish', 'Lax', 'Timid', 'Hasty', 'Serious', 'Jolly', 'Naive',
  'Modest', 'Mild', 'Quiet', 'Bashful', 'Rash', 'Calm', 'Gentle', 'Sassy',
  'Careful', 'Quirky',
];

/// Gen 3 stores its own internal species order: #1–251 match the National dex
/// 1:1, then 25 unused slots, then Hoenn (#252–386) sits at internal 277–411
/// (National + 25). These convert between the two.
int gen3InternalToNational(int internal) {
  if (internal <= 251) return internal;
  if (internal >= 277 && internal <= 411) return internal - 25;
  return 0; // an unused/glitch internal slot
}

int gen3NationalToInternal(int national) =>
    national <= 251 ? national : national + 25;

/// Gen 3 (Western) character table ⇄ ASCII, for nicknames and OT names. Only the
/// printable letters/digits/space/common punctuation are mapped; 0xFF ends a
/// string. Unmapped bytes decode to '' and unmappable chars encode to space.
const _kGen3Terminator = 0xFF;
final Map<int, String> _gen3ToChar = () {
  final m = <int, String>{0x00: ' ', 0xAE: '-', 0xAD: '.', 0xBA: '/', 0xB8: ','};
  for (var i = 0; i < 10; i++) {
    m[0xA1 + i] = '$i'; // 0xA1..0xAA = 0-9
  }
  for (var i = 0; i < 26; i++) {
    m[0xBB + i] = String.fromCharCode(65 + i); // A-Z
  }
  for (var i = 0; i < 26; i++) {
    m[0xD5 + i] = String.fromCharCode(97 + i); // a-z
  }
  return m;
}();
final Map<String, int> _charToGen3 = {
  for (final e in _gen3ToChar.entries) e.value: e.key
};

String gen3DecodeText(Uint8List bytes, int start, int len) {
  final sb = StringBuffer();
  for (var i = 0; i < len; i++) {
    final b = bytes[start + i];
    if (b == _kGen3Terminator) break;
    sb.write(_gen3ToChar[b] ?? '');
  }
  return sb.toString().trimRight();
}

/// Encode [text] into [len] Gen 3 bytes at [start] (padded/terminated with 0xFF).
void gen3EncodeText(Uint8List bytes, int start, int len, String text) {
  for (var i = 0; i < len; i++) {
    if (i < text.length) {
      bytes[start + i] = _charToGen3[text[i]] ?? _charToGen3[' ']!;
    } else {
      bytes[start + i] = _kGen3Terminator;
    }
  }
}

/// A read-only summary of a party Pokémon for the editor UI.
class Gen3PartyMon {
  final int slot; // party index 0..5
  final int dex; // national dex number
  final int level;
  final bool shiny;
  final int nature; // 0..24
  final List<int> ivs; // HP, Atk, Def, Spe, SpA, SpD
  final List<int> evs; // same order
  final List<int> moves; // 4 move ids
  final String nickname; // stored nickname (may differ from species name)
  final String otName; // original trainer name
  final int friendship; // 0..255
  final int exp; // total experience (box mons derive level from this)
  final int ball; // Poké Ball id
  final int metLevel; // level met (0..100)
  final int metLocation; // location id
  final int otGender; // 0 male, 1 female
  final int language; // Gen 3 language code
  final int markings; // 4-bit marking flags
  final int pokerus; // Pokérus byte
  final List<int> contest; // cool, beauty, cute, smart, tough, sheen
  final int? boxSlot; // global PC slot 0..419, or null for a party mon
  String? name; // species name, resolved from the Pokédex index
  Gen3PartyMon({
    required this.slot,
    required this.dex,
    required this.level,
    required this.shiny,
    required this.nature,
    required this.ivs,
    required this.evs,
    required this.moves,
    this.nickname = '',
    this.otName = '',
    this.friendship = 0,
    this.exp = 0,
    this.ball = 0,
    this.metLevel = 0,
    this.metLocation = 0,
    this.otGender = 0,
    this.language = 2,
    this.markings = 0,
    this.pokerus = 0,
    this.contest = const [0, 0, 0, 0, 0, 0],
    this.boxSlot,
    this.name,
  });
  bool get isBoxed => boxSlot != null;
  Gen3PartyMon copyWith({int? level}) => Gen3PartyMon(
        slot: slot,
        dex: dex,
        level: level ?? this.level,
        shiny: shiny,
        nature: nature,
        ivs: ivs,
        evs: evs,
        moves: moves,
        nickname: nickname,
        otName: otName,
        friendship: friendship,
        exp: exp,
        ball: ball,
        metLevel: metLevel,
        metLocation: metLocation,
        otGender: otGender,
        language: language,
        markings: markings,
        pokerus: pokerus,
        contest: contest,
        boxSlot: boxSlot,
        name: name,
      );
  String get natureName => kNatures[nature % 25];
}

/// A pending edit to one party Pokémon (from the editor UI).
class PartyEdit {
  final bool? shiny;
  final List<int>? ivs; // HP, Atk, Def, Spe, SpA, SpD (0..31)
  final List<int>? evs; // same order (0..255, total <= 510)
  final List<int>? moves; // 4 move ids (0 = empty slot)
  final int? nature; // 0..24
  final int? level; // 1..100
  final int? species; // National dex; changing it re-derives stats + moves
  final String? nickname; // stored nickname
  final int? friendship; // 0..255
  final String? otName; // original trainer name
  final int? ball; // Poké Ball id
  final int? metLevel; // 0..100
  final int? metLocation; // location id
  final int? otGender; // 0 male, 1 female
  final int? language; // Gen 3 language code
  final int? markings; // 4-bit marking flags
  final int? pokerus; // Pokérus byte
  final List<int>? contest; // cool, beauty, cute, smart, tough, sheen
  const PartyEdit(
      {this.shiny,
      this.ivs,
      this.evs,
      this.moves,
      this.nature,
      this.level,
      this.species,
      this.nickname,
      this.friendship,
      this.otName,
      this.ball,
      this.metLevel,
      this.metLocation,
      this.otGender,
      this.language,
      this.markings,
      this.pokerus,
      this.contest});
  bool get changesStats =>
      ivs != null ||
      evs != null ||
      nature != null ||
      level != null ||
      species != null;
}

/// A single Gen 3 Pokémon (PK3). Decrypts the 48-byte data block (4 sub-blocks
/// shuffled by PID%24, XOR-encrypted with OTID^PID), exposes editable fields,
/// and re-encrypts with a fresh block checksum. Verified byte-exact round-trip
/// against a real Emerald party Pokémon.
///
/// Works on a boxed (80-byte) or party (100-byte) block; the trailing 20 party
/// bytes (status/level/stats) are preserved on encode. Stat recomputation after
/// a stat-affecting edit needs base stats (added with the editor UI later).
class Pk3 {
  final Uint8List raw; // 80 or 100 bytes (kept; header + tail preserved)
  final Uint8List data; // 48-byte DECRYPTED data block
  String order; // substructure order, e.g. "GAEM" (changes if PID changes)

  Pk3._(this.raw, this.data, this.order);

  static const _orders = [
    'GAEM', 'GAME', 'GEAM', 'GEMA', 'GMAE', 'GMEA',
    'AGEM', 'AGME', 'AEGM', 'AEMG', 'AMGE', 'AMEG',
    'EGAM', 'EGMA', 'EAGM', 'EAMG', 'EMGA', 'EMAG',
    'MGAE', 'MGEA', 'MAGE', 'MAEG', 'MEGA', 'MEAG',
  ];

  static int _u16(Uint8List b, int o) => b[o] | (b[o + 1] << 8);
  static int _u32(Uint8List b, int o) =>
      b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);
  static void _sU16(Uint8List b, int o, int v) {
    b[o] = v & 0xFF;
    b[o + 1] = (v >> 8) & 0xFF;
  }

  static void _sU32(Uint8List b, int o, int v) {
    b[o] = v & 0xFF;
    b[o + 1] = (v >> 8) & 0xFF;
    b[o + 2] = (v >> 16) & 0xFF;
    b[o + 3] = (v >> 24) & 0xFF;
  }

  int get pid => _u32(raw, 0x00);
  int get otid => _u32(raw, 0x04);
  bool get isEmpty => pid == 0 && otid == 0;
  // party blocks (100 bytes) store the current level at 0x54.
  int get level => raw.length > 0x54 ? raw[0x54] : 0;

  /// Decode a PK3 from its (still-encrypted) block.
  factory Pk3.decode(Uint8List block) {
    final raw = Uint8List.fromList(block);
    final pid = _u32(raw, 0x00), otid = _u32(raw, 0x04);
    final key = pid ^ otid;
    final data = Uint8List.fromList(raw.sublist(0x20, 0x50));
    for (var i = 0; i < 48; i += 4) {
      _sU32(data, i, (_u32(data, i) ^ key) & 0xFFFFFFFF);
    }
    return Pk3._(raw, data, _orders[pid % 24]);
  }

  /// Build a fresh, self-consistent PK3 from scratch (for event injection).
  /// Stats are left zero — the caller fills them with [recomputeStats] after
  /// supplying base stats. [party] picks the 100- vs 80-byte block size.
  factory Pk3.create({
    required int otid,
    required int nationalSpecies,
    required int level,
    required int totalExp,
    required List<int> moves,
    required List<int> pp,
    required List<int> ivs,
    required String nickname,
    required String otName,
    required int nature,
    bool shiny = false,
    int ball = 4,
    int heldItem = 0,
    int metLocation = 255,
    int metLevel = 0,
    int language = 2,
    int friendship = 70,
    int otGender = 0,
    int gameOfOrigin = 0,
    bool party = true,
  }) {
    final raw = Uint8List(party ? 100 : 80);
    _sU32(raw, 0x04, otid);
    raw[0x12] = language & 0xFF;
    raw[0x13] = 0x02; // "has species" sanity flag (non-egg, valid)
    // Choose a PID that yields the wanted nature (pid % 25) and shininess.
    final tid = otid & 0xFFFF, sid = otid >> 16;
    var pid = nature + 25 * 0x100; // start above 0 to avoid an empty-looking PID
    for (var n = 0; n < 0x20000; n++) {
      final p = nature + 25 * (0x100 + n);
      if (p > 0xFFFFFFFF) break;
      final sh = (tid ^ sid ^ (p & 0xFFFF) ^ (p >> 16)) < 8;
      if (sh == shiny) {
        pid = p;
        break;
      }
    }
    _sU32(raw, 0x00, pid & 0xFFFFFFFF);
    final pk = Pk3._(raw, Uint8List(48), _orders[pid % 24]);
    pk.setSpeciesNational(nationalSpecies);
    pk.setLevel(level, totalExp);
    pk.setMoves(moves);
    for (var k = 0; k < 4; k++) {
      pk.setPP(k, k < pp.length ? pp[k] : 0);
    }
    pk.setIVs(ivs);
    pk.setNickname(nickname);
    pk.setOtName(otName);
    pk.setHeldItem(heldItem);
    pk.setFriendship(friendship);
    pk.setBall(ball);
    pk.setMetLevel(metLevel);
    pk.setMetLocation(metLocation);
    pk.setOtGender(otGender);
    pk.setGameOfOrigin(gameOfOrigin);
    return pk;
  }

  // sub-block base offset within the decrypted 48-byte data
  int _sub(String letter) => order.indexOf(letter) * 12;

  int get species => _u16(data, _sub('G') + 0x00); // Gen 3 internal index
  int get nationalDex => gen3InternalToNational(species);
  int get heldItem => _u16(data, _sub('G') + 0x02);
  int get friendship => data[_sub('G') + 0x09];
  int get pokerus => data[_sub('M') + 0x00];
  // Nickname (10 bytes @ 0x08) and OT name (7 bytes @ 0x14) live in the raw
  // header, outside the encrypted 48-byte block — so they don't touch the block
  // checksum (only the enclosing section checksum, recomputed on save).
  String get nickname => gen3DecodeText(raw, 0x08, 10);
  String get otName => gen3DecodeText(raw, 0x14, 7);
  int get language => raw[0x12];
  int get markings => raw[0x1B]; // 4 bits: circle/square/triangle/heart
  // "Origins" word (M+0x02): met level (0-6), game of origin (7-10), Poké Ball
  // (11-14), OT gender (bit 15).
  int get _origins => _u16(data, _sub('M') + 0x02);
  int get metLevel => _origins & 0x7F;
  int get gameOfOrigin => (_origins >> 7) & 0xF;
  int get ball => (_origins >> 11) & 0xF;
  int get otGender => (_origins >> 15) & 1; // 0 = male, 1 = female
  int get metLocation => data[_sub('M') + 0x01];
  int get ribbons => _u32(data, _sub('M') + 0x08);
  // Contest condition (E+0x06..0x0B): cool, beauty, cute, smart, tough, sheen.
  List<int> get contest => [for (var k = 0; k < 6; k++) data[_sub('E') + 6 + k]];
  List<int> get moves =>
      [for (var k = 0; k < 4; k++) _u16(data, _sub('A') + k * 2)];
  List<int> get pp => [for (var k = 0; k < 4; k++) data[_sub('A') + 8 + k]];
  void setPP(int index, int value) =>
      data[_sub('A') + 8 + index] = value.clamp(0, 255);
  List<int> get evs =>
      [for (var k = 0; k < 6; k++) data[_sub('E') + k]];
  int get _ivWord => _u32(data, _sub('M') + 0x04);
  List<int> get ivs => [for (var k = 0; k < 6; k++) (_ivWord >> (5 * k)) & 31];
  int get nature => pid % 25;
  bool get isShiny {
    final tid = otid & 0xFFFF, sid = otid >> 16;
    return (tid ^ sid ^ (pid & 0xFFFF) ^ (pid >> 16)) < 8;
  }

  /// Recompute the block checksum (sum of the 24 decrypted u16 words).
  int computeChecksum() {
    var s = 0;
    for (var i = 0; i < 48; i += 2) {
      s = (s + _u16(data, i)) & 0xFFFF;
    }
    return s;
  }

  int get storedChecksum => _u16(raw, 0x1C);

  // ------------------------------------------------------------- legal edits
  void setIVs(List<int> v) {
    var w = 0;
    for (var k = 0; k < 6; k++) {
      w |= (v[k].clamp(0, 31)) << (5 * k);
    }
    w |= _ivWord & (0x3 << 30); // preserve egg + ability bits
    _sU32(data, _sub('M') + 0x04, w);
  }

  void setEVs(List<int> v) {
    for (var k = 0; k < 6; k++) {
      data[_sub('E') + k] = v[k].clamp(0, 255);
    }
  }

  void setMoves(List<int> mv) {
    for (var k = 0; k < 4; k++) {
      _sU16(data, _sub('A') + k * 2, k < mv.length ? mv[k] : 0);
    }
  }

  // Changing the PID also changes the sub-block shuffle order (PID%24) and the
  // XOR key (PID^OTID); re-order the decrypted blocks so fields stay put. The
  // block checksum is order-independent (same 24 words), so it's unaffected.
  void _setPid(int newPid) {
    final blocks = <String, List<int>>{
      for (var i = 0; i < 4; i++) order[i]: data.sublist(i * 12, i * 12 + 12)
    };
    final newOrder = _orders[newPid % 24];
    for (var i = 0; i < 4; i++) {
      data.setRange(i * 12, i * 12 + 12, blocks[newOrder[i]]!);
    }
    order = newOrder;
    _sU32(raw, 0x00, newPid & 0xFFFFFFFF);
  }

  void setHeldItem(int itemId) => _sU16(data, _sub('G') + 0x02, itemId);
  void setFriendship(int v) => data[_sub('G') + 0x09] = v.clamp(0, 255);
  void setPokerus(int v) => data[_sub('M') + 0x00] = v & 0xFF;
  void setNickname(String name) => gen3EncodeText(raw, 0x08, 10, name);
  void setOtName(String name) => gen3EncodeText(raw, 0x14, 7, name);
  void setLanguage(int v) => raw[0x12] = v & 0xFF;
  void setMarkings(int v) => raw[0x1B] = v & 0xF;
  void setMetLocation(int v) => data[_sub('M') + 0x01] = v & 0xFF;
  void _setOrigins(int v) => _sU16(data, _sub('M') + 0x02, v & 0xFFFF);
  void setMetLevel(int v) =>
      _setOrigins((_origins & ~0x7F) | (v.clamp(0, 100) & 0x7F));
  void setGameOfOrigin(int v) =>
      _setOrigins((_origins & ~(0xF << 7)) | ((v & 0xF) << 7));
  void setBall(int v) =>
      _setOrigins((_origins & ~(0xF << 11)) | ((v.clamp(0, 12) & 0xF) << 11));
  void setOtGender(int g) =>
      _setOrigins((_origins & ~(1 << 15)) | ((g & 1) << 15));
  void setContest(List<int> v) {
    for (var k = 0; k < 6; k++) {
      data[_sub('E') + 6 + k] = v[k].clamp(0, 255);
    }
  }

  /// Change the species to National-dex [nat]. Legality (stats, learnset-legal
  /// moves, EXP for the new growth rate, dex flag) is finished by the caller,
  /// which has the PokeAPI data; this just writes the internal species index.
  void setSpeciesNational(int nat) =>
      _sU16(data, _sub('G') + 0x00, gen3NationalToInternal(nat));
  int get exp => _u32(data, _sub('G') + 0x04);
  void setLevel(int level, int exp) {
    if (raw.length > 0x54) raw[0x54] = level.clamp(1, 100);
    _sU32(data, _sub('G') + 0x04, exp);
  }

  /// Regenerate the PID keeping the low 16 bits (gender + ability), searching
  /// the high bits to hit the desired nature and shininess (whichever is left
  /// null is preserved). Falls back to matching nature alone if the exact
  /// nature+shiny combo isn't reachable without changing gender/ability.
  void _regenPid({int? targetNature, bool? targetShiny, bool primaryShiny = false}) {
    // Keep only the low BYTE fixed — that alone preserves gender (PID & 0xFF)
    // and ability (PID & 1). Varying the other 24 bits makes every
    // (nature, shiny) pair reachable, so shiny + nature can always be set
    // together without touching gender/ability.
    final loByte = pid & 0xFF;
    final tid = otid & 0xFFFF, sid = otid >> 16;
    final wantNature = targetNature ?? nature;
    final wantShiny = targetShiny ?? isShiny;
    int? both, shinyOnly, natureOnly;
    for (var up = 0; up <= 0xFFFFFF; up++) {
      final full = ((up << 8) | loByte) & 0xFFFFFFFF;
      final natOk = full % 25 == wantNature;
      final shOk =
          ((tid ^ sid ^ (full & 0xFFFF) ^ (full >> 16)) < 8) == wantShiny;
      if (natOk && shOk) {
        both = full;
        break;
      }
      if (shOk) shinyOnly ??= full;
      if (natOk) natureOnly ??= full;
    }
    // "both" is essentially always reachable now; the fallbacks only matter in
    // pathological cases. gender + ability stay fixed via the low byte either way.
    final chosen = both ??
        (primaryShiny ? (shinyOnly ?? natureOnly) : (natureOnly ?? shinyOnly));
    if (chosen != null) _setPid(chosen);
  }

  /// Make shiny (or not) legally — preserves gender + ability; keeps nature when
  /// possible, otherwise shininess wins.
  void setShiny(bool wantShiny) {
    if (isShiny != wantShiny) {
      _regenPid(targetShiny: wantShiny, primaryShiny: true);
    }
  }

  /// Change nature legally — preserves gender + ability; keeps shininess when
  /// possible, otherwise the nature wins.
  void setNature(int newNature) {
    if (nature != newNature) _regenPid(targetNature: newNature % 25);
  }

  /// Recompute the party stats (HP/Atk/Def/Spe/SpA/SpD) from IVs, EVs, level,
  /// nature and base stats, then heal to full. [baseGen3] is in Gen 3 stat order
  /// (HP, Atk, Def, Spe, SpA, SpD). Only meaningful on a 100-byte party block.
  void recomputeStats(List<int> baseGen3) {
    if (raw.length <= 0x62) return;
    final lvl = level, iv = ivs, ev = evs;
    final up = nature ~/ 5, down = nature % 5; // 0=Atk,1=Def,2=Spe,3=SpA,4=SpD
    final hp =
        (2 * baseGen3[0] + iv[0] + ev[0] ~/ 4) * lvl ~/ 100 + lvl + 10;
    final out = <int>[hp];
    for (var s = 0; s < 5; s++) {
      var v = (2 * baseGen3[s + 1] + iv[s + 1] + ev[s + 1] ~/ 4) * lvl ~/ 100 + 5;
      if (up != down) {
        if (up == s) v = v * 110 ~/ 100;
        if (down == s) v = v * 90 ~/ 100;
      }
      out.add(v);
    }
    _sU16(raw, 0x56, out[0]); // current HP (healed)
    _sU16(raw, 0x58, out[0]); // max HP
    _sU16(raw, 0x5A, out[1]); // Atk
    _sU16(raw, 0x5C, out[2]); // Def
    _sU16(raw, 0x5E, out[3]); // Spe
    _sU16(raw, 0x60, out[4]); // SpA
    _sU16(raw, 0x62, out[5]); // SpD
  }

  /// Re-encrypt and return the block bytes (with a fresh block checksum),
  /// preserving the header and any party-stat tail.
  Uint8List encode() {
    _sU16(raw, 0x1C, computeChecksum());
    final key = pid ^ otid;
    final enc = Uint8List.fromList(data);
    for (var i = 0; i < 48; i += 4) {
      _sU32(enc, i, (_u32(enc, i) ^ key) & 0xFFFFFFFF);
    }
    raw.setRange(0x20, 0x50, enc);
    return raw;
  }
}

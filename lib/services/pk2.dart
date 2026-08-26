import 'dart:typed_data';

/// Total EXP needed to be at [level] under a species' growth rate. Gen 2 uses
/// the same six experience formulas as Gen 3, so the growth-rate keys are the
/// PokeAPI names ('fast', 'medium'/'medium-fast', 'medium-slow', 'slow',
/// 'slow-then-very-fast' = erratic, 'fast-then-very-slow' = fluctuating).
int gen2Exp(String growthRate, int level) {
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

/// The level for a given total [exp] under [growthRate] — boxed Pokémon DO carry
/// a level byte in Gen 2, but this stays useful for validation.
int gen2LevelFromExp(String growthRate, int exp) {
  var lvl = 1;
  for (var l = 2; l <= 100; l++) {
    if (gen2Exp(growthRate, l) <= exp) {
      lvl = l;
    } else {
      break;
    }
  }
  return lvl;
}

/// Gen 2 (English) text terminator.
const int kGen2Terminator = 0x50;

/// Gen 1/2 (Western) character table ⇄ ASCII, for nicknames and OT names. Only
/// the printable letters/digits/space/common punctuation are mapped; 0x50 ends a
/// string. Unmapped bytes decode to '' and unmappable chars encode to space.
final Map<int, String> _gen2ToChar = () {
  final m = <int, String>{
    0x7F: ' ',
    0x9A: '(', 0x9B: ')', 0x9C: ':', 0x9D: ';', 0x9E: '[', 0x9F: ']',
    0xE3: '-', 0xE6: '?', 0xE7: '!', 0xE8: '.', 0xF3: '/', 0xF4: ',',
  };
  for (var i = 0; i < 26; i++) {
    m[0x80 + i] = String.fromCharCode(65 + i); // 0x80..0x99 = A-Z
    m[0xA0 + i] = String.fromCharCode(97 + i); // 0xA0..0xB9 = a-z
  }
  for (var i = 0; i < 10; i++) {
    m[0xF6 + i] = '$i'; // 0xF6..0xFF = 0-9
  }
  return m;
}();
final Map<String, int> _charToGen2 = {
  for (final e in _gen2ToChar.entries) e.value: e.key
};

/// Decode up to [len] Gen 2 bytes at [start] into a string (stops at 0x50).
String gen2DecodeText(Uint8List bytes, int start, int len) {
  final sb = StringBuffer();
  for (var i = 0; i < len; i++) {
    final b = bytes[start + i];
    if (b == kGen2Terminator || b == 0x00) break;
    sb.write(_gen2ToChar[b] ?? '');
  }
  return sb.toString().trimRight();
}

/// Encode [text] into a fresh [len]-byte Gen 2 field (0x50-terminated/padded).
Uint8List gen2EncodeName(String text, {int len = 11}) {
  final out = Uint8List(len)..fillRange(0, len, kGen2Terminator);
  var i = 0;
  for (; i < text.length && i < len - 1; i++) {
    out[i] = _charToGen2[text[i]] ?? _charToGen2[' ']!;
  }
  out[i] = kGen2Terminator; // ensure a terminator
  return out;
}

/// Gender of an Attack DV for a species [genderRate] (PokeAPI convention:
/// eighths female; -1 = genderless, 0 = male-only, 8 = female-only). Gen 2
/// rule (Bulbapedia): female iff Attack DV <= the species' Attack-DV threshold.
/// Returns 0 = male, 1 = female, 2 = genderless.
int gen2GenderOf(int attackDv, int genderRate) {
  switch (genderRate) {
    case -1:
      return 2; // genderless
    case 0:
      return 0; // male only
    case 8:
      return 1; // female only
  }
  // Female Attack-DV thresholds: 12.5%♀→1, 25%♀→3, 50%♀→7, 75%♀→11.
  final threshold = switch (genderRate) {
    1 => 1, // 12.5% female
    2 => 3, // 25% female
    4 => 7, // 50% female
    6 => 11, // 75% female
    7 => 13, // 87.5% female (not used by real Gen 2 species; extrapolated)
    _ => 7,
  };
  return attackDv <= threshold ? 1 : 0;
}

/// A single Generation II Pokémon in **box form** (32 bytes, 0x00..0x1F). The
/// party form adds 16 trailing bytes (status + computed stats) which the game
/// regenerates when a boxed mon is withdrawn — so injecting into a box needs
/// only these 32 bytes. Nickname / OT-name live OUTSIDE the record (in the box's
/// parallel name arrays); they are carried here as fields for convenience and
/// serialised with [nameBytes] / [otBytes].
///
/// All multi-byte scalar fields in Gen 2 (OT ID, EXP, stat-exp, stats) are
/// **big-endian**. The DV word packs Attack/Defense/Speed/Special as nibbles.
class Pk2 {
  /// The 32-byte box record (0x00..0x1F).
  final Uint8List data;

  /// Stored nickname (decoded); may differ from the species name.
  String nickname;

  /// Stored original-trainer name (decoded).
  String otName;

  Pk2._(this.data, this.nickname, this.otName);

  static const int recordSize = 32; // box form
  static const int partyRecordSize = 48;

  // ---- big-endian primitives -------------------------------------------
  static int _u16be(Uint8List b, int o) => (b[o] << 8) | b[o + 1];
  static void _sU16be(Uint8List b, int o, int v) {
    b[o] = (v >> 8) & 0xFF;
    b[o + 1] = v & 0xFF;
  }

  static int _u24be(Uint8List b, int o) =>
      (b[o] << 16) | (b[o + 1] << 8) | b[o + 2];
  static void _sU24be(Uint8List b, int o, int v) {
    b[o] = (v >> 16) & 0xFF;
    b[o + 1] = (v >> 8) & 0xFF;
    b[o + 2] = v & 0xFF;
  }

  /// Build a fresh, legal box-form Pokémon from scratch (for injection). Base
  /// stats / growth-rate / learnset come from the app; pass the derived [totalExp]
  /// (see [gen2Exp]), [moves], per-move [pp], and the four [dvs] directly.
  ///
  /// [dvs] = [Attack, Defense, Speed, Special] DVs (0..15 each); the HP DV is
  /// derived from their low bits and never stored. [statExp] defaults to 0.
  /// [caughtIsCrystal] controls whether the caught-data byte encodes the Crystal
  /// OT-gender bit; in Gold/Silver the two caught bytes are left zero.
  factory Pk2.create({
    required int species, // National dex # (1..251) — Gen 2 uses it directly
    required int otId, // 16-bit trainer ID
    required int level, // 1..100
    required int totalExp,
    required List<int> moves, // up to 4 move ids
    required List<int> pp, // per-move current PP (PP-Ups = 0)
    required List<int> dvs, // [Atk, Def, Spe, Spc], each 0..15
    String nickname = '',
    String otName = '',
    int heldItem = 0,
    int friendship = 70,
    int pokerus = 0,
    List<int> statExp = const [0, 0, 0, 0, 0], // HP,Atk,Def,Spe,Spc
    bool caughtIsCrystal = false,
    int timeOfDayCaught = 1, // 1=morning, 2=day, 3=night
    int otGender = 0, // 0=male, 1=female (Crystal caught data only)
    int caughtLocation = 0,
    int? levelCaught, // defaults to [level]
  }) {
    final d = Uint8List(recordSize);
    d[0x00] = species & 0xFF;
    d[0x01] = heldItem & 0xFF;
    for (var k = 0; k < 4; k++) {
      d[0x02 + k] = k < moves.length ? (moves[k] & 0xFF) : 0;
    }
    _sU16be(d, 0x06, otId & 0xFFFF);
    _sU24be(d, 0x08, totalExp & 0xFFFFFF);
    // Stat experience (EVs): HP,Atk,Def,Spe,Spc — big-endian words.
    for (var k = 0; k < 5; k++) {
      _sU16be(d, 0x0B + k * 2, k < statExp.length ? statExp[k] & 0xFFFF : 0);
    }
    // DV word: high nibble Atk, then Def, Spe, Spc (0x15 hi, 0x16 lo).
    final atk = dvs[0] & 0xF, def = dvs[1] & 0xF, spe = dvs[2] & 0xF, spc = dvs[3] & 0xF;
    d[0x15] = (atk << 4) | def;
    d[0x16] = (spe << 4) | spc;
    for (var k = 0; k < 4; k++) {
      d[0x17 + k] = k < pp.length ? (pp[k] & 0xFF) : 0;
    }
    d[0x1B] = friendship & 0xFF;
    d[0x1C] = pokerus & 0xFF;
    // Caught data (0x1D..0x1E). Crystal only; G/S leave it zero.
    if (caughtIsCrystal) {
      final lc = (levelCaught ?? level).clamp(0, 63);
      d[0x1D] = ((timeOfDayCaught & 0x3) << 6) | lc;
      d[0x1E] = ((otGender & 1) << 7) | (caughtLocation & 0x7F);
    }
    d[0x1F] = level.clamp(1, 100);
    return Pk2._(d, nickname, otName);
  }

  /// Decode a box-form record. Optionally pass the 11-byte name fields from the
  /// box's OT-name / nickname arrays to recover [otName] / [nickname].
  factory Pk2.decode(Uint8List record, {Uint8List? nameBytes, Uint8List? otBytes}) {
    final d = Uint8List.fromList(record.sublist(0, recordSize));
    final nick = nameBytes == null ? '' : gen2DecodeText(nameBytes, 0, nameBytes.length);
    final ot = otBytes == null ? '' : gen2DecodeText(otBytes, 0, otBytes.length);
    return Pk2._(d, nick, ot);
  }

  // ---- field getters ----------------------------------------------------
  int get species => data[0x00];
  set species(int v) => data[0x00] = v & 0xFF;
  int get heldItem => data[0x01];
  List<int> get moves => [for (var k = 0; k < 4; k++) data[0x02 + k]];
  List<int> get pp => [for (var k = 0; k < 4; k++) data[0x17 + k]];
  int get otId => _u16be(data, 0x06);
  int get exp => _u24be(data, 0x08);
  List<int> get statExp => [for (var k = 0; k < 5; k++) _u16be(data, 0x0B + k * 2)];
  int get friendship => data[0x1B];
  int get pokerus => data[0x1C];
  int get level => data[0x1F];

  /// [Attack, Defense, Speed, Special] DVs (0..15 each).
  List<int> get dvs => [
        (data[0x15] >> 4) & 0xF, // Attack
        data[0x15] & 0xF, // Defense
        (data[0x16] >> 4) & 0xF, // Speed
        data[0x16] & 0xF, // Special
      ];
  int get attackDv => (data[0x15] >> 4) & 0xF;
  int get defenseDv => data[0x15] & 0xF;
  int get speedDv => (data[0x16] >> 4) & 0xF;
  int get specialDv => data[0x16] & 0xF;

  /// HP DV is derived from the low bit of each of the other four DVs.
  int get hpDv =>
      ((attackDv & 1) << 3) | ((defenseDv & 1) << 2) | ((speedDv & 1) << 1) | (specialDv & 1);

  /// Gen 2 shininess (Bulbapedia): Defense, Speed and Special DVs all == 10, and
  /// Attack DV in {2,3,6,7,10,11,14,15} (i.e. Attack DV has bit value 2 set).
  bool get isShiny =>
      defenseDv == 10 &&
      speedDv == 10 &&
      specialDv == 10 &&
      (attackDv & 2) != 0;

  /// Gender for a species [genderRate] (PokeAPI eighths-female; -1 genderless).
  /// 0 = male, 1 = female, 2 = genderless.
  int gender(int genderRate) => gen2GenderOf(attackDv, genderRate);

  /// Caught level (Crystal caught data); 0 in Gold/Silver.
  int get levelCaught => data[0x1D] & 0x3F;
  int get timeOfDayCaught => (data[0x1D] >> 6) & 0x3;
  int get otGenderCaught => (data[0x1E] >> 7) & 1; // Crystal only
  int get caughtLocation => data[0x1E] & 0x7F;

  /// The 32-byte box record.
  Uint8List encode() => Uint8List.fromList(data);

  /// The 11-byte nickname field for the box name array.
  Uint8List nameBytes() => gen2EncodeName(nickname);

  /// The 11-byte OT-name field for the box name array.
  Uint8List otBytes() => gen2EncodeName(otName);
}

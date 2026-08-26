import 'dart:typed_data';

/// Total EXP needed to be at [level] under a species' growth rate. Growth-rate
/// keys are PokeAPI names. Generation I only ever uses four groups (fast,
/// medium-fast, medium-slow, slow) — Erratic/Fluctuating are unused in Gen 1,
/// but the extra cases are kept harmless so callers can share tables with Gen 3.
int gen1Exp(String growthRate, int level) {
  final n = level.clamp(1, 100);
  final n3 = n * n * n;
  switch (growthRate) {
    case 'fast':
      return 4 * n3 ~/ 5;
    case 'slow':
      return 5 * n3 ~/ 4;
    case 'medium-slow':
      return (6 * n3 ~/ 5) - 15 * n * n + 100 * n - 140;
    default: // medium / medium-fast
      return n3;
  }
}

/// The level implied by a total [exp] under [growthRate] — the highest level
/// whose EXP threshold is still <= exp. Gen 1 box mons carry a level byte, but
/// this lets the editor confirm the level<->exp pair is self-consistent (legal).
int gen1LevelFromExp(String growthRate, int exp) {
  var lvl = 1;
  for (var l = 2; l <= 100; l++) {
    if (gen1Exp(growthRate, l) <= exp) {
      lvl = l;
    } else {
      break;
    }
  }
  return lvl;
}

/// Gen 1 type ids (used in the type1/type2 record bytes).
const kGen1Types = {
  'normal': 0x00, 'fighting': 0x01, 'flying': 0x02, 'poison': 0x03,
  'ground': 0x04, 'rock': 0x05, 'bug': 0x07, 'ghost': 0x08,
  'fire': 0x14, 'water': 0x15, 'grass': 0x16, 'electric': 0x17,
  'psychic': 0x18, 'ice': 0x19, 'dragon': 0x1A,
};

// -------------------------------------------------------------------------
// National dex <-> Gen 1 internal ROM index.
//
// Gen 1 stores species by an internal ROM order that does NOT follow the
// National Pokédex (unused slots become MissingNo.). Every read/write of a
// species byte must convert. Table from Bulbapedia "List of Pokémon by index
// number (Generation I)" — verified entries only (e.g. Rhydon = 0x01,
// Bulbasaur = 0x99, Pikachu = 0x54, Mew = 0x15).
// -------------------------------------------------------------------------

/// Internal index for each National dex number, indexed by (national - 1).
const List<int> _internalByNational = [
  0x99, 0x09, 0x9A, 0xB0, 0xB2, 0xB4, 0xB1, 0xB3, 0x1C, 0x7B, // 1-10
  0x7C, 0x7D, 0x70, 0x71, 0x72, 0x24, 0x96, 0x97, 0xA5, 0xA6, // 11-20
  0x05, 0x23, 0x6C, 0x2D, 0x54, 0x55, 0x60, 0x61, 0x0F, 0xA8, // 21-30
  0x10, 0x03, 0xA7, 0x07, 0x04, 0x8E, 0x52, 0x53, 0x64, 0x65, // 31-40
  0x6B, 0x82, 0xB9, 0xBA, 0xBB, 0x6D, 0x2E, 0x41, 0x77, 0x3B, // 41-50
  0x76, 0x4D, 0x90, 0x2F, 0x80, 0x39, 0x75, 0x21, 0x14, 0x47, // 51-60
  0x6E, 0x6F, 0x94, 0x26, 0x95, 0x6A, 0x29, 0x7E, 0xBC, 0xBD, // 61-70
  0xBE, 0x18, 0x9B, 0xA9, 0x27, 0x31, 0xA3, 0xA4, 0x25, 0x08, // 71-80
  0xAD, 0x36, 0x40, 0x46, 0x74, 0x3A, 0x78, 0x0D, 0x88, 0x17, // 81-90
  0x8B, 0x19, 0x93, 0x0E, 0x22, 0x30, 0x81, 0x4E, 0x8A, 0x06, // 91-100
  0x8D, 0x0C, 0x0A, 0x11, 0x91, 0x2B, 0x2C, 0x0B, 0x37, 0x8F, // 101-110
  0x12, 0x01, 0x28, 0x1E, 0x02, 0x5C, 0x5D, 0x9D, 0x9E, 0x1B, // 111-120
  0x98, 0x2A, 0x1A, 0x48, 0x35, 0x33, 0x1D, 0x3C, 0x85, 0x16, // 121-130
  0x13, 0x4C, 0x66, 0x69, 0x68, 0x67, 0xAA, 0x62, 0x63, 0x5A, // 131-140
  0x5B, 0xAB, 0x84, 0x4A, 0x4B, 0x49, 0x58, 0x59, 0x42, 0x83, // 141-150
  0x15, // 151
];

/// National dex (1..151) -> Gen 1 internal index. 0 if out of range.
int gen1NationalToInternal(int national) {
  if (national < 1 || national > _internalByNational.length) return 0;
  return _internalByNational[national - 1];
}

/// Reverse map: Gen 1 internal index -> National dex number. Built once.
final Map<int, int> _nationalByInternal = () {
  final m = <int, int>{};
  for (var i = 0; i < _internalByNational.length; i++) {
    m[_internalByNational[i]] = i + 1;
  }
  return m;
}();

/// Gen 1 internal index -> National dex number. 0 for a MissingNo./glitch slot.
int gen1InternalToNational(int internal) => _nationalByInternal[internal] ?? 0;

// -------------------------------------------------------------------------
// Gen 1 (English) text codec. 0x50 terminates a name; fields are 11 bytes
// (up to 10 printable chars + terminator). Bulbapedia "Character encoding
// (Generation I)".
// -------------------------------------------------------------------------
const int kGen1Terminator = 0x50;

final Map<int, String> _gen1ToChar = () {
  final m = <int, String>{
    0x7F: ' ',
    0x9A: '(', 0x9B: ')', 0x9C: ':', 0x9D: ';', 0x9E: '[', 0x9F: ']',
    0xE0: "'", 0xE3: '-', 0xE6: '?', 0xE7: '!', 0xE8: '.',
    0xEF: '♂', 0xF3: '/', 0xF4: ',', 0xF5: '♀',
  };
  for (var i = 0; i < 26; i++) {
    m[0x80 + i] = String.fromCharCode(65 + i); // A-Z
    m[0xA0 + i] = String.fromCharCode(97 + i); // a-z
  }
  for (var i = 0; i < 10; i++) {
    m[0xF6 + i] = '$i'; // 0-9
  }
  return m;
}();
final Map<String, int> _charToGen1 = {
  for (final e in _gen1ToChar.entries) e.value: e.key
};

/// Decode a Gen 1 string of [len] bytes at [start] (stops at 0x50).
String gen1DecodeText(Uint8List bytes, int start, int len) {
  final sb = StringBuffer();
  for (var i = 0; i < len; i++) {
    final b = bytes[start + i];
    if (b == kGen1Terminator) break;
    sb.write(_gen1ToChar[b] ?? '');
  }
  return sb.toString().trimRight();
}

/// Encode [text] into [len] Gen 1 bytes at [start], 0x50-terminated/padded.
/// Text is capped to [len]-1 chars so a terminator always fits; unmappable
/// characters become spaces.
void gen1EncodeText(Uint8List bytes, int start, int len, String text) {
  final space = _charToGen1[' ']!;
  for (var i = 0; i < len; i++) {
    if (i < text.length && i < len - 1) {
      bytes[start + i] = _charToGen1[text[i]] ?? space;
    } else {
      bytes[start + i] = kGen1Terminator;
    }
  }
}

/// Encode a Gen 1 name into a fresh 11-byte field (helper for the editor).
Uint8List gen1EncodeName(String text) {
  final b = Uint8List(11);
  gen1EncodeText(b, 0, 11, text);
  return b;
}

// -------------------------------------------------------------------------
// Gen 1 stat math (shared with Gen 2). StatExp defaults to 0 for a fresh mon.
// -------------------------------------------------------------------------

/// ceil(sqrt(x)) using integer math (for the stat-experience term).
int _ceilSqrt(int x) {
  if (x <= 0) return 0;
  var r = 0;
  while (r * r < x) {
    r++;
  }
  return r;
}

int _statExpTerm(int statExp) {
  final v = _ceilSqrt(statExp.clamp(0, 65535));
  return (v > 255 ? 255 : v) ~/ 4;
}

/// Gen 1 HP stat: floor(((2*(base+dv)) + statExpTerm) * level / 100) + level + 10.
int gen1HpStat(int base, int hpDv, int statExp, int level) =>
    (2 * (base + hpDv) + _statExpTerm(statExp)) * level ~/ 100 + level + 10;

/// Gen 1 non-HP stat: floor(((2*(base+dv)) + statExpTerm) * level / 100) + 5.
int gen1OtherStat(int base, int dv, int statExp, int level) =>
    (2 * (base + dv) + _statExpTerm(statExp)) * level ~/ 100 + 5;

/// The HP DV derived from the other four DVs (LSBs of Atk/Def/Spe/Spc).
int gen1HpDv(int atk, int def, int spe, int spc) =>
    ((atk & 1) << 3) | ((def & 1) << 2) | ((spe & 1) << 1) | (spc & 1);

/// A single Gen 1 Pokémon (PK1) in its 33-byte "in-box" form.
///
/// Multi-byte numeric fields are BIG-ENDIAN (current HP, OT id, 3-byte EXP,
/// stat-experience words). Species is the Gen 1 INTERNAL index — [nationalDex]
/// converts. The nickname and OT name are NOT part of the 33-byte record (in
/// Gen 1 they live in separate per-box arrays), so they are carried alongside
/// as strings for the editor to place; [encode] emits only the 33 record bytes.
///
/// Field map (offset within the record):
///   0x00 species(internal) | 0x01 curHP(2 BE) | 0x03 level | 0x04 status
///   0x05 type1 | 0x06 type2 | 0x07 catchRate | 0x08-0x0B moves
///   0x0C OT id(2 BE) | 0x0E exp(3 BE) | 0x11-0x1A statexp HP/Atk/Def/Spe/Spc(2 BE ea)
///   0x1B DV word(2) | 0x1D-0x20 move PP
class Pk1 {
  /// 33-byte in-box record.
  final Uint8List raw;

  /// Nickname / OT name (stored outside the record in the box container).
  String nickname;
  String otName;

  Pk1._(this.raw, {this.nickname = '', this.otName = ''});

  static const int recordSize = 33; // 0x21

  static int _beU16(Uint8List b, int o) => (b[o] << 8) | b[o + 1];
  static void _sBeU16(Uint8List b, int o, int v) {
    b[o] = (v >> 8) & 0xFF;
    b[o + 1] = v & 0xFF;
  }

  static int _beU24(Uint8List b, int o) =>
      (b[o] << 16) | (b[o + 1] << 8) | b[o + 2];
  static void _sBeU24(Uint8List b, int o, int v) {
    b[o] = (v >> 16) & 0xFF;
    b[o + 1] = (v >> 8) & 0xFF;
    b[o + 2] = v & 0xFF;
  }

  // ---- field accessors ----
  int get species => raw[0x00]; // internal index
  int get nationalDex => gen1InternalToNational(raw[0x00]);
  int get currentHp => _beU16(raw, 0x01);
  int get level => raw[0x03];
  int get status => raw[0x04];
  int get type1 => raw[0x05];
  int get type2 => raw[0x06];
  int get catchRate => raw[0x07];
  List<int> get moves => [raw[0x08], raw[0x09], raw[0x0A], raw[0x0B]];
  int get otId => _beU16(raw, 0x0C);
  int get exp => _beU24(raw, 0x0E);
  List<int> get statExp =>
      [for (var k = 0; k < 5; k++) _beU16(raw, 0x11 + k * 2)]; // HP,Atk,Def,Spe,Spc
  int get dvWord => _beU16(raw, 0x1B);
  int get attackDv => (raw[0x1B] >> 4) & 0xF;
  int get defenseDv => raw[0x1B] & 0xF;
  int get speedDv => (raw[0x1C] >> 4) & 0xF;
  int get specialDv => raw[0x1C] & 0xF;
  int get hpDv => gen1HpDv(attackDv, defenseDv, speedDv, specialDv);
  List<int> get pp => [raw[0x1D], raw[0x1E], raw[0x1F], raw[0x20]];

  bool get isEmpty => raw[0x00] == 0 || raw[0x00] == 0xFF;

  /// Decode a 33-byte record (extra bytes, e.g. a 44-byte party form, are
  /// tolerated — only the first 33 are the in-box record). Nickname/OT can be
  /// supplied from the box container arrays; otherwise left blank.
  factory Pk1.decode(Uint8List record, {String nickname = '', String otName = ''}) {
    final r = Uint8List(recordSize);
    r.setRange(0, recordSize, record.sublist(0, recordSize));
    return Pk1._(r, nickname: nickname, otName: otName);
  }

  /// Build a legal in-box Gen 1 Pokémon from scratch.
  ///
  /// [nationalSpecies] is a NATIONAL dex number (converted to the internal
  /// index internally). [dvs] is [Atk, Def, Spe, Spc] each 0..15 (HP DV is
  /// derived). Stat-experience defaults to all zero. [totalExp] must match
  /// [level] for the species' growth rate (use [gen1Exp]); the caller supplies
  /// growth/move/type/base data from PokeAPI. [currentHp] is the boxed HP (the
  /// game recomputes stats on withdrawal); pass the computed max HP for a
  /// healthy mon, or leave 0 and let the app fill it.
  factory Pk1.create({
    required int nationalSpecies,
    required int level,
    required int totalExp,
    required List<int> moves,
    required List<int> pp,
    required List<int> dvs, // [atk, def, spe, spc]
    required int otId,
    required int type1,
    required int type2,
    required int catchRate,
    String nickname = '',
    String otName = '',
    int status = 0,
    int currentHp = 0,
    List<int> statExp = const [0, 0, 0, 0, 0],
  }) {
    final r = Uint8List(recordSize);
    r[0x00] = gen1NationalToInternal(nationalSpecies);
    _sBeU16(r, 0x01, currentHp & 0xFFFF);
    r[0x03] = level.clamp(1, 100);
    r[0x04] = status & 0xFF;
    r[0x05] = type1 & 0xFF;
    r[0x06] = type2 & 0xFF;
    r[0x07] = catchRate & 0xFF;
    for (var k = 0; k < 4; k++) {
      r[0x08 + k] = k < moves.length ? moves[k] & 0xFF : 0;
    }
    _sBeU16(r, 0x0C, otId & 0xFFFF);
    _sBeU24(r, 0x0E, totalExp & 0xFFFFFF);
    for (var k = 0; k < 5; k++) {
      _sBeU16(r, 0x11 + k * 2, k < statExp.length ? statExp[k] & 0xFFFF : 0);
    }
    final atk = dvs.isNotEmpty ? dvs[0] & 0xF : 0;
    final def = dvs.length > 1 ? dvs[1] & 0xF : 0;
    final spe = dvs.length > 2 ? dvs[2] & 0xF : 0;
    final spc = dvs.length > 3 ? dvs[3] & 0xF : 0;
    r[0x1B] = (atk << 4) | def;
    r[0x1C] = (spe << 4) | spc;
    for (var k = 0; k < 4; k++) {
      // low 6 bits = current PP, high 2 bits = PP Ups (0 for a fresh mon).
      r[0x1D + k] = (k < pp.length ? pp[k] : 0) & 0x3F;
    }
    return Pk1._(r, nickname: nickname, otName: otName);
  }

  /// The 33-byte in-box record.
  Uint8List encode() => Uint8List.fromList(raw);
}

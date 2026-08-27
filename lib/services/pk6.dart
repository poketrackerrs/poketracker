import 'dart:typed_data';

import 'gen6_text.dart';

/// A single Gen 6 (X/Y, Omega Ruby/Alpha Sapphire) Pokémon — "PK6". Box (stored)
/// form is **232** bytes (0xE8); party form is **260** bytes (0x104).
///
/// The encryption is the SAME family as PK4/PK5 (block shuffle + u16 LCRNG
/// keystream), with three concrete changes you must respect:
///
///  1. **Encryption Constant.** Offset 0x00 is no longer the PID — it is a
///     separate 32-bit "Encryption Constant" (EC). The PID moved to **0x18**.
///     The EC drives BOTH the block-shuffle order AND the crypto keystream.
///  2. **The crypt seed is the EC** (offset 0x00) for the main data region AND
///     the party-stat region. (Gen 4/5 seeded the main region with the
///     *checksum* at 0x06 and the party region with the *PID*. Gen 6 uses the EC
///     for everything.) The 0x06 checksum is now ONLY a validity sum, never a
///     seed.
///  3. **Block geometry.** Four blocks of **0x38 (56)** bytes each span
///     0x08..0xE8; party stats occupy 0xE8..0x104 (unshuffled). Gen 4/5 used
///     0x20-byte blocks.
///
/// Everything else is identical to the PK4/PK5 codec: the 24-permutation block
/// order table indexed by `((seed & 0x3E000) >> 13) % 24`, the LCRNG
/// `s = s*0x41C64E6D + 0x6073`, xor of each little-endian u16 with `s >> 16`, and
/// a checksum = sum of the decrypted u16 words of the shuffled region.
///
/// Offsets verified against PKHeX `PK6.cs` / `PokeCrypto.cs`
/// (SIZE_6STORED = 0xE8, SIZE_6PARTY = 0x104, SIZE_6BLOCK = 56).
class Pk6 {
  /// The decrypted, unshuffled buffer.
  final Uint8List data;

  /// Original block length: 232 (box) or 260 (party). Preserved on encode.
  final int length;

  Pk6._(this.data, this.length);

  static const int sizeStored = 232; // 0xE8
  static const int sizeParty = 260; // 0x104
  static const int blockSize = 56; // 0x38
  static const int _mainStart = 0x08;
  static const int _mainEnd = 0xE8; // sizeStored

  // Canonical block order after unshuffle: block A,B,C,D (positions 0,1,2,3).
  // This is PKHeX's BlockPosition table (first 24 rows); rows 24..31 duplicate
  // rows 0..7, which `% 24` reproduces. Letters A/B/C/D == positions 0/1/2/3.
  static const _orders = [
    'ABCD', 'ABDC', 'ACBD', 'ADBC', 'ACDB', 'ADCB',
    'BACD', 'BADC', 'CABD', 'DABC', 'CADB', 'DACB',
    'BCAD', 'BDAC', 'CBAD', 'DBAC', 'CDAB', 'DCAB',
    'BCDA', 'BDCA', 'CBDA', 'DBCA', 'CDBA', 'DCBA',
  ];
  static const _letterIndex = {'A': 0, 'B': 1, 'C': 2, 'D': 3};

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

  static int _lcrng(int state) => (state * 0x41C64E6D + 0x6073) & 0xFFFFFFFF;

  /// XOR each little-endian u16 of [buf]`[start, start+len)` with the keystream
  /// from an LCRNG seeded by [seed]. Self-inverse (encrypt == decrypt).
  static void _crypt(Uint8List buf, int start, int len, int seed) {
    var state = seed & 0xFFFFFFFF;
    for (var i = 0; i < len; i += 2) {
      state = _lcrng(state);
      final k = (state >> 16) & 0xFFFF;
      final w = (buf[start + i] | (buf[start + i + 1] << 8)) ^ k;
      buf[start + i] = w & 0xFF;
      buf[start + i + 1] = (w >> 8) & 0xFF;
    }
  }

  /// Shuffle index from the Encryption Constant (Gen 6 seeds shuffle by the EC).
  static int _shuffleIndex(int ec) => ((ec & 0x3E000) >> 13) % 24;

  /// Decode a PK6 from its (encrypted, shuffled) block. Accepts a 232- or
  /// 260-byte block; anything >= 260 is treated as a party block.
  factory Pk6.decode(Uint8List block) {
    final length = block.length >= sizeParty ? sizeParty : sizeStored;
    final out = Uint8List.fromList(block.sublist(0, length));
    final ec = _u32(out, 0x00);

    // Decrypt: main region (0x08..0xE8) then party stats (0xE8..), BOTH seeded
    // by the EC. Each CryptArray call reseeds with the EC (separate streams).
    _crypt(out, _mainStart, _mainEnd - _mainStart, ec);
    if (length == sizeParty) _crypt(out, _mainEnd, length - _mainEnd, ec);

    // Unshuffle the four 56-byte blocks into canonical A,B,C,D order.
    final order = _orders[_shuffleIndex(ec)];
    final shuffled = out.sublist(_mainStart, _mainEnd);
    for (var i = 0; i < 4; i++) {
      final dst = _letterIndex[order[i]]! * blockSize;
      out.setRange(_mainStart + dst, _mainStart + dst + blockSize,
          shuffled, i * blockSize);
    }
    return Pk6._(out, length);
  }

  /// Build a legal PK6 from scratch (canonical decrypted form). Base-stat /
  /// growth-rate / move tables are supplied by the caller; this only lays out
  /// bytes. [encode] then shuffles + encrypts + writes the sanity checksum.
  ///
  /// [encryptionConstant] drives shuffle + crypto; if null it defaults to the
  /// PID (a legal choice for most origins). [gender] 0 male / 1 female /
  /// 2 genderless. [nature] is stored (0..24). Dates are stored as year-2000.
  factory Pk6.create({
    required int species,
    required int pid,
    required int tid,
    required int sid,
    required int exp,
    required List<int> moves,
    required List<int> pp,
    required List<int> ivs,
    required int ability, // ability id
    required int abilityNumber, // 1/2/4 (slot 0/1/hidden bitflag)
    required int nature, // stored 0..24
    required String nickname,
    required String otName,
    int? encryptionConstant,
    int heldItem = 0,
    List<int> ppUps = const [0, 0, 0, 0],
    List<int> relearnMoves = const [0, 0, 0, 0],
    List<int> evs = const [0, 0, 0, 0, 0, 0],
    int ball = 4, // Poké Ball
    int metLocation = 0,
    int metLevel = 1,
    int eggLocation = 0,
    int otGender = 0,
    int gender = 0,
    int form = 0,
    int language = 2, // English
    int friendship = 70,
    int originGame = 24, // X=24, Y=25, OR=26, AS=27
    int country = 0,
    int region = 0,
    int consoleRegion = 0,
    int metYear = 16, // 2016
    int metMonth = 1,
    int metDay = 1,
    bool fateful = false,
    bool nicknamed = false,
    bool isEgg = false,
    bool party = false,
  }) {
    final len = party ? sizeParty : sizeStored;
    final d = Uint8List(len);
    final ec = encryptionConstant ?? pid;
    _sU32(d, 0x00, ec & 0xFFFFFFFF); // Encryption Constant
    _sU16(d, 0x08, species & 0xFFFF); // Species
    _sU16(d, 0x0A, heldItem & 0xFFFF); // Held item
    _sU16(d, 0x0C, tid & 0xFFFF); // TID
    _sU16(d, 0x0E, sid & 0xFFFF); // SID
    _sU32(d, 0x10, exp & 0xFFFFFFFF); // EXP
    d[0x14] = ability & 0xFF; // Ability id
    d[0x15] = abilityNumber & 0xFF; // Ability number (1/2/4)
    _sU32(d, 0x18, pid & 0xFFFFFFFF); // PID (moved here in Gen 6)
    d[0x1C] = nature & 0xFF; // Nature (stored)
    // 0x1D: fateful (bit0), gender (bits1-2), alt-form (bits3-7).
    d[0x1D] = (fateful ? 1 : 0) | ((gender & 3) << 1) | ((form & 0x1F) << 3);
    for (var k = 0; k < 6; k++) {
      d[0x1E + k] = (k < evs.length ? evs[k] : 0).clamp(0, 255);
    }
    gen6EncodeText(d, 0x40, 13, nickname); // 26-byte nickname (12 + term)
    for (var k = 0; k < 4; k++) {
      _sU16(d, 0x5A + k * 2, k < moves.length ? moves[k] : 0);
    }
    for (var k = 0; k < 4; k++) {
      d[0x62 + k] = k < pp.length ? pp[k] & 0xFF : 0;
    }
    for (var k = 0; k < 4; k++) {
      d[0x66 + k] = k < ppUps.length ? ppUps[k] & 0xFF : 0;
    }
    for (var k = 0; k < 4; k++) {
      _sU16(d, 0x6A + k * 2, k < relearnMoves.length ? relearnMoves[k] : 0);
    }
    // 0x74 IV32: 6×5-bit IVs, bit30 isEgg, bit31 isNicknamed.
    var iv = 0;
    for (var k = 0; k < 6; k++) {
      iv |= ((k < ivs.length ? ivs[k] : 0).clamp(0, 31)) << (5 * k);
    }
    if (isEgg) iv |= (1 << 30);
    if (nicknamed) iv |= (1 << 31);
    _sU32(d, 0x74, iv & 0xFFFFFFFF);
    d[0x93] = 0; // CurrentHandler = OT
    gen6EncodeText(d, 0xB0, 13, otName); // 26-byte OT name
    d[0xCA] = friendship.clamp(0, 255); // OT friendship
    d[0xD1] = 0; // egg date (non-egg)
    d[0xD2] = 0;
    d[0xD3] = 0;
    d[0xD4] = metYear & 0xFF; // met date (year - 2000)
    d[0xD5] = metMonth & 0xFF;
    d[0xD6] = metDay & 0xFF;
    _sU16(d, 0xD8, eggLocation & 0xFFFF);
    _sU16(d, 0xDA, metLocation & 0xFFFF);
    d[0xDC] = ball & 0xFF;
    d[0xDD] = (metLevel.clamp(0, 100) & 0x7F) | ((otGender & 1) << 7);
    d[0xDF] = originGame & 0xFF; // game of origin
    d[0xE0] = country & 0xFF;
    d[0xE1] = region & 0xFF;
    d[0xE2] = consoleRegion & 0xFF;
    d[0xE3] = language & 0xFF;
    final m = Pk6._(d, len);
    if (party) m.data[0xEC] = _levelFromExpGuess(exp).clamp(1, 100);
    return m;
  }

  bool get isParty => length == sizeParty;

  // ------------------------------------------------------------- header
  int get encryptionConstant => _u32(data, 0x00);
  int get sanity => _u16(data, 0x04);
  int get storedChecksum => _u16(data, 0x06);
  bool get isEmpty => species == 0;

  // ----------------------------------------------------- Block A (0x08)
  int get species => _u16(data, 0x08);
  int get heldItem => _u16(data, 0x0A);
  int get tid => _u16(data, 0x0C);
  int get sid => _u16(data, 0x0E);
  int get exp => _u32(data, 0x10);
  int get ability => data[0x14];
  int get abilityNumber => data[0x15];
  int get pid => _u32(data, 0x18); // NOTE: PID is at 0x18 in Gen 6
  int get nature => data[0x1C];
  set nature(int v) => data[0x1C] = v & 0xFF;
  bool get fateful => (data[0x1D] & 1) == 1;
  int get gender => (data[0x1D] >> 1) & 3;
  int get form => (data[0x1D] >> 3) & 0x1F;
  List<int> get evs => [for (var k = 0; k < 6; k++) data[0x1E + k]];

  // ----------------------------------------------------- Block B (0x40)
  String get nickname => gen6DecodeText(data, 0x40, 13);
  List<int> get moves => [for (var k = 0; k < 4; k++) _u16(data, 0x5A + k * 2)];
  List<int> get pp => [for (var k = 0; k < 4; k++) data[0x62 + k]];
  List<int> get ppUps => [for (var k = 0; k < 4; k++) data[0x66 + k]];
  List<int> get relearnMoves =>
      [for (var k = 0; k < 4; k++) _u16(data, 0x6A + k * 2)];
  int get _ivWord => _u32(data, 0x74);
  List<int> get ivs => [for (var k = 0; k < 6; k++) (_ivWord >> (5 * k)) & 31];
  bool get isEgg => (_ivWord >> 30) & 1 == 1;
  bool get isNicknamed => (_ivWord >> 31) & 1 == 1;

  // ----------------------------------------------------- Block C/D
  int get currentHandler => data[0x93];
  String get otName => gen6DecodeText(data, 0xB0, 13);
  int get otFriendship => data[0xCA];
  int get metLocation => _u16(data, 0xDA);
  int get eggLocation => _u16(data, 0xD8);
  int get ballId => data[0xDC];
  int get metLevel => data[0xDD] & 0x7F;
  int get otGender => (data[0xDD] >> 7) & 1;
  int get originGame => data[0xDF];
  int get language => data[0xE3];

  // ------------------------------------------------ Party stat block
  /// Party level, read straight from the (unshuffled, plaintext) stat block at
  /// 0xEC. Only meaningful on a 260-byte party block; box mons derive level
  /// from EXP via the caller's growth-rate table.
  int get partyLevel => length == sizeParty ? data[0xEC] : 0;
  int get statHpCurrent => length == sizeParty ? _u16(data, 0xF0) : 0;
  int get statHpMax => length == sizeParty ? _u16(data, 0xF2) : 0;

  /// Gen 6 shininess: `(TID ^ SID ^ PIDhi ^ PIDlo) < 16` (threshold widened
  /// from 8 in Gen 3–5).
  bool isShiny(int trainerTid, int trainerSid) =>
      (trainerTid ^ trainerSid ^ (pid >> 16) ^ (pid & 0xFFFF)) < 16;

  /// Given the caller's growth-rate EXP table (`expForLevel[level]` = minimum
  /// EXP to BE that level, indices 1..100), return this mon's level from its
  /// stored EXP. Use for box mons (no stored level byte).
  int levelFromExp(List<int> expForLevel) {
    final e = exp;
    var lvl = 1;
    for (var l = 1; l < expForLevel.length; l++) {
      if (e >= expForLevel[l]) {
        lvl = l;
      } else {
        break;
      }
    }
    return lvl.clamp(1, 100);
  }

  // Rough fallback used only to seed a party level when create(party:true) is
  // called without a real growth table (medium-fast ~ n^3). Real callers should
  // set the level via recomputeStats with their own table.
  static int _levelFromExpGuess(int exp) {
    var l = 1;
    while (l < 100 && (l + 1) * (l + 1) * (l + 1) <= exp) {
      l++;
    }
    return l;
  }

  // ----------------------------------------------------------- setters
  void setSpecies(int v) => _sU16(data, 0x08, v);
  void setNickname(String s) => gen6EncodeText(data, 0x40, 13, s);
  void setMoves(List<int> mv) {
    for (var k = 0; k < 4; k++) {
      _sU16(data, 0x5A + k * 2, k < mv.length ? mv[k] : 0);
    }
  }

  void setIVs(List<int> v) {
    var w = _ivWord & (0x3 << 30); // preserve egg + nicknamed
    for (var k = 0; k < 6; k++) {
      w |= (v[k].clamp(0, 31)) << (5 * k);
    }
    _sU32(data, 0x74, w & 0xFFFFFFFF);
  }

  /// Recompute party battle stats (HP,Atk,Def,Spe,SpA,SpD) from IVs/EVs/nature/
  /// base stats and heal to full. [baseStats] in Gen order. No-op on box blocks.
  void recomputeStats(int level, List<int> baseStats) {
    if (length < sizeParty) return;
    data[0xEC] = level.clamp(1, 100);
    final iv = ivs, ev = evs;
    final up = nature ~/ 5, down = nature % 5; // 0=Atk,1=Def,2=Spe,3=SpA,4=SpD
    final hp =
        (2 * baseStats[0] + iv[0] + ev[0] ~/ 4) * level ~/ 100 + level + 10;
    final out = <int>[hp];
    for (var s = 0; s < 5; s++) {
      var v =
          (2 * baseStats[s + 1] + iv[s + 1] + ev[s + 1] ~/ 4) * level ~/ 100 + 5;
      if (up != down) {
        if (up == s) v = v * 110 ~/ 100;
        if (down == s) v = v * 90 ~/ 100;
      }
      out.add(v);
    }
    _sU32(data, 0xE8, 0); // clear status condition
    _sU16(data, 0xF0, out[0]); // current HP
    _sU16(data, 0xF2, out[0]); // max HP
    _sU16(data, 0xF4, out[1]); // Atk
    _sU16(data, 0xF6, out[2]); // Def
    _sU16(data, 0xF8, out[3]); // Spe
    _sU16(data, 0xFA, out[4]); // SpA
    _sU16(data, 0xFC, out[5]); // SpD
  }

  /// Sanity checksum: sum of the u16 words of the shuffled region 0x08..0xE8.
  /// Order-independent (a sum), so we compute it over the canonical buffer.
  int computeChecksum() {
    var s = 0;
    for (var i = _mainStart; i < _mainEnd; i += 2) {
      s = (s + _u16(data, i)) & 0xFFFF;
    }
    return s;
  }

  /// Re-shuffle, re-encrypt, and write a fresh checksum. Returns a new block of
  /// the original length; `decode → encode` is byte-exact.
  Uint8List encode() {
    final out = Uint8List.fromList(data);
    _sU16(out, 0x06, computeChecksum());

    final ec = _u32(out, 0x00);
    // Re-shuffle canonical A,B,C,D back into the EC's block order.
    final order = _orders[_shuffleIndex(ec)];
    final canon = out.sublist(_mainStart, _mainEnd);
    for (var i = 0; i < 4; i++) {
      final src = _letterIndex[order[i]]! * blockSize;
      out.setRange(
          _mainStart + i * blockSize, _mainStart + i * blockSize + blockSize,
          canon, src);
    }
    // Re-encrypt with the EC-seeded streams.
    _crypt(out, _mainStart, _mainEnd - _mainStart, ec);
    if (length == sizeParty) _crypt(out, _mainEnd, length - _mainEnd, ec);
    return out;
  }
}

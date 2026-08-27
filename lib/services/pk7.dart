import 'dart:typed_data';

import 'gen7_text.dart';

/// A single Gen 7 (Sun/Moon, Ultra Sun/Ultra Moon) Pokémon — "PK7". Box (stored)
/// form is **232** bytes (0xE8); party form is **260** bytes (0x104). Same sizes
/// as PK6.
///
/// The encryption is the SAME FAMILY as PK4/PK5/PK6 (shuffle four data blocks,
/// XOR a keystream from an LCRNG using the constants 0x41C64E6D / 0x6073, then a
/// u16-sum sanity checksum) — BUT with three crypto changes that MUST be honored
/// versus the Gen 4/5 (`Pk5`) reader:
///
///   1. SEED = the **Encryption Constant** (u32 @ 0x00), NOT the checksum.
///      In Gen 4/5 the main-data keystream was seeded by the checksum @ 0x06 and
///      the party stats by the PID. In Gen 6/7 BOTH regions are seeded by the EC.
///   2. SHUFFLE ORDER index = `((EC >> 13) & 31) % 24`, computed from the EC,
///      NOT the PID.  (Gen 4/5 used the PID.)
///   3. The party-stats region restarts the LCRNG from the EC (a fresh call),
///      exactly like the main region — see `_crypt` calls in [decode]/[encode].
///
/// Block layout (0x38 = 56 bytes per block, four blocks 0x08..0xE8):
///   0x00 u32 Encryption Constant   (plaintext — drives shuffle + crypt)
///   0x06 u16 Checksum (sum of u16 over 0x08..0xE8)  (plaintext)
///   0x08 u16 Species
///   0x0A u16 Held item
///   0x0C u16 TID16      0x0E u16 SID16
///   0x10 u32 EXP
///   0x14 u8  Ability    0x15 u8 AbilityNumber(&7) / hidden-ability bit
///   0x18 u32 PID
///   0x1C u8  Nature (stored 0..24, decoupled from PID)
///   0x1D u8  bit0 fateful · bits1-2 gender · bits3-7 alt-form
///   0x1E..0x23 EVs (HP,Atk,Def,Spe,SpA,SpD)   0x24..0x29 contest
///   0x40 Nickname (UTF-16, 12 chars, 0x1A bytes)
///   0x5A..0x60 Moves 1-4 (u16)   0x62..0x65 PP   0x66..0x69 PP-Ups
///   0x6A..0x71 Relearn moves     0x74 u32 IV32 (6×5 bits + egg30 + nick31)
///   0x78 HT (handling trainer) name    0x93 CurrentHandler
///   0xB0 OT name (0x1A bytes)   0xCA OT friendship
///   0xD8 u16 EggLocation  0xDA u16 MetLocation  0xDC Ball
///   0xDD MetLevel(&0x7F)+OTgender(bit7)  0xDE HyperTrainFlags  0xDF Version
///   0xE3 Language
///   0xEC (party only) Stat_Level    0xF0.. party battle stats
class Pk7 {
  /// The decrypted, unshuffled buffer.
  final Uint8List data;

  /// Original block length: 232 (box) or 260 (party). Preserved on encode.
  final int length;

  Pk7._(this.data, this.length);

  static const int sizeStored = 232; // 0xE8
  static const int sizeParty = 260; // 0x104
  static const int blockSize = 56; // 0x38, four of them span 0x08..0xE8
  static const int dataStart = 0x08;
  static const int dataEnd = 0xE8; // checksum + main-crypt region end

  // Same 24 block permutations used by every Gen 3-7 entity. Feed the EC (Gen
  // 6/7), not the PID.
  static const _orders = [
    'GAEM', 'GAME', 'GEAM', 'GEMA', 'GMAE', 'GMEA',
    'AGEM', 'AGME', 'AEGM', 'AEMG', 'AMGE', 'AMEG',
    'EGAM', 'EGMA', 'EAGM', 'EAMG', 'EMGA', 'EMAG',
    'MGAE', 'MGEA', 'MAGE', 'MAEG', 'MEGA', 'MEAG',
  ];
  static const _letterIndex = {'G': 0, 'A': 1, 'E': 2, 'M': 3};

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

  /// Gen 6/7 shuffle selector — driven by the ENCRYPTION CONSTANT, not the PID.
  static int _shuffleIndex(int ec) => ((ec & 0x3E000) >> 13) % 24;

  /// Decode a PK7 from its (encrypted, shuffled) block. Accepts a 232- or
  /// 260-byte block; anything >= 260 is treated as a party block.
  factory Pk7.decode(Uint8List block) {
    final length = block.length >= sizeParty ? sizeParty : sizeStored;
    final out = Uint8List.fromList(block.sublist(0, length));
    final ec = _u32(out, 0x00);

    // Decrypt the 224-byte main region (0x08..0xE8) with the EC-seeded stream.
    _crypt(out, dataStart, dataEnd - dataStart, ec);

    // Unshuffle the four 56-byte blocks into canonical G,A,E,M order.
    final order = _orders[_shuffleIndex(ec)];
    final shuffled = out.sublist(dataStart, dataEnd);
    for (var i = 0; i < 4; i++) {
      final dst = _letterIndex[order[i]]! * blockSize;
      out.setRange(dataStart + dst, dataStart + dst + blockSize, shuffled,
          i * blockSize);
    }

    // Party battle stats (0xE8..0x104) — FRESH LCRNG re-seeded by the EC.
    if (length == sizeParty) {
      _crypt(out, dataEnd, sizeParty - dataEnd, ec);
    }
    return Pk7._(out, length);
  }

  /// Build a minimal-legal PK7 from scratch (canonical decrypted form). The
  /// caller supplies all game tables (species, moves, ability, nature, etc.).
  /// [encode] then checksums, shuffles, and encrypts.
  ///
  /// [encryptionConstant] drives both the shuffle and the keystream; if omitted
  /// it defaults to [pid] (legal for many encounters). [gender] 0=M 1=F 2=N.
  /// [originGame] is the Version byte (Sun 30, Moon 31, Ultra Sun 32,
  /// Ultra Moon 33).
  factory Pk7.create({
    required int species,
    required int pid,
    required int tid,
    required int sid,
    required int exp,
    required List<int> moves,
    required List<int> pp,
    required List<int> ivs,
    required int ability,
    required int nature,
    required String nickname,
    required String otName,
    int? encryptionConstant,
    int abilityNumber = 1, // 1/2/4 = slot 1/2/hidden
    int heldItem = 0,
    int ball = 4,
    int metLocation = 0,
    int metLevel = 0,
    int otGender = 0,
    int gender = 0,
    int language = 2, // English
    int friendship = 70,
    int originGame = 30, // Sun
    int form = 0,
    bool fateful = false,
    bool nicknamed = false,
    List<int>? relearnMoves,
    List<int>? evs,
    bool party = false,
  }) {
    final len = party ? sizeParty : sizeStored;
    final d = Uint8List(len);
    final m = Pk7._(d, len);
    _sU32(d, 0x00, (encryptionConstant ?? pid) & 0xFFFFFFFF);
    m.setSpecies(species);
    m.setHeldItem(heldItem);
    _sU16(d, 0x0C, tid & 0xFFFF);
    _sU16(d, 0x0E, sid & 0xFFFF);
    m.setExp(exp);
    d[0x14] = ability & 0xFF;
    d[0x15] = abilityNumber & 7;
    m.setPid(pid);
    d[0x1C] = nature & 0xFF;
    // 0x1D: fateful (bit0), gender (bits1-2), alt-form (bits3-7).
    d[0x1D] = (fateful ? 1 : 0) | ((gender & 3) << 1) | ((form & 0x1F) << 3);
    if (evs != null) m.setEVs(evs);
    gen7EncodeText(d, 0x40, 12, nickname);
    m.setMoves(moves);
    for (var i = 0; i < 4 && i < pp.length; i++) {
      m.setPP(i, pp[i]);
    }
    if (relearnMoves != null) {
      for (var i = 0; i < 4 && i < relearnMoves.length; i++) {
        _sU16(d, 0x6A + i * 2, relearnMoves[i]);
      }
    }
    m.setIVs(ivs);
    m.setNicknamed(nicknamed);
    gen7EncodeText(d, 0xB0, 12, otName);
    d[0xCA] = friendship.clamp(0, 255);
    m.setMetLocation(metLocation);
    m.setBall(ball);
    m.setMetLevel(metLevel);
    m.setOtGender(otGender);
    d[0xDF] = originGame & 0xFF;
    d[0xE3] = language & 0xFF;
    return m;
  }

  bool get isParty => length == sizeParty;

  // ------------------------------------------------------------- header
  int get encryptionConstant => _u32(data, 0x00);
  int get storedChecksum => _u16(data, 0x06);
  bool get isEmpty => species == 0;

  // -------------------------------------------------- block A (0x08)
  int get species => _u16(data, 0x08);
  int get heldItem => _u16(data, 0x0A);
  int get tid => _u16(data, 0x0C);
  int get sid => _u16(data, 0x0E);
  int get exp => _u32(data, 0x10);
  int get ability => data[0x14];
  int get abilityNumber => data[0x15] & 7;
  int get pid => _u32(data, 0x18);

  /// Gen 6/7 STORED nature (byte 0x1C).
  int get nature => data[0x1C];
  set nature(int v) => data[0x1C] = v & 0xFF;

  bool get fateful => (data[0x1D] & 1) == 1;
  int get gender => (data[0x1D] >> 1) & 3;
  int get form => (data[0x1D] >> 3) & 0x1F;

  /// EVs in the order HP, Atk, Def, Spe, SpA, SpD.
  List<int> get evs => [for (var k = 0; k < 6; k++) data[0x1E + k]];

  // -------------------------------------------------- block B (0x40)
  String get nickname => gen7DecodeText(data, 0x40, 12);
  List<int> get moves => [for (var k = 0; k < 4; k++) _u16(data, 0x5A + k * 2)];
  List<int> get pp => [for (var k = 0; k < 4; k++) data[0x62 + k]];
  List<int> get ppUps => [for (var k = 0; k < 4; k++) data[0x66 + k]];
  List<int> get relearnMoves =>
      [for (var k = 0; k < 4; k++) _u16(data, 0x6A + k * 2)];

  int get _ivWord => _u32(data, 0x74);

  /// IVs in the order HP, Atk, Def, Spe, SpA, SpD.
  List<int> get ivs => [for (var k = 0; k < 6; k++) (_ivWord >> (5 * k)) & 31];
  bool get isEgg => (_ivWord >> 30) & 1 == 1;
  bool get isNicknamed => (_ivWord >> 31) & 1 == 1;

  // -------------------------------------------------- block C / D
  String get otName => gen7DecodeText(data, 0xB0, 12);
  int get otFriendship => data[0xCA];
  int get eggLocation => _u16(data, 0xD8);
  int get metLocation => _u16(data, 0xDA);
  int get ballId => data[0xDC];
  int get metLevel => data[0xDD] & 0x7F;
  int get otGender => (data[0xDD] >> 7) & 1;
  int get hyperTrainFlags => data[0xDE];
  int get originGame => data[0xDF];
  int get language => data[0xE3];

  /// Gen 6+ shiny: `(TID ^ SID ^ (PID>>16) ^ (PID & 0xFFFF)) < 16`.
  /// (Threshold is 16, NOT the Gen 1-5 value of 8.)
  bool isShiny(int trainerTid, int trainerSid) =>
      (trainerTid ^ trainerSid ^ (pid >> 16) ^ (pid & 0xFFFF)) < 16;

  /// Stored party level byte (0xEC); box mons don't have it (derive from EXP).
  int get partyLevel => length == sizeParty ? data[0xEC] : 0;

  // -------------------------------------------------------------- setters
  void setSpecies(int v) => _sU16(data, 0x08, v);
  void setHeldItem(int v) => _sU16(data, 0x0A, v);
  void setExp(int v) => _sU32(data, 0x10, v & 0xFFFFFFFF);
  void setPid(int v) => _sU32(data, 0x18, v & 0xFFFFFFFF);
  void setBall(int v) => data[0xDC] = v & 0xFF;
  void setMetLocation(int v) => _sU16(data, 0xDA, v & 0xFFFF);
  void setMetLevel(int v) =>
      data[0xDD] = (data[0xDD] & 0x80) | (v.clamp(0, 100) & 0x7F);
  void setOtGender(int g) => data[0xDD] = (data[0xDD] & 0x7F) | ((g & 1) << 7);

  void setEVs(List<int> v) {
    for (var k = 0; k < 6; k++) {
      data[0x1E + k] = v[k].clamp(0, 255);
    }
  }

  void setMoves(List<int> mv) {
    for (var k = 0; k < 4; k++) {
      _sU16(data, 0x5A + k * 2, k < mv.length ? mv[k] : 0);
    }
  }

  void setPP(int index, int value) => data[0x62 + index] = value.clamp(0, 255);

  void setIVs(List<int> v) {
    var w = _ivWord & (0x3 << 30); // preserve egg + nicknamed flags
    for (var k = 0; k < 6; k++) {
      w |= (v[k].clamp(0, 31)) << (5 * k);
    }
    _sU32(data, 0x74, w & 0xFFFFFFFF);
  }

  void setNicknamed(bool v) {
    var w = _ivWord;
    w = v ? (w | (1 << 31)) : (w & ~(1 << 31));
    _sU32(data, 0x74, w & 0xFFFFFFFF);
  }

  /// Recompute party battle stats from IVs/EVs/STORED-nature/base stats and set
  /// the stored level byte (0xEC). [baseStats] in Gen order (HP,Atk,Def,Spe,
  /// SpA,SpD). Only meaningful on a 260-byte party block. Heals to full.
  void recomputeStats(int level, List<int> baseStats) {
    if (length < sizeParty) return;
    data[0xEC] = level.clamp(1, 100);
    final iv = ivs, ev = evs;
    final up = nature ~/ 5, down = nature % 5;
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
    _sU16(data, 0xF0, out[0]); // current HP
    _sU16(data, 0xF2, out[0]); // max HP
    _sU16(data, 0xF4, out[1]); // Atk
    _sU16(data, 0xF6, out[2]); // Def
    _sU16(data, 0xF8, out[3]); // Spe
    _sU16(data, 0xFA, out[4]); // SpA
    _sU16(data, 0xFC, out[5]); // SpD
  }

  /// Also allow setting party level directly (for tests / EXP-derived level).
  void setPartyLevel(int level) {
    if (length >= sizeParty) data[0xEC] = level.clamp(1, 100);
  }

  /// Sanity checksum: sum of the u16 words over the main data region 0x08..0xE8.
  int computeChecksum() {
    var s = 0;
    for (var i = dataStart; i < dataEnd; i += 2) {
      s = (s + _u16(data, i)) & 0xFFFF;
    }
    return s;
  }

  /// Re-checksum, re-shuffle (EC-driven), re-encrypt (EC-seeded). Returns a new
  /// block of the original length; decode → encode is byte-exact.
  Uint8List encode() {
    final out = Uint8List.fromList(data);
    final ec = _u32(out, 0x00);
    _sU16(out, 0x06, computeChecksum());

    // Re-shuffle canonical G,A,E,M back into the EC's block order.
    final order = _orders[_shuffleIndex(ec)];
    final canon = out.sublist(dataStart, dataEnd);
    for (var i = 0; i < 4; i++) {
      final src = _letterIndex[order[i]]! * blockSize;
      out.setRange(dataStart + i * blockSize, dataStart + i * blockSize + blockSize,
          canon, src);
    }

    // Re-encrypt with the same EC-seeded streams used to decrypt.
    _crypt(out, dataStart, dataEnd - dataStart, ec);
    if (length == sizeParty) {
      _crypt(out, dataEnd, sizeParty - dataEnd, ec);
    }
    return out;
  }
}

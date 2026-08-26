import 'dart:typed_data';

import 'gen5_text.dart';

/// A single Gen 5 (Black/White, Black 2/White 2) Pokémon — "PK5". Box form is
/// 136 bytes; party form is **220** bytes (Gen 4's party form was 236 — the
/// Gen 5 battle-stat block is shorter).
///
/// The wire format and encryption are byte-for-byte IDENTICAL to Gen 4 (PKHeX
/// uses the same `Decrypt45`/`Encrypt45` for both):
///   0x00 u32 PID
///   0x04 u16 sanity flags
///   0x06 u16 checksum (sum of the 64 decrypted data words) — the crypt seed
///   0x08..0x88 four 32-byte substructures (Growth/Attacks/EVs/Misc) SHUFFLED
///                by `((PID & 0x3E000) >> 13) % 24` and ENCRYPTED with a u16
///                keystream from an LCRNG seeded by the checksum.
///   0x88..0xDC (party only) battle stats, encrypted by an LCRNG seeded by PID.
///
/// The ONLY layout changes from PK4 are in the Misc block (0x40..):
///   0x40 : fateful(bit0) / gender(bits1-2) / form(bits3-7)   — same as PK4
///   0x41 : NATURE (0..24) — NEW. In Gen 4 nature was derived from `PID % 25`;
///          Gen 5 STORES it here, fully decoupled from the PID.
///   0x42 : bit0 = Hidden Ability, bit1 = N's Pokémon ("N sparkle") — NEW.
/// Ability stays at 0x15. Everything else keeps the PK4 absolute offsets.
class Pk5 {
  /// The decrypted, unshuffled buffer.
  final Uint8List data;

  /// Original block length: 136 (box) or 220 (party). Preserved on encode.
  final int length;

  Pk5._(this.data, this.length);

  static const int sizeStored = 136; // 0x88
  static const int sizeParty = 220; // 0xDC (Gen 4 was 236)

  // Canonical block order after unshuffle: Growth, Attacks, EVs, Misc.
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

  static int _shuffleIndex(int pid) => ((pid & 0x3E000) >> 13) % 24;

  /// Decode a PK5 from its (encrypted, shuffled) block. Accepts a 136- or
  /// 220-byte block; anything >= 220 is treated as a party block.
  factory Pk5.decode(Uint8List block) {
    final length = block.length >= sizeParty ? sizeParty : sizeStored;
    final out = Uint8List.fromList(block.sublist(0, length));
    final pid = _u32(out, 0x00);
    final checksum = _u16(out, 0x06);

    // Decrypt the 128 data bytes with the checksum-seeded stream.
    _crypt(out, 0x08, 128, checksum);

    // Unshuffle the four 32-byte blocks into canonical G,A,E,M order.
    final order = _orders[_shuffleIndex(pid)];
    final shuffled = out.sublist(0x08, 0x88);
    for (var i = 0; i < 4; i++) {
      final dst = _letterIndex[order[i]]! * 32;
      out.setRange(0x08 + dst, 0x08 + dst + 32, shuffled, i * 32);
    }

    // Party battle stats use a PID-seeded stream.
    if (length == sizeParty) _crypt(out, 0x88, sizeParty - 0x88, pid);

    return Pk5._(out, length);
  }

  /// Build a legal PK5 from scratch (canonical decrypted form). Mirrors
  /// `Pkx.create`, PLUS a stored [nature] (byte 0x41) and [hiddenAbility]
  /// (0x42 bit0). Gen 5 stores nature independently, so pass any 0..24 nature
  /// regardless of the PID. [encode] then shuffles + encrypts + checksums.
  ///
  /// [gender] is 0 male / 1 female / 2 genderless; [originGame] is the Gen 5
  /// game-of-origin value (Black 20, White 21, Black 2 22, White 2 23).
  factory Pk5.create({
    required int species,
    required int pid,
    required int tid,
    required int sid,
    required int exp,
    required List<int> moves,
    required List<int> pp,
    required List<int> ivs,
    required int ability,
    required int nature, // NEW: stored 0..24 (decoupled from pid % 25)
    required String nickname,
    required String otName,
    int heldItem = 0,
    int ball = 4,
    int metLocation = 0,
    int metLevel = 0,
    int otGender = 0,
    int gender = 0,
    int language = 2, // English
    int friendship = 70,
    int originGame = 20, // Black
    int form = 0,
    bool fateful = false,
    bool nicknamed = false,
    bool hiddenAbility = false, // NEW: 0x42 bit0
    bool nsPokemon = false, // NEW: 0x42 bit1
    int metYear = 10, // 2010 (BW launch era)
    int metMonth = 1,
    int metDay = 1,
    bool party = false,
  }) {
    final len = party ? sizeParty : sizeStored;
    final d = Uint8List(len);
    final m = Pk5._(d, len);
    m.setPid(pid);
    m.setSpecies(species);
    m.setHeldItem(heldItem);
    _sU16(d, 0x0C, tid & 0xFFFF); // TID
    _sU16(d, 0x0E, sid & 0xFFFF); // SID
    m.setExp(exp);
    m.setFriendship(friendship);
    m.setAbility(ability);
    d[0x17] = language & 0xFF;
    m.setMoves(moves);
    for (var i = 0; i < 4 && i < pp.length; i++) {
      m.setPP(i, pp[i]);
    }
    m.setIVs(ivs);
    m.setNicknamed(nicknamed);
    // 0x40: fateful (bit0), gender (bits1-2), alt-form (bits3-7).
    d[0x40] = (fateful ? 1 : 0) | ((gender & 3) << 1) | ((form & 0x1F) << 3);
    d[0x41] = nature & 0xFF; // NEW: stored nature
    d[0x42] = (hiddenAbility ? 1 : 0) | (nsPokemon ? 2 : 0); // NEW flags
    gen5EncodeText(d, 0x48, 11, nickname);
    d[0x5F] = originGame & 0xFF; // game of origin
    gen5EncodeText(d, 0x68, 8, otName);
    d[0x78] = metYear & 0xFF; // egg date (unused for non-eggs) — kept 0 normally
    d[0x7B] = metYear & 0xFF; // met date (year-2000, month, day)
    d[0x7C] = metMonth & 0xFF;
    d[0x7D] = metDay & 0xFF;
    m.setMetLocation(metLocation);
    m.setBall(ball);
    m.setMetLevel(metLevel);
    m.setOtGender(otGender);
    return m;
  }

  bool get isParty => length == sizeParty;

  // ------------------------------------------------------------- header
  int get pid => _u32(data, 0x00);
  int get sanity => _u16(data, 0x04);
  int get storedChecksum => _u16(data, 0x06);
  bool get isEmpty => pid == 0 && species == 0;

  // -------------------------------------------------- Growth block (0x08)
  int get species => _u16(data, 0x08);
  int get heldItem => _u16(data, 0x0A);
  int get tid => _u16(data, 0x0C);
  int get sid => _u16(data, 0x0E);
  int get exp => _u32(data, 0x10);
  int get friendship => data[0x14];
  int get ability => data[0x15];

  /// Effort values, in the order HP, Atk, Def, Spe, SpA, SpD.
  List<int> get evs => [for (var k = 0; k < 6; k++) data[0x18 + k]];

  // ------------------------------------------------- Attacks block (0x28)
  List<int> get moves => [for (var k = 0; k < 4; k++) _u16(data, 0x28 + k * 2)];
  List<int> get pp => [for (var k = 0; k < 4; k++) data[0x30 + k]];
  List<int> get ppUps => [for (var k = 0; k < 4; k++) data[0x34 + k]];

  int get _ivWord => _u32(data, 0x38);

  /// Individual values, in the order HP, Atk, Def, Spe, SpA, SpD.
  List<int> get ivs => [for (var k = 0; k < 6; k++) (_ivWord >> (5 * k)) & 31];
  bool get isEgg => (_ivWord >> 30) & 1 == 1;
  bool get isNicknamed => (_ivWord >> 31) & 1 == 1;

  // ----------------------------------------------- Misc block (0x40..)
  int get fatefulGenderForm => data[0x40];
  bool get fateful => (data[0x40] & 1) == 1;
  int get gender => (data[0x40] >> 1) & 3;
  int get form => (data[0x40] >> 3) & 0x1F;

  /// Gen 5 STORED nature (byte 0x41), NOT `pid % 25`.
  int get nature => data[0x41];
  set nature(int v) => data[0x41] = v & 0xFF;

  /// 0x42 bit0 — the Pokémon uses its Hidden (Dream World) Ability.
  bool get hiddenAbility => (data[0x42] & 1) == 1;
  set hiddenAbility(bool v) =>
      data[0x42] = (data[0x42] & ~1) | (v ? 1 : 0);

  /// 0x42 bit1 — N's Pokémon flag ("N sparkle").
  bool get nsPokemon => (data[0x42] & 2) == 2;
  set nsPokemon(bool v) => data[0x42] = (data[0x42] & ~2) | (v ? 2 : 0);

  // ----------------------------------------------------- names / origin
  Uint8List get nicknameRaw => Uint8List.fromList(data.sublist(0x48, 0x48 + 22));
  Uint8List get otNameRaw => Uint8List.fromList(data.sublist(0x68, 0x68 + 16));
  String get nickname => gen5DecodeText(data, 0x48, 11);
  String get otName => gen5DecodeText(data, 0x68, 8);

  int get language => data[0x17];
  int get originGame => data[0x5F];
  int get ballId => data[0x83];
  int get metLevel => data[0x84] & 0x7F;
  int get otGender => (data[0x84] >> 7) & 1;
  int get metLocation => _u16(data, 0x80);
  List<int> get contest => [for (var k = 0; k < 6; k++) data[0x1E + k]];

  /// Shiny when `TID ^ SID ^ (PID>>16) ^ (PID&0xFFFF) < 8`.
  bool isShiny(int trainerTid, int trainerSid) =>
      (trainerTid ^ trainerSid ^ (pid >> 16) ^ (pid & 0xFFFF)) < 8;

  // -------------------------------------------------------------- setters
  void setSpecies(int v) => _sU16(data, 0x08, v);
  void setHeldItem(int v) => _sU16(data, 0x0A, v);
  void setExp(int v) => _sU32(data, 0x10, v & 0xFFFFFFFF);
  void setFriendship(int v) => data[0x14] = v.clamp(0, 255);
  void setAbility(int v) => data[0x15] = v & 0xFF;

  void setEVs(List<int> v) {
    for (var k = 0; k < 6; k++) {
      data[0x18 + k] = v[k].clamp(0, 255);
    }
  }

  void setMoves(List<int> mv) {
    for (var k = 0; k < 4; k++) {
      _sU16(data, 0x28 + k * 2, k < mv.length ? mv[k] : 0);
    }
  }

  void setPP(int index, int value) => data[0x30 + index] = value.clamp(0, 255);

  void setIVs(List<int> v) {
    var w = _ivWord & (0x3 << 30); // preserve egg + nicknamed flags
    for (var k = 0; k < 6; k++) {
      w |= (v[k].clamp(0, 31)) << (5 * k);
    }
    _sU32(data, 0x38, w & 0xFFFFFFFF);
  }

  void setPid(int v) => _sU32(data, 0x00, v & 0xFFFFFFFF);
  void setLanguage(int v) => data[0x17] = v & 0xFF;
  void setBall(int v) => data[0x83] = v & 0xFF;
  void setMetLevel(int v) =>
      data[0x84] = (data[0x84] & 0x80) | (v.clamp(0, 100) & 0x7F);
  void setOtGender(int g) => data[0x84] = (data[0x84] & 0x7F) | ((g & 1) << 7);
  void setMetLocation(int v) => _sU16(data, 0x80, v & 0xFFFF);

  void setNicknamed(bool v) {
    var w = _ivWord;
    w = v ? (w | (1 << 31)) : (w & ~(1 << 31));
    _sU32(data, 0x38, w & 0xFFFFFFFF);
  }

  /// The stored party level byte (0x8C); box mons don't have it.
  int get partyLevel => length == sizeParty ? data[0x8C] : 0;

  /// Recompute the party battle stats from IVs/EVs/STORED-nature/base stats.
  /// [baseStats] is in Gen order (HP, Atk, Def, Spe, SpA, SpD). Only meaningful
  /// on a 220-byte party block. Heals to full.
  void recomputeStats(int level, List<int> baseStats) {
    if (length < sizeParty) return;
    data[0x8C] = level.clamp(1, 100);
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
    _sU16(data, 0x8E, out[0]); // current HP (healed)
    _sU16(data, 0x90, out[0]); // max HP
    _sU16(data, 0x92, out[1]); // Atk
    _sU16(data, 0x94, out[2]); // Def
    _sU16(data, 0x96, out[3]); // Spe
    _sU16(data, 0x98, out[4]); // SpA
    _sU16(data, 0x9A, out[5]); // SpD
  }

  /// Recompute the block checksum: sum of the 64 decrypted data u16 words.
  int computeChecksum() {
    var s = 0;
    for (var i = 0x08; i < 0x88; i += 2) {
      s = (s + _u16(data, i)) & 0xFFFF;
    }
    return s;
  }

  /// Re-shuffle, re-encrypt, and write a fresh checksum. Returns a new block of
  /// the original length; decode → encode is byte-exact.
  Uint8List encode() {
    final out = Uint8List.fromList(data);
    final checksum = computeChecksum();
    _sU16(out, 0x06, checksum);

    // Re-shuffle canonical G,A,E,M back into the PID's block order.
    final order = _orders[_shuffleIndex(pid)];
    final canon = out.sublist(0x08, 0x88);
    for (var i = 0; i < 4; i++) {
      final src = _letterIndex[order[i]]! * 32;
      out.setRange(0x08 + i * 32, 0x08 + i * 32 + 32, canon, src);
    }

    // Re-encrypt with the same streams used to decrypt.
    _crypt(out, 0x08, 128, checksum);
    if (length == sizeParty) _crypt(out, 0x88, sizeParty - 0x88, pid);
    return out;
  }
}

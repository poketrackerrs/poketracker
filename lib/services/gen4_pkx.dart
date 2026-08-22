import 'dart:typed_data';

/// A single Gen 4 (Diamond/Pearl/Platinum, HeartGold/SoulSilver) Pokémon —
/// "PKX"/PK4. Box form is 136 bytes; party form is 236 bytes (the extra 100
/// hold the derived battle stats).
///
/// Wire format (all little-endian):
///   0x00 u32 PID
///   0x04 u16 sanity flags
///   0x06 u16 checksum (sum of the 64 decrypted data words)
///   0x08..0x88 = 128 bytes = four 32-byte substructures (Growth / Attacks /
///                EVs&Condition / Misc) SHUFFLED by `((PID & 0x3E000) >> 13) % 24`
///                and ENCRYPTED with a u16 keystream from an LCRNG seeded by the
///                checksum. Decrypt first, then unshuffle to a canonical order.
///   0x88..0xEC (party only) battle stats, encrypted by an LCRNG seeded by the
///                PID (a different seed from the data block).
///
/// Unlike Gen 3, the Growth block also carries TID/SID (so exp sits at Growth
/// +0x08, not +0x04) and the EVs live in the Growth block; the IV word lives in
/// the Attacks block. This codec therefore addresses fields by their ABSOLUTE
/// offset inside a reconstructed (decrypted + unshuffled) buffer — the same way
/// PKHeX does — which is unambiguous. Verified byte-exact (decode → encode →
/// decode) against a real Platinum party (Chimchar: species 390, moves
/// Scratch/Leer, nickname "CHIMCHAR", OT "Rafael").
///
/// Gen 4 uses the National dex directly — there is no Gen-3-style remap.
class Pkx {
  /// The decrypted, unshuffled buffer: header (0x00..0x08) + canonical data
  /// blocks (0x08..0x88) + (party only) decrypted battle stats (0x88..).
  final Uint8List data;

  /// Original block length: 136 (box) or 236 (party). Preserved on encode.
  final int length;

  Pkx._(this.data, this.length);

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
  /// from an LCRNG seeded by [seed]. XOR is its own inverse, so the same call
  /// both encrypts and decrypts.
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

  /// Decode a PKM from its (still-encrypted, shuffled) block. Accepts a 136- or
  /// 236-byte block; anything longer is treated as a 236-byte party block.
  factory Pkx.decode(Uint8List block) {
    final length = block.length >= 236 ? 236 : 136;
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
    if (length == 236) _crypt(out, 0x88, 236 - 0x88, pid);

    return Pkx._(out, length);
  }

  bool get isParty => length == 236;

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

  // ----------------------------------------------------- names / origin
  /// Raw 22-byte nickname region (11 little-endian Gen 4 characters, 0xFFFF
  /// terminated). Character-table decoding is left to the UI layer.
  Uint8List get nicknameRaw => Uint8List.fromList(data.sublist(0x48, 0x48 + 22));

  /// Raw 16-byte OT-name region (8 little-endian Gen 4 characters).
  Uint8List get otNameRaw => Uint8List.fromList(data.sublist(0x68, 0x68 + 16));

  int get nature => pid % 25;

  /// Shiny when `TID ^ SID ^ (PID>>16) ^ (PID&0xFFFF) < 8`. Gen 4 keeps the
  /// mon's own TID/SID in the Growth block, so pass the trainer's for a
  /// cross-check or use [tid]/[sid].
  bool isShiny(int trainerTid, int trainerSid) =>
      (trainerTid ^ trainerSid ^ (pid >> 16) ^ (pid & 0xFFFF)) < 8;

  // -------------------------------------------------------------- setters
  void setSpecies(int v) => _sU16(data, 0x08, v);
  void setHeldItem(int v) => _sU16(data, 0x0A, v);
  void setExp(int v) => _sU32(data, 0x10, v & 0xFFFFFFFF);
  void setFriendship(int v) => data[0x14] = v.clamp(0, 255);

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

  /// Recompute the block checksum: sum of the 64 decrypted data u16 words.
  int computeChecksum() {
    var s = 0;
    for (var i = 0x08; i < 0x88; i += 2) {
      s = (s + _u16(data, i)) & 0xFFFF;
    }
    return s;
  }

  /// Re-shuffle and re-encrypt, writing a fresh checksum. Returns a new block of
  /// the original length; the decode → encode round-trip is byte-exact.
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
    if (length == 236) _crypt(out, 0x88, 236 - 0x88, pid);
    return out;
  }
}

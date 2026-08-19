import 'dart:typed_data';

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
  final String order; // substructure order, e.g. "GAEM"

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

  // sub-block base offset within the decrypted 48-byte data
  int _sub(String letter) => order.indexOf(letter) * 12;

  int get species => _u16(data, _sub('G') + 0x00);
  int get heldItem => _u16(data, _sub('G') + 0x02);
  List<int> get moves =>
      [for (var k = 0; k < 4; k++) _u16(data, _sub('A') + k * 2)];
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

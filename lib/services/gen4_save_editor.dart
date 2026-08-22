import 'dart:typed_data';

/// Read/write access to a Gen 4 (Diamond/Pearl/Platinum, HGSS) `.sav`.
///
/// Foundation of the Gen 4 save editor — mirrors [Gen3SaveEditor]'s "verify
/// checksums before you ever write" contract. A Gen 4 save is 512 KB and holds
/// two blocks — a "general" (trainer/game) block and a "storage" (PC boxes)
/// block — each duplicated across two 0x40000 halves. The valid copy is the one
/// whose footer carries the Gen 4 magic and a matching CRC16; when both copies
/// are valid the higher save counter wins.
///
/// Verified against a real Platinum save: half A was blank (0xFF), half B's two
/// blocks both validated (magic 0x20060623, CRC16 over data minus the 0x14-byte
/// footer, stored at block end − 2).
class Gen4SaveEditor {
  final Uint8List bytes;
  final int generalOfs; // active general block base
  final int storageOfs; // active storage block base
  final int generalSize;
  final int storageSize;

  Gen4SaveEditor._(this.bytes, this.generalOfs, this.storageOfs,
      this.generalSize, this.storageSize);

  static const int _magic = 0x20060623; // DPPt/HGSS footer signature
  static const int _footer = 0x14; // trailing footer bytes (counter…crc)
  static const int _half = 0x40000;

  // Block sizes per game family. (DP/HGSS differ from Platinum; added as those
  // saves are verified. Platinum is confirmed against a real save.)
  static const Map<String, ({int general, int storage})> _sizes = {
    'platinum': (general: 0xCF2C, storage: 0x121E4),
    'diamond': (general: 0xC100, storage: 0x121E4),
    'pearl': (general: 0xC100, storage: 0x121E4),
    'heartgold': (general: 0xF628, storage: 0x12310),
    'soulsilver': (general: 0xF628, storage: 0x12310),
  };

  static int _u16(Uint8List b, int o) => b[o] | (b[o + 1] << 8);
  static int _u32(Uint8List b, int o) =>
      b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);

  /// CRC16-CCITT (poly 0x1021, init 0xFFFF) — the Gen 4 block checksum.
  static int crc16(Uint8List b, int start, int len) {
    var c = 0xFFFF;
    for (var i = 0; i < len; i++) {
      c ^= b[start + i] << 8;
      for (var k = 0; k < 8; k++) {
        c = (c & 0x8000) != 0 ? ((c << 1) ^ 0x1021) & 0xFFFF : (c << 1) & 0xFFFF;
      }
    }
    return c;
  }

  /// Is the block at [base] of [size] a valid Gen 4 block (magic + CRC)?
  static bool _blockOk(Uint8List b, int base, int size) {
    if (base + size > b.length) return false;
    if (_u32(b, base + size - 0x8) != _magic) return false;
    return crc16(b, base, size - _footer) == _u16(b, base + size - 2);
  }

  static int _counter(Uint8List b, int base, int size) =>
      _u32(b, base + size - _footer);

  /// Parse a Gen 4 save; throws if no valid block is found for [versionId].
  factory Gen4SaveEditor.load(Uint8List raw, String versionId) {
    if (raw.length < 0x80000) {
      throw const FormatException('Not a Gen 4 save (expected 512 KB).');
    }
    final b = Uint8List.fromList(raw);
    final sz = _sizes[versionId] ?? _sizes['platinum']!;

    // Pick the valid copy of each block (general at half+0, storage after it);
    // when both halves are valid, the higher save counter is active.
    int pick(int intraOfs, int size) {
      final a = 0x00000 + intraOfs, c = _half + intraOfs;
      final aOk = _blockOk(b, a, size), cOk = _blockOk(b, c, size);
      if (aOk && cOk) {
        return _counter(b, c, size) >= _counter(b, a, size) ? c : a;
      }
      if (cOk) return c;
      if (aOk) return a;
      return -1;
    }

    final g = pick(0, sz.general);
    final s = pick(sz.general, sz.storage);
    if (g < 0 || s < 0) {
      throw const FormatException('No valid Gen 4 save block found.');
    }
    return Gen4SaveEditor._(b, g, s, sz.general, sz.storage);
  }

  /// SAFE self-check: both active blocks' stored CRC16 must match a recompute.
  ({bool ok, List<String> mismatches}) verifyChecksums() {
    final bad = <String>[];
    for (final (name, base, size) in [
      ('general', generalOfs, generalSize),
      ('storage', storageOfs, storageSize),
    ]) {
      final got = crc16(bytes, base, size - _footer);
      final want = _u16(bytes, base + size - 2);
      if (got != want) {
        bad.add('$name: computed 0x${got.toRadixString(16)} != '
            'stored 0x${want.toRadixString(16)}');
      }
    }
    return (ok: bad.isEmpty, mismatches: bad);
  }

  /// Recompute + store a block's CRC16. MUST be called after editing it.
  void _fixBlock(int base, int size) {
    final crc = crc16(bytes, base, size - _footer);
    bytes[base + size - 2] = crc & 0xFF;
    bytes[base + size - 1] = (crc >> 8) & 0xFF;
  }

  void fixGeneral() => _fixBlock(generalOfs, generalSize);
  void fixStorage() => _fixBlock(storageOfs, storageSize);

  int get saveCounter => _counter(bytes, generalOfs, generalSize);

  Uint8List toBytes() => bytes;
}

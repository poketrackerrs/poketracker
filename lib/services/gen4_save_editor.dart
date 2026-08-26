import 'dart:typed_data';

import 'gen4_text.dart' show gen4DecodeText, gen4EncodeText;

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

  // ---- Platinum general-block field offsets (relative to generalOfs) --------
  // Verified against a real Platinum save. DP and HGSS shift these (party moves,
  // block sizes differ) — reconfirm before trusting writes there.
  static const int _otName = 0x68; // 8 char slots
  static const int _tid = 0x78;
  static const int _sid = 0x7A;
  static const int _money = 0x7C;
  static const int _gender = 0x80;
  static const int _partyCount = 0x9C;
  static const int _partyData = 0xA0;
  static const int partySlotSize = 236;

  // PC storage: box slots pack from the storage block's start.
  static const int boxCount = 18;
  static const int perBox = 30;
  static const int boxSlotSize = 136;

  Gen4Trainer trainer() => Gen4Trainer(
        name: gen4DecodeText(bytes, generalOfs + _otName, 8),
        tid: _u16(bytes, generalOfs + _tid),
        sid: _u16(bytes, generalOfs + _sid),
        money: _u32(bytes, generalOfs + _money),
        gender: bytes[generalOfs + _gender] & 1,
      );

  int get money => _u32(bytes, generalOfs + _money);
  void setMoney(int v) {
    _setU32(generalOfs + _money, v.clamp(0, 9999999));
    fixGeneral();
  }

  void setTrainer(Gen4Trainer t) {
    gen4EncodeText(bytes, generalOfs + _otName, 8, t.name);
    _setU16(generalOfs + _tid, t.tid & 0xFFFF);
    _setU16(generalOfs + _sid, t.sid & 0xFFFF);
    _setU32(generalOfs + _money, t.money.clamp(0, 9999999));
    bytes[generalOfs + _gender] = t.gender & 1;
    fixGeneral();
  }

  void _setU16(int o, int v) {
    bytes[o] = v & 0xFF;
    bytes[o + 1] = (v >> 8) & 0xFF;
  }

  void _setU32(int o, int v) {
    bytes[o] = v & 0xFF;
    bytes[o + 1] = (v >> 8) & 0xFF;
    bytes[o + 2] = (v >> 16) & 0xFF;
    bytes[o + 3] = (v >> 24) & 0xFF;
  }

  // ---- Party (in the general block) ----
  int get partyCount =>
      _u32(bytes, generalOfs + _partyCount).clamp(0, 6);

  Uint8List partyBlock(int i) {
    final o = generalOfs + _partyData + i * partySlotSize;
    return Uint8List.fromList(bytes.sublist(o, o + partySlotSize));
  }

  void writePartyBlock(int i, Uint8List block) {
    final o = generalOfs + _partyData + i * partySlotSize;
    bytes.setRange(o, o + block.length.clamp(0, partySlotSize), block);
    fixGeneral();
  }

  // ---- PC boxes (in the storage block) ----
  Uint8List boxSlot(int globalIndex) {
    final o = storageOfs + globalIndex * boxSlotSize;
    return Uint8List.fromList(bytes.sublist(o, o + boxSlotSize));
  }

  /// Zero every PC box slot (18×30) and fix the storage checksum once. Empty
  /// slots are trivially valid, so this is a safe way to wipe corrupt boxes.
  void clearAllBoxes() {
    final zero = Uint8List(boxSlotSize);
    for (var g = 0; g < boxCount * perBox; g++) {
      final o = storageOfs + g * boxSlotSize;
      bytes.setRange(o, o + boxSlotSize, zero);
    }
    fixStorage();
  }

  void writeBoxSlot(int globalIndex, Uint8List block) {
    final o = storageOfs + globalIndex * boxSlotSize;
    bytes.setRange(o, o + block.length.clamp(0, boxSlotSize), block);
    fixStorage();
  }

  // ---- Bag (in the general block) ----------------------------------------
  // Verified against PKHeX PlayerBag4Pt/DP/HGSS. Bag base + per-pocket
  // (relative offset, slot count), all relative to the general-block base.
  // A slot is 4 bytes: u16 itemId (LE) + u16 quantity (LE).
  static const Map<String, int> _bagBase = {
    'platinum': 0x630,
    'diamond': 0x624,
    'pearl': 0x624,
    'heartgold': 0x644,
    'soulsilver': 0x644,
  };

  // Pocket layouts keyed by family. (relOffset, slotCount) in pocket order:
  // items, keyItems, tmHm, mail, medicine, berries, balls, battle.
  static const List<({int off, int count})> _pouchDPPt = [
    (off: 0x000, count: 162),
    (off: 0x294, count: 40),
    (off: 0x35C, count: 100),
    (off: 0x4EC, count: 12),
    (off: 0x51C, count: 38),
    (off: 0x5BC, count: 64),
    (off: 0x6BC, count: 15),
    (off: 0x6F8, count: 13),
  ];
  static const List<({int off, int count})> _pouchHGSS = [
    (off: 0x000, count: 162),
    (off: 0x294, count: 43),
    (off: 0x35C, count: 100),
    (off: 0x4F0, count: 12),
    (off: 0x520, count: 38),
    (off: 0x5C0, count: 64),
    (off: 0x6C0, count: 24),
    (off: 0x720, count: 13),
  ];

  List<({int off, int count})> _pouches(String version) =>
      (version == 'heartgold' || version == 'soulsilver')
          ? _pouchHGSS
          : _pouchDPPt;

  /// Absolute offset of pocket [index] (0..7) for [version].
  int _pouchBase(String version, int index) =>
      generalOfs + (_bagBase[version] ?? 0x630) + _pouches(version)[index].off;

  /// Read one bag pocket by its order index (0=items … 7=battle). Returns the
  /// non-empty (id, qty) entries, packed.
  List<({int id, int qty})> readPocket(String version, int index) {
    final base = _pouchBase(version, index);
    final count = _pouches(version)[index].count;
    final out = <({int id, int qty})>[];
    for (var i = 0; i < count; i++) {
      final o = base + i * 4;
      final id = _u16(bytes, o);
      final qty = _u16(bytes, o + 2);
      if (id != 0) out.add((id: id, qty: qty));
    }
    return out;
  }

  /// Overwrite one bag pocket with [entries] (packed from slot 0; remaining
  /// slots zero-filled). Silently drops entries past the pocket's capacity.
  /// Caller must call [fixGeneral] afterwards.
  void writePocket(String version, int index, List<({int id, int qty})> entries) {
    final base = _pouchBase(version, index);
    final count = _pouches(version)[index].count;
    for (var i = 0; i < count; i++) {
      final o = base + i * 4;
      final id = i < entries.length ? entries[i].id & 0xFFFF : 0;
      final qty = i < entries.length ? entries[i].qty & 0xFFFF : 0;
      bytes[o] = id & 0xFF;
      bytes[o + 1] = (id >> 8) & 0xFF;
      bytes[o + 2] = qty & 0xFF;
      bytes[o + 3] = (qty >> 8) & 0xFF;
    }
  }

  // ---- Pokédex caught + gym badges (general block) -----------------------
  // Verified against PKHeX Zukan4 / SAV4. (caughtBase, badgeByte, badge2Byte)
  // relative to the general-block base; caughtBase = PokeDex + 4.
  static const Map<String, (int, int, int)> _dexBadge = {
    'platinum': (0x132C, 0x82, -1),
    'diamond': (0x12E0, 0x7E, -1),
    'pearl': (0x12E0, 0x7E, -1),
    'heartgold': (0x12BC, 0x7E, 0x83),
    'soulsilver': (0x12BC, 0x7E, 0x83),
  };

  /// The set of owned (caught) National-dex species (1..493), LSB-first.
  Set<int> caughtDex(String version) {
    final d = _dexBadge[version] ?? _dexBadge['platinum']!;
    final base = generalOfs + d.$1;
    final out = <int>{};
    for (var n = 0; n < 493; n++) {
      if ((bytes[base + (n >> 3)] >> (n & 7)) & 1 == 1) out.add(n + 1);
    }
    return out;
  }

  /// Gym badge count (DPPt 0..8, HGSS 0..16).
  int badgeCount(String version) {
    final d = _dexBadge[version] ?? _dexBadge['platinum']!;
    var c = _popcount8(bytes[generalOfs + d.$2]);
    if (d.$3 >= 0) c += _popcount8(bytes[generalOfs + d.$3]);
    return c;
  }

  static int _popcount8(int b) {
    var c = 0;
    for (var i = 0; i < 8; i++) {
      if ((b >> i) & 1 == 1) c++;
    }
    return c;
  }

  Uint8List toBytes() => bytes;
}

/// A Gen 4 trainer card (general block).
class Gen4Trainer {
  final String name;
  final int tid, sid, money, gender; // gender: 0 male, 1 female
  const Gen4Trainer({
    required this.name,
    required this.tid,
    required this.sid,
    required this.money,
    required this.gender,
  });
  Gen4Trainer copyWith({String? name, int? tid, int? sid, int? money, int? gender}) =>
      Gen4Trainer(
        name: name ?? this.name,
        tid: tid ?? this.tid,
        sid: sid ?? this.sid,
        money: money ?? this.money,
        gender: gender ?? this.gender,
      );
}

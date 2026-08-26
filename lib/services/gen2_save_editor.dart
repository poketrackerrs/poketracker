import 'dart:typed_data';

import 'pk2.dart' show Pk2, gen2DecodeText, gen2EncodeName;

/// Read/write access to a Gen 2 (Gold / Silver / Crystal, English) `.sav`.
///
/// Format (Bulbapedia "Save data structure (Generation II)"): 32 KiB (0x8000)
/// SRAM. Trainer / party / Pokédex live in bank 1; the 14 archived PC boxes live
/// in banks 2–3 at fixed offsets. Gold/Silver and Crystal share the box layout
/// but differ on almost every bank-1 offset AND on both checksum ranges — this
/// class branches on [versionId] ('gold' | 'silver' | 'crystal').
///
/// Two 16-bit checksums (little-endian, plain byte-sum): a PRIMARY over the main
/// block and a SECONDARY/backup over a mirror region. The PC boxes themselves are
/// NOT covered by either checksum; the Pokédex and party ARE (inside the primary
/// range), so any dex/party edit must recompute checksums. This class recomputes
/// BOTH on every mutation. NOTHING is trusted until [verifyChecksums] passes.
class Gen2SaveEditor {
  final Uint8List bytes;
  final Gen2Offsets o;
  final String versionId;

  Gen2SaveEditor._(this.bytes, this.o, this.versionId);

  static const int saveSize = 0x8000;

  /// PC box start offsets (English; identical in G/S and Crystal). Stride 0x450
  /// (1104 bytes); the 1102-byte payload + 2 pad.
  static const List<int> boxOffsets = [
    0x4000, 0x4450, 0x48A0, 0x4CF0, 0x5140, 0x5590, 0x59E0,
    0x6000, 0x6450, 0x68A0, 0x6CF0, 0x7140, 0x7590, 0x79E0,
  ];
  static const int boxCount = 14;
  static const int perBox = 20;

  // Box internal layout (offsets from a box's base).
  static const int _boxCountByte = 0x000;
  static const int _boxSpeciesList = 0x001; // 20 species + 0xFF terminator
  static const int _boxRecords = 0x016; // 20 * 32-byte records
  static const int _boxOtNames = 0x296; // 20 * 11-byte OT names
  static const int _boxNicknames = 0x372; // 20 * 11-byte nicknames
  static const int _boxPayload = 0x44E; // 1102 bytes (the checksummed image)

  static int _u16be(Uint8List b, int off) => (b[off] << 8) | b[off + 1];

  /// Parse a raw save. Accepts exactly 32 KiB (larger buffers are truncated to
  /// the first 0x8000). Operates on a COPY so the caller's bytes are untouched.
  factory Gen2SaveEditor.load(Uint8List raw, String versionId) {
    if (raw.length < saveSize) {
      throw FormatException(
          'Not a Gen 2 save (expected >= 0x8000 bytes, got ${raw.length}).');
    }
    final b = Uint8List.fromList(raw.sublist(0, saveSize));
    final off = Gen2Offsets.forVersion(versionId);
    return Gen2SaveEditor._(b, off, versionId);
  }

  // ------------------------------------------------------------- checksums
  /// 16-bit sum of every byte in [ranges] (inclusive), masked to 16 bits.
  int _sumRanges(List<List<int>> ranges) {
    var sum = 0;
    for (final r in ranges) {
      for (var i = r[0]; i <= r[1]; i++) {
        sum = (sum + bytes[i]) & 0xFFFF;
      }
    }
    return sum & 0xFFFF;
  }

  int computePrimaryChecksum() => _sumRanges(o.primaryRanges);
  int computeSecondaryChecksum() => _sumRanges(o.secondaryRanges);

  int get storedPrimaryChecksum =>
      bytes[o.primaryStore] | (bytes[o.primaryStore + 1] << 8);
  int get storedSecondaryChecksum =>
      bytes[o.secondaryStore] | (bytes[o.secondaryStore + 1] << 8);

  void _writeLe16(int off, int v) {
    bytes[off] = v & 0xFF;
    bytes[off + 1] = (v >> 8) & 0xFF;
  }

  /// Recompute and store BOTH checksums. Call after any mutation that lands in a
  /// checksummed range (party / Pokédex / trainer / current-box working copy).
  void fixChecksums() {
    _writeLe16(o.primaryStore, computePrimaryChecksum());
    _writeLe16(o.secondaryStore, computeSecondaryChecksum());
  }

  /// SAFE self-check: both stored checksums must equal the recomputed values. If
  /// this fails on a real save, an offset or a range table is wrong — DO NOT
  /// write until it passes.
  ({bool ok, List<String> mismatches}) verifyChecksums() {
    final bad = <String>[];
    final p = computePrimaryChecksum(), sp = storedPrimaryChecksum;
    if (p != sp) {
      bad.add('primary: computed 0x${p.toRadixString(16)} != '
          'stored 0x${sp.toRadixString(16)}');
    }
    final s = computeSecondaryChecksum(), ss = storedSecondaryChecksum;
    if (s != ss) {
      bad.add('secondary: computed 0x${s.toRadixString(16)} != '
          'stored 0x${ss.toRadixString(16)}');
    }
    return (ok: bad.isEmpty, mismatches: bad);
  }

  // -------------------------------------------------------------- trainer
  int get trainerId => _u16be(bytes, o.trainerId);
  String get trainerName => gen2DecodeText(bytes, o.trainerName, 11);

  /// Money is a 3-byte big-endian value.
  int get money => (bytes[o.money] << 16) | (bytes[o.money + 1] << 8) | bytes[o.money + 2];

  /// Which box (0..13) is currently loaded into the working copy.
  int get currentBoxNumber => bytes[o.currentBoxNumber] & 0x7F;

  // ------------------------------------------------------------- box read
  int boxOffset(int box) => boxOffsets[box];
  int boxMonCount(int box) => bytes[boxOffsets[box] + _boxCountByte];

  /// The 32-byte record of box [box] slot [slot].
  Uint8List boxRecord(int box, int slot) {
    final o0 = boxOffsets[box] + _boxRecords + slot * Pk2.recordSize;
    return Uint8List.fromList(bytes.sublist(o0, o0 + Pk2.recordSize));
  }

  /// Decode box [box] slot [slot] into a [Pk2] (with its names).
  Pk2 boxMon(int box, int slot) {
    final base = boxOffsets[box];
    final nameBytes = Uint8List.fromList(bytes.sublist(
        base + _boxNicknames + slot * 11, base + _boxNicknames + slot * 11 + 11));
    final otBytes = Uint8List.fromList(bytes.sublist(
        base + _boxOtNames + slot * 11, base + _boxOtNames + slot * 11 + 11));
    return Pk2.decode(boxRecord(box, slot), nameBytes: nameBytes, otBytes: otBytes);
  }

  // ------------------------------------------------------------- box write
  /// Write a 32-byte [record] (+ 11-byte name fields) into box [box] slot [slot],
  /// keeping the count byte and species-list terminator consistent. Does NOT fix
  /// checksums (boxes are not checksummed) unless it is the current box — see
  /// [addBoxMon], which handles the working-copy mirror.
  void _writeIntoBox(int box, int slot, Uint8List record, Uint8List otName11,
      Uint8List nick11) {
    final base = boxOffsets[box];
    final count = bytes[base + _boxCountByte];
    if (slot >= count) {
      // Growing the box: bump count and re-terminate the species list.
      bytes[base + _boxCountByte] = slot + 1;
    }
    bytes[base + _boxSpeciesList + slot] = record[0]; // species
    // Terminator immediately after the last occupied slot.
    final newCount = bytes[base + _boxCountByte];
    if (newCount < perBox) {
      bytes[base + _boxSpeciesList + newCount] = 0xFF;
    }
    bytes.setRange(base + _boxRecords + slot * Pk2.recordSize,
        base + _boxRecords + slot * Pk2.recordSize + Pk2.recordSize, record);
    bytes.setRange(
        base + _boxOtNames + slot * 11, base + _boxOtNames + slot * 11 + 11, otName11);
    bytes.setRange(base + _boxNicknames + slot * 11,
        base + _boxNicknames + slot * 11 + 11, nick11);
  }

  /// Inject a box-form Pokémon into the first NON-current box that has a free
  /// slot (avoids the current-box working-copy mirror complication). If every
  /// non-current box is full it falls back to the current box AND mirrors the box
  /// image into the working copy. Returns (box, slot), or null if all 14 full.
  ///
  /// [record] is a 32-byte box record (e.g. `Pk2.create(...).encode()`).
  ({int box, int slot})? addBoxMon(Uint8List record,
      {String otName = '', String nickname = ''}) {
    final ot11 = gen2EncodeName(otName);
    final nick11 = gen2EncodeName(nickname);
    final cur = currentBoxNumber;

    int? pick(bool allowCurrent) {
      for (var b = 0; b < boxCount; b++) {
        if (!allowCurrent && b == cur) continue;
        if (boxMonCount(b) < perBox) return b;
      }
      return null;
    }

    var box = pick(false);
    box ??= pick(true); // every non-current box full — use current box
    if (box == null) return null;

    final slot = boxMonCount(box);
    _writeIntoBox(box, slot, record, ot11, nick11);

    if (box == cur) {
      // Mirror the whole archived box image into the current-box working copy,
      // which lives inside the primary checksum range.
      bytes.setRange(o.currentBoxData, o.currentBoxData + _boxPayload,
          bytes.sublist(boxOffsets[box], boxOffsets[box] + _boxPayload));
      fixChecksums();
    }
    return (box: box, slot: slot);
  }

  // -------------------------------------------------------------- Pokédex
  void _setDexBit(int arrayOfs, int nationalDex) {
    final i = nationalDex - 1;
    if (i < 0 || i >= 251) return;
    bytes[arrayOfs + (i >> 3)] |= (1 << (i & 7));
  }

  bool _getDexBit(int arrayOfs, int nationalDex) {
    final i = nationalDex - 1;
    if (i < 0 || i >= 251) return false;
    return (bytes[arrayOfs + (i >> 3)] & (1 << (i & 7))) != 0;
  }

  /// Mark a species (national dex 1..251) as owned (caught) AND seen, then fix
  /// checksums (the dex arrays sit inside the primary checksum range).
  void markCaught(int nationalDex) {
    _setDexBit(o.dexOwned, nationalDex);
    _setDexBit(o.dexSeen, nationalDex);
    fixChecksums();
  }

  /// Mark a species (national dex 1..251) as seen only, then fix checksums.
  void markSeen(int nationalDex) {
    _setDexBit(o.dexSeen, nationalDex);
    fixChecksums();
  }

  bool isOwned(int nationalDex) => _getDexBit(o.dexOwned, nationalDex);
  bool isSeen(int nationalDex) => _getDexBit(o.dexSeen, nationalDex);

  int get ownedCount => _countBits(o.dexOwned, 32);
  int get seenCount => _countBits(o.dexSeen, 32);

  int _countBits(int ofs, int len) {
    var n = 0;
    for (var i = 0; i < len; i++) {
      var v = bytes[ofs + i];
      while (v != 0) {
        n += v & 1;
        v >>= 1;
      }
    }
    return n;
  }

  /// The edited save bytes (edits are applied in place on the loaded copy).
  Uint8List toBytes() => bytes;
}

/// Per-version Gen 2 offsets + checksum ranges (English releases).
class Gen2Offsets {
  final int trainerId;
  final int trainerName;
  final int money;
  final int currentBoxNumber;
  final int currentBoxData; // working copy of the selected box
  final int party;
  final int dexOwned;
  final int dexSeen;
  final int primaryStore; // where the primary checksum is written (LE)
  final int secondaryStore; // where the secondary checksum is written (LE)
  final List<List<int>> primaryRanges; // inclusive byte ranges
  final List<List<int>> secondaryRanges;

  const Gen2Offsets({
    required this.trainerId,
    required this.trainerName,
    required this.money,
    required this.currentBoxNumber,
    required this.currentBoxData,
    required this.party,
    required this.dexOwned,
    required this.dexSeen,
    required this.primaryStore,
    required this.secondaryStore,
    required this.primaryRanges,
    required this.secondaryRanges,
  });

  factory Gen2Offsets.forVersion(String versionId) {
    switch (versionId) {
      case 'crystal':
        return const Gen2Offsets(
          trainerId: 0x2009,
          trainerName: 0x200B,
          money: 0x23DC,
          currentBoxNumber: 0x2700,
          currentBoxData: 0x2D10,
          party: 0x2865,
          dexOwned: 0x2A27,
          dexSeen: 0x2A47,
          primaryStore: 0x2D0D,
          secondaryStore: 0x1F0D,
          primaryRanges: [
            [0x2009, 0x2B82]
          ],
          secondaryRanges: [
            [0x1209, 0x1D82]
          ],
        );
      case 'gold':
      case 'silver':
      default:
        return const Gen2Offsets(
          trainerId: 0x2009,
          trainerName: 0x200B,
          money: 0x23DB,
          currentBoxNumber: 0x2724,
          currentBoxData: 0x2D6C,
          party: 0x288A,
          dexOwned: 0x2A4C,
          dexSeen: 0x2A6C,
          primaryStore: 0x2D69,
          secondaryStore: 0x7E6D,
          primaryRanges: [
            [0x2009, 0x2D68]
          ],
          secondaryRanges: [
            [0x0C6B, 0x17EC],
            [0x3D96, 0x3F3F],
            [0x7E39, 0x7E6C],
          ],
        );
    }
  }
}

import 'dart:typed_data';

import 'gen5_text.dart' show gen5DecodeText, gen5EncodeText;
import 'pk5.dart';

/// Read/write access to a Gen 5 (Black/White, Black 2/White 2) `.sav`.
///
/// Unlike Gen 4's dual general/storage partitions, a Gen 5 save's main region is
/// a flat array of fixed blocks at ABSOLUTE offsets, each block carrying a
/// CRC16-CCITT (init 0xFFFF, PKHeX's `Checksums.CRC16_CCITT`) stored TWICE:
///   • an in-block copy at `blockOffset + blockLen + 2`, and
///   • a mirror in the master "checksum block" at `chkBase + 2*blockIndex`.
/// The checksum block is itself a block and must be re-checksummed LAST (its own
/// CRC doubles as the save-validity footer that `SaveUtil.IsValidFooter5` reads).
///
/// Layout is identical between BW and B2W2 for boxes/party/trainer; only the
/// checksum-block base, the Pokédex block, and the main-region size differ.
///
/// Offsets & block tables taken from PKHeX `SaveBlockAccessor5BW` /
/// `SaveBlockAccessor5B2W2`, `BlockInfoNDS`, `SAV5`.
class Gen5SaveEditor {
  final Uint8List bytes;
  final bool isB2W2;

  Gen5SaveEditor._(this.bytes, this.isB2W2, this._blocks);

  static const int rawSize = 0x80000; // full .sav (both versions)

  // ---- version-invariant main-region constants (SAV5.cs) ----
  static const int boxBase = 0x400; // box 0 data
  static const int boxStride = 0x1000; // per-box block stride
  static const int boxDataLen = 0xFF0; // 30 * 136
  static const int boxCount = 24;
  static const int perBox = 30;
  static const int boxSlotSize = 136;

  static const int partyBase = 0x18E00; // block 26
  static const int partyCountOfs = partyBase + 4; // 0x18E04
  static const int partyDataOfs = partyBase + 8; // 0x18E08
  static const int partySlotSize = 220;

  // Trainer block (PlayerData5, block 27 @ 0x19400) — same field offsets BW/B2W2.
  static const int trainerBase = 0x19400;
  static const int otNameOfs = trainerBase + 0x04; // 0x19404, 8 char slots
  static const int tidOfs = trainerBase + 0x14; // 0x19414
  static const int sidOfs = trainerBase + 0x16; // 0x19416

  // Box-names / layout block (block 0 @ 0x00000).
  static const int boxLayoutBase = 0x00000;
  static const int currentBoxOfs = boxLayoutBase; // byte 0

  static int _u16(Uint8List b, int o) => b[o] | (b[o + 1] << 8);

  /// PKHeX `Checksums.CRC16_CCITT` — the exact bit-twiddle Gen 5 uses (init
  /// 0xFFFF, NO final inversion). Distinct from the Gen 4 editor's algorithm.
  static int crc16ccitt(Uint8List b, int start, int len) {
    var top = 0xFF, bot = 0xFF;
    for (var i = 0; i < len; i++) {
      var x = b[start + i] ^ top;
      x ^= (x >> 4);
      top = (bot ^ (x >> 3) ^ (x << 4)) & 0xFF;
      bot = (x ^ (x << 5)) & 0xFF;
    }
    return ((top << 8) | bot) & 0xFFFF;
  }

  // ---------------------------------------------------------------- block table
  // Each block: (offset, dataLen, inBlockChkOfs, mirrorChkOfs). The checksum
  // block is the LAST entry. Values are verbatim from PKHeX's accessors.
  final List<_Block5> _blocks;

  int get _chkBlockIndex => _blocks.length - 1;

  // Pokédex block index (BW: 55 @ 0x21600, B2W2: 54 @ 0x21400).
  int get pokedexBlockIndex => isB2W2 ? 54 : 55;
  int get pokedexOffset => _blocks[pokedexBlockIndex].offset;

  /// Parse a Gen 5 save. [versionId] is 'black' | 'white' | 'black2' | 'white2'.
  factory Gen5SaveEditor.load(Uint8List raw, String versionId) {
    if (raw.length < rawSize) {
      throw const FormatException('Not a Gen 5 save (expected 512 KB).');
    }
    final v = versionId.toLowerCase();
    final b2 = v == 'black2' || v == 'white2' || v == 'b2' || v == 'w2';
    final b = Uint8List.fromList(raw);
    return Gen5SaveEditor._(b, b2, b2 ? _tableB2W2() : _tableBW());
  }

  int get mainSize => isB2W2 ? 0x26000 : 0x24000;
  int get chkBlockBase => isB2W2 ? 0x25F00 : 0x23F00;

  // ------------------------------------------------------- checksum operations
  /// Recompute + store block [i]'s CRC into BOTH its in-block copy and its
  /// mirror in the checksum block. Does NOT refresh the checksum block itself.
  void _fixBlock(int i) {
    final blk = _blocks[i];
    final crc = crc16ccitt(bytes, blk.offset, blk.dataLen);
    _setU16(blk.inBlockChkOfs, crc);
    _setU16(blk.mirrorChkOfs, crc);
  }

  /// Recompute the checksum block's OWN crc (must run after any mirror write).
  void _fixChecksumBlock() {
    final blk = _blocks[_chkBlockIndex];
    final crc = crc16ccitt(bytes, blk.offset, blk.dataLen);
    _setU16(blk.inBlockChkOfs, crc); // == mirrorChkOfs for the last block
  }

  /// Fix block [i] and then the checksum block (the two-step chain the games
  /// require after editing any block).
  void _fixBlockAndFooter(int i) {
    _fixBlock(i);
    _fixChecksumBlock();
  }

  /// Recompute EVERY block + the checksum block (like PKHeX `SetChecksums`).
  void fixAllChecksums() {
    for (var i = 0; i < _blocks.length - 1; i++) {
      _fixBlock(i);
    }
    _fixChecksumBlock();
  }

  /// SAFE self-check: every block's stored in-block CRC and mirror must match a
  /// recompute. Returns the list of mismatching block indices/names.
  ({bool ok, List<String> mismatches}) verifyChecksums() {
    final bad = <String>[];
    for (var i = 0; i < _blocks.length; i++) {
      final blk = _blocks[i];
      final got = crc16ccitt(bytes, blk.offset, blk.dataLen);
      final inBlk = _u16(bytes, blk.inBlockChkOfs);
      final mirror = _u16(bytes, blk.mirrorChkOfs);
      if (got != inBlk) {
        bad.add('block $i in-block: computed 0x${got.toRadixString(16)} != '
            'stored 0x${inBlk.toRadixString(16)}');
      }
      if (got != mirror) {
        bad.add('block $i mirror: computed 0x${got.toRadixString(16)} != '
            'stored 0x${mirror.toRadixString(16)}');
      }
    }
    return (ok: bad.isEmpty, mismatches: bad);
  }

  // ------------------------------------------------- read-only auto-tracker
  // Gen 5 max National-dex species (Legal.MaxSpeciesID_5). Genesect = 649.
  static const int maxSpecies = 649;

  // Zukan5 block-relative layout (BitSeenSize 0x54; header u32 magic + u32
  // packed/national-dex flags): caught region 0 @ 0x08, then 4 seen regions.
  static const int _dexCaughtRel = 0x08; // Region 0: Caught/owned flags
  static const int _dexSeenRel = 0x5C; // Region 1 (Seen Male/Genderless)
  static const int _bitRegion = 0x54; // 84 bytes per region

  /// Absolute offset of the Pokédex "caught/owned" bitfield (species N → bit
  /// N-1). BW 0x21608, B2W2 0x21408.
  int get dexCaughtOffset => pokedexOffset + _dexCaughtRel;

  /// Absolute offset of the first "seen" region (Male/Genderless).
  /// BW 0x2165C, B2W2 0x2145C. Four regions of 0x54 follow (see spec).
  int get dexSeenOffset => pokedexOffset + _dexSeenRel;

  bool _flag(int ofs, int bit) => (bytes[ofs + (bit >> 3)] >> (bit & 7)) & 1 == 1;

  /// Number of distinct species (1..649) flagged CAUGHT/owned.
  int caughtCount() {
    var n = 0;
    for (var sp = 1; sp <= maxSpecies; sp++) {
      if (_flag(dexCaughtOffset, sp - 1)) n++;
    }
    return n;
  }

  /// Number of distinct species SEEN in any of the 4 seen regions.
  int seenCount() {
    var n = 0;
    for (var sp = 1; sp <= maxSpecies; sp++) {
      final bit = sp - 1;
      for (var r = 0; r < 4; r++) {
        if (_flag(dexSeenOffset + r * _bitRegion, bit)) {
          n++;
          break;
        }
      }
    }
    return n;
  }

  /// True if species [sp] (1..649) is flagged caught/owned.
  bool isCaught(int sp) =>
      sp >= 1 && sp <= maxSpecies && _flag(dexCaughtOffset, sp - 1);

  // ---- Gym badges (Misc5, block 52 @ 0x21200 BW / 0x21100 B2W2) ----
  int get miscBlockOffset => _blocks[52].offset;

  /// Absolute offset of the badge byte (Misc5.Badges = Data[0x4]).
  /// BW 0x21204, B2W2 0x21104. Bit i (0..7) = badge (i+1).
  int get badgesOffset => miscBlockOffset + 0x4;

  int get badgeByte => bytes[badgesOffset];

  /// Number of gym badges obtained (popcount of the badge byte, bits 0..7).
  int badgeCount() {
    var b = badgeByte, n = 0;
    while (b != 0) {
      n += b & 1;
      b >>= 1;
    }
    return n;
  }

  /// Money (Misc5.Money = u32 @ Misc block base). BW 0x21200, B2W2 0x21100.
  int get money => _u32BytesAt(miscBlockOffset);
  int _u32BytesAt(int o) =>
      bytes[o] | (bytes[o + 1] << 8) | (bytes[o + 2] << 16) | (bytes[o + 3] << 24);

  /// Team read: decode each non-empty party slot to (species, level).
  List<({int species, int level})> team() {
    final out = <({int species, int level})>[];
    for (var i = 0; i < partyCount; i++) {
      final mon = Pk5.decode(partySlot(i));
      if (!mon.isEmpty) {
        out.add((species: mon.species, level: mon.partyLevel));
      }
    }
    return out;
  }

  // ------------------------------------------------------------------- trainer
  Gen5Trainer trainer() => Gen5Trainer(
        name: gen5DecodeText(bytes, otNameOfs, 8),
        tid: _u16(bytes, tidOfs),
        sid: _u16(bytes, sidOfs),
      );

  void setTrainer(Gen5Trainer t) {
    gen5EncodeText(bytes, otNameOfs, 8, t.name);
    _setU16(tidOfs, t.tid & 0xFFFF);
    _setU16(sidOfs, t.sid & 0xFFFF);
    _fixBlockAndFooter(27); // Trainer Data block
  }

  int get tid => _u16(bytes, tidOfs);
  int get sid => _u16(bytes, sidOfs);
  String get otName => gen5DecodeText(bytes, otNameOfs, 8);
  int get currentBox => bytes[currentBoxOfs];

  // --------------------------------------------------------------- PC boxes
  /// Absolute offset of a (box, slot). Boxes are separate blocks 0x1000 apart.
  int boxSlotOffset(int box, int slot) =>
      boxBase + box * boxStride + slot * boxSlotSize;

  /// Absolute offset of a global slot index (0 .. 24*30-1).
  int globalSlotOffset(int globalIndex) =>
      boxSlotOffset(globalIndex ~/ perBox, globalIndex % perBox);

  /// Block index (in the block table) for a given box: box N is block N+1.
  int _boxBlockIndex(int box) => box + 1;

  /// Read the raw 136-byte (encrypted) slot at (box, slot).
  Uint8List boxSlot(int box, int slot) {
    final o = boxSlotOffset(box, slot);
    return Uint8List.fromList(bytes.sublist(o, o + boxSlotSize));
  }

  /// Read the raw 136-byte slot at a global index.
  Uint8List boxSlotGlobal(int globalIndex) =>
      boxSlot(globalIndex ~/ perBox, globalIndex % perBox);

  /// Decode the slot at (box, slot) into a [Pk5] (or null if empty).
  Pk5? boxMon(int box, int slot) {
    final raw = boxSlot(box, slot);
    final mon = Pk5.decode(raw);
    return mon.isEmpty ? null : mon;
  }

  /// Write a raw 136-byte (already encrypted) block into (box, slot) and refresh
  /// that box's checksum + the checksum block.
  void writeBoxSlot(int box, int slot, Uint8List block) {
    final o = boxSlotOffset(box, slot);
    bytes.setRange(o, o + block.length.clamp(0, boxSlotSize), block);
    _fixBlockAndFooter(_boxBlockIndex(box));
  }

  /// Insert an (encrypted 136-byte) mon into the first empty box slot, scanning
  /// boxes 0..23 in order. Returns the global slot index used, or -1 if full.
  int addBoxMon(Uint8List block) {
    for (var box = 0; box < boxCount; box++) {
      for (var slot = 0; slot < perBox; slot++) {
        final o = boxSlotOffset(box, slot);
        final species = // decrypt just enough to test emptiness
            Pk5.decode(Uint8List.fromList(bytes.sublist(o, o + boxSlotSize)))
                .isEmpty;
        if (species) {
          writeBoxSlot(box, slot, block);
          return box * perBox + slot;
        }
      }
    }
    return -1;
  }

  // ----------------------------------------------------------------- party
  int get partyCount => bytes[partyCountOfs].clamp(0, 6);

  int partyDataOfsFor(int i) => partyDataOfs + i * partySlotSize;

  Uint8List partySlot(int i) {
    final o = partyDataOfsFor(i);
    return Uint8List.fromList(bytes.sublist(o, o + partySlotSize));
  }

  void _setU16(int o, int v) {
    bytes[o] = v & 0xFF;
    bytes[o + 1] = (v >> 8) & 0xFF;
  }

  Uint8List toBytes() => bytes;

  // ------------------------------------------------------------- block tables
  static List<_Block5> _tableBW() {
    final blocks = <_Block5>[];
    // Boxes + names share the same repeating footer scheme; build boxes first.
    // Block 0: Box Names.
    blocks.add(_Block5(0x00000, 0x03E0, 0x003E2, 0x23F00));
    // Blocks 1..24: Box 1..24 (offset 0x400 + (N-1)*0x1000).
    for (var i = 1; i <= 24; i++) {
      final ofs = 0x400 + (i - 1) * 0x1000;
      blocks.add(_Block5(ofs, 0x0FF0, ofs + 0x0FF0 + 2, 0x23F00 + i * 2));
    }
    // Remaining blocks (index -> offset, dataLen). inBlockChk = ofs+len+2,
    // mirror = 0x23F00 + 2*index. Verbatim from SaveBlockAccessor5BW.
    const rest = <List<int>>[
      [25, 0x18400, 0x09C0], [26, 0x18E00, 0x0534], [27, 0x19400, 0x0068],
      [28, 0x19500, 0x009C], [29, 0x19600, 0x1338], [30, 0x1AA00, 0x07C4],
      [31, 0x1B200, 0x0D54], [32, 0x1C000, 0x002C], [33, 0x1C100, 0x0658],
      [34, 0x1C800, 0x0A94], [35, 0x1D300, 0x01AC], [36, 0x1D500, 0x03EC],
      [37, 0x1D900, 0x005C], [38, 0x1DA00, 0x01E0], [39, 0x1DC00, 0x00A8],
      [40, 0x1DD00, 0x0460], [41, 0x1E200, 0x1400], [42, 0x1F700, 0x02A4],
      [43, 0x1FA00, 0x02DC], [44, 0x1FD00, 0x034C], [45, 0x20100, 0x03EC],
      [46, 0x20500, 0x00F8], [47, 0x20600, 0x02FC], [48, 0x20900, 0x0094],
      [49, 0x20A00, 0x035C], [50, 0x20E00, 0x01CC], [51, 0x21000, 0x0168],
      [52, 0x21200, 0x00EC], [53, 0x21300, 0x01B0], [54, 0x21500, 0x001C],
      [55, 0x21600, 0x04D4], [56, 0x21B00, 0x0034], [57, 0x21C00, 0x003C],
      [58, 0x21D00, 0x01AC], [59, 0x21F00, 0x0B90], [60, 0x22B00, 0x009C],
      [61, 0x22C00, 0x0850], [62, 0x23500, 0x0028], [63, 0x23600, 0x0284],
      [64, 0x23900, 0x0010], [65, 0x23A00, 0x005C], [66, 0x23B00, 0x016C],
      [67, 0x23D00, 0x0040], [68, 0x23E00, 0x00FC],
    ];
    for (final r in rest) {
      final idx = r[0], ofs = r[1], len = r[2];
      blocks.add(_Block5(ofs, len, ofs + len + 2, 0x23F00 + idx * 2));
    }
    // Block 69: Checksum block (in-block chk == mirror == 0x23F9A).
    blocks.add(_Block5(0x23F00, 0x008C, 0x23F9A, 0x23F9A));
    return blocks;
  }

  static List<_Block5> _tableB2W2() {
    final blocks = <_Block5>[];
    blocks.add(_Block5(0x00000, 0x03E0, 0x003E2, 0x25F00));
    for (var i = 1; i <= 24; i++) {
      final ofs = 0x400 + (i - 1) * 0x1000;
      blocks.add(_Block5(ofs, 0x0FF0, ofs + 0x0FF0 + 2, 0x25F00 + i * 2));
    }
    const rest = <List<int>>[
      [25, 0x18400, 0x09EC], [26, 0x18E00, 0x0534], [27, 0x19400, 0x00B0],
      [28, 0x19500, 0x00A8], [29, 0x19600, 0x1338], [30, 0x1AA00, 0x07C4],
      [31, 0x1B200, 0x0D54], [32, 0x1C000, 0x0094], [33, 0x1C100, 0x0658],
      [34, 0x1C800, 0x0A94], [35, 0x1D300, 0x01AC], [36, 0x1D500, 0x03EC],
      [37, 0x1D900, 0x005C], [38, 0x1DA00, 0x01E0], [39, 0x1DC00, 0x00A8],
      [40, 0x1DD00, 0x0460], [41, 0x1E200, 0x1400], [42, 0x1F700, 0x02A4],
      [43, 0x1FA00, 0x00E0], [44, 0x1FB00, 0x034C], [45, 0x1FF00, 0x04E0],
      [46, 0x20400, 0x00F8], [47, 0x20500, 0x02FC], [48, 0x20800, 0x0094],
      [49, 0x20900, 0x035C], [50, 0x20D00, 0x01D4], [51, 0x20F00, 0x01E0],
      [52, 0x21100, 0x00F0], [53, 0x21200, 0x01B4], [54, 0x21400, 0x04DC],
      [55, 0x21900, 0x0034], [56, 0x21A00, 0x003C], [57, 0x21B00, 0x01AC],
      [58, 0x21D00, 0x0B90], [59, 0x22900, 0x00AC], [60, 0x22A00, 0x0850],
      [61, 0x23300, 0x0284], [62, 0x23600, 0x0010], [63, 0x23700, 0x00A8],
      [64, 0x23800, 0x016C], [65, 0x23A00, 0x0080], [66, 0x23B00, 0x00FC],
      [67, 0x23C00, 0x16A8], [68, 0x25300, 0x0498], [69, 0x25800, 0x0060],
      [70, 0x25900, 0x00FC], [71, 0x25A00, 0x03E4], [72, 0x25E00, 0x00F0],
    ];
    for (final r in rest) {
      final idx = r[0], ofs = r[1], len = r[2];
      blocks.add(_Block5(ofs, len, ofs + len + 2, 0x25F00 + idx * 2));
    }
    // Block 73: Checksum block.
    blocks.add(_Block5(0x25F00, 0x0094, 0x25FA2, 0x25FA2));
    return blocks;
  }
}

/// One Gen 5 save block descriptor (see PKHeX `BlockInfoNDS`).
class _Block5 {
  final int offset;
  final int dataLen;
  final int inBlockChkOfs; // ofs + len + 2
  final int mirrorChkOfs; // chkBase + 2*index
  const _Block5(
      this.offset, this.dataLen, this.inBlockChkOfs, this.mirrorChkOfs);
}

/// A Gen 5 trainer identity (subset of PlayerData5).
class Gen5Trainer {
  final String name;
  final int tid, sid;
  const Gen5Trainer({required this.name, required this.tid, required this.sid});
  Gen5Trainer copyWith({String? name, int? tid, int? sid}) => Gen5Trainer(
        name: name ?? this.name,
        tid: tid ?? this.tid,
        sid: sid ?? this.sid,
      );
}

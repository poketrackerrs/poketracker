import 'dart:typed_data';

import 'gen6_text.dart' show gen6DecodeText, gen6EncodeText;
import 'pk6.dart';

/// Read/write access to a Gen 6 (X/Y, Omega Ruby/Alpha Sapphire) 3DS "main"
/// save. The file is the DECRYPTED inner save (as extracted by Checkpoint/JKSM/
/// PKHeX) — PKHeX opens "main" directly; there is no whole-file decryption. Only
/// the sizes differ: XY = 0x65600, ORAS = 0x76000.
///
/// Unlike Gen 5's per-block dual CRC (in-block copy + mirror), Gen 6 keeps ONE
/// copy of each block's CRC16-CCITT in a block-metadata footer that begins at
/// `SIZE - 0x200`. The footer is: 0x10 bytes of timestamps, a 4-byte "BEEF"
/// magic (→ 0x14 header), then one 8-byte record per block
/// `{u32 length, u16 id, u16 crc16}`. So block `id`'s stored CRC lives at
/// `metaBase + 0x14 + id*8 + 6`. The CRC routine is byte-for-byte the SAME
/// `Checksums.CRC16_CCITT` the Gen 5 editor already uses.
///
/// Offsets are verbatim from PKHeX `SaveBlockAccessor6XY` / `SaveBlockAccessor6AO`,
/// `SAV6XY` / `SAV6AO`, `BlockInfo3DS`, `Zukan6`, `Misc6XY/AO`, `MyStatus6`.
class Sav6SaveEditor {
  final Uint8List bytes;
  final bool isORAS;
  final List<_Block6> _blocks;

  Sav6SaveEditor._(this.bytes, this.isORAS, this._blocks);

  static const int sizeXY = 0x65600;
  static const int sizeORAS = 0x76000;

  // ---- offsets shared by XY & ORAS (block 17 MyStatus, block 18 party, etc.)
  static const int trainerBase = 0x14000; // block 17 MyStatus
  static const int tidOfs = trainerBase + 0x00; // 0x14000
  static const int sidOfs = trainerBase + 0x02; // 0x14002
  static const int versionOfs = trainerBase + 0x04; // 0x14004
  static const int genderOfs = trainerBase + 0x05; // 0x14005
  static const int languageOfs = trainerBase + 0x2D; // 0x1402D
  static const int otNameOfs = trainerBase + 0x48; // 0x14048 (26 bytes)

  static const int partyBase = 0x14200; // block 18 PokePartySave
  static const int partySlotSize = 260; // 0x104 (party PK6)
  static const int partyMax = 6;
  static const int partyCountOfs = partyBase + partyMax * partySlotSize; // 0x14818

  static const int zukanBase = 0x15000; // block 20 ZukanData
  // Owned/"caught" national-dex bit array: block+0x8, 0x60 bytes (bits 0..720).
  static const int zukanCaughtOfs = zukanBase + 0x08; // 0x15008
  static const int nationalDexMax = 721; // Gen 6 national dex

  static const int miscBase = 0x04200; // block 11 Misc (both versions)
  static const int badgesOfs = miscBase + 0x0C; // 0x0420C, one byte, 8 bits
  static const int moneyOfs = miscBase + 0x08; // 0x04208, u32

  static const int boxLayoutBase = 0x04400; // block 12
  static const int currentBoxOfs = boxLayoutBase; // first byte

  // Box storage: 31 boxes × 30 slots × 232 (stored PK6). Base differs per game.
  static const int boxCount = 31;
  static const int perBox = 30;
  static const int boxSlotSize = 232; // 0xE8
  int get boxBase => isORAS ? 0x33000 : 0x22600;
  int get _boxBlockId => isORAS ? 56 : 53;

  int get metaBase => (isORAS ? sizeORAS : sizeXY) - 0x200;

  static int _u16(Uint8List b, int o) => b[o] | (b[o + 1] << 8);
  void _setU16(int o, int v) {
    bytes[o] = v & 0xFF;
    bytes[o + 1] = (v >> 8) & 0xFF;
  }

  /// PKHeX `Checksums.CRC16_CCITT` (init 0xFFFF, no final inversion) — the same
  /// routine Gen 5 uses. Gen 6 blocks are checksummed with this over
  /// `[offset, offset+length)`.
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

  /// Parse a Gen 6 save. [versionId] is 'x' | 'y' | 'omegaruby' | 'alphasapphire'
  /// (also accepts 'or' | 'as' | 'oras').
  factory Sav6SaveEditor.load(Uint8List raw, String versionId) {
    final v = versionId.toLowerCase();
    final oras = v == 'omegaruby' ||
        v == 'alphasapphire' ||
        v == 'or' ||
        v == 'as' ||
        v == 'oras';
    final expected = oras ? sizeORAS : sizeXY;
    if (raw.length < expected) {
      throw FormatException('Not a Gen 6 ${oras ? "ORAS" : "XY"} save '
          '(expected 0x${expected.toRadixString(16)} bytes, got '
          '0x${raw.length.toRadixString(16)}).');
    }
    final b = Uint8List.fromList(raw);
    return Sav6SaveEditor._(b, oras, oras ? _tableORAS() : _tableXY());
  }

  // -------------------------------------------------------- checksums
  int _chkOfsFor(int id) => metaBase + 0x14 + id * 8 + 6;

  /// Recompute + store block [id]'s CRC into its footer record. Targeted fix —
  /// only touch blocks you actually modified (safest on real saves).
  void _fixBlock(int id) {
    final blk = _blocks.firstWhere((x) => x.id == id);
    _setU16(_chkOfsFor(id), crc16ccitt(bytes, blk.offset, blk.length));
  }

  /// Recompute EVERY block's CRC (PKHeX `SetChecksums`). Safe because the block
  /// table is verbatim from PKHeX; unmodified blocks re-derive their existing
  /// CRC (a no-op).
  void fixAllChecksums() {
    for (final blk in _blocks) {
      _setU16(_chkOfsFor(blk.id), crc16ccitt(bytes, blk.offset, blk.length));
    }
  }

  /// Read-only self-check: every block's stored footer CRC must match a
  /// recompute. Returns the list of mismatching block ids.
  ({bool ok, List<String> mismatches}) verifyChecksums() {
    final bad = <String>[];
    for (final blk in _blocks) {
      final got = crc16ccitt(bytes, blk.offset, blk.length);
      final stored = _u16(bytes, _chkOfsFor(blk.id));
      if (got != stored) {
        bad.add('block ${blk.id} (${blk.name}): computed '
            '0x${got.toRadixString(16)} != stored 0x${stored.toRadixString(16)}');
      }
    }
    return (ok: bad.isEmpty, mismatches: bad);
  }

  // ---------------------------------------------------------- trainer
  Gen6Trainer trainer() => Gen6Trainer(
        name: gen6DecodeText(bytes, otNameOfs, 13),
        tid: _u16(bytes, tidOfs),
        sid: _u16(bytes, sidOfs),
        gender: bytes[genderOfs],
        language: bytes[languageOfs],
      );

  void setTrainer(Gen6Trainer t) {
    gen6EncodeText(bytes, otNameOfs, 13, t.name);
    _setU16(tidOfs, t.tid & 0xFFFF);
    _setU16(sidOfs, t.sid & 0xFFFF);
    bytes[genderOfs] = t.gender & 0xFF;
    bytes[languageOfs] = t.language & 0xFF;
    _fixBlock(17); // MyStatus block
  }

  int get tid => _u16(bytes, tidOfs);
  int get sid => _u16(bytes, sidOfs);
  String get otName => gen6DecodeText(bytes, otNameOfs, 13);
  int get currentBox => bytes[currentBoxOfs];

  // ------------------------------------------------------------ badges
  int get badgeByte => bytes[badgesOfs];

  /// Number of gym badges obtained (popcount of the 8-bit badge flag byte).
  int badgeCount() {
    var n = 0, v = bytes[badgesOfs];
    while (v != 0) {
      n += v & 1;
      v >>= 1;
    }
    return n;
  }

  /// Write the raw 8-bit badge flag byte and refresh the Misc block CRC.
  void setBadgeByte(int v) {
    bytes[badgesOfs] = v & 0xFF;
    _fixBlock(11);
  }

  // ----------------------------------------------------------- Pokédex
  /// Count of species OWNED ("caught") in the national dex (species 1..721).
  /// Reads the Zukan6 owned bit array at 0x15008 (bit index = species-1).
  int caughtDexCount() {
    var n = 0;
    for (var species = 1; species <= nationalDexMax; species++) {
      final bit = species - 1;
      final o = zukanCaughtOfs + (bit >> 3);
      if ((bytes[o] >> (bit & 7)) & 1 == 1) n++;
    }
    return n;
  }

  bool isCaught(int species) {
    if (species < 1 || species > nationalDexMax) return false;
    final bit = species - 1;
    return (bytes[zukanCaughtOfs + (bit >> 3)] >> (bit & 7)) & 1 == 1;
  }

  /// Set/clear the OWNED flag for [species] and refresh the Zukan block CRC.
  /// (This is the minimal "caught" flag; a fully legal dex entry would also set
  /// a seen/displayed/language bit — out of scope for a read-only sync.)
  void setCaught(int species, bool value) {
    if (species < 1 || species > nationalDexMax) return;
    final bit = species - 1;
    final o = zukanCaughtOfs + (bit >> 3);
    if (value) {
      bytes[o] |= (1 << (bit & 7));
    } else {
      bytes[o] &= ~(1 << (bit & 7));
    }
    _fixBlock(20);
  }

  // ------------------------------------------------------------- party
  int get partyCount => bytes[partyCountOfs].clamp(0, partyMax);

  int partySlotOffset(int i) => partyBase + i * partySlotSize;

  Uint8List partySlot(int i) {
    final o = partySlotOffset(i);
    return Uint8List.fromList(bytes.sublist(o, o + partySlotSize));
  }

  Pk6? partyMon(int i) {
    final mon = Pk6.decode(partySlot(i));
    return mon.isEmpty ? null : mon;
  }

  /// The party team as (species, level) pairs. Level comes straight from the
  /// party stat block (PK6 0xEC), so no growth-rate table is needed.
  List<({int species, int level})> partyTeam() {
    final out = <({int species, int level})>[];
    final count = partyCount;
    for (var i = 0; i < count; i++) {
      final mon = partyMon(i);
      if (mon != null) {
        out.add((species: mon.species, level: mon.partyLevel));
      }
    }
    return out;
  }

  // ----------------------------------------------------------- PC boxes
  int boxSlotOffset(int box, int slot) =>
      boxBase + (box * perBox + slot) * boxSlotSize;

  Uint8List boxSlot(int box, int slot) {
    final o = boxSlotOffset(box, slot);
    return Uint8List.fromList(bytes.sublist(o, o + boxSlotSize));
  }

  Pk6? boxMon(int box, int slot) {
    final mon = Pk6.decode(boxSlot(box, slot));
    return mon.isEmpty ? null : mon;
  }

  bool _boxSlotEmpty(int box, int slot) {
    final o = boxSlotOffset(box, slot);
    // species at 0x08 of a decrypted mon; decode just enough.
    return Pk6.decode(
            Uint8List.fromList(bytes.sublist(o, o + boxSlotSize)))
        .isEmpty;
  }

  /// Write a raw (already-encrypted) 232-byte block into (box, slot) and refresh
  /// the box block's CRC.
  void writeBoxSlot(int box, int slot, Uint8List block) {
    final o = boxSlotOffset(box, slot);
    final n = block.length < boxSlotSize ? block.length : boxSlotSize;
    bytes.setRange(o, o + n, block);
    _fixBlock(_boxBlockId);
  }

  /// Insert an (encrypted 232-byte) mon into the first empty box slot, scanning
  /// boxes 0..30 in order. Returns the global slot index used, or -1 if full.
  int addBoxMon(Uint8List block) {
    for (var box = 0; box < boxCount; box++) {
      for (var slot = 0; slot < perBox; slot++) {
        if (_boxSlotEmpty(box, slot)) {
          writeBoxSlot(box, slot, block);
          return box * perBox + slot;
        }
      }
    }
    return -1;
  }

  Uint8List toBytes() => bytes;

  // ------------------------------------------------------- block tables
  // (id, offset, length, name) — verbatim from PKHeX SaveBlockAccessor6XY/AO.
  static List<_Block6> _tableXY() => const [
        _Block6(0, 0x00000, 0x002C8, 'Puff'),
        _Block6(1, 0x00400, 0x00B88, 'MyItem'),
        _Block6(2, 0x01000, 0x0002C, 'ItemInfo'),
        _Block6(3, 0x01200, 0x00038, 'GameTime'),
        _Block6(4, 0x01400, 0x00150, 'Situation'),
        _Block6(5, 0x01600, 0x00004, 'RandomGroup'),
        _Block6(6, 0x01800, 0x00008, 'PlayTime'),
        _Block6(7, 0x01A00, 0x001C0, 'Fashion'),
        _Block6(8, 0x01C00, 0x000BE, 'Amie'),
        _Block6(9, 0x01E00, 0x00024, 'Temp'),
        _Block6(10, 0x02000, 0x02100, 'FieldMoveModel'),
        _Block6(11, 0x04200, 0x00140, 'Misc'),
        _Block6(12, 0x04400, 0x00440, 'BoxLayout'),
        _Block6(13, 0x04A00, 0x00574, 'BattleBox'),
        _Block6(14, 0x05000, 0x04E28, 'PSS1'),
        _Block6(15, 0x0A000, 0x04E28, 'PSS2'),
        _Block6(16, 0x0F000, 0x04E28, 'PSS3'),
        _Block6(17, 0x14000, 0x00170, 'MyStatus'),
        _Block6(18, 0x14200, 0x0061C, 'PokeParty'),
        _Block6(19, 0x14A00, 0x00504, 'EventWork'),
        _Block6(20, 0x15000, 0x006A0, 'Zukan'),
        _Block6(21, 0x15800, 0x00644, 'Hologram'),
        _Block6(22, 0x16000, 0x00104, 'UnionPokemon'),
        _Block6(23, 0x16200, 0x00004, 'ConfigSave'),
        _Block6(24, 0x16400, 0x00420, 'AmieDecoration'),
        _Block6(25, 0x16A00, 0x00064, 'OPower'),
        _Block6(26, 0x16C00, 0x003F0, 'StrengthRock'),
        _Block6(27, 0x17000, 0x0070C, 'TrainerPRVideo'),
        _Block6(28, 0x17800, 0x00180, 'GtsData'),
        _Block6(29, 0x17A00, 0x00004, 'PackedMenuBits'),
        _Block6(30, 0x17C00, 0x0000C, 'PSSProfileQA'),
        _Block6(31, 0x17E00, 0x00048, 'RepelInfo'),
        _Block6(32, 0x18000, 0x00054, 'BossFetch'),
        _Block6(33, 0x18200, 0x00644, 'Streetpass'),
        _Block6(34, 0x18A00, 0x005C8, 'BattleSpot'),
        _Block6(35, 0x19000, 0x002F8, 'MACLog'),
        _Block6(36, 0x19400, 0x01B40, 'HallOfFame'),
        _Block6(37, 0x1B000, 0x001F4, 'Maison'),
        _Block6(38, 0x1B200, 0x001F0, 'Daycare'),
        _Block6(39, 0x1B400, 0x00216, 'BattleInstitute'),
        _Block6(40, 0x1B800, 0x00390, 'BerryField'),
        _Block6(41, 0x1BC00, 0x01A90, 'MysteryGift'),
        _Block6(42, 0x1D800, 0x00308, 'SubEventLog'),
        _Block6(43, 0x1DC00, 0x00618, 'PokeDiary'),
        _Block6(44, 0x1E400, 0x0025C, 'Record'),
        _Block6(45, 0x1E800, 0x00834, 'FriendSafari'),
        _Block6(46, 0x1F200, 0x00318, 'SuperTrain'),
        _Block6(47, 0x1F600, 0x007D0, 'Unused'),
        _Block6(48, 0x1FE00, 0x00C48, 'LinkInfo'),
        _Block6(49, 0x20C00, 0x00078, 'PSSUsage'),
        _Block6(50, 0x20E00, 0x00200, 'GameSync'),
        _Block6(51, 0x21000, 0x00C84, 'PSSIcon'),
        _Block6(52, 0x21E00, 0x00628, 'Validation'),
        _Block6(53, 0x22600, 0x34AD0, 'Box'),
        _Block6(54, 0x57200, 0x0E058, 'JPEG'),
      ];

  static List<_Block6> _tableORAS() => const [
        _Block6(0, 0x00000, 0x002C8, 'Puff'),
        _Block6(1, 0x00400, 0x00B90, 'MyItem'),
        _Block6(2, 0x01000, 0x0002C, 'ItemInfo'),
        _Block6(3, 0x01200, 0x00038, 'GameTime'),
        _Block6(4, 0x01400, 0x00150, 'Situation'),
        _Block6(5, 0x01600, 0x00004, 'RandomGroup'),
        _Block6(6, 0x01800, 0x00008, 'PlayTime'),
        _Block6(7, 0x01A00, 0x001C0, 'Fashion'),
        _Block6(8, 0x01C00, 0x000BE, 'Amie'),
        _Block6(9, 0x01E00, 0x00024, 'Temp'),
        _Block6(10, 0x02000, 0x02100, 'FieldMoveModel'),
        _Block6(11, 0x04200, 0x00130, 'Misc'),
        _Block6(12, 0x04400, 0x00440, 'BoxLayout'),
        _Block6(13, 0x04A00, 0x00574, 'BattleBox'),
        _Block6(14, 0x05000, 0x04E28, 'PSS1'),
        _Block6(15, 0x0A000, 0x04E28, 'PSS2'),
        _Block6(16, 0x0F000, 0x04E28, 'PSS3'),
        _Block6(17, 0x14000, 0x00170, 'MyStatus'),
        _Block6(18, 0x14200, 0x0061C, 'PokeParty'),
        _Block6(19, 0x14A00, 0x00504, 'EventWork'),
        _Block6(20, 0x15000, 0x011CC, 'Zukan'),
        _Block6(21, 0x16200, 0x00644, 'Hologram'),
        _Block6(22, 0x16C00, 0x00104, 'UnionPokemon'),
        _Block6(23, 0x16E00, 0x00004, 'ConfigSave'),
        _Block6(24, 0x16E00, 0x00420, 'AmieDecoration'),
        _Block6(25, 0x17400, 0x00064, 'OPower'),
        _Block6(26, 0x17600, 0x003F0, 'StrengthRock'),
        _Block6(27, 0x17A00, 0x0070C, 'TrainerPRVideo'),
        _Block6(28, 0x18200, 0x00180, 'GtsData'),
        _Block6(29, 0x18400, 0x00004, 'PackedMenuBits'),
        _Block6(30, 0x18600, 0x0000C, 'PSSProfileQA'),
        _Block6(31, 0x18800, 0x00048, 'RepelInfo'),
        _Block6(32, 0x18A00, 0x00054, 'BossFetch'),
        _Block6(33, 0x18C00, 0x00644, 'Streetpass'),
        _Block6(34, 0x19400, 0x005C8, 'BattleSpot'),
        _Block6(35, 0x19A00, 0x002F8, 'MACLog'),
        _Block6(36, 0x19E00, 0x01B40, 'HallOfFame'),
        _Block6(37, 0x1BA00, 0x001F4, 'Maison'),
        _Block6(38, 0x1BC00, 0x003E0, 'Daycare'),
        _Block6(39, 0x1C000, 0x00216, 'BattleInstitute'),
        _Block6(40, 0x1C400, 0x00640, 'BerryField'),
        _Block6(41, 0x1CC00, 0x01A90, 'MysteryGift'),
        _Block6(42, 0x1E800, 0x00400, 'SubEventLog'),
        _Block6(43, 0x1EC00, 0x00618, 'PokeDiary'),
        _Block6(44, 0x1F400, 0x0025C, 'Record'),
        _Block6(45, 0x1F800, 0x00834, 'FriendSafari'),
        _Block6(46, 0x20200, 0x00318, 'SuperTrain'),
        _Block6(47, 0x20600, 0x007D0, 'Unused'),
        _Block6(48, 0x20E00, 0x00C48, 'LinkInfo'),
        _Block6(49, 0x21C00, 0x00078, 'PSSUsage'),
        _Block6(50, 0x21E00, 0x00200, 'GameSync'),
        _Block6(51, 0x22000, 0x00C84, 'PSSIcon'),
        _Block6(52, 0x22E00, 0x00628, 'Validation'),
        _Block6(53, 0x23600, 0x00400, 'Contest'),
        _Block6(54, 0x23A00, 0x07AD0, 'SecretBase'),
        _Block6(55, 0x2B600, 0x078B0, 'EonTicket'),
        _Block6(56, 0x33000, 0x34AD0, 'Box'),
        _Block6(57, 0x67C00, 0x0E058, 'JPEG'),
      ];
}

class _Block6 {
  final int id;
  final int offset;
  final int length;
  final String name;
  const _Block6(this.id, this.offset, this.length, this.name);
}

/// A Gen 6 trainer identity (subset of MyStatus6).
class Gen6Trainer {
  final String name;
  final int tid, sid, gender, language;
  const Gen6Trainer({
    required this.name,
    required this.tid,
    required this.sid,
    this.gender = 0,
    this.language = 2,
  });
}

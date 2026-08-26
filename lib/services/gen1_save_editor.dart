import 'dart:typed_data';

import 'pk1.dart'
    show gen1DecodeText, gen1EncodeText, kGen1Terminator, Pk1;

/// Read/write access to a Gen 1 (Red / Blue / Yellow, English) `.sav`.
///
/// Mirrors [Gen3SaveEditor]'s API (load / verifyChecksums / boxSlot /
/// writeBoxSlot / addBoxMon / markCaught / markSeen / toBytes). Operates on a
/// COPY of the caller's bytes; nothing is written until a caller asks.
///
/// Format (Bulbapedia "Save data structure (Generation I)"): 32 KB SRAM. The
/// main save data spans 0x2598..0x3522 and is the ONLY region protected by the
/// single 8-bit checksum stored at 0x3523. PC boxes 1-12 live in banks 2 and 3
/// (0x4000 / 0x6000) and are NOT checksummed in Gen 1. The currently-open box
/// also has a working copy at 0x30C0 (inside the checksummed region).
class Gen1SaveEditor {
  final Uint8List bytes;

  Gen1SaveEditor._(this.bytes);

  // ---- main data (bank 1) ----
  static const int mainDataStart = 0x2598; // trainer name; start of checksum
  static const int mainDataEnd = 0x3522; // last checksummed byte (inclusive)
  static const int checksumOffset = 0x3523;
  static const int trainerNameOffset = 0x2598; // 11 bytes
  static const int dexOwnedOffset = 0x25A3; // 19 bytes
  static const int dexSeenOffset = 0x25B6; // 19 bytes
  static const int moneyOffset = 0x25F3; // 3 bytes BCD
  static const int rivalNameOffset = 0x25F6; // 11 bytes
  static const int trainerIdOffset = 0x2605; // 2 bytes BE
  static const int partyOffset = 0x2F2C; // 0x194 bytes
  static const int currentBoxOffset = 0x30C0; // 0x462 bytes
  static const int currentBoxNumberOffset = 0x284C; // low 7 bits = box 0..11
  static const int dexBytes = 19;
  static const int speciesCount = 151;

  // ---- box layout ----
  static const int boxCount = 12;
  static const int boxCapacity = 20; // slots per box
  static const int boxSize = 0x462; // 1122 bytes
  static const int bank2Start = 0x4000; // boxes 1..6
  static const int bank3Start = 0x6000; // boxes 7..12
  // within a box:
  static const int _boxCountOfs = 0x00;
  static const int _boxSpeciesListOfs = 0x01; // count entries + 0xFF terminator
  static const int _boxRecordsOfs = 0x16; // 20 * 33
  static const int _boxOtNamesOfs = 0x2AA; // 20 * 11
  static const int _boxNicknamesOfs = 0x386; // 20 * 11
  static const int _nameLen = 11;

  /// Physical file offset of PC box [index] (0..11) in its bank.
  static int boxOffset(int index) => index < 6
      ? bank2Start + index * boxSize
      : bank3Start + (index - 6) * boxSize;

  /// Parse a raw SRAM image into an editor. Throws [FormatException] if the
  /// file is too small. Works on a COPY so the caller's bytes are safe.
  factory Gen1SaveEditor.load(Uint8List raw) {
    if (raw.length < 0x8000) {
      throw const FormatException('Not a Gen 1 SRAM save (expected 32 KB).');
    }
    return Gen1SaveEditor._(Uint8List.fromList(raw));
  }

  // ---- checksum ----
  /// Gen 1 main-data checksum: sum every byte from 0x2598..0x3522, then invert
  /// the low byte (~sum & 0xFF).
  int computeChecksum() {
    var sum = 0;
    for (var i = mainDataStart; i <= mainDataEnd; i++) {
      sum = (sum + bytes[i]) & 0xFF;
    }
    return (~sum) & 0xFF;
  }

  int get storedChecksum => bytes[checksumOffset];

  /// SAFE self-check: the recomputed main-data checksum must equal the stored
  /// one. If this fails on a real save, the range/formula is wrong — do not
  /// trust writes until it passes.
  ({bool ok, int computed, int stored}) verifyChecksums() {
    final got = computeChecksum();
    return (ok: got == storedChecksum, computed: got, stored: storedChecksum);
  }

  /// Recompute and store the main-data checksum. Call after any edit inside
  /// 0x2598..0x3522 (name, dex, party, money, current-box copy).
  void fixChecksum() => bytes[checksumOffset] = computeChecksum();

  // ---- trainer / ids ----
  String get trainerName => gen1DecodeText(bytes, trainerNameOffset, _nameLen);
  String get rivalName => gen1DecodeText(bytes, rivalNameOffset, _nameLen);
  int get trainerId => (bytes[trainerIdOffset] << 8) | bytes[trainerIdOffset + 1];

  void setTrainerName(String name) {
    gen1EncodeText(bytes, trainerNameOffset, _nameLen, name);
    fixChecksum();
  }

  // ---- Pokédex flags ----
  void _setDexBit(int ofs, int nationalDex) {
    final i = nationalDex - 1;
    if (i < 0 || i >= speciesCount) return;
    bytes[ofs + (i >> 3)] |= (1 << (i & 7));
  }

  bool _getDexBit(int ofs, int nationalDex) {
    final i = nationalDex - 1;
    if (i < 0 || i >= speciesCount) return false;
    return (bytes[ofs + (i >> 3)] & (1 << (i & 7))) != 0;
  }

  int _countDex(int ofs) {
    var n = 0;
    for (var d = 1; d <= speciesCount; d++) {
      if (_getDexBit(ofs, d)) n++;
    }
    return n;
  }

  int get caughtCount => _countDex(dexOwnedOffset);
  int get seenCount => _countDex(dexSeenOffset);
  bool isCaught(int nationalDex) => _getDexBit(dexOwnedOffset, nationalDex);
  bool isSeen(int nationalDex) => _getDexBit(dexSeenOffset, nationalDex);

  /// Mark a species (National dex) SEEN.
  void markSeen(int nationalDex) {
    _setDexBit(dexSeenOffset, nationalDex);
    fixChecksum();
  }

  /// Mark a species (National dex) caught — sets owned AND seen (a caught mon
  /// is always seen), then fixes the checksum.
  void markCaught(int nationalDex) {
    _setDexBit(dexOwnedOffset, nationalDex);
    _setDexBit(dexSeenOffset, nationalDex);
    fixChecksum();
  }

  // ---- boxes ----
  /// Current box number (0..11) from 0x284C (low 7 bits).
  int get currentBoxNumber => bytes[currentBoxNumberOffset] & 0x7F;

  /// Number of Pokémon stored in box [index] (0..11).
  int boxMonCount(int index) => bytes[boxOffset(index) + _boxCountOfs];

  /// Read PC box slot [slot] of box [index] as its 33-byte in-box record.
  Uint8List boxSlot(int index, int slot) {
    final base = boxOffset(index) + _boxRecordsOfs + slot * Pk1.recordSize;
    return Uint8List.fromList(bytes.sublist(base, base + Pk1.recordSize));
  }

  /// Read a full [Pk1] (record + OT/nickname strings) from box [index] slot.
  Pk1 boxMon(int index, int slot) {
    final b = boxOffset(index);
    return Pk1.decode(
      boxSlot(index, slot),
      otName: gen1DecodeText(bytes, b + _boxOtNamesOfs + slot * _nameLen, _nameLen),
      nickname:
          gen1DecodeText(bytes, b + _boxNicknamesOfs + slot * _nameLen, _nameLen),
    );
  }

  /// Overwrite box [index] slot [slot] with a 33-byte record (record only;
  /// species list, count, and name arrays are managed by [addBoxMon]).
  /// Boxes in banks 2/3 are not checksummed; the current-box copy at 0x30C0 is,
  /// so a checksum fix is applied when [index] is the current box.
  void writeBoxSlot(int index, int slot, Uint8List record) {
    final base = boxOffset(index) + _boxRecordsOfs + slot * Pk1.recordSize;
    bytes.setRange(base, base + Pk1.recordSize, record);
    if (index == currentBoxNumber) fixChecksum();
  }

  /// Append a Pokémon (33-byte in-box record + OT/nickname) to the first
  /// NON-current box that has a free slot. Skipping the current box avoids the
  /// 0x30C0 working-copy sync issue. Writes the record, the species-list entry,
  /// the 0xFF terminator, the OT-name/nickname arrays, and bumps the count.
  ///
  /// Returns the box index and slot it landed in, or null if every non-current
  /// box is full.
  ({int box, int slot})? addBoxMon(Uint8List record,
      {String otName = '', String nickname = ''}) {
    final current = currentBoxNumber;
    for (var box = 0; box < boxCount; box++) {
      if (box == current) continue;
      final b = boxOffset(box);
      final count = bytes[b + _boxCountOfs];
      if (count >= boxCapacity) continue;

      final internalSpecies = record[0]; // Gen 1 internal index

      // record
      final recBase = b + _boxRecordsOfs + count * Pk1.recordSize;
      bytes.setRange(recBase, recBase + Pk1.recordSize, record);

      // species list: entry at count, 0xFF terminator right after
      bytes[b + _boxSpeciesListOfs + count] = internalSpecies;
      bytes[b + _boxSpeciesListOfs + count + 1] = 0xFF;

      // OT name + nickname (11-byte fields, 0x50-terminated)
      gen1EncodeText(bytes, b + _boxOtNamesOfs + count * _nameLen, _nameLen, otName);
      gen1EncodeText(
          bytes, b + _boxNicknamesOfs + count * _nameLen, _nameLen, nickname);

      // bump count
      bytes[b + _boxCountOfs] = count + 1;

      return (box: box, slot: count);
    }
    return null;
  }

  /// Initialise an empty box [index] (count 0, species-list terminator 0xFF).
  void clearBox(int index) {
    final b = boxOffset(index);
    bytes[b + _boxCountOfs] = 0;
    bytes[b + _boxSpeciesListOfs] = 0xFF;
    if (index == currentBoxNumber) fixChecksum();
  }

  /// The edited save bytes (edits applied in place on the loaded copy).
  Uint8List toBytes() => bytes;

  // expose so callers can double-check name terminators if needed
  static int get nameTerminator => kGen1Terminator;
}

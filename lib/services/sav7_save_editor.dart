import 'dart:typed_data';

import 'gen7_text.dart';
import 'pk7.dart';

/// Read (+ box-inject) access to a decrypted Gen 7 "main" save.
///
/// FILE: a 3DS "main" export (JKSM / Checkpoint / godmode9) is already plain —
/// PKHeX does NOT whole-file-decrypt it; it only validates per-block CRCs and a
/// whole-file MemeCrypto signature. Sizes (SaveUtil.SIZE_G7*):
///   • Sun/Moon (SAV7SM):        0x6BE00 = 441,856 bytes
///   • Ultra Sun/Moon (SAV7USUM): 0x6CC00 = 445,440 bytes
/// The two are told apart by file size alone (both carry the "BEEF" footer).
///
/// LAYOUT: the save is a list of fixed blocks (SaveBlockAccessor7SM/USUM). USUM
/// shifted every block by +0x200 vs SM. The block-checksum metadata table sits
/// in the last 0x200 bytes: BlockMetadataOffset = size - 0x200. Per PKHeX each
/// block's CRC16 is written at  BlockMetadataOffset + 0x14 + id*8 + 6  (entry =
/// {u32 len, u16 id, u16 chk}). Gen 7 blocks use CRC16-CCITT.
///
/// WRITE CAVEAT (read this before shipping an injector): a save edited on-disk
/// will NOT load on a real console / Citra until (a) every touched block's CRC
/// is refreshed in the metadata table AND (b) the whole file is re-signed with
/// **MemeCrypto** (SHA-256 + AES + a static RSA-2048 key PKHeX embeds). This
/// class refreshes block CRCs; it does **not** implement MemeCrypto (that port
/// is a separate task — flagged). Reading (sync) needs neither.
class Sav7SaveEditor {
  final Uint8List bytes;
  final bool isUSUM;

  Sav7SaveEditor._(this.bytes, this.isUSUM);

  static const int sizeSM = 0x6BE00; // 441,856
  static const int sizeUSUM = 0x6CC00; // 445,440

  // ---- per-version absolute block offsets (SaveBlockAccessor7SM / 7USUM) ----
  // Block ids are identical between versions; USUM is uniformly +0x200.
  int get _shift => isUSUM ? 0x200 : 0x000;

  int get myStatusOffset => 0x1200 + _shift; // MyStatus (trainer card) — id 3
  int get partyOffset => 0x1400 + _shift; // PokePartySave — id 4
  int get dexOffset => 0x2A00 + _shift; // ZukanData (Pokédex) — id 6
  int get eventWorkOffset => 0x1C00 + _shift; // EventWork — id 5
  int get miscOffset => 0x4000 + _shift; // Misc — id 9
  int get boxOffset => 0x4E00 + _shift; // BoxPokemon (PC storage) — id 14

  // ---- box geometry: 32 boxes × 30 slots × 232, CONTIGUOUS (no per-box gap) --
  static const int boxCount = 32;
  static const int perBox = 30;
  static const int slotSize = Pk7.sizeStored; // 232
  int get totalSlots => boxCount * perBox; // 960

  // ---- party: 6 slots of 260, count byte after the 6th (Party + 6*260) ------
  static const int partySlotSize = Pk7.sizeParty; // 260
  int get partyCountOffset => partyOffset + 6 * partySlotSize; // +0x618

  // ---- dex: caught/owned bit region is +0x88 into the Zukan block -----------
  // (Zukan7: OFS_CAUGHT = SIZE_MAGIC(4)+SIZE_FLAGS(4)+SIZE_MISC(0x80) = 0x88.)
  static const int dexOwnedRel = 0x88;
  int get dexOwnedOffset => dexOffset + dexOwnedRel;
  int get maxSpecies => isUSUM ? 807 : 802; // National dex ceiling

  // ---- MyStatus7 field offsets (relative to the block) ---------------------
  static const int _msTid = 0x00; // u16
  static const int _msSid = 0x02; // u16
  static const int _msOtName = 0x38; // UTF-16, 12 chars

  // ---- block-checksum metadata ---------------------------------------------
  int get blockMetadataOffset => bytes.length - 0x200;
  static const int boxBlockId = 14;

  static int _u16(Uint8List b, int o) => b[o] | (b[o + 1] << 8);
  void _setU16(int o, int v) {
    bytes[o] = v & 0xFF;
    bytes[o + 1] = (v >> 8) & 0xFF;
  }

  /// Parse a Gen 7 save. [versionId] ∈ {sun, moon, ultrasun, ultramoon}
  /// (aliases: us, um, usum). Size is validated but the BEEF footer is NOT
  /// required, so a zero-filled synthetic buffer of the right size also loads.
  factory Sav7SaveEditor.load(Uint8List raw, String versionId) {
    final v = versionId.toLowerCase().replaceAll(' ', '');
    final usumId = v == 'ultrasun' ||
        v == 'ultramoon' ||
        v == 'us' ||
        v == 'um' ||
        v == 'usum';
    final expected = usumId ? sizeUSUM : sizeSM;
    if (raw.length != expected) {
      // Accept the other size if it matches, else complain.
      if (raw.length == sizeSM && !usumId) {
        // ok
      } else if (raw.length == sizeUSUM && usumId) {
        // ok
      } else {
        throw FormatException(
            'Gen 7 save size mismatch: got 0x${raw.length.toRadixString(16)}, '
            'expected 0x${expected.toRadixString(16)} for "$versionId".');
      }
    }
    return Sav7SaveEditor._(Uint8List.fromList(raw), usumId);
  }

  // -------------------------------------------------------------- CRC16-CCITT
  /// CRC16-CCITT (init 0xFFFF, poly 0x1021, MSB-first, no reflection) over
  /// bytes `[start, start+len)`. This is the routine Gen 6/7 3DS block metadata
  /// uses. (Whether Gen 7 applies a final ~chk inversion — PKHeX's `CRC16Invert`
  /// vs `CRC16_CCITT` — should be confirmed against a real save before relying
  /// on the WRITE path; it does not affect any read/sync feature. See
  /// [invertBlockCrc].)
  static bool invertBlockCrc = false;
  static int crc16ccitt(Uint8List b, int start, int len) {
    var chk = 0xFFFF;
    for (var i = 0; i < len; i++) {
      chk ^= (b[start + i] << 8);
      for (var j = 0; j < 8; j++) {
        if ((chk & 0x8000) != 0) {
          chk = ((chk << 1) ^ 0x1021) & 0xFFFF;
        } else {
          chk = (chk << 1) & 0xFFFF;
        }
      }
    }
    return (invertBlockCrc ? (~chk) : chk) & 0xFFFF;
  }

  /// Where block [id]'s CRC16 lives in the footer metadata table.
  int _blockChecksumOffset(int id) => blockMetadataOffset + 0x14 + id * 8 + 6;

  /// Refresh block [id]'s CRC16 given its data [offset]/[len].
  void fixBlockChecksum(int id, int offset, int len) {
    final crc = crc16ccitt(bytes, offset, len);
    _setU16(_blockChecksumOffset(id), crc);
  }

  /// Refresh the BoxPokemon block's CRC (id 14) after a box write. Length is the
  /// full PC region: 32*30*232 = 0x36600.
  void fixBoxChecksum() =>
      fixBlockChecksum(boxBlockId, boxOffset, totalSlots * slotSize);

  /// Read-only self-check of the stored CRC for a given block. Returns
  /// (ok, computed, stored).
  ({bool ok, int computed, int stored}) verifyBlockChecksum(
      int id, int offset, int len) {
    final computed = crc16ccitt(bytes, offset, len);
    final stored = _u16(bytes, _blockChecksumOffset(id));
    return (ok: computed == stored, computed: computed, stored: stored);
  }

  /// Verify the box block only (the one this editor writes). A fuller
  /// verifyChecksums() over every block needs the complete id/offset/len table.
  ({bool ok, int computed, int stored}) verifyChecksums() =>
      verifyBlockChecksum(boxBlockId, boxOffset, totalSlots * slotSize);

  // ------------------------------------------------------------------- trainer
  Sav7Trainer trainer() => Sav7Trainer(
        name: gen7DecodeText(bytes, myStatusOffset + _msOtName, 12),
        tid: _u16(bytes, myStatusOffset + _msTid),
        sid: _u16(bytes, myStatusOffset + _msSid),
      );

  int get tid => _u16(bytes, myStatusOffset + _msTid);
  int get sid => _u16(bytes, myStatusOffset + _msSid);
  String get otName => gen7DecodeText(bytes, myStatusOffset + _msOtName, 12);

  // --------------------------------------------------------------- PC boxes
  int boxSlotOffset(int globalIndex) => boxOffset + globalIndex * slotSize;

  Uint8List rawSlot(int globalIndex) {
    final o = boxSlotOffset(globalIndex);
    return Uint8List.fromList(bytes.sublist(o, o + slotSize));
  }

  Pk7? boxMon(int globalIndex) {
    final mon = Pk7.decode(rawSlot(globalIndex));
    return mon.isEmpty ? null : mon;
  }

  void writeSlot(int globalIndex, Uint8List block) {
    final o = boxSlotOffset(globalIndex);
    bytes.setRange(o, o + block.length.clamp(0, slotSize), block);
    fixBoxChecksum();
  }

  /// Inject an (encrypted, 232-byte) mon into the first empty PC slot, scanning
  /// global slots 0..959. Returns the slot index used, or -1 if full. Refreshes
  /// the box block CRC (NOT MemeCrypto — see class doc).
  int addBoxMon(Uint8List block) {
    for (var i = 0; i < totalSlots; i++) {
      if (Pk7.decode(rawSlot(i)).isEmpty) {
        writeSlot(i, block);
        return i;
      }
    }
    return -1;
  }

  // ----------------------------------------------------------------- party
  int get partyCount => bytes[partyCountOffset].clamp(0, 6);

  Uint8List partySlotRaw(int i) {
    final o = partyOffset + i * partySlotSize;
    return Uint8List.fromList(bytes.sublist(o, o + partySlotSize));
  }

  /// The active team as (species, level) pairs (level read from the stored
  /// party-stat byte 0xEC after decryption).
  List<({int species, int level})> party() {
    final out = <({int species, int level})>[];
    final n = partyCount;
    for (var i = 0; i < n; i++) {
      final mon = Pk7.decode(partySlotRaw(i));
      if (mon.isEmpty) continue;
      out.add((species: mon.species, level: mon.partyLevel));
    }
    return out;
  }

  // -------------------------------------------------------------- Pokédex
  bool caught(int species) {
    if (species < 1 || species > maxSpecies) return false;
    final bit = species - 1;
    final byte = bytes[dexOwnedOffset + (bit >> 3)];
    return (byte >> (bit & 7)) & 1 == 1;
  }

  /// Set/clear an owned bit (used by tests; the sync app is read-only).
  void setCaught(int species, [bool value = true]) {
    if (species < 1 || species > maxSpecies) return;
    final bit = species - 1;
    final o = dexOwnedOffset + (bit >> 3);
    if (value) {
      bytes[o] = bytes[o] | (1 << (bit & 7));
    } else {
      bytes[o] = bytes[o] & ~(1 << (bit & 7));
    }
  }

  /// Number of OWNED (caught) National-dex species, 1..[maxSpecies]. Forms and
  /// the four "seen" arrays live in separate regions and are excluded here.
  int caughtDexCount() {
    var n = 0;
    for (var s = 1; s <= maxSpecies; s++) {
      if (caught(s)) n++;
    }
    return n;
  }

  // ------------------------------------------------- "badge"-equivalent proxy
  /// Gen 7 has NO gyms/badges and PKHeX exposes no first-class badge counter.
  /// Story progress (Grand Trials cleared, 0..4) lives in EventWork event flags,
  /// whose exact indices are game-specific and NOT verified here. This returns a
  /// best-effort count from caller-supplied Grand-Trial flag indices; with none
  /// supplied it returns 0. Wire real indices once confirmed against a save.
  ///
  /// EventWork block starts at [eventWorkOffset]; the flag bit region within it
  /// still needs a verified base offset before [eventFlag] is trustworthy.
  int progressCount({List<int>? grandTrialFlagIndices, int? flagRegionBase}) {
    if (grandTrialFlagIndices == null || flagRegionBase == null) return 0;
    var n = 0;
    for (final idx in grandTrialFlagIndices) {
      if (eventFlag(idx, flagRegionBase)) n++;
    }
    return n;
  }

  /// Read event flag [index] given the absolute [flagRegionBase] of the flag
  /// bit array. Provided so the app can wire Grand-Trial flags once verified.
  bool eventFlag(int index, int flagRegionBase) {
    final o = flagRegionBase + (index >> 3);
    if (o >= bytes.length) return false;
    return (bytes[o] >> (index & 7)) & 1 == 1;
  }

  Uint8List toBytes() => bytes;
}

/// A Gen 7 trainer identity (subset of MyStatus7).
class Sav7Trainer {
  final String name;
  final int tid, sid;
  const Sav7Trainer({required this.name, required this.tid, required this.sid});
}

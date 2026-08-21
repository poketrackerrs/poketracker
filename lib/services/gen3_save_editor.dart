import 'dart:typed_data';

import 'pk3.dart' show gen3DecodeText, gen3EncodeText;

/// Read/write access to a Gen 3 (RSE / FRLG / Emerald) `.sav`.
///
/// This is the foundation of the in-app save editor. It maps the rotated
/// sections, computes the per-section checksum, and (once verified on real
/// saves) writes edits back safely. NOTHING here mutates the file until a
/// caller explicitly asks — and [verifyChecksums] must pass first.
///
/// Format (Bulbapedia / PKHeX): 128 KB file = two 0xE000 save blocks (A @ 0,
/// B @ 0xE000). The block with the higher save-index is active. Each block is
/// 14 sections of 0x1000; a section stores its id at 0xFF4, signature
/// 0x08012025 at 0xFF8, save index at 0xFFC, and a 16-bit checksum at 0xFF6
/// over the section's used byte range.
class Gen3SaveEditor {
  final Uint8List bytes;
  final int base; // physical offset of the active block (0 or 0xE000)
  final Map<int, int> sectionOffset; // section id -> physical offset

  Gen3SaveEditor._(this.bytes, this.base, this.sectionOffset);

  static const int _signature = 0x08012025;
  static const int _blockSize = 0xE000;
  static const int _sectionSize = 0x1000;

  /// Used-byte length of each section id (the region the checksum covers).
  /// Ids 5..13 all use 0xF80. Confirmed against real saves before writes ship.
  static const Map<int, int> _usedSize = {
    0: 0xF2C, 1: 0xF80, 2: 0xF80, 3: 0xF80, 4: 0xF08,
    5: 0xF80, 6: 0xF80, 7: 0xF80, 8: 0xF80, 9: 0xF80,
    10: 0xF80, 11: 0xF80, 12: 0xF80, 13: 0x7D0,
  };

  static int _u16(Uint8List b, int o) => b[o] | (b[o + 1] << 8);
  static int _u32(Uint8List b, int o) =>
      b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);
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

  /// Parse a raw save into an editor. Throws [FormatException] if it isn't a
  /// recognisable GBA save. Operates on a COPY so the caller's bytes are safe.
  factory Gen3SaveEditor.load(Uint8List raw) {
    if (raw.length < 0x20000) {
      throw const FormatException('Not a GBA save (expected at least 128 KB).');
    }
    final b = Uint8List.fromList(raw);

    int saveIndexOf(int base) {
      if (_u32(b, base + 0xFF8) != _signature) return -1;
      final idx = _u32(b, base + 0xFFC);
      return idx == 0xFFFFFFFF ? -1 : idx;
    }

    final a = saveIndexOf(0x0000);
    final c = saveIndexOf(_blockSize);
    if (a < 0 && c < 0) {
      throw const FormatException('No valid GBA save block found.');
    }
    final base = (c > a) ? _blockSize : 0x0000;

    final sectionOffset = <int, int>{};
    for (var slot = 0; slot < 14; slot++) {
      final so = base + slot * _sectionSize;
      if (_u32(b, so + 0xFF8) != _signature) continue;
      sectionOffset[_u16(b, so + 0xFF4)] = so;
    }
    if (sectionOffset[0] == null) {
      throw const FormatException('GBA save trainer section (0) missing.');
    }
    return Gen3SaveEditor._(b, base, sectionOffset);
  }

  /// Gen 3 section checksum: sum the used bytes as 32-bit little-endian words,
  /// then fold the high 16 bits into the low 16 bits.
  int computeChecksum(int sectionId) {
    final ofs = sectionOffset[sectionId];
    if (ofs == null) return 0;
    final used = _usedSize[sectionId]!;
    var sum = 0;
    for (var i = 0; i < used; i += 4) {
      sum = (sum + _u32(bytes, ofs + i)) & 0xFFFFFFFF;
    }
    return ((sum & 0xFFFF) + (sum >> 16)) & 0xFFFF;
  }

  int storedChecksum(int sectionId) =>
      _u16(bytes, sectionOffset[sectionId]! + 0xFF6);

  /// SAFE self-check: every present section's recomputed checksum must equal
  /// the one stored in the file. If this fails on a real save, the checksum
  /// algorithm or the used-size table is wrong — DO NOT write until it passes.
  ({bool ok, List<String> mismatches}) verifyChecksums() {
    final bad = <String>[];
    for (final id in sectionOffset.keys) {
      final got = computeChecksum(id), want = storedChecksum(id);
      if (got != want) {
        bad.add('section $id: computed '
            '0x${got.toRadixString(16)} != stored 0x${want.toRadixString(16)}');
      }
    }
    return (ok: bad.isEmpty, mismatches: bad);
  }

  // ---------------------------------------------------------------- editing
  // Per-game offsets. Emerald is VERIFIED against a real save; RS/FRLG are from
  // Bulbapedia/PKHeX and must be confirmed on real saves before trusting writes.
  int _s(int id) => sectionOffset[id]!;

  _Gen3Offsets _ofsFor(String versionId) {
    switch (versionId) {
      case 'emerald':
        return const _Gen3Offsets(
            keyOfs: 0x00AC, money: 0x0490,
            seen1: 0x005C, seen2Sec: 1, seen2: 0x0988,
            seen3Sec: 4, seen3: 0x0CA4);
      case 'firered':
      case 'leafgreen':
        return const _Gen3Offsets(
            keyOfs: 0x0AF8, money: 0x0290,
            seen1: 0x005C, seen2Sec: 1, seen2: 0x05F8,
            seen3Sec: 4, seen3: 0x0B98);
      default: // ruby / sapphire
        return const _Gen3Offsets(
            keyOfs: -1, money: 0x0490,
            seen1: 0x005C, seen2Sec: 1, seen2: 0x0938,
            seen3Sec: 4, seen3: 0x0C0C);
    }
  }

  /// FRLG/Emerald XOR many values with a per-save "security key" (RS: none).
  int _securityKey(_Gen3Offsets o) => o.keyOfs < 0 ? 0 : _u32(bytes, _s(0) + o.keyOfs);

  int getMoney(String versionId) {
    final o = _ofsFor(versionId);
    return (_u32(bytes, _s(1) + o.money) ^ _securityKey(o)) & 0xFFFFFFFF;
  }

  void setMoney(String versionId, int value) {
    final o = _ofsFor(versionId);
    final v = value.clamp(0, 999999);
    _setU32(_s(1) + o.money, (v ^ _securityKey(o)) & 0xFFFFFFFF);
    fixChecksum(1);
  }

  // ---- Trainer info (section 0; offsets are the same across RSE/FRLG) ----
  // name @0x00 (7), gender @0x08 (0=M/1=F), TID @0x0A, SID @0x0C,
  // playtime hours @0x0E (u16), minutes @0x10, seconds @0x11.
  Gen3Trainer trainer() => Gen3Trainer(
        name: gen3DecodeText(bytes, _s(0) + 0x00, 7),
        gender: bytes[_s(0) + 0x08] & 1,
        tid: _u16(bytes, _s(0) + 0x0A),
        sid: _u16(bytes, _s(0) + 0x0C),
        hours: _u16(bytes, _s(0) + 0x0E),
        minutes: bytes[_s(0) + 0x10],
      );

  void setTrainer(Gen3Trainer t) {
    gen3EncodeText(bytes, _s(0) + 0x00, 7, t.name);
    bytes[_s(0) + 0x08] = t.gender & 1;
    _setU16(_s(0) + 0x0A, t.tid & 0xFFFF);
    _setU16(_s(0) + 0x0C, t.sid & 0xFFFF);
    _setU16(_s(0) + 0x0E, t.hours.clamp(0, 999) & 0xFFFF);
    bytes[_s(0) + 0x10] = t.minutes.clamp(0, 59);
    fixChecksum(0);
  }

  static const int _dexBytes = 49; // 386 species -> 49 bytes
  int get caughtCount => _countBits(_s(0) + 0x28, _dexBytes);

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

  void _setDexBit(int ofs, int dexIndex) {
    // dexIndex is 0-based (national dex number - 1)
    bytes[ofs + (dexIndex >> 3)] |= (1 << (dexIndex & 7));
  }

  /// Mark a species (national dex number) caught — sets the owned bit and all
  /// three "seen" mirrors (kept in sync or the game sanitises them).
  void markCaught(String versionId, int nationalDex) {
    final o = _ofsFor(versionId);
    final i = nationalDex - 1;
    if (i < 0 || i >= 386) return;
    _setDexBit(_s(0) + 0x28, i); // owned
    _setDexBit(_s(0) + o.seen1, i);
    _setDexBit(_s(o.seen2Sec) + o.seen2, i);
    _setDexBit(_s(o.seen3Sec) + o.seen3, i);
    fixChecksum(0);
    fixChecksum(o.seen2Sec);
    fixChecksum(o.seen3Sec);
  }

  /// Mark every species 1..386 caught + seen (complete the dex).
  void markAllCaught(String versionId) {
    final o = _ofsFor(versionId);
    for (final target in [
      _s(0) + 0x28,
      _s(0) + o.seen1,
      _s(o.seen2Sec) + o.seen2,
      _s(o.seen3Sec) + o.seen3,
    ]) {
      for (var i = 0; i < 386; i++) {
        _setDexBit(target, i);
      }
    }
    fixChecksum(0);
    fixChecksum(o.seen2Sec);
    fixChecksum(o.seen3Sec);
  }

  /// How many species are marked SEEN (from the primary seen mirror).
  int seenCount(String versionId) =>
      _countBits(_s(0) + _ofsFor(versionId).seen1, _dexBytes);

  /// The three "seen" mirror targets for a version (kept in sync by the game).
  List<int> _seenTargets(_Gen3Offsets o) => [
        _s(0) + o.seen1,
        _s(o.seen2Sec) + o.seen2,
        _s(o.seen3Sec) + o.seen3,
      ];

  /// Mark every species 1..386 SEEN (all three mirrors), leaving owned as-is.
  void markAllSeen(String versionId) {
    final o = _ofsFor(versionId);
    for (final target in _seenTargets(o)) {
      for (var i = 0; i < 386; i++) {
        _setDexBit(target, i);
      }
    }
    fixChecksum(0);
    fixChecksum(o.seen2Sec);
    fixChecksum(o.seen3Sec);
  }

  /// Mark one species (national dex) SEEN in all three mirrors.
  void markSeen(String versionId, int nationalDex) {
    final o = _ofsFor(versionId);
    final i = nationalDex - 1;
    if (i < 0 || i >= 386) return;
    for (final target in _seenTargets(o)) {
      _setDexBit(target, i);
    }
    fixChecksum(0);
    fixChecksum(o.seen2Sec);
    fixChecksum(o.seen3Sec);
  }

  // Gen 3 SaveBlock1 (trainer/game data) is logically contiguous but stored
  // across sections 1..4 (0xF80 usable bytes each). Map a logical SaveBlock1
  // offset to the physical byte offset (and to its section, for the checksum).
  int _secForLogical(int l) => 1 + (l ~/ 0xF80);
  int _logical(int l) => _s(_secForLogical(l)) + (l % 0xF80);

  // Bag pockets: (logical SaveBlock1 offset, slots) per game and pocket. Each
  // slot is (item id u16, quantity u16); quantities are XOR'd with the low 16
  // bits of the security key on E/FRLG (RS: key 0). Offsets from PKHeX.
  ({int ofs, int slots}) _pocket(String v, Gen3Pocket p) {
    switch (v) {
      case 'firered':
      case 'leafgreen':
        switch (p) {
          case Gen3Pocket.items:
            return (ofs: 0x0310, slots: 42);
          case Gen3Pocket.keyItems:
            return (ofs: 0x03B8, slots: 30);
          case Gen3Pocket.balls:
            return (ofs: 0x0430, slots: 13);
          case Gen3Pocket.tmHm:
            return (ofs: 0x0464, slots: 58);
          case Gen3Pocket.berries:
            return (ofs: 0x054C, slots: 43);
        }
      case 'ruby':
      case 'sapphire':
        switch (p) {
          case Gen3Pocket.items:
            return (ofs: 0x0560, slots: 20);
          case Gen3Pocket.keyItems:
            return (ofs: 0x05B0, slots: 20);
          case Gen3Pocket.balls:
            return (ofs: 0x0600, slots: 16);
          case Gen3Pocket.tmHm:
            return (ofs: 0x0640, slots: 64);
          case Gen3Pocket.berries:
            return (ofs: 0x0740, slots: 46);
        }
      default: // emerald
        switch (p) {
          case Gen3Pocket.items:
            return (ofs: 0x0560, slots: 30);
          case Gen3Pocket.keyItems:
            return (ofs: 0x05D8, slots: 30);
          case Gen3Pocket.balls:
            return (ofs: 0x0650, slots: 16);
          case Gen3Pocket.tmHm:
            return (ofs: 0x0690, slots: 64);
          case Gen3Pocket.berries:
            return (ofs: 0x0790, slots: 46);
        }
    }
  }

  /// Read the non-empty entries of one bag pocket as (id, qty).
  List<({int id, int qty})> pocketItems(String v, Gen3Pocket p) {
    final pk = _pocket(v, p);
    final key = _securityKey(_ofsFor(v)) & 0xFFFF;
    final out = <({int id, int qty})>[];
    for (var i = 0; i < pk.slots; i++) {
      final o = _logical(pk.ofs + i * 4);
      final id = _u16(bytes, o);
      if (id == 0) continue;
      out.add((id: id, qty: (_u16(bytes, o + 2) ^ key) & 0xFFFF));
    }
    return out;
  }

  int pocketSlots(String v, Gen3Pocket p) => _pocket(v, p).slots;

  /// Overwrite a whole pocket with [items] (packed from slot 0; the rest are
  /// cleared). Fixes every section the pocket touches.
  void setPocket(String v, Gen3Pocket p, List<({int id, int qty})> items) {
    final pk = _pocket(v, p);
    final key = _securityKey(_ofsFor(v)) & 0xFFFF;
    final touched = <int>{};
    for (var i = 0; i < pk.slots; i++) {
      final o = _logical(pk.ofs + i * 4);
      if (i < items.length) {
        _setU16(o, items[i].id & 0xFFFF);
        _setU16(o + 2, (items[i].qty & 0xFFFF) ^ key);
      } else {
        _setU16(o, 0);
        _setU16(o + 2, 0);
      }
      touched.add(_secForLogical(pk.ofs + i * 4));
    }
    for (final s in touched) {
      fixChecksum(s);
    }
  }

  int _eventFlagBlock(String v) {
    switch (v) {
      case 'emerald':
        return 0x139C;
      case 'firered':
      case 'leafgreen':
        return 0x0EE0;
      default:
        return 0x1220; // ruby / sapphire
    }
  }

  /// Add a key item (id) to the Key Items pocket. Returns false if full.
  bool addKeyItem(String versionId, int itemId) {
    final pk = _pocket(versionId, Gen3Pocket.keyItems);
    final key = _securityKey(_ofsFor(versionId)) & 0xFFFF;
    for (var i = 0; i < pk.slots; i++) {
      final o = _logical(pk.ofs + i * 4);
      final id = _u16(bytes, o);
      if (id == itemId || id == 0) {
        _setU16(o, itemId);
        _setU16(o + 2, (1 ^ key) & 0xFFFF); // quantity 1
        fixChecksum(_secForLogical(pk.ofs + i * 4));
        return true;
      }
    }
    return false;
  }

  /// Set an event flag (by number) in the SaveBlock1 flag array.
  void setEventFlag(String versionId, int flag) {
    final l = _eventFlagBlock(versionId) + (flag >> 3);
    bytes[_logical(l)] |= (1 << (flag & 7));
    fixChecksum(_secForLogical(l));
  }

  /// Give an event ticket: adds the key item AND sets its enable flag so the
  /// ferry offers the destination. Ticket ids/flags below are per-game; flags
  /// are the part to confirm by testing in the emulator.
  void giveTicket(String versionId, Gen3Ticket t) {
    final def = _ticketDefs[t]!;
    if (!def.games.contains(_family(versionId))) return;
    addKeyItem(versionId, def.itemId);
    final flag = def.flags[_family(versionId)];
    if (flag != null) setEventFlag(versionId, flag);
  }

  static String _family(String v) => switch (v) {
        'emerald' => 'e',
        'firered' || 'leafgreen' => 'frlg',
        _ => 'rs',
      };

  /// Tickets available in this game (for the editor UI).
  static List<Gen3Ticket> ticketsFor(String versionId) => Gen3Ticket.values
      .where((t) => _ticketDefs[t]!.games.contains(_family(versionId)))
      .toList();

  // party: count @ logical 0x0234 (RSE) / 0x0034 (FRLG), then 6 x 100-byte mons
  int _partyOfs(String v) =>
      (v == 'firered' || v == 'leafgreen') ? 0x0034 : 0x0234;
  int partyCount(String versionId) =>
      _u32(bytes, _logical(_partyOfs(versionId)));
  Uint8List partyBlock(String versionId, int i) {
    final o = _logical(_partyOfs(versionId) + 4 + i * 100);
    return Uint8List.fromList(bytes.sublist(o, o + 100));
  }

  void writePartyBlock(String versionId, int i, Uint8List block) {
    final logical = _partyOfs(versionId) + 4 + i * 100;
    bytes.setRange(_logical(logical), _logical(logical) + 100, block);
    fixChecksum(_secForLogical(logical));
  }

  /// Recompute and store a section's checksum. MUST be called after any edit to
  /// that section or the game rejects the save.
  void fixChecksum(int sectionId) =>
      _setU16(_s(sectionId) + 0xFF6, computeChecksum(sectionId));

  // ---- PC box storage (SaveBlock2) ----
  // The PC buffer (a 4-byte current-box header, then 14*30 = 420 slots of 80
  // bytes) is logically contiguous but stored across sections 5..13 (0xF80
  // usable each; section 13 short but never reached by the box data). An 80-byte
  // slot routinely straddles a section boundary, so box I/O is byte-wise.
  static const int pcBoxCount = 14;
  static const int pcPerBox = 30;
  int _pcLogical(int l) => _s(5 + (l ~/ 0xF80)) + (l % 0xF80);

  /// Read PC box slot [index] (0..419) as its 80-byte PK3 block.
  Uint8List boxSlot(int index) {
    final base = 4 + index * 80;
    return Uint8List.fromList(
        [for (var i = 0; i < 80; i++) bytes[_pcLogical(base + i)]]);
  }

  /// Write PC box slot [index], fixing the checksum of every section it touches.
  void writeBoxSlot(int index, Uint8List block) {
    final base = 4 + index * 80;
    final touched = <int>{};
    for (var i = 0; i < 80; i++) {
      final l = base + i;
      bytes[_pcLogical(l)] = block[i];
      touched.add(5 + (l ~/ 0xF80));
    }
    for (final s in touched) {
      fixChecksum(s);
    }
  }

  /// The edited save bytes (edits are applied in place on the loaded copy).
  Uint8List toBytes() => bytes;
}

/// Gen 3 event tickets — each unlocks a ferry to an event-Pokémon island.
enum Gen3Ticket {
  eon('Eon Ticket', 'Southern Island — Latios / Latias'),
  mystic('Mystic Ticket', 'Navel Rock — Lugia & Ho-Oh'),
  aurora('Aurora Ticket', 'Birth Island — Deoxys'),
  oldSeaMap('Old Sea Map', 'Faraway Island — Mew');

  final String label;
  final String unlocks;
  const Gen3Ticket(this.label, this.unlocks);
}

class _TicketDef {
  final int itemId;
  final Set<String> games; // families that have this ticket: 'rs','e','frlg'
  final Map<String, int> flags; // family -> enable flag (verify by testing)
  const _TicketDef(this.itemId, this.games, this.flags);
}

// Item ids: Eon 275, Mystic 276, Aurora 277, Old Sea Map 278. Enable flags are
// set for Emerald (the game we can test); FRLG/RS add the item only for now.
const _ticketDefs = <Gen3Ticket, _TicketDef>{
  Gen3Ticket.eon: _TicketDef(275, {'rs', 'e'}, {'e': 0x2D3}),
  Gen3Ticket.mystic: _TicketDef(276, {'frlg', 'e'}, {'e': 0x2D1}),
  Gen3Ticket.aurora: _TicketDef(277, {'frlg', 'e'}, {'e': 0x2D2}),
  Gen3Ticket.oldSeaMap: _TicketDef(278, {'e'}, {'e': 0x2D0}),
};

/// The five Gen 3 bag pockets.
enum Gen3Pocket { items, keyItems, balls, tmHm, berries }

/// A Gen 3 trainer card (section 0).
class Gen3Trainer {
  final String name;
  final int gender; // 0 = male, 1 = female
  final int tid, sid;
  final int hours, minutes;
  const Gen3Trainer({
    required this.name,
    required this.gender,
    required this.tid,
    required this.sid,
    required this.hours,
    required this.minutes,
  });
  Gen3Trainer copyWith({
    String? name,
    int? gender,
    int? tid,
    int? sid,
    int? hours,
    int? minutes,
  }) =>
      Gen3Trainer(
        name: name ?? this.name,
        gender: gender ?? this.gender,
        tid: tid ?? this.tid,
        sid: sid ?? this.sid,
        hours: hours ?? this.hours,
        minutes: minutes ?? this.minutes,
      );
}

class _Gen3Offsets {
  final int keyOfs; // security key offset in section 0 (-1 = none, RS)
  final int money; // money offset in section 1
  final int seen1; // seen copy 1 offset in section 0
  final int seen2Sec, seen2; // seen copy 2 section + offset
  final int seen3Sec, seen3; // seen copy 3 section + offset
  const _Gen3Offsets({
    required this.keyOfs,
    required this.money,
    required this.seen1,
    required this.seen2Sec,
    required this.seen2,
    required this.seen3Sec,
    required this.seen3,
  });
}

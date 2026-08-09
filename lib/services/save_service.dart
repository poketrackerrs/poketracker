import 'dart:typed_data';
import '../models/save_models.dart';

/// Parses emulator save files into [SaveData]. Only unencrypted, well-documented
/// data is read; anything uncertain is reported as a note rather than guessed.
///
/// Confidence by generation (validate against a real save before trusting):
///  - Gen 1 (RBY): caught dex, badges, party, playtime, trainer — implemented.
///  - Gen 3 (RSE/FRLG/E): caught dex, playtime, trainer — implemented;
///    badges + party need more work (party mons are encrypted).
///  - Gen 2/4/5: not yet.
class SaveService {
  SaveData parse(Uint8List bytes,
      {required int generation, required String versionId}) {
    switch (generation) {
      case 1:
        return _parseGen1(bytes, versionId);
      case 2:
        return _parseGen2(bytes, versionId);
      case 3:
        return _parseGen3(bytes, versionId);
      case 4:
        return _parseGen4(bytes, versionId);
      case 5:
        return _parseGen5(bytes, versionId);
      default:
        throw SaveParseException(
            'Auto-tracking for Gen $generation saves is coming soon.');
    }
  }

  // ==================================================================== Gen 1

  static int _countBits(Uint8List b, int start, int lenBytes) {
    var n = 0;
    for (var i = 0; i < lenBytes; i++) {
      var v = b[start + i];
      while (v != 0) {
        n += v & 1;
        v >>= 1;
      }
    }
    return n;
  }

  static Set<int> _dexFromBitfield(Uint8List b, int start, int maxDex) {
    final out = <int>{};
    for (var dex = 1; dex <= maxDex; dex++) {
      final bitIndex = dex - 1;
      final byte = b[start + (bitIndex >> 3)];
      if ((byte & (1 << (bitIndex & 7))) != 0) out.add(dex);
    }
    return out;
  }

  SaveData _parseGen1(Uint8List b, String versionId) {
    if (b.length < 0x8000) {
      throw const SaveParseException(
          'This does not look like a Game Boy save (expected 32 KB).');
    }
    // English RBY offsets (Bulbapedia "Save data structure (Generation I)").
    const ownedOfs = 0x25A3; // 19 bytes
    const seenOfs = 0x25B6; // 19 bytes
    const badgesOfs = 0x2602; // 1 byte, 8 Kanto badge bits
    const partyOfs = 0x2F2C; // count, species list, then 44-byte structs
    const nameOfs = 0x2598; // 11 bytes
    const tidOfs = 0x2605; // 2 bytes big-endian
    const timeOfs = 0x2CED; // hours, (unused), minutes, seconds

    final caught = _dexFromBitfield(b, ownedOfs, 151);
    final seen = _countBits(b, seenOfs, 19);
    final badges = _countBits(b, badgesOfs, 1);

    final team = <SaveTeamMon>[];
    final count = b[partyOfs].clamp(0, 6);
    for (var i = 0; i < count; i++) {
      final index = b[partyOfs + 1 + i]; // species internal index
      final structOfs = partyOfs + 8 + i * 44; // 0x2F34 + i*44
      final level = b[structOfs + 0x21];
      team.add(SaveTeamMon(dexId: _gen1IndexToDex[index], level: level));
    }

    final tid = (b[tidOfs] << 8) | b[tidOfs + 1];
    final hours = b[timeOfs];
    final minutes = b[timeOfs + 2];

    return SaveData(
      generation: 1,
      versionId: versionId,
      caughtDex: caught,
      seenCount: seen,
      badgeCount: badges,
      team: team,
      trainerName: _decodeGen1Text(b, nameOfs, 11),
      trainerId: tid,
      playTime: Duration(hours: hours, minutes: minutes),
    );
  }

  // ==================================================================== Gen 2

  SaveData _parseGen2(Uint8List b, String versionId) {
    if (b.length < 0x8000) {
      throw const SaveParseException(
          'This does not look like a Game Boy Color save (expected 32 KB).');
    }
    final crystal = versionId == 'crystal';
    // English GS vs Crystal offsets (Bulbapedia).
    final ownedOfs = crystal ? 0x2A47 : 0x2A4C; // 32 bytes
    final seenOfs = crystal ? 0x2A67 : 0x2A6C; // 32 bytes
    final johtoOfs = crystal ? 0x23E5 : 0x23E4; // 1 byte (8 Johto badges)
    final partyOfs = crystal ? 0x2865 : 0x288A; // count, species list, structs
    const nameOfs = 0x200B; // 11 bytes
    const tidOfs = 0x2008; // 2 bytes big-endian
    const timeOfs = 0x2053; // hours (2), minutes (1), seconds (1)

    final caught = _dexFromBitfield(b, ownedOfs, 251);
    final seen = _countBits(b, seenOfs, 32);
    final badges = _countBits(b, johtoOfs, 1); // Johto gym badges (0-8)

    final team = <SaveTeamMon>[];
    final count = b[partyOfs].clamp(0, 6);
    for (var i = 0; i < count; i++) {
      final species = b[partyOfs + 1 + i]; // Gen 2 index == national dex
      final structOfs = partyOfs + 8 + i * 48;
      final level = b[structOfs + 0x1F];
      team.add(SaveTeamMon(
        dexId: (species >= 1 && species <= 251) ? species : null,
        level: level,
      ));
    }

    final tid = (b[tidOfs] << 8) | b[tidOfs + 1];
    final hours = (b[timeOfs] << 8) | b[timeOfs + 1];
    final minutes = b[timeOfs + 2];

    return SaveData(
      generation: 2,
      versionId: versionId,
      caughtDex: caught,
      seenCount: seen,
      badgeCount: badges,
      team: team,
      trainerName: _decodeGen1Text(b, nameOfs, 11), // same charset as Gen 1
      trainerId: tid,
      playTime: Duration(hours: hours, minutes: minutes),
      notes: const [
        'Badge count is Johto gyms only; Kanto gyms aren\'t mapped yet.',
      ],
    );
  }

  // ==================================================================== Gen 3

  static int _u16(Uint8List b, int o) => b[o] | (b[o + 1] << 8);
  static int _u32(Uint8List b, int o) =>
      b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);

  SaveData _parseGen3(Uint8List b, String versionId) {
    if (b.length < 0x20000) {
      throw const SaveParseException(
          'This does not look like a GBA save (expected 128 KB).');
    }
    const signature = 0x08012025;
    const blockSize = 0xE000; // 14 sections * 0x1000
    const sectionSize = 0x1000;

    int saveIndexOf(int base) {
      if (_u32(b, base + 0xFF8) != signature) return -1;
      final idx = _u32(b, base + 0xFFC);
      return idx == 0xFFFFFFFF ? -1 : idx;
    }

    final a = saveIndexOf(0x0000);
    final c = saveIndexOf(blockSize);
    if (a < 0 && c < 0) {
      throw const SaveParseException('No valid GBA save block found.');
    }
    final base = (c > a) ? blockSize : 0x0000;

    // Map section id -> physical offset (sections are stored rotated).
    final sectionOffset = <int, int>{};
    for (var slot = 0; slot < 14; slot++) {
      final so = base + slot * sectionSize;
      if (_u32(b, so + 0xFF8) != signature) continue;
      sectionOffset[_u16(b, so + 0xFF4)] = so;
    }
    final s0 = sectionOffset[0];
    if (s0 == null) {
      throw const SaveParseException('GBA save trainer section missing.');
    }

    // Owned (caught) national-dex bitfield is in section 0 at 0x28 for all Gen 3
    // games, indexed by (national dex number - 1). (Bulbapedia.)
    final ownedOfs = s0 + 0x28;
    final caught = _dexFromBitfield(b, ownedOfs, 386);

    final tid = _u32(b, s0 + 0x0A) & 0xFFFF;
    final hours = _u16(b, s0 + 0x0E);
    final minutes = b[s0 + 0x10];

    return SaveData(
      generation: 3,
      versionId: versionId,
      caughtDex: caught,
      trainerName: _decodeGen3Text(b, s0, 7),
      trainerId: tid,
      playTime: Duration(hours: hours, minutes: minutes),
      notes: const [
        'Gen 3 badges and team aren\'t read yet — coming next.',
      ],
    );
  }

  // ============================================================== Gen 4 (DS)

  SaveData _parseGen4(Uint8List b, String versionId) {
    if (b.length < 0x80000) {
      throw const SaveParseException(
          'This does not look like a DS save (expected 512 KB).');
    }
    // General (small) block size per game; two block-pairs, second at +0x40000.
    final genSize = switch (versionId) {
      'platinum' => 0xCF2C,
      'heartgold' || 'soulsilver' => 0xF700,
      _ => 0xC100, // diamond / pearl
    };
    // Pick the most recent slot by the save counter in the block footer
    // (last 0x14 bytes of the general block).
    int counter(int base) => _u32(b, base + genSize - 0x14);
    final base = (counter(0x40000) > counter(0x0000)) ? 0x40000 : 0x0000;

    final tid = _u32(b, base + 0x78) & 0xFFFF; // public trainer ID
    final hours = _u16(b, base + 0x8A);
    final minutes = b[base + 0x8C];

    return SaveData(
      generation: 4,
      versionId: versionId,
      trainerId: tid,
      playTime: Duration(hours: hours, minutes: minutes),
      notes: const [
        'Gen 4 caught-Pokedex, badges, and team are still being calibrated. '
            'Send me a DS save (.sav/.dsv) for this game and I\'ll finish them '
            'in a patch.',
      ],
    );
  }

  // ============================================================== Gen 5 (DS)

  SaveData _parseGen5(Uint8List b, String versionId) {
    return SaveData(
      generation: 5,
      versionId: versionId,
      notes: const [
        'Gen 5 auto-tracking is being calibrated. Send me a Black/White or '
            'B2W2 save (.sav/.dsv) and I\'ll enable caught-Pokedex, team, and '
            'badges in a patch.',
      ],
    );
  }

  // ---------------------------------------------------------------- text codecs

  static String _decodeGen1Text(Uint8List b, int start, int maxLen) {
    final sb = StringBuffer();
    for (var i = 0; i < maxLen; i++) {
      final c = b[start + i];
      if (c == 0x50) break; // terminator
      if (c == 0x7F) {
        sb.write(' ');
      } else if (c >= 0x80 && c <= 0x99) {
        sb.writeCharCode('A'.codeUnitAt(0) + (c - 0x80));
      } else if (c >= 0xA0 && c <= 0xB9) {
        sb.writeCharCode('a'.codeUnitAt(0) + (c - 0xA0));
      } else if (c >= 0xF6 && c <= 0xFF) {
        sb.writeCharCode('0'.codeUnitAt(0) + (c - 0xF6));
      }
    }
    return sb.toString().trim();
  }

  static String _decodeGen3Text(Uint8List b, int start, int maxLen) {
    final sb = StringBuffer();
    for (var i = 0; i < maxLen; i++) {
      final c = b[start + i];
      if (c == 0xFF) break; // terminator
      if (c == 0x00) {
        sb.write(' ');
      } else if (c >= 0xA1 && c <= 0xAA) {
        sb.writeCharCode('0'.codeUnitAt(0) + (c - 0xA1));
      } else if (c >= 0xBB && c <= 0xD4) {
        sb.writeCharCode('A'.codeUnitAt(0) + (c - 0xBB));
      } else if (c >= 0xD5 && c <= 0xEE) {
        sb.writeCharCode('a'.codeUnitAt(0) + (c - 0xD5));
      }
    }
    return sb.toString().trim();
  }

  /// Gen 1 species internal index -> national dex number (MissingNo omitted).
  static const Map<int, int> _gen1IndexToDex = {
    0x01: 112, 0x02: 115, 0x03: 32, 0x04: 35, 0x05: 21, 0x06: 100, 0x07: 34,
    0x08: 80, 0x09: 2, 0x0A: 103, 0x0B: 108, 0x0C: 102, 0x0D: 88, 0x0E: 94,
    0x0F: 29, 0x10: 31, 0x11: 104, 0x12: 111, 0x13: 131, 0x14: 59, 0x15: 151,
    0x16: 130, 0x17: 90, 0x18: 72, 0x19: 92, 0x1A: 123, 0x1B: 120, 0x1C: 9,
    0x1D: 127, 0x1E: 114, 0x21: 58, 0x22: 95, 0x23: 22, 0x24: 16, 0x25: 79,
    0x26: 64, 0x27: 75, 0x28: 113, 0x29: 67, 0x2A: 122, 0x2B: 106, 0x2C: 107,
    0x2D: 24, 0x2E: 47, 0x2F: 54, 0x30: 96, 0x31: 76, 0x33: 126, 0x35: 125,
    0x36: 82, 0x37: 109, 0x39: 56, 0x3A: 86, 0x3B: 50, 0x3C: 128, 0x40: 83,
    0x41: 48, 0x42: 149, 0x46: 84, 0x47: 60, 0x48: 124, 0x49: 146, 0x4A: 144,
    0x4B: 145, 0x4C: 132, 0x4D: 52, 0x4E: 98, 0x52: 37, 0x53: 38, 0x54: 25,
    0x55: 26, 0x58: 147, 0x59: 148, 0x5A: 140, 0x5B: 141, 0x5C: 116, 0x5D: 117,
    0x60: 27, 0x61: 28, 0x62: 138, 0x63: 139, 0x64: 39, 0x65: 40, 0x66: 133,
    0x67: 136, 0x68: 135, 0x69: 134, 0x6A: 66, 0x6B: 41, 0x6C: 23, 0x6D: 46,
    0x6E: 61, 0x6F: 62, 0x70: 13, 0x71: 14, 0x72: 15, 0x74: 85, 0x75: 57,
    0x76: 51, 0x77: 49, 0x78: 87, 0x7B: 10, 0x7C: 11, 0x7D: 12, 0x7E: 68,
    0x80: 55, 0x81: 97, 0x82: 42, 0x83: 150, 0x84: 143, 0x85: 129, 0x88: 89,
    0x8A: 99, 0x8B: 91, 0x8D: 101, 0x8E: 36, 0x8F: 110, 0x90: 53, 0x91: 105,
    0x93: 93, 0x94: 63, 0x95: 65, 0x96: 17, 0x97: 18, 0x98: 121, 0x99: 1,
    0x9A: 3, 0x9B: 73, 0x9D: 118, 0x9E: 119, 0xA3: 77, 0xA4: 78, 0xA5: 19,
    0xA6: 20, 0xA7: 33, 0xA8: 30, 0xA9: 74, 0xAA: 137, 0xAB: 142, 0xAD: 81,
    0xB0: 4, 0xB1: 7, 0xB2: 5, 0xB3: 8, 0xB4: 6, 0xB9: 43, 0xBA: 44, 0xBB: 45,
    0xBC: 69, 0xBD: 70, 0xBE: 71,
  };
}

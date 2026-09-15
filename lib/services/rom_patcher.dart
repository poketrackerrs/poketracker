import 'dart:typed_data';

/// Applies ROM-hack patch files (IPS / UPS / BPS) to a user-supplied clean base
/// ROM, in pure Dart so it works identically on every platform. UPS and BPS
/// embed CRC32s of the source and target, so we verify the user picked the right
/// base ROM and that the output is byte-correct — a wrong base ROM is rejected
/// with a clear message instead of producing a silently broken game.
///
/// xdelta/VCDIFF is intentionally NOT supported yet (general delta format, needs
/// a much larger decoder); IPS/UPS/BPS cover the overwhelming majority of hacks.

enum RomPatchFormat { ips, ups, bps }

extension RomPatchFormatName on RomPatchFormat {
  String get label => switch (this) {
        RomPatchFormat.ips => 'IPS',
        RomPatchFormat.ups => 'UPS',
        RomPatchFormat.bps => 'BPS',
      };
}

class RomPatchResult {
  final Uint8List output;
  final RomPatchFormat format;

  /// True when the patch carried CRC32s and they matched (UPS/BPS). IPS has no
  /// checksums, so it's [hasChecksum] == false and [verified] == false.
  final bool verified;
  bool get hasChecksum => format != RomPatchFormat.ips;

  const RomPatchResult(this.output, this.format, {required this.verified});
}

/// Thrown for a bad patch. [wrongBaseRom] is set when the source CRC didn't
/// match — i.e. the user applied the patch to the wrong base ROM.
class RomPatchException implements Exception {
  final String message;
  final bool wrongBaseRom;
  const RomPatchException(this.message, {this.wrongBaseRom = false});
  @override
  String toString() => message;
}

/// Applies [patch] to [base], auto-detecting the format from the magic bytes.
RomPatchResult applyRomPatch(Uint8List base, Uint8List patch) {
  try {
    if (_magic(patch, 'PATCH')) {
      return RomPatchResult(_applyIps(base, patch), RomPatchFormat.ips,
          verified: false);
    }
    if (_magic(patch, 'UPS1')) {
      return RomPatchResult(_applyUps(base, patch), RomPatchFormat.ups,
          verified: true);
    }
    if (_magic(patch, 'BPS1')) {
      return RomPatchResult(_applyBps(base, patch), RomPatchFormat.bps,
          verified: true);
    }
    throw const RomPatchException(
        'Unrecognized patch format. Supported: IPS, UPS, BPS.');
  } on RomPatchException {
    rethrow;
  } on RangeError {
    throw const RomPatchException('The patch file is truncated or corrupt.');
  }
}

// ---- IPS: "PATCH" + records {offset u24, size u16, data} … "EOF" -------------
// size 0 marks an RLE run: {runLength u16, value u8}. All big-endian. An optional
// 3-byte truncate length may follow EOF.
Uint8List _applyIps(Uint8List base, Uint8List patch) {
  final out = List<int>.from(base); // growable — IPS can extend the ROM
  var p = 5;
  while (p + 3 <= patch.length) {
    if (patch[p] == 0x45 && patch[p + 1] == 0x4F && patch[p + 2] == 0x46) {
      p += 3; // "EOF"
      break;
    }
    final offset = (patch[p] << 16) | (patch[p + 1] << 8) | patch[p + 2];
    p += 3;
    final size = (patch[p] << 8) | patch[p + 1];
    p += 2;
    if (size == 0) {
      final run = (patch[p] << 8) | patch[p + 1];
      p += 2;
      final value = patch[p++];
      _grow(out, offset + run);
      for (var i = 0; i < run; i++) {
        out[offset + i] = value;
      }
    } else {
      _grow(out, offset + size);
      for (var i = 0; i < size; i++) {
        out[offset + i] = patch[p++];
      }
    }
  }
  if (p + 3 <= patch.length) {
    final truncate = (patch[p] << 16) | (patch[p + 1] << 8) | patch[p + 2];
    if (truncate > 0 && truncate < out.length) {
      return Uint8List.fromList(out.sublist(0, truncate));
    }
  }
  return Uint8List.fromList(out);
}

void _grow(List<int> out, int len) {
  while (out.length < len) {
    out.add(0);
  }
}

// ---- UPS: "UPS1" srcSize dstSize {relOffset, xorBytes…0x00}… footer ----------
// Footer (last 12 bytes) = srcCRC, dstCRC, patchCRC (u32 LE each).
Uint8List _applyUps(Uint8List base, Uint8List patch) {
  final r = _Reader(patch, 4);
  r.decode(); // source size (informational; CRC below is the real check)
  final dstSize = r.decode();
  final out = Uint8List(dstSize);
  for (var i = 0; i < dstSize; i++) {
    out[i] = i < base.length ? base[i] : 0;
  }
  var outPos = 0;
  final bodyEnd = patch.length - 12;
  while (r.pos < bodyEnd) {
    outPos += r.decode();
    while (true) {
      final x = patch[r.pos++];
      final src = outPos < base.length ? base[outPos] : 0;
      if (outPos < out.length) out[outPos] = src ^ x; // guard terminator-at-end
      outPos++;
      if (x == 0) break;
    }
  }
  _checkCrc(base, out, patch);
  return out;
}

// ---- BPS: "BPS1" srcSize dstSize metaSize meta {actions…} footer -------------
// Action = decode(); command = data&3, length = (data>>2)+1.
//   0 SourceRead, 1 TargetRead, 2 SourceCopy(+signed off), 3 TargetCopy(+signed).
Uint8List _applyBps(Uint8List base, Uint8List patch) {
  final r = _Reader(patch, 4);
  r.decode(); // source size
  final dstSize = r.decode();
  final metaSize = r.decode();
  r.pos += metaSize; // skip metadata
  final out = Uint8List(dstSize);
  var outPos = 0, srcRel = 0, dstRel = 0;
  final bodyEnd = patch.length - 12;
  while (r.pos < bodyEnd) {
    final data = r.decode();
    final command = data & 3;
    final length = (data >> 2) + 1;
    switch (command) {
      case 0: // SourceRead
        for (var i = 0; i < length; i++) {
          out[outPos] = base[outPos];
          outPos++;
        }
      case 1: // TargetRead
        for (var i = 0; i < length; i++) {
          out[outPos++] = patch[r.pos++];
        }
      case 2: // SourceCopy
        final d = r.decode();
        srcRel += (d & 1) != 0 ? -(d >> 1) : (d >> 1);
        for (var i = 0; i < length; i++) {
          out[outPos++] = base[srcRel++];
        }
      case 3: // TargetCopy
        final d = r.decode();
        dstRel += (d & 1) != 0 ? -(d >> 1) : (d >> 1);
        for (var i = 0; i < length; i++) {
          out[outPos++] = out[dstRel++];
        }
    }
  }
  _checkCrc(base, out, patch);
  return out;
}

void _checkCrc(Uint8List base, Uint8List out, Uint8List patch) {
  final srcCrc = _u32le(patch, patch.length - 12);
  final dstCrc = _u32le(patch, patch.length - 8);
  if (crc32(base) != srcCrc) {
    throw const RomPatchException(
        'This patch is for a different base ROM — the file you picked doesn\'t '
        'match what the patch expects.',
        wrongBaseRom: true);
  }
  if (crc32(out) != dstCrc) {
    throw const RomPatchException(
        'Patch applied but the result failed its checksum — the patch file '
        'looks corrupt.');
  }
}

/// beat/UPS/BPS variable-length integer + a little cursor.
class _Reader {
  final Uint8List d;
  int pos;
  _Reader(this.d, this.pos);
  int decode() {
    var data = 0, shift = 1;
    while (true) {
      final x = d[pos++];
      data += (x & 0x7f) * shift;
      if ((x & 0x80) != 0) break;
      shift <<= 7;
      data += shift;
    }
    return data;
  }
}

bool _magic(Uint8List d, String sig) {
  if (d.length < sig.length) return false;
  for (var i = 0; i < sig.length; i++) {
    if (d[i] != sig.codeUnitAt(i)) return false;
  }
  return true;
}

int _u32le(Uint8List d, int o) =>
    d[o] | (d[o + 1] << 8) | (d[o + 2] << 16) | (d[o + 3] << 24);

final Uint32List _crcTable = () {
  final t = Uint32List(256);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
    }
    t[n] = c;
  }
  return t;
}();

/// Standard CRC32 (IEEE, as used by UPS/BPS footers).
int crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final b in bytes) {
    crc = _crcTable[(crc ^ b) & 0xFF] ^ (crc >> 8);
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

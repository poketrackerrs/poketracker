import 'dart:typed_data';
import '../lib/services/rom_patcher.dart';

// Standalone check for the ROM patcher: `dart run tool/test_rom_patcher.dart`.
// Verifies CRC32, the three appliers via round-trips, and wrong-base rejection.

int _fails = 0;
void expect(bool ok, String what) {
  print('${ok ? 'ok  ' : 'FAIL'}  $what');
  if (!ok) _fails++;
}

bool _eq(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

// beat/UPS/BPS varint ENCODER (inverse of the decoder) — for building fixtures.
List<int> _enc(int n) {
  final out = <int>[];
  while (true) {
    final x = n & 0x7f;
    n = (n >> 7);
    if (n == 0) {
      out.add(0x80 | x);
      break;
    }
    out.add(x);
    n--;
  }
  return out;
}

List<int> _u32le(int v) => [v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff];

// A minimal-but-valid BPS that rebuilds [dst] from [src] with one TargetRead.
List<int> _buildBps(Uint8List src, Uint8List dst) {
  final body = <int>[]
    ..addAll('BPS1'.codeUnits)
    ..addAll(_enc(src.length))
    ..addAll(_enc(dst.length))
    ..addAll(_enc(0)) // no metadata
    ..addAll(_enc(((dst.length - 1) << 2) | 1)) // TargetRead, whole target
    ..addAll(dst);
  body
    ..addAll(_u32le(crc32(src)))
    ..addAll(_u32le(crc32(dst)));
  body.addAll(_u32le(crc32(body)));
  return body;
}

// A minimal UPS: one block at offset 0 XORing every byte (all-differ fixture).
List<int> _buildUps(Uint8List src, Uint8List dst) {
  final body = <int>[]
    ..addAll('UPS1'.codeUnits)
    ..addAll(_enc(src.length))
    ..addAll(_enc(dst.length))
    ..addAll(_enc(0)); // relative offset 0
  for (var i = 0; i < dst.length; i++) {
    body.add(dst[i] ^ (i < src.length ? src[i] : 0));
  }
  body.add(0x00); // block terminator
  body
    ..addAll(_u32le(crc32(src)))
    ..addAll(_u32le(crc32(dst)));
  body.addAll(_u32le(crc32(body)));
  return body;
}

void main() {
  // 1) CRC32 known vector.
  expect(crc32('123456789'.codeUnits) == 0xCBF43926, 'crc32 "123456789"');

  // 2) IPS: overwrite 3 bytes at offset 4, leave the rest intact.
  final base = Uint8List.fromList(List.generate(16, (i) => i));
  final ips = <int>[]
    ..addAll('PATCH'.codeUnits)
    ..addAll([0x00, 0x00, 0x04]) // offset
    ..addAll([0x00, 0x03]) // size
    ..addAll([0xAA, 0xBB, 0xCC])
    ..addAll('EOF'.codeUnits);
  final r1 = applyRomPatch(base, Uint8List.fromList(ips));
  expect(r1.output[4] == 0xAA && r1.output[5] == 0xBB && r1.output[6] == 0xCC,
      'IPS wrote the record');
  expect(r1.output[3] == 3 && r1.output[7] == 7, 'IPS left the rest intact');

  // 3) BPS round-trip (all-new target) + checksum verified.
  final src = Uint8List.fromList(List.generate(8, (i) => i));
  final bpsDst = Uint8List.fromList([9, 8, 7, 6, 0xDE, 0xAD, 0xBE, 0xEF]);
  final r3 = applyRomPatch(src, Uint8List.fromList(_buildBps(src, bpsDst)));
  expect(_eq(r3.output, bpsDst) && r3.verified, 'BPS round-trip + verified');

  // 4) UPS round-trip (every byte XOR 0xFF) + checksum verified.
  final upsDst = Uint8List.fromList([for (final b in src) b ^ 0xFF]);
  final r4 = applyRomPatch(src, Uint8List.fromList(_buildUps(src, upsDst)));
  expect(_eq(r4.output, upsDst) && r4.verified, 'UPS round-trip + verified');

  // 5) Wrong base ROM is rejected with wrongBaseRom set.
  var rejected = false;
  try {
    applyRomPatch(
        Uint8List.fromList(List.filled(8, 99)), Uint8List.fromList(_buildBps(src, bpsDst)));
  } on RomPatchException catch (e) {
    rejected = e.wrongBaseRom;
  }
  expect(rejected, 'wrong base ROM rejected');

  print(_fails == 0 ? '\nALL PASS' : '\n$_fails FAILED');
}

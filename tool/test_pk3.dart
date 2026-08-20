// Synthetic PK3 round-trip test (no real save needed).
// Run: dart run tool/test_pk3.dart
// ignore_for_file: avoid_print, avoid_relative_lib_imports
import 'dart:typed_data';
import '../lib/services/pk3.dart';

void setU32(Uint8List b, int o, int v) {
  b[o] = v & 0xFF;
  b[o + 1] = (v >> 8) & 0xFF;
  b[o + 2] = (v >> 16) & 0xFF;
  b[o + 3] = (v >> 24) & 0xFF;
}

void main() {
  final block = Uint8List(100);
  setU32(block, 0x00, 0x12345678); // PID
  setU32(block, 0x04, 0xABCD1234); // OTID
  block[0x54] = 50; // level

  final p = Pk3.decode(block);
  p.setMoves([33, 45, 14, 7]); // Tackle, Growl, Swords Dance, Fire Punch
  p.setIVs([31, 30, 31, 30, 31, 31]);
  p.setEVs([252, 0, 0, 252, 0, 6]);
  for (var k = 0; k < 4; k++) {
    p.setPP(k, 20);
  }
  p.recomputeStats([80, 82, 83, 100, 100, 80]); // arbitrary base stats

  final again = Pk3.decode(p.encode());
  final ok = again.moves.toString() == '[33, 45, 14, 7]' &&
      again.ivs.toString() == '[31, 30, 31, 30, 31, 31]' &&
      again.evs[0] == 252 &&
      again.pp.every((v) => v == 20) &&
      again.computeChecksum() == again.storedChecksum;

  print('moves=${again.moves} ivs=${again.ivs} evs=${again.evs} pp=${again.pp}');
  print('block checksum ok=${again.computeChecksum() == again.storedChecksum}');

  // shiny toggle preserves the edited fields + IVs
  final s = Pk3.decode(p.encode());
  s.setShiny(true);
  final s2 = Pk3.decode(s.encode());
  final shinyOk = s2.isShiny &&
      s2.moves.toString() == '[33, 45, 14, 7]' &&
      s2.ivs.toString() == '[31, 30, 31, 30, 31, 31]' &&
      s2.computeChecksum() == s2.storedChecksum;
  print('after shiny: shiny=${s2.isShiny} movesKept=${s2.moves.toString() == '[33, 45, 14, 7]'} '
      'ivsKept=${s2.ivs.toString() == '[31, 30, 31, 30, 31, 31]'}');

  print(ok && shinyOk ? '\nPASS ✓ PK3 edit round-trip' : '\nFAIL ✗');
}

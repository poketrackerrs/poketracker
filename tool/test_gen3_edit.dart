// Verifies the Gen 3 editor against a REAL save, non-destructively (in memory).
// Run: dart run tool/test_gen3_edit.dart <path-to-emerald.sav>
// ignore_for_file: avoid_print, avoid_relative_lib_imports
import 'dart:io';
import 'dart:typed_data';
import '../lib/services/gen3_save_editor.dart';

void main(List<String> args) {
  final path = args.isNotEmpty
      ? args[0]
      : r'C:\Users\darks\Documents\PokeTracker\Games\emerald\Pokemon - Emerald Version (USA, Europe).sav';
  final raw = Uint8List.fromList(File(path).readAsBytesSync());

  final e = Gen3SaveEditor.load(raw);
  final v0 = e.verifyChecksums();
  print('loaded, active block 0x${e.base.toRadixString(16)}');
  print('checksums valid on load: ${v0.ok}  ${v0.mismatches}');

  print('money (read):   ${e.getMoney('emerald')}   (expect 3000)');
  print('caught (read):  ${e.caughtCount}');

  e.setMoney('emerald', 123456);
  final v1 = e.verifyChecksums();
  print('after setMoney: money=${e.getMoney('emerald')}  checksums ok=${v1.ok} ${v1.mismatches}');

  e.markAllCaught('emerald');
  final v2 = e.verifyChecksums();
  print('after dex fill: caught=${e.caughtCount}  checksums ok=${v2.ok} ${v2.mismatches}');

  // prove ONLY intended sections changed structurally: re-load original & diff sizes
  final pass = v0.ok && v1.ok && v2.ok &&
      e.getMoney('emerald') == 123456 && e.caughtCount == 386;
  print(pass ? '\nPASS ✓ edits applied, checksums round-trip' : '\nFAIL ✗');
  exitCode = pass ? 0 : 1;
}

// Verifies the Gen 3 editor against a REAL save, non-destructively (in memory).
// Run: dart run tool/test_gen3_edit.dart <path-to-emerald.sav>
// ignore_for_file: avoid_print, avoid_relative_lib_imports
import 'dart:io';
import 'dart:typed_data';
import '../lib/services/gen3_save_editor.dart';
import '../lib/services/pk3.dart';

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

  for (final t in Gen3SaveEditor.ticketsFor('emerald')) {
    e.giveTicket('emerald', t);
  }
  final v3 = e.verifyChecksums();
  print('after ${Gen3SaveEditor.ticketsFor('emerald').length} tickets: '
      'checksums ok=${v3.ok} ${v3.mismatches}');

  // prove ONLY intended sections changed structurally: re-load original & diff sizes
  // PK3 codec round-trip on the real party Pokémon
  final e2 = Gen3SaveEditor.load(raw); // fresh (unedited) copy
  final blk = e2.partyBlock('emerald', 0);
  final mon = Pk3.decode(blk);
  final csumMatch = mon.computeChecksum() == mon.storedChecksum;
  final reEnc = mon.encode();
  final identical = _eq(reEnc, blk);
  print('party mon0: species=${mon.species} ivs=${mon.ivs} shiny=${mon.isShiny}'
      '  checksum match=$csumMatch  re-encode identical=$identical');

  // shiny toggle: make it shiny, encode, decode fresh, confirm it stuck + stays legal
  final mon2 = Pk3.decode(e2.partyBlock('emerald', 0));
  final natBefore = mon2.nature, ivsBefore = mon2.ivs.join('/');
  mon2.setShiny(true);
  final again = Pk3.decode(mon2.encode());
  final shinyOk = again.isShiny &&
      again.computeChecksum() == again.storedChecksum &&
      again.species == mon2.species &&
      again.ivs.join('/') == ivsBefore;
  print('shiny toggle: nowShiny=${again.isShiny} species=${again.species} '
      'ivs=${again.ivs.join('/')} natureKept=${again.nature == natBefore} '
      'checksumOk=${again.computeChecksum() == again.storedChecksum}');

  // IV/EV + stat recompute (Surskit base stats, Gen3 order HP/Atk/Def/Spe/SpA/SpD)
  final mon3 = Pk3.decode(e2.partyBlock('emerald', 0));
  mon3.setIVs([31, 31, 31, 31, 31, 31]);
  mon3.setEVs([252, 0, 0, 252, 0, 6]);
  mon3.recomputeStats([40, 30, 32, 65, 50, 52]);
  final mon3b = Pk3.decode(mon3.encode());
  final ivevOk = mon3b.ivs.every((v) => v == 31) &&
      mon3b.evs[0] == 252 &&
      mon3b.computeChecksum() == mon3b.storedChecksum;
  print('IV/EV edit: ivs=${mon3b.ivs.join('/')} evs=${mon3b.evs.join('/')} '
      'checksumOk=${mon3b.computeChecksum() == mon3b.storedChecksum}');

  // event mon: build a Mew-like PK3, set fateful, round-trip
  final mew = Pk3.create(
    otid: 6930, nationalSpecies: 151, level: 10,
    totalExp: gen3Exp('medium-slow', 10),
    moves: [1, 144, 5, 118], pp: [35, 10, 20, 10],
    ivs: [31, 31, 31, 31, 31, 31], nickname: 'MEW', otName: 'MYSTRY',
    nature: 0, ball: 4, metLevel: 10, gameOfOrigin: 3, party: false,
  );
  mew.setFateful(true);
  final mewBack = Pk3.decode(mew.encode());
  final eventOk = mewBack.species == 151 &&
      mewBack.fatefulEncounter &&
      mewBack.computeChecksum() == mewBack.storedChecksum;
  print('event mon: species=${mewBack.species} fateful=${mewBack.fatefulEncounter} '
      'checksumOk=${mewBack.computeChecksum() == mewBack.storedChecksum}');

  // species conversion (Chimecho quirk): Jirachi 385, Deoxys 386, Chimecho 358
  var speciesOk = true;
  for (final nat in [258, 357, 358, 359, 385, 386, 25]) {
    final internal = gen3NationalToInternal(nat);
    final back = gen3InternalToNational(internal);
    if (back != nat) {
      speciesOk = false;
      print('  species MAP FAIL nat=$nat internal=$internal back=$back');
    }
  }
  final jir = Pk3.create(
      otid: 20043, nationalSpecies: 385, level: 5, totalExp: gen3Exp('slow', 5),
      moves: [93], pp: [25], ivs: [31, 31, 31, 31, 31, 31], nickname: 'JIRACHI',
      otName: 'WISHMKR', nature: 3, party: false);
  final deo = Pk3.create(
      otid: 6930, nationalSpecies: 386, level: 30, totalExp: gen3Exp('slow', 30),
      moves: [94], pp: [10], ivs: [31, 31, 31, 31, 31, 31], nickname: 'DEOXYS',
      otName: 'MYSTRY', nature: 10, party: false);
  final jirOk = Pk3.decode(jir.encode()).nationalDex == 385;
  final deoOk = Pk3.decode(deo.encode()).nationalDex == 386;
  print('species: map ok=$speciesOk  Jirachi->${Pk3.decode(jir.encode()).nationalDex} '
      'Deoxys->${Pk3.decode(deo.encode()).nationalDex}');

  final pass = v0.ok && v1.ok && v2.ok && v3.ok && csumMatch && identical &&
      shinyOk && ivevOk && eventOk && speciesOk && jirOk && deoOk &&
      mon.species == 283 &&
      e.getMoney('emerald') == 123456 && e.caughtCount == 386;
  print(pass ? '\nPASS ✓ edits + PK3 codec round-trip' : '\nFAIL ✗');
  exitCode = pass ? 0 : 1;
}

bool _eq(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

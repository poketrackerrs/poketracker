// Throwaway harness: runs the real save parser against a save file and prints
// what it extracted. Run: dart run tool/validate_save.dart "<path to .sav>"
import 'dart:io';
import 'package:poketracker/services/save_service.dart';

void main(List<String> args) {
  final path = args.isNotEmpty
      ? args[0]
      : r'C:\Users\darks\Documents\PokeTracker\Games\emerald\Pokemon - Emerald Version (USA, Europe).sav';
  final bytes = File(path).readAsBytesSync();
  stdout.writeln('file: $path  (${bytes.length} bytes)');
  final d = SaveService().parse(bytes, generation: 3, versionId: 'emerald');
  stdout.writeln('trainer name : "${d.trainerName}"');
  stdout.writeln('trainer ID   : ${d.trainerId}');
  stdout.writeln('secret ID    : ${d.secretId}');
  stdout.writeln('play time    : ${d.playTimeText}');
  stdout.writeln('caught count : ${d.caughtCount}');
  final ids = d.caughtDex.toList()..sort();
  stdout.writeln('caught dex ids (first 30): ${ids.take(30).toList()}');
  stdout.writeln('highest caught dex id: ${ids.isEmpty ? "-" : ids.last}');
}

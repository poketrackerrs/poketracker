import 'dart:io';
import 'package:flutter/services.dart' show MethodChannel;
import '../data/games_data.dart';

/// Mirrors downloaded ROMs into a shared folder laid out the way Lemuroid's
/// scanner expects — `<shared>/PokeTracker/<platform>/<file>` — so pointing
/// Lemuroid at `<shared>/PokeTracker` once makes every game show up.
///
/// Android only. Lemuroid can't be launched into with a specific ROM (no
/// external-launch intent), and it can't read the app's private storage, so
/// the only way to feed it our library is to copy files somewhere it can scan.
class LemuroidSyncService {
  static const _channel = MethodChannel('poketracker/storage');

  /// Lemuroid platform-folder name for a game's generation, or null if the
  /// generation has no handheld emulator we sync (Gen 6+).
  static String? platformFolder(int generation) {
    switch (generation) {
      case 1:
        return 'gb';
      case 2:
        return 'gbc';
      case 3:
        return 'gba';
      case 4:
      case 5:
        return 'nds';
      default:
        return null;
    }
  }

  Future<bool> hasAccess() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('hasAllFilesAccess') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens the system "All files access" screen if needed. Returns true if
  /// access was already granted (no trip to Settings required).
  Future<bool> requestAccess() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('requestAllFilesAccess') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// The shared folder to point Lemuroid at, e.g.
  /// `/storage/emulated/0/PokeTracker`. Null off Android or if unavailable.
  Future<String?> targetRoot() async {
    if (!Platform.isAndroid) return null;
    try {
      final ext = await _channel.invokeMethod<String>('externalStorageDir');
      if (ext == null || ext.isEmpty) return null;
      return '$ext${Platform.pathSeparator}PokeTracker';
    } catch (_) {
      return null;
    }
  }

  /// Copies one ROM into its platform subfolder. Best-effort: silently returns
  /// false if access is missing, the generation isn't syncable, or the copy
  /// fails. Skips the copy when an identical file (same size) is already there.
  Future<bool> mirror(String gameId, String romPath) async {
    if (!Platform.isAndroid) return false;
    final src = File(romPath);
    if (!await src.exists()) return false;
    final gen = _generationFor(gameId);
    if (gen == null) return false;
    final folder = platformFolder(gen);
    if (folder == null) return false;
    final root = await targetRoot();
    if (root == null) return false;
    if (!await hasAccess()) return false;
    try {
      final sep = Platform.pathSeparator;
      final dir = Directory('$root$sep$folder');
      if (!await dir.exists()) await dir.create(recursive: true);
      final name = romPath.split(RegExp(r'[\\/]')).last;
      final dest = File('${dir.path}$sep$name');
      if (await dest.exists() &&
          await dest.length() == await src.length()) {
        return true; // already mirrored
      }
      await src.copy(dest.path);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Mirrors every installed ROM. [installed] maps gameId -> file path (null if
  /// not downloaded). Returns the number of games now present in the folder.
  Future<int> syncAll(Map<String, String?> installed) async {
    if (!Platform.isAndroid) return 0;
    if (!await hasAccess()) return 0;
    var count = 0;
    for (final entry in installed.entries) {
      final path = entry.value;
      if (path == null) continue;
      if (await mirror(entry.key, path)) count++;
    }
    return count;
  }

  int? _generationFor(String gameId) {
    for (final g in kGames) {
      if (g.id == gameId) return g.generation;
    }
    return null;
  }
}

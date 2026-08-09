import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/games_data.dart';
import '../models/game.dart';
import '../models/progress.dart';
import '../services/storage_service.dart';
import '../services/library_service.dart';
import '../services/emulator_service.dart';

/// Central app state: holds progress for every game and persists on change.
class AppState extends ChangeNotifier {
  final StorageService _storage = StorageService();
  final LibraryService _library = LibraryService();
  final EmulatorService _emu = EmulatorService();
  final Map<String, GameProgress> _progress = {};
  List<DetectedEmulator> _detectedEmulators = [];

  List<DetectedEmulator> get detectedEmulators => _detectedEmulators;

  // ---- Games library / downloads --------------------------------------
  Map<String, String> _driveFolders = {}; // gameId -> Drive folder id
  final Map<String, String?> _installed = {}; // gameId -> filename or null
  final Map<String, double> _downloadProgress = {}; // gameId -> 0..1
  String _libraryPath = '';

  String get libraryPath => _libraryPath;

  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;

  bool _loaded = false;
  bool get isLoaded => _loaded;

  Future<void> init() async {
    final saved = await _storage.load();
    _progress.addAll(saved);
    final prefs = await SharedPreferences.getInstance();
    _themeMode = ThemeMode.values[
        (prefs.getInt('thememode') ?? ThemeMode.system.index)
            .clamp(0, ThemeMode.values.length - 1)];
    await _loadLibrary();
    _loaded = true;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('thememode', mode.index);
  }

  /// Opens an external URL in the default browser.
  Future<void> openExternal(String url) async {
    if (Platform.isWindows) {
      await Process.start('explorer.exe', [url]);
    } else if (Platform.isMacOS) {
      await Process.start('open', [url]);
    } else if (Platform.isLinux) {
      await Process.start('xdg-open', [url]);
    }
  }

  Future<void> _loadLibrary() async {
    _driveFolders = await _library.loadDriveFolders();
    await refreshInstalled();
    _detectedEmulators = await _emu.detectAll();
  }

  Future<void> refreshEmulators() async {
    _detectedEmulators = await _emu.detectAll();
    notifyListeners();
  }

  /// Records a user-picked emulator executable and re-scans.
  Future<void> setEmulatorPath(String emulatorName, String path) async {
    await _emu.setManualPath(emulatorName, path);
    await refreshEmulators();
  }

  /// Builds the game->Drive-folder map from a shared parent folder link, so the
  /// download buttons appear. Returns how many games were linked.
  Future<int> importDriveSources(String link) async {
    final n = await _library.importDriveFolderTree(link);
    _driveFolders = await _library.loadDriveFolders();
    notifyListeners();
    return n;
  }

  /// The installed emulator that can run a game, or null. Switch-era games
  /// (Gen 8-9 and Let's Go) have no supported emulator in the catalog.
  DetectedEmulator? emulatorForGame(Game game) {
    if (game.generation >= 8 ||
        game.id == 'lets-go-pikachu' ||
        game.id == 'lets-go-eevee') {
      return null;
    }
    for (final d in _detectedEmulators) {
      if (d.installed && d.emu.generations.contains(game.generation)) return d;
    }
    return null;
  }

  bool canLaunch(Game game) =>
      isInstalled(game.id) && emulatorForGame(game) != null;

  /// Launches a game's ROM in its detected emulator.
  Future<void> launchGame(Game game) async {
    final rom = _installed[game.id];
    final d = emulatorForGame(game);
    if (rom == null || d?.path == null) return;
    await _emu.launch(d!.path!, rom);
  }

  /// Re-scans emulators if needed, then launches. Returns true if it launched.
  Future<bool> tryLaunchGame(Game game) async {
    if (!canLaunch(game)) await refreshEmulators();
    if (canLaunch(game)) {
      await launchGame(game);
      return true;
    }
    return false;
  }

  /// Rescans the library so installed/removed ROMs are reflected. Each game's
  /// value is the full file path, or null if its subfolder has no ROM.
  Future<void> refreshInstalled() async {
    final dir = await _library.libraryDir();
    _libraryPath = dir.path;
    for (final g in kGames) {
      final f = await _library.fileForGame(g.id);
      _installed[g.id] = f?.path;
    }
    notifyListeners();
  }

  bool isInstalled(String gameId) => _installed[gameId] != null;
  bool canDownload(String gameId) => _driveFolders.containsKey(gameId);
  double? downloadProgress(String gameId) => _downloadProgress[gameId];

  /// Downloads a game's ROM from its configured Drive folder into the library.
  Future<void> downloadGame(String gameId) async {
    final folderId = _driveFolders[gameId];
    if (folderId == null || _downloadProgress.containsKey(gameId)) return;
    _downloadProgress[gameId] = 0;
    notifyListeners();
    try {
      final file = await _library.downloadFromFolder(gameId, folderId, (p) {
        _downloadProgress[gameId] = p;
        notifyListeners();
      });
      _installed[gameId] = file.path;
    } finally {
      _downloadProgress.remove(gameId);
      notifyListeners();
    }
  }

  Future<void> deleteGameFile(String gameId) async {
    await _library.deleteForGame(gameId);
    _installed[gameId] = null;
    notifyListeners();
  }

  /// Opens the library folder in the OS file manager.
  Future<void> openLibraryFolder() async {
    if (_libraryPath.isEmpty) return;
    if (Platform.isWindows) {
      await Process.start('explorer.exe', [_libraryPath]);
    } else if (Platform.isMacOS) {
      await Process.start('open', [_libraryPath]);
    } else if (Platform.isLinux) {
      await Process.start('xdg-open', [_libraryPath]);
    }
  }

  /// Reveals a downloaded game's ROM in the file manager (selects the file on
  /// Windows); falls back to opening the library folder.
  Future<void> revealGameFile(String gameId) async {
    final path = _installed[gameId];
    if (path == null) return openLibraryFolder();
    if (Platform.isWindows) {
      await Process.start('explorer.exe', ['/select,$path']);
    } else {
      await openLibraryFolder();
    }
  }

  /// Returns progress for a game, creating an empty record if needed.
  GameProgress progressFor(String gameId) {
    return _progress.putIfAbsent(gameId, () => GameProgress(gameId: gameId));
  }

  void _persist() {
    notifyListeners();
    _storage.save(_progress);
  }

  // ---- Milestones -----------------------------------------------------
  void setMilestone(String gameId, String milestone, bool done) {
    progressFor(gameId).milestones[milestone] = done;
    _persist();
  }

  // ---- Pokedex --------------------------------------------------------
  void setDexSeen(String gameId, int value) {
    progressFor(gameId).dexSeen = value.clamp(0, 100000);
    _persist();
  }

  void setDexCaught(String gameId, int value) {
    progressFor(gameId).dexCaught = value.clamp(0, 100000);
    _persist();
  }

  // ---- Caught species (per-game dex) ----------------------------------
  void setCaught(String gameId, int speciesId, bool caught) {
    final set = progressFor(gameId).caughtSpecies;
    if (caught) {
      set.add(speciesId);
    } else {
      set.remove(speciesId);
    }
    _persist();
  }

  bool isCaught(String gameId, int speciesId) =>
      progressFor(gameId).caughtSpecies.contains(speciesId);

  int caughtCount(String gameId) => progressFor(gameId).caughtSpecies.length;

  // ---- Team -----------------------------------------------------------
  void addTeamMember(String gameId) {
    final team = progressFor(gameId).team;
    if (team.length < 6) team.add(TeamMember());
    _persist();
  }

  void updateTeamMember(String gameId, int index, TeamMember member) {
    progressFor(gameId).team[index] = member;
    _persist();
  }

  void removeTeamMember(String gameId, int index) {
    progressFor(gameId).team.removeAt(index);
    _persist();
  }

  // ---- Shiny hunts ----------------------------------------------------
  void addShinyHunt(String gameId) {
    progressFor(gameId).shinyHunts.add(ShinyHunt());
    _persist();
  }

  void updateShinyHunt(String gameId, int index, ShinyHunt hunt) {
    progressFor(gameId).shinyHunts[index] = hunt;
    _persist();
  }

  void removeShinyHunt(String gameId, int index) {
    progressFor(gameId).shinyHunts.removeAt(index);
    _persist();
  }

  // ---- Derived stats --------------------------------------------------
  /// Overall completion for a game as a 0.0-1.0 fraction, averaging
  /// milestone progress and caught-dex progress.
  double completion(Game game) {
    final p = progressFor(game.id);
    final milestoneTotal = game.milestones.length;
    final milestoneDone =
        p.milestones.values.where((v) => v).length.clamp(0, milestoneTotal);
    final milestoneFrac =
        milestoneTotal == 0 ? 0.0 : milestoneDone / milestoneTotal;
    // Prefer the real per-species caught set; fall back to the manual counter.
    final caught = p.caughtSpecies.isNotEmpty ? p.caughtSpecies.length : p.dexCaught;
    final dexFrac =
        game.dexTotal == 0 ? 0.0 : (caught / game.dexTotal).clamp(0, 1);
    return (milestoneFrac + dexFrac) / 2;
  }
}

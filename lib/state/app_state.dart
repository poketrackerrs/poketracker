import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/games_data.dart';
import '../models/game.dart';
import '../models/progress.dart';
import '../models/save_models.dart';
import '../services/storage_service.dart';
import '../services/library_service.dart';
import '../services/emulator_service.dart';
import '../services/save_service.dart';
import '../services/pokedex_service.dart';

/// Central app state: holds progress for every game and persists on change.
class AppState extends ChangeNotifier {
  final StorageService _storage = StorageService();
  final LibraryService _library = LibraryService();
  final EmulatorService _emu = EmulatorService();
  final SaveService _save = SaveService();
  final PokedexService _pokedex = PokedexService();
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

  // ---- Appearance ------------------------------------------------------
  static const Color defaultAccent = Color(0xFFEE1515); // Poke Ball red
  Color _accent = defaultAccent;
  Color get accent => _accent;

  bool _regionTint = true;
  bool get regionTint => _regionTint;

  bool _loaded = false;
  bool get isLoaded => _loaded;

  Future<void> init() async {
    final saved = await _storage.load();
    _progress.addAll(saved);
    final prefs = await SharedPreferences.getInstance();
    _themeMode = ThemeMode.values[
        (prefs.getInt('thememode') ?? ThemeMode.system.index)
            .clamp(0, ThemeMode.values.length - 1)];
    _accent = Color(prefs.getInt('accent') ?? defaultAccent.toARGB32());
    _regionTint = prefs.getBool('regiontint') ?? true;
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

  Future<void> setAccent(Color color) async {
    _accent = color;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('accent', color.toARGB32());
  }

  Future<void> setRegionTint(bool value) async {
    _regionTint = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('regiontint', value);
  }

  // ---- Home dashboard stats -------------------------------------------
  /// Games with any recorded progress.
  int get startedCount => kGames.where((g) => completion(g) > 0).length;

  /// Total species caught across every game.
  int get totalCaught =>
      _progress.values.fold(0, (a, p) => a + p.caughtSpecies.length);

  /// Total gym badges earned across every game (milestones named "…Badge").
  int get totalBadges => _progress.values.fold(
      0,
      (a, p) =>
          a +
          p.milestones.entries
              .where((e) => e.value && e.key.contains('Badge'))
              .length);

  /// Opens an external URL (store page, etc.) in the default browser/app.
  /// Uses url_launcher so it works on Android and iOS as well as desktop.
  Future<void> openExternal(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
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

  // ---- Save-file auto-tracker -----------------------------------------

  /// A manually-set save-file path for a game (overrides auto-discovery).
  Future<String?> savePath(String gameId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('savepath:$gameId');
  }

  Future<void> setSavePath(String gameId, String path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path.trim().isEmpty) {
      await prefs.remove('savepath:$gameId');
    } else {
      await prefs.setString('savepath:$gameId', path.trim());
    }
  }

  /// Finds a game's save file: a user-set path, else a save alongside the ROM.
  Future<File?> _findSaveFile(String gameId) async {
    final manual = await savePath(gameId);
    if (manual != null && manual.isNotEmpty && File(manual).existsSync()) {
      return File(manual);
    }
    final rom = _installed[gameId];
    if (rom == null) return null;
    final dir = File(rom).parent;
    if (!dir.existsSync()) return null;
    const exts = ['.sav', '.srm', '.sav1', '.dsv', '.sa1', '.fla'];
    final dot = rom.lastIndexOf('.');
    final romBase = dot == -1 ? rom : rom.substring(0, dot);
    for (final e in exts) {
      final f = File('$romBase$e');
      if (f.existsSync()) return f;
    }
    for (final f in dir.listSync().whereType<File>()) {
      final lower = f.path.toLowerCase();
      if (exts.any((e) => lower.endsWith(e))) return f;
    }
    return null;
  }

  /// Reads and parses a game's save into a preview [SaveData], resolving team
  /// names. Returns null if no save file is found. Throws [SaveParseException]
  /// with a friendly message on a bad/unsupported save.
  Future<SaveData?> scanSave(Game game) async {
    final file = await _findSaveFile(game.id);
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    final data = _save.parse(
      Uint8List.fromList(bytes),
      generation: game.generation,
      versionId: game.version,
    );
    if (data.team.any((m) => m.dexId != null && m.name == null)) {
      try {
        final index = await _pokedex.loadIndex();
        final byId = {for (final s in index) s.id: s.name};
        for (final m in data.team) {
          if (m.dexId != null) m.name = byId[m.dexId!];
        }
      } catch (_) {}
    }
    return data;
  }

  /// Writes selected fields of a parsed save into a game's progress. Caught
  /// species are merged (never removed); team replaces the current team.
  Future<void> applySaveData(
    Game game,
    SaveData data, {
    bool dex = true,
    bool badges = true,
    bool team = true,
  }) async {
    final p = progressFor(game.id);
    if (dex) {
      p.caughtSpecies.addAll(data.caughtDex);
      if (data.seenCount > p.dexSeen) p.dexSeen = data.seenCount;
    }
    if (badges && data.badgeCount != null) {
      final n = data.badgeCount!.clamp(0, game.milestones.length);
      for (var i = 0; i < n; i++) {
        p.milestones[game.milestones[i]] = true;
      }
    }
    if (team && data.team.isNotEmpty) {
      p.team
        ..clear()
        ..addAll(data.team.map((m) => TeamMember(
              species: m.name ?? (m.dexId != null ? '#${m.dexId}' : ''),
              nickname: m.nickname ?? '',
              level: m.level,
            )));
    }
    _persist();
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

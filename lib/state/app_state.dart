import 'dart:async';
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
import '../services/emulator_bios.dart';
import '../services/library_service.dart';
import '../services/emulator_service.dart';
import '../services/save_service.dart';
import '../services/gen3_save_editor.dart';
import '../services/pk3.dart';
import '../services/pokedex_service.dart';
import '../services/lemuroid_sync.dart';

/// Result of a launch attempt.
enum LaunchOutcome {
  /// The ROM was handed to the emulator.
  launched,

  /// The emulator opened but couldn't auto-load the ROM (it doesn't accept the
  /// launch intent) — the user must load the ROM from inside it.
  handoffFailed,

  /// No installed emulator can run this game.
  noEmulator,
}

/// Central app state: holds progress for every game and persists on change.
class AppState extends ChangeNotifier {
  final StorageService _storage = StorageService();
  final LibraryService _library = LibraryService();
  final EmulatorService _emu = EmulatorService();
  final SaveService _save = SaveService();
  final PokedexService _pokedex = PokedexService();
  final LemuroidSyncService _lemuroid = LemuroidSyncService();
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

  bool _consoleMode = true; // Games page: console shelf (true) vs classic list
  bool get consoleMode => _consoleMode;

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
    _consoleMode = prefs.getBool('consolemode') ?? true;
    await _loadLibrary();
    _loaded = true;
    notifyListeners();
    // Best-effort, off the critical path: pull the DS BIOS from the user's
    // private Drive folder if it's linked and the files aren't here yet.
    unawaited(_autoFetchBiosIfNeeded());
  }

  /// Byte lengths that count as a valid file, keyed by target name (single
  /// source of truth is EmulatorBios' slot list).
  Map<String, List<int>> get _biosSizes =>
      {for (final s in kNdsBiosSlots) s.fileName: s.sizes};

  Future<void> _autoFetchBiosIfNeeded() async {
    if (!(Platform.isWindows || Platform.isAndroid)) return;
    try {
      final bios = EmulatorBios();
      if (await bios.hasAllNds()) return;
      final cores = await bios.sysDirPath();
      final got = await _library.fetchNdsBios(cores, _biosSizes);
      if (got.isNotEmpty) notifyListeners();
    } catch (_) {}
  }

  /// User-triggered BIOS fetch (from the DS BIOS screen). Returns how many of
  /// the three files are present afterwards.
  Future<int> fetchDsBiosFromDrive() async {
    final bios = EmulatorBios();
    final cores = await bios.sysDirPath();
    final got = await _library.fetchNdsBios(cores, _biosSizes);
    notifyListeners();
    return got.length;
  }

  /// Whether a private BIOS Drive folder is linked (so the "Fetch from Drive"
  /// action is worth offering).
  bool get hasBiosDriveFolder => _driveFolders.containsKey(kBiosFolderKey);

  // ---- Nintendo 3DS (Windows): pull update CIAs from Drive ------------
  /// Whether a private "3ds firmware" Drive folder is linked.
  bool get has3dsDriveFolder => _driveFolders.containsKey(k3dsFolderKey);

  /// Records a direct link to the user's 3DS firmware/CIA Drive folder.
  Future<void> link3dsFolder(String link) async {
    await _library.set3dsFolderFromLink(link);
    _driveFolders = await _library.loadDriveFolders();
    notifyListeners();
  }

  /// Downloads the 3DS system files + update CIAs from the linked Drive folder
  /// into `Documents/PokeTracker/3DS`. Returns how many files are present.
  Future<int> fetch3dsUpdatesFromDrive() async {
    final n = await _library.fetch3dsUpdates();
    notifyListeners();
    return n;
  }

  /// Opens the managed 3DS folder in the OS file manager, landing on the CIAs:
  /// the `updates` subfolder when it has files, otherwise the base folder.
  Future<void> open3dsFolder() async {
    final base = (await _library.threeDsDir()).path;
    final updates = Directory('$base${Platform.pathSeparator}updates');
    final hasUpdates = updates.existsSync() &&
        updates.listSync().whereType<File>().isNotEmpty;
    final dir = hasUpdates ? updates.path : base;
    if (Platform.isWindows) {
      await Process.start('explorer.exe', [dir]);
    } else if (Platform.isMacOS) {
      await Process.start('open', [dir]);
    } else if (Platform.isLinux) {
      await Process.start('xdg-open', [dir]);
    }
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

  Future<void> setConsoleMode(bool value) async {
    _consoleMode = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('consolemode', value);
  }

  // ---- Home dashboard stats -------------------------------------------
  /// Games with any recorded progress.
  int get startedCount => kGames.where((g) => completion(g) > 0).length;

  /// Total base species caught across every game (excludes alternate forms).
  int get totalCaught => _progress.values.fold(
      0, (a, p) => a + p.caughtSpecies.where((id) => id < 10000).length);

  /// The set of national-dex ids caught in any game (for the global Pokedex).
  Set<int> get allCaughtSpecies {
    final s = <int>{};
    for (final p in _progress.values) {
      s.addAll(p.caughtSpecies);
    }
    return s;
  }

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

  // ------------------------------------------------ Gen 3 save editor (write)
  /// Current editable Gen 3 values, or null if there's no valid Gen 3 save.
  Future<({int money, int caught})?> readGen3Save(Game game) async {
    if (game.generation != 3) return null;
    final file = await _findSaveFile(game.id);
    if (file == null) return null;
    try {
      final e =
          Gen3SaveEditor.load(Uint8List.fromList(await file.readAsBytes()));
      if (!e.verifyChecksums().ok) return null;
      return (money: e.getMoney(game.version), caught: e.caughtCount);
    } catch (_) {
      return null;
    }
  }

  /// Reads a Gen 3 party (decrypting each PK3) for the editor's Pokémon view.
  Future<List<Gen3PartyMon>?> readGen3Party(Game game) async {
    if (game.generation != 3) return null;
    final file = await _findSaveFile(game.id);
    if (file == null) return null;
    try {
      final e =
          Gen3SaveEditor.load(Uint8List.fromList(await file.readAsBytes()));
      if (!e.verifyChecksums().ok) return null;
      final out = <Gen3PartyMon>[];
      final n = e.partyCount(game.version).clamp(0, 6);
      for (var i = 0; i < n; i++) {
        final m = Pk3.decode(e.partyBlock(game.version, i));
        if (m.isEmpty) continue;
        out.add(Gen3PartyMon(
          slot: i,
          dex: m.species,
          level: m.level,
          shiny: m.isShiny,
          nature: m.nature,
          ivs: m.ivs,
          evs: m.evs,
          moves: m.moves,
        ));
      }
      try {
        final byId = {for (final s in await _pokedex.loadIndex()) s.id: s.name};
        for (final m in out) {
          m.name = byId[m.dex];
        }
      } catch (_) {}
      return out;
    } catch (_) {
      return null;
    }
  }

  /// The moves a species can legally know in Gen 3 (any RSE/FRLG method),
  /// as (id, name), deduped + sorted. For the move-editor dropdowns.
  Future<List<({int id, String name})>> gen3Learnset(int dex) async {
    try {
      final d = await _pokedex.fetchDetail(dex);
      final seen = <int>{};
      final out = <({int id, String name})>[];
      for (final mv in d.moves) {
        if (mv.generation != 3 || mv.id == 0 || !seen.add(mv.id)) continue;
        out.add((id: mv.id, name: mv.name));
      }
      out.sort((a, b) => a.name.compareTo(b.name));
      return out;
    } catch (_) {
      return [];
    }
  }

  /// Applies Gen 3 edits and writes the save back, backing up the original
  /// first. Refuses to write unless checksums are valid before AND after the
  /// edit. Returns a human-readable status message.
  Future<String> writeGen3Save(Game game,
      {int? money,
      bool completeDex = false,
      List<Gen3Ticket> tickets = const [],
      Map<int, PartyEdit> partyEdits = const {}}) async {
    if (game.generation != 3) return 'Save editing is Gen 3-only for now.';
    final file = await _findSaveFile(game.id);
    if (file == null) return 'No save file found for ${game.title}.';
    final raw = Uint8List.fromList(await file.readAsBytes());
    final Gen3SaveEditor e;
    try {
      e = Gen3SaveEditor.load(raw);
    } catch (err) {
      return 'Not a readable GBA save.';
    }
    if (!e.verifyChecksums().ok) {
      return 'Save checksums look wrong — refusing to edit it.';
    }
    if (money != null) e.setMoney(game.version, money);
    if (completeDex) e.markAllCaught(game.version);
    for (final t in tickets) {
      e.giveTicket(game.version, t);
    }
    for (final entry in partyEdits.entries) {
      final ed = entry.value;
      final m = Pk3.decode(e.partyBlock(game.version, entry.key));
      if (m.isEmpty) continue;
      if (ed.level != null) {
        final rate = await _pokedex.growthRate(m.species);
        m.setLevel(ed.level!, gen3Exp(rate, ed.level!));
      }
      if (ed.nature != null) m.setNature(ed.nature!);
      if (ed.shiny != null) m.setShiny(ed.shiny!);
      if (ed.ivs != null) m.setIVs(ed.ivs!);
      if (ed.evs != null) m.setEVs(ed.evs!);
      if (ed.moves != null) {
        m.setMoves(ed.moves!);
        for (var k = 0; k < 4; k++) {
          final id = k < ed.moves!.length ? ed.moves![k] : 0;
          m.setPP(k, id == 0 ? 0 : await _pokedex.movePP(id));
        }
      }
      if (ed.changesStats) {
        try {
          final st = (await _pokedex.fetchDetail(m.species)).stats;
          int g(String k) => st[k] ?? 50;
          m.recomputeStats([
            g('hp'), g('attack'), g('defense'),
            g('speed'), g('special-attack'), g('special-defense'),
          ]);
        } catch (_) {/* offline: stats stay as-is, IV/EV still applied */}
      }
      e.writePartyBlock(game.version, entry.key, m.encode());
    }
    if (!e.verifyChecksums().ok) {
      return 'Edit produced bad checksums — aborted, your save was NOT changed.';
    }
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final bak = File('${file.path}.bak-$stamp');
    await bak.writeAsBytes(raw, flush: true); // original, untouched
    await file.writeAsBytes(e.toBytes(), flush: true); // edited copy
    return 'Saved. Backup written next to the save '
        '(${bak.uri.pathSegments.last}). Reload it in your emulator to check.';
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
      // Skip library-only emulators (e.g. Lemuroid) — they can't be launched
      // into with a specific ROM, so the Play button must not select them.
      if (!d.emu.launchable) continue;
      if (d.installed && d.emu.generations.contains(game.generation)) return d;
    }
    return null;
  }

  bool canLaunch(Game game) =>
      isInstalled(game.id) && emulatorForGame(game) != null;

  /// True if [game] can run in the **built-in** player: mGBA for the Game Boy
  /// family (GB/GBC/GBA = gens 1–3) and melonDS for Nintendo DS (gens 4–5).
  bool canPlayBuiltIn(Game game) =>
      (Platform.isWindows || Platform.isAndroid) &&
      game.generation >= 1 &&
      game.generation <= 5 &&
      isInstalled(game.id);

  /// Full path to the installed ROM for the built-in player, or null.
  String? builtInRomPath(Game game) => _installed[game.id];

  /// Launches a game's ROM in its detected emulator. Returns true if the ROM
  /// was handed to the emulator.
  Future<bool> launchGame(Game game) async {
    final rom = _installed[game.id];
    final d = emulatorForGame(game);
    if (rom == null || d?.path == null) return false;
    return _emu.launch(d!.path!, rom);
  }

  /// The emulator that would run [game], for user-facing messages.
  String? emulatorNameFor(Game game) => emulatorForGame(game)?.emu.name;

  /// Re-scans emulators if needed, then launches.
  Future<LaunchOutcome> tryLaunchGame(Game game) async {
    if (!canLaunch(game)) await refreshEmulators();
    if (!canLaunch(game)) return LaunchOutcome.noEmulator;
    final ok = await launchGame(game);
    return ok ? LaunchOutcome.launched : LaunchOutcome.handoffFailed;
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
      // If the Lemuroid folder is set up (access granted), mirror the new ROM
      // there too so it appears in Lemuroid without a manual re-sync.
      if (Platform.isAndroid) {
        _lemuroid.mirror(gameId, file.path); // best-effort, fire-and-forget
      }
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

  // ---- Lemuroid folder sync (Android) ---------------------------------
  /// Whether the app already has the storage access needed to write the
  /// shared Lemuroid folder.
  Future<bool> lemuroidHasAccess() => _lemuroid.hasAccess();

  /// Opens the "All files access" screen if needed. Returns true if access is
  /// already granted.
  Future<bool> lemuroidRequestAccess() => _lemuroid.requestAccess();

  /// The folder to point Lemuroid at (e.g. /storage/emulated/0/PokeTracker).
  Future<String?> lemuroidFolder() => _lemuroid.targetRoot();

  /// Copies every downloaded ROM into the shared Lemuroid folder. Returns how
  /// many games are now present there.
  Future<int> lemuroidSyncAll() => _lemuroid.syncAll(_installed);

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
    // Count base species only (form ids are >= 10000 and aren't in dexTotal);
    // fall back to the manual counter when nothing is tracked per-species.
    final baseCaught = p.caughtSpecies.where((id) => id < 10000).length;
    final caught = baseCaught > 0 ? baseCaught : p.dexCaught;
    final dexFrac =
        game.dexTotal == 0 ? 0.0 : (caught / game.dexTotal).clamp(0, 1);
    return (milestoneFrac + dexFrac) / 2;
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/games_data.dart';
import '../data/gen3_events.dart';
import '../data/frlg_achievements.dart';
import '../data/gen3_metloc.dart';
import '../models/achievement.dart';
import '../models/game.dart';
import '../models/progress.dart';
import '../models/save_models.dart';
import '../services/storage_service.dart';
import '../services/emulator_bios.dart';
import '../services/library_service.dart';
import '../services/emulator_service.dart';
import '../services/save_service.dart';
import '../services/save_server.dart';
import '../services/gen3_save_editor.dart';
import '../services/gen3_live_ram.dart';
import '../services/gen4_save_editor.dart';
import '../services/gen4_pkx.dart';
import '../services/gen4_text.dart';
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

  bool _devMode = false; // developer tools (iOS: local save server)
  bool get devMode => _devMode;

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
    _devMode = prefs.getBool('devmode') ?? false;
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
    if (!(Platform.isWindows || Platform.isAndroid || Platform.isIOS)) return;
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

  Future<void> setDevMode(bool value) async {
    _devMode = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('devmode', value);
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

  // =============================== Achievements ===============================
  // All achievements unlock automatically from already-tracked progress
  // (badges, caught-dex, shinies, team). Per-game and cross-game (global).

  /// True if the user has any tracked progress for this game (without creating
  /// an empty progress record, unlike [progressFor]).
  bool hasProgress(String gameId) {
    final p = _progress[gameId];
    return p != null &&
        (p.caughtSpecies.isNotEmpty ||
            p.milestones.values.any((v) => v) ||
            p.team.isNotEmpty ||
            p.shinyHunts.isNotEmpty);
  }

  int badgesEarned(String gameId) => progressFor(gameId)
      .milestones
      .entries
      .where((e) => e.value && e.key.contains('Badge'))
      .length;

  int _shiniesCaught(String gameId) =>
      progressFor(gameId).shinyHunts.where((h) => h.caught).length;

  int get totalShiniesCaught =>
      _progress.values.fold(0, (a, p) => a + p.shinyHunts.where((h) => h.caught).length);

  int get championCount => _progress.values
      .where((p) => p.milestones['Champion'] == true)
      .length;

  int _maxTeamLevel(String gameId) => progressFor(gameId)
      .team
      .fold(0, (a, m) => m.level > a ? m.level : a);

  /// Generations the user has made any progress in (caught something or earned
  /// a milestone), for the "played across N generations" achievement.
  int get generationsPlayed {
    final gens = <int>{};
    for (final g in kGames) {
      final p = _progress[g.id];
      if (p == null) continue;
      if (p.caughtSpecies.isNotEmpty || p.milestones.values.any((v) => v)) {
        gens.add(g.generation);
      }
    }
    return gens.length;
  }

  AchievementStatus _threshold(Achievement a, int value, int target) =>
      AchievementStatus(
        achievement: a,
        unlocked: value >= target,
        progress: target == 0 ? 1 : (value / target).clamp(0, 1).toDouble(),
        detail: '$value / $target',
      );

  AchievementStatus _flag(Achievement a, bool done) => AchievementStatus(
        achievement: a,
        unlocked: done,
        progress: done ? 1 : 0,
      );

  /// Toggle a manual (non-auto-detectable) achievement on/off.
  void toggleAchievement(String gameId, String achId, bool done) {
    final s = progressFor(gameId).unlockedAchievements;
    if (done) {
      s.add(achId);
    } else {
      s.remove(achId);
    }
    _persist();
  }

  /// The curated FireRed/LeafGreen achievement set (sourced from the RA base
  /// set). Auto-unlocks from badges/champion/caught-dex; the rest are manual.
  List<AchievementStatus> _frlgAchievements(Game game) {
    final p = progressFor(game.id);
    final ctx = AchContext(
      badges: badgesEarned(game.id),
      champion: p.milestones['Champion'] == true,
      caught: p.caughtSpecies,
      caughtCount: p.caughtSpecies.where((s) => s < 10000).length,
    );
    return [
      // Only show auto-trackable achievements for now (skip manual tap-offs).
      for (final a in kFrlgAchievements.where((a) => !a.isManual))
        () {
          // Auto (badges/caught/champion) OR flag (stored on sync).
          final unlocked = a.auto != null
              ? a.auto!(ctx)
              : p.unlockedAchievements.contains(a.id);
          return AchievementStatus(
            achievement: Achievement(
              id: a.id,
              title: a.title,
              description: a.description,
              icon: a.group.icon,
              group: a.group,
              points: a.points,
            ),
            unlocked: unlocked,
            progress: unlocked ? 1 : 0,
            // Only truly-manual achievements (no auto, no event flags) get the
            // tappable check-off; flag-based ones unlock from the save.
            manual: a.isManual,
          );
        }(),
    ];
  }

  /// Per-game achievements, evaluated from that game's tracked progress.
  List<AchievementStatus> gameAchievements(Game game) {
    if (game.version == 'firered' || game.version == 'leafgreen') {
      return _frlgAchievements(game);
    }
    final id = game.id;
    final p = progressFor(id);
    final badgeTotal =
        game.milestones.where((m) => m.contains('Badge')).length;
    final badges = badgesEarned(id);
    final caught = p.caughtSpecies.where((s) => s < 10000).length;
    final shinies = _shiniesCaught(id);
    final maxLvl = _maxTeamLevel(id);
    final teamSize = p.team.length;

    return [
      // Progression
      _flag(
          const Achievement(
              id: 'first-badge',
              title: 'Gym Challenger',
              description: 'Earn your first Gym Badge',
              icon: Icons.emoji_events,
              group: AchGroup.progression),
          badges >= 1),
      if (badgeTotal >= 8)
        _threshold(
            Achievement(
                id: 'half-badges',
                title: 'Halfway There',
                description: 'Earn 4 Gym Badges',
                icon: Icons.emoji_events,
                group: AchGroup.progression),
            badges,
            4),
      _threshold(
          Achievement(
              id: 'all-badges',
              title: 'Badge Master',
              description: 'Earn all Gym Badges',
              icon: Icons.workspace_premium,
              group: AchGroup.progression),
          badges,
          badgeTotal == 0 ? 8 : badgeTotal),
      if (game.milestones.contains('Elite Four'))
        _flag(
            const Achievement(
                id: 'elite-four',
                title: 'Elite Four',
                description: 'Defeat the Elite Four',
                icon: Icons.shield_moon,
                group: AchGroup.progression),
            p.milestones['Elite Four'] == true),
      if (game.milestones.contains('Champion'))
        _flag(
            const Achievement(
                id: 'champion',
                title: 'Champion',
                description: 'Become the Pokémon League Champion',
                icon: Icons.military_tech,
                group: AchGroup.progression),
            p.milestones['Champion'] == true),
      // Collection
      _threshold(
          const Achievement(
              id: 'catch-10',
              title: 'Getting Started',
              description: 'Catch 10 species',
              icon: Icons.catching_pokemon,
              group: AchGroup.collection),
          caught,
          10),
      _threshold(
          const Achievement(
              id: 'catch-50',
              title: 'Collector',
              description: 'Catch 50 species',
              icon: Icons.catching_pokemon,
              group: AchGroup.collection),
          caught,
          50),
      _threshold(
          Achievement(
              id: 'dex-complete',
              title: 'Regional Champion',
              description: 'Complete the ${game.region} Pokédex',
              icon: Icons.auto_stories,
              group: AchGroup.collection),
          caught,
          game.dexTotal),
      // Shiny
      _flag(
          const Achievement(
              id: 'first-shiny',
              title: 'Sparkle',
              description: 'Catch a shiny Pokémon',
              icon: Icons.auto_awesome,
              group: AchGroup.shiny),
          shinies >= 1),
      _threshold(
          const Achievement(
              id: 'shiny-5',
              title: 'Shiny Hunter',
              description: 'Catch 5 shiny Pokémon',
              icon: Icons.auto_awesome_motion,
              group: AchGroup.shiny),
          shinies,
          5),
      // Team
      _flag(
          const Achievement(
              id: 'full-team',
              title: 'Full Squad',
              description: 'Build a team of 6',
              icon: Icons.groups,
              group: AchGroup.team),
          teamSize >= 6),
      _flag(
          const Achievement(
              id: 'level-100',
              title: 'Powerhouse',
              description: 'Raise a Pokémon to Lv 100',
              icon: Icons.bolt,
              group: AchGroup.team),
          maxLvl >= 100),
    ];
  }

  /// Cross-game / meta achievements spanning the whole library.
  List<AchievementStatus> globalAchievements() {
    return [
      _threshold(
          const Achievement(
              id: 'g-badges-8',
              title: 'Badge Collector',
              description: 'Earn 8 Gym Badges across all games',
              icon: Icons.emoji_events,
              group: AchGroup.meta),
          totalBadges,
          8),
      _threshold(
          const Achievement(
              id: 'g-badges-24',
              title: 'Badge Baron',
              description: 'Earn 24 Gym Badges across all games',
              icon: Icons.workspace_premium,
              group: AchGroup.meta),
          totalBadges,
          24),
      _threshold(
          const Achievement(
              id: 'g-badges-50',
              title: 'Badge Overlord',
              description: 'Earn 50 Gym Badges across all games',
              icon: Icons.military_tech,
              group: AchGroup.meta),
          totalBadges,
          50),
      _threshold(
          const Achievement(
              id: 'g-champ-3',
              title: 'Multi-Region Champion',
              description: 'Become Champion in 3 regions',
              icon: Icons.public,
              group: AchGroup.meta),
          championCount,
          3),
      _threshold(
          const Achievement(
              id: 'g-catch-100',
              title: 'Pokédex Progress',
              description: 'Catch 100 species across all games',
              icon: Icons.catching_pokemon,
              group: AchGroup.collection),
          totalCaught,
          100),
      _threshold(
          const Achievement(
              id: 'g-catch-500',
              title: 'Serious Collector',
              description: 'Catch 500 species across all games',
              icon: Icons.menu_book,
              group: AchGroup.collection),
          totalCaught,
          500),
      _threshold(
          const Achievement(
              id: 'g-catch-1000',
              title: 'Gotta Catch a Thousand',
              description: 'Catch 1000 species across all games',
              icon: Icons.auto_stories,
              group: AchGroup.collection),
          totalCaught,
          1000),
      _flag(
          const Achievement(
              id: 'g-first-shiny',
              title: 'First Sparkle',
              description: 'Catch your first shiny anywhere',
              icon: Icons.auto_awesome,
              group: AchGroup.shiny),
          totalShiniesCaught >= 1),
      _threshold(
          const Achievement(
              id: 'g-shiny-10',
              title: 'Shiny Legend',
              description: 'Catch 10 shiny Pokémon',
              icon: Icons.auto_awesome_motion,
              group: AchGroup.shiny),
          totalShiniesCaught,
          10),
      _threshold(
          const Achievement(
              id: 'g-generations',
              title: 'Journey Through Time',
              description: 'Make progress in 3 different generations',
              icon: Icons.history_edu,
              group: AchGroup.meta),
          generationsPlayed,
          3),
    ];
  }

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
    var data = _save.parse(
      Uint8List.fromList(bytes),
      generation: game.generation,
      versionId: game.version,
    );
    // Gen 3: enrich with badges + team (the flat parser doesn't read these).
    if (game.generation == 3) {
      try {
        final e = Gen3SaveEditor.load(Uint8List.fromList(bytes));
        if (e.verifyChecksums().ok) {
          final party = await readGen3Party(game) ?? const <Gen3PartyMon>[];
          // FireRed/LeafGreen: evaluate the curated achievement set's event
          // flags (rival/Rocket/story beats) so they auto-unlock.
          final flagAch = <String>{};
          var gameClear = false;
          if (game.version == 'firered' || game.version == 'leafgreen') {
            gameClear = e.getEventFlag(game.version, kFrlgGameClearFlag);
            for (final a in kFrlgAchievements) {
              final f = a.flags;
              if (f == null) continue;
              if (f.any((n) => e.getEventFlag(game.version, n))) {
                flagAch.add(a.id);
              }
            }
          }
          data = data.copyWith(
            badgeCount: e.badgeCount(game.version),
            money: e.getMoney(game.version),
            team: [
              for (final m in party)
                SaveTeamMon(
                    dexId: m.dex,
                    level: m.level,
                    nickname: m.nickname,
                    name: m.name),
            ],
            notes: const [],
            flagAchievements: flagAch,
            gameClear: gameClear,
          );
        }
      } catch (_) {/* keep the flat parse */}
    }
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
  Future<({int money, int caught, int seen})?> readGen3Save(Game game) async {
    if (game.generation != 3) return null;
    final file = await _findSaveFile(game.id);
    if (file == null) return null;
    try {
      final e =
          Gen3SaveEditor.load(Uint8List.fromList(await file.readAsBytes()));
      if (!e.verifyChecksums().ok) return null;
      return (
        money: e.getMoney(game.version),
        caught: e.caughtCount,
        seen: e.seenCount(game.version),
      );
    } catch (_) {
      return null;
    }
  }

  // ========================= Gen 4 (DPPt / HGSS) =========================
  /// Trainer + money summary for a Gen 4 save.
  Future<({int money, String trainer, int tid, int sid, int gender})?>
      readGen4Save(Game game) async {
    if (game.generation != 4) return null;
    final file = await _findSaveFile(game.id);
    if (file == null) return null;
    try {
      final e = Gen4SaveEditor.load(
          Uint8List.fromList(await file.readAsBytes()), game.version);
      if (!e.verifyChecksums().ok) return null;
      final t = e.trainer();
      return (
        money: e.money,
        trainer: t.name,
        tid: t.tid,
        sid: t.sid,
        gender: t.gender
      );
    } catch (_) {
      return null;
    }
  }

  /// Reads a Gen 4 party for the editor (reuses the Gen3PartyMon UI model).
  Future<List<Gen3PartyMon>?> readGen4Party(Game game) async {
    if (game.generation != 4) return null;
    final file = await _findSaveFile(game.id);
    if (file == null) return null;
    try {
      final e = Gen4SaveEditor.load(
          Uint8List.fromList(await file.readAsBytes()), game.version);
      if (!e.verifyChecksums().ok) return null;
      final t = e.trainer();
      final out = <Gen3PartyMon>[];
      for (var i = 0; i < e.partyCount; i++) {
        final m = Pkx.decode(e.partyBlock(i));
        if (m.isEmpty) continue;
        var level = 0;
        try {
          level = gen3LevelFromExp(await _pokedex.growthRate(m.species), m.exp);
        } catch (_) {}
        out.add(Gen3PartyMon(
          slot: i,
          dex: m.species,
          level: level,
          shiny: m.isShiny(t.tid, t.sid),
          nature: m.nature,
          ivs: m.ivs,
          evs: m.evs,
          moves: m.moves,
          nickname: gen4DecodeText(m.nicknameRaw, 0, 11),
          otName: t.name,
          friendship: m.friendship,
          exp: m.exp,
          pid: m.pid,
          otid: (t.tid & 0xFFFF) | ((t.sid & 0xFFFF) << 16),
          ball: m.ballId,
          metLevel: m.metLevel,
          metLocation: m.metLocation,
          otGender: m.otGender,
          language: m.language,
          markings: m.markings,
          contest: m.contest,
          heldItem: m.heldItem,
          ability: m.ability,
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

  /// Applies Gen 4 edits and writes back (backup + checksum guard).
  Future<String> writeGen4Save(Game game,
      {int? money,
      Gen4Trainer? trainer,
      Map<int, PartyEdit> partyEdits = const {}}) async {
    if (game.generation != 4) return 'Gen 4 editing only.';
    final file = await _findSaveFile(game.id);
    if (file == null) return 'No save file found for ${game.title}.';
    final raw = Uint8List.fromList(await file.readAsBytes());
    final Gen4SaveEditor e;
    try {
      e = Gen4SaveEditor.load(raw, game.version);
    } catch (_) {
      return 'Not a readable Gen 4 save.';
    }
    if (!e.verifyChecksums().ok) {
      return 'Save checksums look wrong — refusing to edit it.';
    }
    if (money != null) e.setMoney(money);
    if (trainer != null) e.setTrainer(trainer);
    final t = e.trainer();
    for (final entry in partyEdits.entries) {
      final m = Pkx.decode(e.partyBlock(entry.key));
      if (m.isEmpty) continue;
      await _applyGen4MonEdit(m, entry.value, t.tid, t.sid);
      e.writePartyBlock(entry.key, m.encode());
    }
    if (!e.verifyChecksums().ok) {
      return 'Edit produced bad checksums — aborted, your save was NOT changed.';
    }
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final bak = File('${file.path}.bak-$stamp');
    await bak.writeAsBytes(raw, flush: true);
    await file.writeAsBytes(e.toBytes(), flush: true);
    return 'Saved. Backup written next to the save '
        '(${bak.uri.pathSegments.last}). Reload it in your emulator to check.';
  }

  Future<void> _applyGen4MonEdit(Pkx m, PartyEdit ed, int tid, int sid) async {
    final speciesChanged = ed.species != null && ed.species != m.species;
    final dex = ed.species ?? m.species;
    if (ed.species != null) m.setSpecies(ed.species!);
    final targetLevel = ed.level ?? m.partyLevel;
    if (ed.level != null || speciesChanged) {
      m.setExp(gen3Exp(await _pokedex.growthRate(dex), targetLevel));
    }
    // Strict-legal: a correlated Method-1 PID+IV (checker-safe) supersedes
    // nature/shiny/IVs — the same engine Gen 3 uses (Method 1 is how Gen 4
    // gift/starter Pokémon are generated).
    if (ed.legalPid != null) {
      m.setPid(ed.legalPid!);
      if (ed.ivs != null) m.setIVs(ed.ivs!);
    } else {
      if (ed.nature != null || ed.shiny != null) {
        m.regenNatureShiny(
            nature: ed.nature,
            shiny: ed.shiny,
            tid: tid,
            sid: sid,
            primaryShiny: ed.shiny != null);
      }
      if (ed.ivs != null) m.setIVs(ed.ivs!);
    }
    if (ed.evs != null) m.setEVs(ed.evs!);
    if (ed.friendship != null) m.setFriendship(ed.friendship!);
    if (ed.ball != null) m.setBall(ed.ball!);
    if (ed.metLevel != null) m.setMetLevel(ed.metLevel!);
    if (ed.metLocation != null) m.setMetLocation(ed.metLocation!);
    if (ed.otGender != null) m.setOtGender(ed.otGender!);
    if (ed.language != null) m.setLanguage(ed.language!);
    if (ed.markings != null) m.setMarkings(ed.markings!);
    if (ed.contest != null) m.setContest(ed.contest!);
    if (ed.heldItem != null) m.setHeldItem(ed.heldItem!);
    // Ability: explicit choice wins; a species change resets it to the new
    // species' ability for this PID's slot (keeps it legal).
    if (ed.ability != null) {
      m.setAbility(ed.ability!);
    } else if (speciesChanged) {
      final abs = await pokedexAbilities(dex);
      final normal = [for (final a in abs) if (!a.hidden) a];
      if (normal.isNotEmpty) {
        m.setAbility(normal[(m.pid & 1) % normal.length].id);
      }
    }
    // Moves: explicit list wins; a species change resets to a legal moveset.
    var newMoves = ed.moves;
    if (newMoves == null && speciesChanged) {
      newMoves = [for (final mv in (await gen3Learnset(dex, gen: 4)).take(4)) mv.id];
    }
    if (newMoves != null) {
      m.setMoves(newMoves);
      for (var k = 0; k < 4; k++) {
        final id = k < newMoves.length ? newMoves[k] : 0;
        m.setPP(k, id == 0 ? 0 : await _pokedex.movePP(id));
      }
    }
    // Nickname: explicit wins; a species change resets to the species name.
    if (ed.nickname != null) {
      gen4EncodeText(m.data, 0x48, 11, ed.nickname!);
      m.setNicknamed(true);
    } else if (speciesChanged) {
      var name = '';
      for (final s in await _pokedex.loadIndex()) {
        if (s.id == dex) {
          name = s.name;
          break;
        }
      }
      if (name.isNotEmpty) gen4EncodeText(m.data, 0x48, 11, name.toUpperCase());
      m.setNicknamed(false);
    }
    // Recompute party stats when a stat-affecting field changed.
    final statsChanged = ed.level != null ||
        speciesChanged ||
        ed.ivs != null ||
        ed.evs != null ||
        ed.nature != null ||
        ed.shiny != null ||
        ed.legalPid != null;
    if (m.isParty && statsChanged) {
      try {
        final st = (await _pokedex.fetchDetail(dex)).stats;
        int g(String k) => st[k] ?? 50;
        m.recomputeStats(targetLevel, [
          g('hp'), g('attack'), g('defense'),
          g('speed'), g('special-attack'), g('special-defense'),
        ]);
      } catch (_) {/* offline: stored stats stay until the next in-game heal */}
    }
  }

  // ------------------------------------------------ save transfer over Wi-Fi
  final SaveServer saveServer = SaveServer();

  /// Start receiving saves: returns this device's LAN IP + pairing token, or
  /// null if the server couldn't bind / no Wi-Fi address was found.
  Future<({String ip, String token})?> startSaveReceiver() async {
    saveServer.onReceive = _receiveSave;
    if (await saveServer.start() == null) return null;
    final ip = await saveServer.lanIp();
    if (ip == null) {
      await saveServer.stop();
      return null;
    }
    notifyListeners();
    return (ip: ip, token: saveServer.token);
  }

  Future<void> stopSaveReceiver() async {
    await saveServer.stop();
    notifyListeners();
  }

  // Places an incoming save: overwrites the game's existing save (backup first),
  // else drops it in the canonical Games/<id>/ folder.
  Future<String> _receiveSave(String gameId, String name, List<int> bytes) async {
    if (bytes.length < 0x2000) return 'Rejected: file too small for a save.';
    if (!kGames.any((g) => g.id == gameId)) return 'Rejected: unknown game.';
    try {
      File target;
      final existing = await _findSaveFile(gameId);
      if (existing != null) {
        final stamp = DateTime.now().millisecondsSinceEpoch;
        await File('${existing.path}.bak-$stamp')
            .writeAsBytes(await existing.readAsBytes(), flush: true);
        target = existing;
      } else {
        final docs = await getApplicationDocumentsDirectory();
        final dir = Directory('${docs.path}/PokeTracker/Games/$gameId');
        await dir.create(recursive: true);
        target = File('${dir.path}/${name.isEmpty ? 'save.sav' : name}');
      }
      await target.writeAsBytes(bytes, flush: true);
      return 'OK — wrote ${bytes.length} bytes.';
    } catch (e) {
      return 'Receiver error: $e';
    }
  }

  /// Sends [game]'s save to a peer running the receiver at [host] with [token].
  Future<String> sendSaveToPeer(Game game, String host, String token) async {
    final file = await _findSaveFile(game.id);
    if (file == null) return 'No save file found for ${game.title}.';
    final bytes = await file.readAsBytes();
    final name = file.uri.pathSegments.last;
    final uri = Uri.parse('http://${host.trim()}:${SaveServer.port}/put'
        '?t=${token.trim()}&game=${game.id}&name=$name');
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 8);
      final req = await client.postUrl(uri);
      req.add(bytes);
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      client.close();
      if (resp.statusCode == 200) {
        return 'Sent ${game.title} (${bytes.length} bytes). Peer: $body';
      }
      if (resp.statusCode == HttpStatus.forbidden) {
        return 'Rejected: wrong code. Re-check the code on the other device.';
      }
      return 'Send failed (HTTP ${resp.statusCode}).';
    } catch (_) {
      return 'Send failed: could not reach $host on the same Wi-Fi.';
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
          dex: m.nationalDex,
          level: m.level,
          shiny: m.isShiny,
          nature: m.nature,
          ivs: m.ivs,
          evs: m.evs,
          moves: m.moves,
          nickname: m.nickname,
          otName: m.otName,
          friendship: m.friendship,
          pid: m.pid,
          otid: m.otid,
          ball: m.ball,
          metLevel: m.metLevel,
          metLocation: m.metLocation,
          otGender: m.otGender,
          language: m.language,
          markings: m.markings,
          pokerus: m.pokerus,
          contest: m.contest,
          heldItem: m.heldItem,
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

  /// Reads the PC boxes (14×30 = 420 slots) for the editor's box view. Returns
  /// only occupied slots, each tagged with its global slot index (0..419).
  Future<List<Gen3PartyMon>?> readGen3Boxes(Game game) async {
    if (game.generation != 3) return null;
    final file = await _findSaveFile(game.id);
    if (file == null) return null;
    try {
      final e =
          Gen3SaveEditor.load(Uint8List.fromList(await file.readAsBytes()));
      if (!e.verifyChecksums().ok) return null;
      final out = <Gen3PartyMon>[];
      final total = Gen3SaveEditor.pcBoxCount * Gen3SaveEditor.pcPerBox;
      for (var g = 0; g < total; g++) {
        final m = Pk3.decode(e.boxSlot(g));
        if (m.isEmpty) continue;
        out.add(Gen3PartyMon(
          slot: g % Gen3SaveEditor.pcPerBox,
          boxSlot: g,
          dex: m.nationalDex,
          level: 0, // derived from exp when opened for editing
          shiny: m.isShiny,
          nature: m.nature,
          ivs: m.ivs,
          evs: m.evs,
          moves: m.moves,
          nickname: m.nickname,
          otName: m.otName,
          friendship: m.friendship,
          exp: m.exp,
          pid: m.pid,
          otid: m.otid,
          ball: m.ball,
          metLevel: m.metLevel,
          metLocation: m.metLocation,
          otGender: m.otGender,
          language: m.language,
          markings: m.markings,
          pokerus: m.pokerus,
          contest: m.contest,
          heldItem: m.heldItem,
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
  /// Reads the trainer card (name/gender/ID/playtime) for the editor.
  Future<Gen3Trainer?> readGen3Trainer(Game game) async {
    if (game.generation != 3) return null;
    final file = await _findSaveFile(game.id);
    if (file == null) return null;
    try {
      final e =
          Gen3SaveEditor.load(Uint8List.fromList(await file.readAsBytes()));
      if (!e.verifyChecksums().ok) return null;
      return e.trainer();
    } catch (_) {
      return null;
    }
  }

  /// Reads the five bag pockets for the editor. Keyed by pocket.
  Future<Map<Gen3Pocket, List<({int id, int qty})>>?> readGen3Bag(
      Game game) async {
    if (game.generation != 3) return null;
    final file = await _findSaveFile(game.id);
    if (file == null) return null;
    try {
      final e =
          Gen3SaveEditor.load(Uint8List.fromList(await file.readAsBytes()));
      if (!e.verifyChecksums().ok) return null;
      return {
        for (final p in Gen3Pocket.values) p: e.pocketItems(game.version, p),
      };
    } catch (_) {
      return null;
    }
  }

  /// Builds an event Pokémon into an encoded PK3 block (party or box variant),
  /// pulling EXP/PP/base-stats from PokeAPI. Legal-by-construction.
  /// The level-up moveset a species would know at [level] in generation [gen]:
  /// the (up to) 4 highest-level moves it has learned by then.
  Future<List<int>> legalLevelUpMoves(int dex, int gen, int level) async {
    try {
      final d = await _pokedex.fetchDetail(dex);
      final lv = [
        for (final m in d.moves)
          if (m.method == 'level-up' &&
              m.generation == gen &&
              m.level > 0 &&
              m.level <= level)
            m
      ]..sort((a, b) => a.level.compareTo(b.level));
      final seen = <int>{};
      final out = <int>[];
      for (final m in lv.reversed) {
        if (seen.add(m.id)) out.add(m.id);
        if (out.length == 4) break;
      }
      return out.reversed.toList(); // lowest-level first
    } catch (_) {
      return const [];
    }
  }

  /// The minimum level a freshly-added [dex] can legally be: the max of its
  /// evolution requirement and its base species' lowest wild level (≥ 2).
  Future<int> minAddLevel(Game game, int dex) async {
    var m = 2;
    try {
      final evo = await _pokedex.evolutionMinLevel(dex);
      if (evo > m) m = evo;
      final base = await _pokedex.baseSpeciesOf(dex);
      final enc = await _pokedex.encountersIn(base, game.version);
      if (enc.isNotEmpty) {
        final wildMin = enc.map((e) => e.minLevel).reduce((a, b) => a < b ? a : b);
        if (wildMin > m) m = wildMin;
      }
    } catch (_) {}
    return m.clamp(2, 100);
  }

  /// Builds a legal-by-construction Gen 3 Pokémon of [dex] at [level] (Method-1
  /// correlated PID+IVs, level-appropriate moves, the player as OT) and injects
  /// it into the first free PC box slot. Backs up + checksum-guards the write.
  Future<String> addLegalMonToBox(Game game, int dex, {int level = 5}) async {
    if (game.generation != 3) return 'Adding to the box is Gen 3-only for now.';
    // Never below the species' minimum legal level (evolution requirement).
    level = level.clamp(await minAddLevel(game, dex), 100);
    final trainer = await readGen3Trainer(game);
    if (trainer == null) {
      return 'No save found — play and save in-game once first.';
    }
    final otid = (trainer.tid & 0xFFFF) | ((trainer.sid & 0xFFFF) << 16);
    final rate = await _pokedex.growthRate(dex);
    var moves = await legalLevelUpMoves(dex, game.generation, level);
    if (moves.isEmpty) {
      moves = [
        for (final m in (await gen3Learnset(dex, gen: game.generation)).take(4))
          m.id
      ];
    }
    final pp = [for (final m in moves) await _pokedex.movePP(m)];
    var genderRate = -1;
    try {
      genderRate = (await _pokedex.fetchDetail(dex)).genderRate;
    } catch (_) {}
    // Met location: use the evolution line's BASE species' wild encounter spot
    // (so an evolved mon reads as "caught as the base here, then evolved").
    // Falls back to the species' own encounters, then a "fateful" special value.
    int metLocation = kMetlocFateful;
    int metLevel = level;
    try {
      final baseDex = await _pokedex.baseSpeciesOf(dex);
      var enc = await _pokedex.encountersIn(baseDex, game.version);
      if (enc.isEmpty && baseDex != dex) {
        enc = await _pokedex.encountersIn(dex, game.version);
      }
      if (enc.isNotEmpty) {
        // Prefer the lowest-level encounter (where you'd first catch the base).
        enc.sort((a, b) => a.minLevel.compareTo(b.minLevel));
        for (final e in enc) {
          final loc = gen3MapsecForArea(e.area);
          if (loc != null) {
            metLocation = loc;
            metLevel = e.minLevel.clamp(2, level); // caught level ≤ current
            break;
          }
        }
      }
    } catch (_) {/* keep the fateful fallback */}
    // Deterministic-but-varied nature; PID+IVs correlated so a checker accepts.
    final nature = (dex * 31 + level * 7) % 25;
    final legal = gen3Method1Find(
        tid: otid & 0xFFFF,
        sid: otid >> 16,
        nature: nature,
        shiny: false,
        genderRate: genderRate);
    var name = '';
    for (final s in await _pokedex.loadIndex()) {
      if (s.id == dex) {
        name = s.name;
        break;
      }
    }
    final origin = switch (game.version) {
      'sapphire' => 1,
      'ruby' => 2,
      'emerald' => 3,
      'firered' => 4,
      'leafgreen' => 5,
      _ => 4,
    };
    final pk = Pk3.create(
      otid: otid,
      nationalSpecies: dex,
      level: level,
      totalExp: gen3Exp(rate, level),
      moves: [for (var i = 0; i < 4; i++) i < moves.length ? moves[i] : 0],
      pp: [for (var i = 0; i < 4; i++) i < pp.length ? pp[i] : 0],
      ivs: legal?.ivs ?? const [31, 31, 31, 31, 31, 31],
      nickname: name.isEmpty ? 'POKEMON' : name.toUpperCase(),
      otName: trainer.name,
      nature: nature,
      ball: 4,
      metLocation: metLocation,
      metLevel: metLevel,
      otGender: trainer.gender,
      gameOfOrigin: origin,
      party: false, // box mon (80-byte block)
    );
    if (legal != null) pk.setPidAndIvs(legal.pid, legal.ivs);
    final res = await writeGen3Save(game, boxInjects: [pk.encode()]);
    if (!res.startsWith('Saved')) return res;
    final pretty = name.isEmpty
        ? '#$dex'
        : name[0].toUpperCase() + name.substring(1).replaceAll('-', ' ');
    return 'Added $pretty (Lv $level) to the PC box.';
  }

  Future<Uint8List> buildEventMon(Game game, Gen3Event ev,
      {required bool party}) async {
    final otid = (ev.otTid & 0xFFFF) | ((ev.otSid & 0xFFFF) << 16);
    final rate = await _pokedex.growthRate(ev.dex);
    final pp = <int>[];
    for (final mid in ev.moves) {
      pp.add(mid == 0 ? 0 : await _pokedex.movePP(mid));
    }
    var name = '';
    for (final s in await _pokedex.loadIndex()) {
      if (s.id == ev.dex) {
        name = s.name;
        break;
      }
    }
    // Game-of-origin must be a valid Gen 3 game (0 flags as illegal); use the
    // cartridge the event is going onto.
    final origin = switch (game.version) {
      'sapphire' => 1,
      'ruby' => 2,
      'emerald' => 3,
      'firered' => 4,
      'leafgreen' => 5,
      _ => 4,
    };
    final pk = Pk3.create(
      otid: otid,
      nationalSpecies: ev.dex,
      level: ev.level,
      totalExp: gen3Exp(rate, ev.level),
      moves: ev.moves,
      pp: pp,
      ivs: const [31, 31, 31, 31, 31, 31],
      nickname: name.isEmpty ? 'EVENT' : name.toUpperCase(),
      otName: ev.otName,
      nature: ev.nature,
      ball: ev.ball,
      heldItem: ev.heldItem,
      metLocation: ev.metLocation,
      metLevel: ev.metLevel,
      gameOfOrigin: origin,
      party: party,
    );
    pk.setFateful(ev.fateful); // Mew/Deoxys need this to obey + read as legit
    if (party) {
      try {
        final st = (await _pokedex.fetchDetail(ev.dex)).stats;
        int g(String k) => st[k] ?? 50;
        pk.recomputeStats([
          g('hp'), g('attack'), g('defense'),
          g('speed'), g('special-attack'), g('special-defense'),
        ]);
      } catch (_) {/* offline: stats stay 0 until first heal */}
    }
    return pk.encode();
  }

  /// Finds a checker-legal (Method-1 correlated) PID + IVs for [dex] with the
  /// wanted nature/shiny, preserving the current gender + ability. [startSeed]
  /// lets the UI re-roll for a different (still legal) IV spread. Returns null
  /// if nothing was found (e.g. an impossible shiny frame within the budget).
  Future<({int pid, List<int> ivs, int seed})?> findLegalPidIv({
    required int dex,
    required int tid,
    required int sid,
    required int nature,
    required bool shiny,
    required int currentPid,
    int? wantAbility,
    int startSeed = 0,
  }) async {
    var genderRate = -1;
    try {
      genderRate = (await _pokedex.fetchDetail(dex)).genderRate;
    } catch (_) {/* offline: don't constrain gender */}
    final wantGender =
        genderRate == -1 ? null : gen3GenderOf(currentPid, genderRate);
    return gen3Method1Find(
      tid: tid,
      sid: sid,
      nature: nature,
      shiny: shiny,
      genderRate: genderRate,
      wantGender: wantGender,
      // Ability slot lives in PID bit 0 — target the requested slot so the
      // stored ability stays consistent with the PID (checker-legal).
      wantAbility: wantAbility ?? (currentPid & 1),
      startSeed: startSeed,
    );
  }

  /// The level a boxed Pokémon of [dex] with [exp] total experience is at.
  Future<int> gen3LevelForExp(int dex, int exp) async =>
      gen3LevelFromExp(await _pokedex.growthRate(dex), exp);

  /// A species' Gen 3 typing (for the editor's dex-style header).
  Future<List<String>> pokedexTypes(int dex) async {
    try {
      return (await _pokedex.fetchDetail(dex)).typesForGeneration(3);
    } catch (_) {
      return const [];
    }
  }

  /// A species' abilities (id + name + hidden flag) in slot order, for the
  /// editor's ability picker. Ability ids match the in-game (Gen 3/4) index.
  Future<List<({int id, String name, bool hidden})>> pokedexAbilities(
      int dex) async {
    try {
      final a = (await _pokedex.fetchDetail(dex)).abilities;
      return [for (final x in a) (id: x.id, name: x.name, hidden: x.isHidden)];
    } catch (_) {
      return const [];
    }
  }

  /// Move display info (power/PP/type/category) for the editor's move rows.
  Future<({int power, int pp, int accuracy, String type, String damageClass})>
      moveInfo(int id) => _pokedex.moveInfo(id);

  /// All species (National dex id + name), sorted by dex, for the editor's
  /// species picker.
  Future<List<({int id, String name})>> allSpeciesForPicker() async {
    try {
      final idx = await _pokedex.loadIndex();
      final out = [for (final s in idx) (id: s.id, name: s.name)];
      out.sort((a, b) => a.id.compareTo(b.id));
      return out;
    } catch (_) {
      return [];
    }
  }

  /// The legal move pool for [dex] in generation [gen] (RSE/FRLG = 3, DPPt/HGSS
  /// = 4, …), deduped + sorted. Defaults to Gen 3.
  Future<List<({int id, String name})>> gen3Learnset(int dex,
      {int gen = 3}) async {
    try {
      final d = await _pokedex.fetchDetail(dex);
      final seen = <int>{};
      final out = <({int id, String name})>[];
      for (final mv in d.moves) {
        if (mv.generation != gen || mv.id == 0 || !seen.add(mv.id)) continue;
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
  /// Reorganize every boxed Pokémon (Gen 3) by National Dex number, packing
  /// them from Box 1 Slot 1 onward. Backs up the save, verifies checksums, and
  /// only writes if they pass.
  Future<String> sortGen3BoxesByDex(Game game) async {
    if (game.generation != 3) return 'Only Gen 3 boxes can be sorted here.';
    final file = await _findSaveFile(game.id);
    if (file == null) return 'No save file found for ${game.title}.';
    final raw = Uint8List.fromList(await file.readAsBytes());
    final e = Gen3SaveEditor.load(raw);
    if (!e.verifyChecksums().ok) {
      return 'Save checksums are invalid — not sorting.';
    }
    final total = Gen3SaveEditor.pcBoxCount * Gen3SaveEditor.pcPerBox;
    final mons = <({int dex, int level, Uint8List block})>[];
    for (var g = 0; g < total; g++) {
      final block = e.boxSlot(g);
      final m = Pk3.decode(block);
      if (m.isEmpty) continue;
      mons.add((dex: m.nationalDex, level: m.level, block: block));
    }
    if (mons.isEmpty) return 'No boxed Pokémon to sort.';
    // Sort by Dex number, then by level (stable, tidy within a species).
    mons.sort((a, b) {
      final d = a.dex.compareTo(b.dex);
      return d != 0 ? d : a.level.compareTo(b.level);
    });
    final empty = Uint8List(80);
    for (var g = 0; g < total; g++) {
      e.writeBoxSlot(g, g < mons.length ? mons[g].block : empty);
    }
    if (!e.verifyChecksums().ok) {
      return 'Sort produced bad checksums — aborted, your save was NOT changed.';
    }
    final stamp = DateTime.now().millisecondsSinceEpoch;
    await File('${file.path}.bak-$stamp').writeAsBytes(raw, flush: true);
    await file.writeAsBytes(e.toBytes(), flush: true);
    notifyListeners();
    return 'Organized ${mons.length} Pokémon by Dex number. '
        'Backup written next to the save.';
  }

  Future<String> writeGen3Save(Game game,
      {int? money,
      bool completeDex = false,
      bool completeSeenDex = false,
      List<Gen3Ticket> tickets = const [],
      Map<int, PartyEdit> partyEdits = const {},
      Map<int, PartyEdit> boxEdits = const {},
      Gen3Trainer? trainer,
      Map<Gen3Pocket, List<({int id, int qty})>>? bag,
      List<Uint8List> partyInjects = const [],
      List<Uint8List> boxInjects = const []}) async {
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
    if (completeSeenDex) e.markAllSeen(game.version);
    if (trainer != null) e.setTrainer(trainer);
    if (bag != null) {
      for (final entry in bag.entries) {
        e.setPocket(game.version, entry.key, entry.value);
      }
    }
    for (final t in tickets) {
      e.giveTicket(game.version, t);
    }
    for (final entry in partyEdits.entries) {
      final m = Pk3.decode(e.partyBlock(game.version, entry.key));
      if (m.isEmpty) continue;
      await _applyGen3MonEdit(m, entry.value, game, e);
      e.writePartyBlock(game.version, entry.key, m.encode());
    }
    for (final entry in boxEdits.entries) {
      final m = Pk3.decode(e.boxSlot(entry.key));
      if (m.isEmpty) continue;
      await _applyGen3MonEdit(m, entry.value, game, e);
      e.writeBoxSlot(entry.key, m.encode());
    }
    for (final b in partyInjects) {
      e.addPartyMon(game.version, b);
      e.markCaught(game.version, Pk3.decode(b).nationalDex);
    }
    for (final b in boxInjects) {
      e.addBoxMon(b);
      e.markCaught(game.version, Pk3.decode(b).nationalDex);
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

  /// How many editor backups exist next to a game's save.
  Future<int> gen3BackupCount(Game game) async {
    final file = await _findSaveFile(game.id);
    if (file == null) return 0;
    return _backupsFor(file).length;
  }

  List<File> _backupsFor(File save) {
    final prefix = '${save.path}.bak-';
    final baks = save.parent
        .listSync()
        .whereType<File>()
        .where((f) => f.path.startsWith(prefix))
        .toList();
    // Newest first, by the millisecond timestamp suffix.
    int ts(File f) => int.tryParse(f.path.substring(prefix.length)) ?? 0;
    baks.sort((a, b) => ts(b).compareTo(ts(a)));
    return baks;
  }

  /// Restores the most recent editor backup over the current save (only if that
  /// backup itself has valid checksums). Undoes a bad edit.
  Future<String> restoreGen3Backup(Game game) async {
    final file = await _findSaveFile(game.id);
    if (file == null) return 'No save file found for ${game.title}.';
    final baks = _backupsFor(file);
    if (baks.isEmpty) return 'No backup found to restore.';
    // Restore the newest backup that actually passes checksums — skip any
    // corrupt ones (e.g. a bad save the emulator may have backed up).
    for (final bak in baks) {
      try {
        final bytes = Uint8List.fromList(await bak.readAsBytes());
        if (!Gen3SaveEditor.load(bytes).verifyChecksums().ok) continue;
        await file.writeAsBytes(bytes, flush: true);
        return 'Restored ${bak.uri.pathSegments.last}. Reload it in your '
            'emulator.';
      } catch (_) {
        continue;
      }
    }
    return 'No valid backup found to restore.';
  }

  /// Applies one PartyEdit to a decoded PK3 in place (shared by party + box).
  /// Legal-by-construction: a species change re-derives EXP, stats, moves and
  /// the default nickname; all PokeAPI lookups use National dex.
  Future<void> _applyGen3MonEdit(
      Pk3 m, PartyEdit ed, Game game, Gen3SaveEditor e) async {
      // All PokeAPI lookups use the National dex; on a species change [dex] is
      // the NEW species so stats/moves/growth are derived for what it becomes.
      final speciesChanged = ed.species != null && ed.species != m.nationalDex;
      final dex = ed.species ?? m.nationalDex;
      if (ed.species != null) m.setSpeciesNational(ed.species!);
      // EXP must be re-derived when the level changes or the species changes
      // (a new species may have a different growth rate).
      final targetLevel = ed.level ?? m.level;
      if (ed.level != null || speciesChanged) {
        final rate = await _pokedex.growthRate(dex);
        m.setLevel(targetLevel, gen3Exp(rate, targetLevel));
      }
      // Strict-legal: a correlated Method-1 PID+IV supersedes nature/shiny/IVs.
      if (ed.legalPid != null) {
        m.setPidAndIvs(ed.legalPid!, ed.ivs ?? m.ivs);
      } else {
        if (ed.nature != null) m.setNature(ed.nature!);
        if (ed.shiny != null) m.setShiny(ed.shiny!);
        if (ed.ivs != null) m.setIVs(ed.ivs!);
      }
      if (ed.evs != null) m.setEVs(ed.evs!);
      if (ed.friendship != null) m.setFriendship(ed.friendship!);
      if (ed.otName != null) m.setOtName(ed.otName!);
      if (ed.ball != null) m.setBall(ed.ball!);
      if (ed.metLevel != null) m.setMetLevel(ed.metLevel!);
      if (ed.metLocation != null) m.setMetLocation(ed.metLocation!);
      if (ed.otGender != null) m.setOtGender(ed.otGender!);
      if (ed.language != null) m.setLanguage(ed.language!);
      if (ed.markings != null) m.setMarkings(ed.markings!);
      if (ed.pokerus != null) m.setPokerus(ed.pokerus!);
      if (ed.contest != null) m.setContest(ed.contest!);
      if (ed.heldItem != null) m.setHeldItem(ed.heldItem!);
      // Moves: an explicit list wins; a species change without one resets to a
      // legal moveset (the old moves are illegal on the new species).
      var newMoves = ed.moves;
      if (newMoves == null && speciesChanged) {
        newMoves = [for (final mv in (await gen3Learnset(dex)).take(4)) mv.id];
      }
      if (newMoves != null) {
        m.setMoves(newMoves);
        for (var k = 0; k < 4; k++) {
          final id = k < newMoves.length ? newMoves[k] : 0;
          m.setPP(k, id == 0 ? 0 : await _pokedex.movePP(id));
        }
      }
      // Nickname: explicit wins; a species change renames to the new species
      // (Gen 3 default nicknames are the species name in caps).
      if (ed.nickname != null) {
        m.setNickname(ed.nickname!);
      } else if (speciesChanged) {
        var name = '';
        for (final s in await _pokedex.loadIndex()) {
          if (s.id == dex) {
            name = s.name;
            break;
          }
        }
        if (name.isNotEmpty) m.setNickname(name.toUpperCase());
      }
      if (ed.changesStats) {
        try {
          final st = (await _pokedex.fetchDetail(dex)).stats;
          int g(String k) => st[k] ?? 50;
          m.recomputeStats([
            g('hp'), g('attack'), g('defense'),
            g('speed'), g('special-attack'), g('special-defense'),
          ]);
        } catch (_) {/* offline: stats stay as-is, IV/EV still applied */}
      }
      if (speciesChanged) e.markCaught(game.version, dex);
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
      // Mark the first N badge milestones (badges are earned in gym order).
      final badgeMilestones =
          game.milestones.where((m) => m.contains('Badge')).toList();
      final n = data.badgeCount!.clamp(0, badgeMilestones.length);
      for (var i = 0; i < n; i++) {
        p.milestones[badgeMilestones[i]] = true;
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
    // Event-flag achievements (FRLG story beats) auto-unlock on sync.
    if (data.flagAchievements.isNotEmpty) {
      p.unlockedAchievements.addAll(data.flagAchievements);
    }
    // Game-clear flag → mark the Champion / Elite Four milestones too.
    if (data.gameClear) {
      if (game.milestones.contains('Champion')) p.milestones['Champion'] = true;
      if (game.milestones.contains('Elite Four')) {
        p.milestones['Elite Four'] = true;
      }
    }
    _persist();
  }

  /// Auto-sync progress after a built-in play session: re-reads the freshly
  /// written save and applies dex + badges + team (non-destructive to the save).
  /// Returns a short summary for a snackbar, or null if nothing was read.
  Future<String?> autoSyncAfterPlay(Game game) async {
    SaveData? data;
    try {
      data = await scanSave(game);
    } catch (_) {
      return null;
    }
    if (data == null) return null;
    final before = badgesEarned(game.id);
    final beforeCaught = progressFor(game.id).caughtSpecies.length;
    await applySaveData(game, data, dex: true, badges: true, team: true);
    final badgeGain = badgesEarned(game.id) - before;
    final caughtGain =
        progressFor(game.id).caughtSpecies.length - beforeCaught;
    final parts = <String>[];
    if (data.badgeCount != null) parts.add('${data.badgeCount} badges');
    if (data.caughtCount > 0) parts.add('${data.caughtCount} caught');
    if (parts.isEmpty) return null;
    final delta = (badgeGain > 0 || caughtGain > 0)
        ? ' (+$badgeGain badge${badgeGain == 1 ? '' : 's'}, +$caughtGain caught)'
        : '';
    return 'Synced ${parts.join(' · ')}$delta';
  }

  /// Applies [data] and returns the titles of any achievements that newly
  /// unlocked (for toasts). Shared by the on-save and live-RAM paths.
  Future<List<String>> _detectUnlocks(Game game, SaveData data,
      {bool team = true}) async {
    final before = <String>{
      for (final s in gameAchievements(game))
        if (s.unlocked) s.achievement.id,
    };
    await applySaveData(game, data, dex: true, badges: true, team: team);
    return [
      for (final s in gameAchievements(game))
        if (s.unlocked && !before.contains(s.achievement.id))
          s.achievement.title,
    ];
  }

  /// Live achievement sync from the committed save (on in-game save / on exit).
  Future<List<String>> syncAndDetectUnlocks(Game game) async {
    SaveData? data;
    try {
      data = await scanSave(game);
    } catch (_) {
      return const [];
    }
    if (data == null) return const [];
    return _detectUnlocks(game, data, team: true);
  }

  // Cached committed editor used to fingerprint the live RAM (anchors are
  // stable, so it only needs loading once per game).
  Gen3SaveEditor? _anchorEditor;
  String? _anchorGameId;

  /// TRUE-LIVE achievement detection: reads the emulator's working RAM (EWRAM)
  /// so unlocks fire the instant they happen in-game, without saving. Falls
  /// back to nothing (callers keep the on-save path) if the RAM can't be read.
  Future<List<String>> liveRamUnlocks(Game game, Uint8List ewram) async {
    if (game.generation != 3) return const [];
    if (_anchorGameId != game.id || _anchorEditor == null) {
      final file = await _findSaveFile(game.id);
      if (file == null) return const [];
      try {
        _anchorEditor =
            Gen3SaveEditor.load(Uint8List.fromList(await file.readAsBytes()));
        _anchorGameId = game.id;
      } catch (_) {
        return const [];
      }
    }
    final ed = _anchorEditor!;
    final live = readGen3LiveRam(ewram, ed, game.version, 386);
    if (!live.any) return const [];

    final caught = live.caughtDex;
    final flagOf = live.flagOf;
    int? badgeCount;
    final flagAch = <String>{};
    var gameClear = false;
    if (flagOf != null) {
      final bb = ed.badgeFlagBase(game.version);
      var n = 0;
      for (var i = 0; i < 8; i++) {
        if (flagOf(bb + i)) n++;
      }
      badgeCount = n;
      if (game.version == 'firered' || game.version == 'leafgreen') {
        gameClear = flagOf(kFrlgGameClearFlag);
        for (final a in kFrlgAchievements) {
          final f = a.flags;
          if (f != null && f.any(flagOf)) flagAch.add(a.id);
        }
      }
    }

    // Skip the write+notify unless the live read actually adds something.
    final p = progressFor(game.id);
    final newCaught =
        caught != null && caught.any((id) => !p.caughtSpecies.contains(id));
    final newFlags = flagAch.any((id) => !p.unlockedAchievements.contains(id));
    final newBadge = badgeCount != null && badgeCount > badgesEarned(game.id);
    final newClear = gameClear && p.milestones['Champion'] != true;
    if (!newCaught && !newFlags && !newBadge && !newClear) return const [];

    final data = SaveData(
      generation: 3,
      versionId: game.version,
      caughtDex: caught ?? const {},
      badgeCount: badgeCount,
      flagAchievements: flagAch,
      gameClear: gameClear,
    );
    return _detectUnlocks(game, data, team: false);
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
      (Platform.isWindows || Platform.isAndroid || Platform.isIOS) &&
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

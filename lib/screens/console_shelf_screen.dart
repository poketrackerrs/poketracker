import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/region_theme.dart';
import '../models/game.dart';
import '../state/app_state.dart';
import '../widgets/console_art.dart';
import '../widgets/game_box_art.dart';
import 'cartridge_viewer.dart';
import 'emulators_screen.dart';
import 'emulator_screen.dart';
import 'game_screen.dart';
import 'launch3d.dart';

/// A shelf of a console's games shown as cartridge spines. Tap a spine to bring
/// the box forward; play runs the box-open → cartridge-insert → power-on
/// animation, then hands off to the emulator.
class ConsoleShelfScreen extends StatefulWidget {
  final BoxPlatform platform;
  final List<Game> games;
  const ConsoleShelfScreen(
      {super.key, required this.platform, required this.games});

  @override
  State<ConsoleShelfScreen> createState() => _ConsoleShelfScreenState();
}

class _ConsoleShelfScreenState extends State<ConsoleShelfScreen> {
  int _selected = 0;

  Color _tint(BuildContext context, Game g) {
    final state = context.read<AppState>();
    return state.regionTint ? regionColor(g.region, state.accent) : state.accent;
  }

  /// The .glb models are for the Game Boy family; the viewer works on mobile
  /// (model_viewer_plus) and Windows (webview_windows / WebView2).
  bool get _show3dCartridge =>
      (Platform.isAndroid || Platform.isIOS || Platform.isWindows) &&
      (widget.platform == BoxPlatform.gb || widget.platform == BoxPlatform.gbc);

  /// A real 3D console model exists only for the Game Boy.
  bool get _show3dConsole =>
      (Platform.isAndroid || Platform.isIOS || Platform.isWindows) &&
      widget.platform == BoxPlatform.gb;

  /// Which platforms get the cartridge slot-in launch animation: Game Boy (the
  /// classic 3D frames) and GBA (the Game Boy Advance SP scene in launch3d.dart).
  // Master switch for the Play launch animations. Off for now — Play launches
  // straight into the game. Return true to bring the animations back.
  bool get _launchAnimations => false;

  bool get _useLaunch3D =>
      (Platform.isAndroid || Platform.isIOS || Platform.isWindows) &&
      (widget.platform == BoxPlatform.gb ||
          widget.platform == BoxPlatform.gba);

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final game = widget.games[_selected];
    final accent = state.accent;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        title: Text(kConsoleNames[widget.platform] ?? 'Console'),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: _show3dConsole
                        ? () => showModelViewerDialog(context,
                            src: 'assets/models/gameboy_classic.glb',
                            title: kConsoleNames[widget.platform] ?? 'Console')
                        : null,
                    child: ConsoleArt(
                        platform: widget.platform,
                        size: 150,
                        preview: true,
                        interactive: true),
                  ),
                  if (_show3dConsole)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('Tap to view in 3D',
                          style: Theme.of(context).textTheme.bodySmall),
                    ),
                  const SizedBox(height: 12),
                  _selectedPanel(context, state, game),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
          _shelf(context, state),
        ],
      ),
    );
  }

  /// A compact glance at the player's tracked progress for [game].
  Widget _statsPreview(BuildContext context, AppState state, Game game) {
    final prog = state.progressFor(game.id);
    final baseCaught =
        prog.caughtSpecies.where((id) => id < 10000).length;
    final caught = baseCaught > 0 ? baseCaught : prog.dexCaught;
    final pct = (state.completion(game) * 100).round();
    final badgeLabels =
        game.milestones.where((m) => m.contains('Badge')).toList();
    final badges = badgeLabels.where((m) => prog.milestones[m] == true).length;
    final tint = _tint(context, game);

    Widget pill(String value, String label) => Container(
          constraints: const BoxConstraints(minWidth: 72),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(value,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700, color: tint)),
              Text(label, style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        );

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 10,
        runSpacing: 8,
        children: [
          pill('$pct%', 'Complete'),
          pill('$caught/${game.dexTotal}', 'Caught'),
          if (badgeLabels.isNotEmpty)
            pill('$badges/${badgeLabels.length}', 'Badges'),
          if (prog.team.isNotEmpty) pill('${prog.team.length}/6', 'Team'),
          if (prog.shinyHunts.isNotEmpty)
            pill('${prog.shinyHunts.where((h) => h.caught).length}', 'Shiny'),
        ],
      ),
    );
  }

  Widget _selectedPanel(BuildContext context, AppState state, Game game) {
    final installed = state.isInstalled(game.id);
    final canDownload = state.canDownload(game.id);
    final downloading = state.downloadProgress(game.id) != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          GestureDetector(
            onTap: () => _showBoxPopout(context, game),
            child: Hero(
              tag: 'boxhero_${game.id}',
              child: GameBoxArt(game: game, height: 170),
            ),
          ),
          const SizedBox(height: 2),
          Text('Tap the box to inspect',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 10),
          Text(game.title,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center),
          Text('${game.region} • ${game.releaseYear}',
              style: Theme.of(context).textTheme.bodySmall),
          _statsPreview(context, state, game),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              if (downloading)
                const FilledButton(onPressed: null, child: Text('Downloading…'))
              else if (installed)
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: _tint(context, game)),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Play'),
                  onPressed: () => _runLaunch(context, game),
                )
              else if (canDownload)
                FilledButton.icon(
                  icon: const Icon(Icons.download),
                  label: const Text('Download'),
                  onPressed: () async {
                    final m = ScaffoldMessenger.of(context);
                    try {
                      await context.read<AppState>().downloadGame(game.id);
                      m.showSnackBar(
                          SnackBar(content: Text('Downloaded ${game.title}')));
                    } catch (e) {
                      m.showSnackBar(
                          SnackBar(content: Text('Download failed: $e')));
                    }
                  },
                )
              else
                const Text('Link your Drive in Settings'),
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => GameScreen(game: game)),
                ),
                child: const Text('Details'),
              ),
              if (_show3dCartridge)
                TextButton.icon(
                  icon: const Icon(Icons.view_in_ar, size: 18),
                  label: const Text('Cartridge 3D'),
                  onPressed: () => showModelViewerDialog(context,
                      src: 'assets/models/gameboy_cartridge.glb',
                      title: game.title),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Pops the game's box into a hovering, drag-to-rotate overlay.
  void _showBoxPopout(BuildContext context, Game game) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GameBoxArt(game: game, height: 360, interactive: true),
            const SizedBox(height: 16),
            const Text('Drag to rotate · tap outside to close',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _shelf(BuildContext context, AppState state) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF8A5A33), Color(0xFF5E3D22)],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 150,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: widget.games.length,
              separatorBuilder: (_, _) => const SizedBox(width: 7),
              itemBuilder: (context, i) {
                final g = widget.games[i];
                final selected = i == _selected;
                return GestureDetector(
                  onTap: () => setState(() => _selected = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOut,
                    transform: Matrix4.translationValues(0, selected ? -18 : 0, 0),
                    width: 30,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(4)),
                      boxShadow: const [
                        BoxShadow(
                            color: Colors.black38,
                            blurRadius: 3,
                            offset: Offset(2, 0)),
                      ],
                      border: selected
                          ? Border.all(color: Colors.white, width: 2)
                          : null,
                    ),
                    // Real box spine artwork so the shelf matches the boxes.
                    child: GameSpine(game: g),
                  ),
                );
              },
            ),
          ),
          Container(
            height: 12,
            decoration: const BoxDecoration(
              color: Color(0xFF7A4E2C),
              boxShadow: [
                BoxShadow(
                    color: Colors.black45, blurRadius: 6, offset: Offset(0, 3)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _runLaunch(BuildContext context, Game game) async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final builtInRom =
        state.canPlayBuiltIn(game) ? state.builtInRomPath(game) : null;
    LaunchOutcome outcome = LaunchOutcome.noEmulator;
    Future<void> doLaunch() async {
      // Built-in games open in-app after the animation; skip the hand-off.
      if (builtInRom != null) return;
      outcome = await state.tryLaunchGame(game);
    }

    if (_launchAnimations) {
      if (_useLaunch3D) {
        // Real console + cartridge slot-in animation.
        await showLaunch3D(context, game: game, onLaunch: doLaunch);
      } else {
        await showDialog(
          context: context,
          barrierDismissible: false,
          barrierColor: Colors.black.withValues(alpha: 0.9),
          builder: (ctx) => _LaunchSequence(
            game: game,
            platform: widget.platform,
            tint: _tint(context, game),
            onLaunch: doLaunch,
          ),
        );
      }
    } else {
      // Launch animations are turned off for now — launch straight away.
      await doLaunch();
    }
    if (!mounted) return;
    if (builtInRom != null) {
      navigator.push(MaterialPageRoute(
          builder: (_) => EmulatorScreen(game: game, romPath: builtInRom)));
      return;
    }
    void toEmulators() => navigator.push(
        MaterialPageRoute(builder: (_) => const EmulatorsScreen()));
    switch (outcome) {
      case LaunchOutcome.launched:
        messenger.showSnackBar(
            SnackBar(content: Text('Launching ${game.title}…')));
      case LaunchOutcome.handoffFailed:
        final emu = state.emulatorNameFor(game) ?? 'the emulator';
        messenger.showSnackBar(SnackBar(
          content: Text(
              'Opened $emu, but it won\'t load ${game.title} automatically. '
              'Load it from inside $emu, or install My Boy!/My OldBoy! for '
              'one-tap launch.'),
          duration: const Duration(seconds: 7),
          action: SnackBarAction(label: 'Emulators', onPressed: toEmulators),
        ));
      case LaunchOutcome.noEmulator:
        messenger.showSnackBar(SnackBar(
          content: Text('No emulator found for ${game.title}.'),
          action: SnackBarAction(label: 'Emulators', onPressed: toEmulators),
        ));
    }
  }
}

/// Short title (drops the "Pokemon " prefix) for narrow spines.
String _shortTitle(Game g) =>
    g.title.replaceFirst(RegExp(r'^Pok[eé]mon\s+'), '');

/// The animated launch sequence overlay.
class _LaunchSequence extends StatefulWidget {
  final Game game;
  final BoxPlatform platform;
  final Color tint;
  final Future<void> Function() onLaunch;
  const _LaunchSequence({
    required this.game,
    required this.platform,
    required this.tint,
    required this.onLaunch,
  });

  @override
  State<_LaunchSequence> createState() => _LaunchSequenceState();
}

class _LaunchSequenceState extends State<_LaunchSequence>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  final AudioPlayer _sfx = AudioPlayer();
  bool _playedInsert = false;
  bool _playedPower = false;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 3200))
      ..addStatusListener((s) async {
        if (s == AnimationStatus.completed) {
          await widget.onLaunch();
          if (mounted) Navigator.of(context).pop();
        }
      })
      ..addListener(_maybePlaySounds);
    // Let the Hero fly-in finish before the box hinges open.
    Future.delayed(const Duration(milliseconds: 380), () {
      if (mounted) _c.forward();
    });
  }

  void _maybePlaySounds() {
    final t = _c.value;
    if (!_playedInsert && t >= 0.62) {
      _playedInsert = true;
      _play('sfx/insert.wav');
    }
    if (!_playedPower && t >= 0.9) {
      _playedPower = true;
      _play('sfx/poweron.wav');
    }
  }

  Future<void> _play(String asset) async {
    try {
      await _sfx.stop();
      await _sfx.play(AssetSource(asset));
    } catch (_) {}
  }

  @override
  void dispose() {
    _c.dispose();
    _sfx.dispose();
    super.dispose();
  }

  double _seg(double t, double a, double b) =>
      ((t - a) / (b - a)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(24),
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          // Box flies in (Hero), hinges open, ejects the cartridge.
          final open = Curves.easeIn.transform(_seg(t, 0.12, 0.34));
          final boxOpacity = 1 - _seg(t, 0.34, 0.46);
          final lid = Matrix4.identity()
            ..setEntry(3, 2, 0.0018)
            ..rotateX(-1.35 * open);
          // Cartridge rises into the console's (back-facing) top slot.
          final cartFade = _seg(t, 0.34, 0.44);
          final travel = Curves.easeInOut.transform(_seg(t, 0.44, 0.68));
          final cartDy = 40.0 + (-250.0 - 40.0) * travel;
          final cartScale = 1.0 - 0.5 * travel;
          final cartOpacity = cartFade * (1 - _seg(t, 0.62, 0.7));
          // Console shows its back while the cart inserts, then rotates to
          // front and powers on.
          final gb = widget.platform == BoxPlatform.gb;
          final rot = Curves.easeInOut.transform(_seg(t, 0.7, 0.9));
          final yaw = gb ? math.pi * (1 - rot) : null; // back → front
          final glow = _seg(t, 0.9, 1.0);
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConsoleArt(
                  platform: widget.platform,
                  size: 160,
                  glow: glow,
                  yaw: yaw,
                  pitch: gb ? 0.14 : null),
              SizedBox(
                height: 250,
                child: Center(
                  child: Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: [
                      Opacity(
                        opacity: boxOpacity.clamp(0.0, 1.0),
                        child: Transform(
                          alignment: Alignment.topCenter,
                          transform: lid,
                          child: Hero(
                            tag: 'boxhero_${widget.game.id}',
                            child: GameBoxArt(game: widget.game, height: 180),
                          ),
                        ),
                      ),
                      Transform.translate(
                        offset: Offset(0, cartDy),
                        child: Transform.scale(
                          scale: cartScale,
                          child: Opacity(
                            opacity: cartOpacity.clamp(0.0, 1.0),
                            child: CartridgeArt(
                                color: widget.tint,
                                platform: widget.platform,
                                size: 88),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                glow > 0.1
                    ? 'Now loading ${_shortTitle(widget.game)}…'
                    : (t > 0.44
                        ? 'Inserting cartridge…'
                        : 'Opening case…'),
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          );
        },
      ),
    );
  }
}

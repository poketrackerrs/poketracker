import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/region_theme.dart';
import '../models/game.dart';
import '../state/app_state.dart';
import '../widgets/console_art.dart';
import '../widgets/game_box_art.dart';
import 'emulators_screen.dart';
import 'game_screen.dart';

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
          const SizedBox(height: 16),
          ConsoleArt(platform: widget.platform, size: 130),
          const SizedBox(height: 12),
          Expanded(child: _selectedPanel(context, state, game)),
          _shelf(context, state),
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
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Hero(
            tag: 'boxhero_${game.id}',
            child: GameBoxArt(game: game, height: 170),
          ),
          const SizedBox(height: 12),
          Text(game.title, style: Theme.of(context).textTheme.titleMedium),
          Text('${game.region} • ${game.releaseYear}',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (downloading)
                const FilledButton(
                    onPressed: null, child: Text('Downloading…'))
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
                Text('Link your Drive in Settings to download',
                    style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => GameScreen(game: game)),
                ),
                child: const Text('Details'),
              ),
            ],
          ),
        ],
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
                    decoration: BoxDecoration(
                      color: _tint(context, g),
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
                    alignment: Alignment.bottomCenter,
                    padding: const EdgeInsets.only(bottom: 10),
                    child: RotatedBox(
                      quarterTurns: 1,
                      child: Text(
                        _shortTitle(g),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
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
    bool launched = false;
    await showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.9),
      builder: (ctx) => _LaunchSequence(
        game: game,
        platform: widget.platform,
        tint: _tint(context, game),
        onLaunch: () async {
          launched = await state.tryLaunchGame(game);
        },
      ),
    );
    if (!mounted) return;
    if (launched) {
      messenger.showSnackBar(
          SnackBar(content: Text('Launching ${game.title}…')));
    } else {
      messenger.showSnackBar(SnackBar(
        content: Text('No emulator found for ${game.title}.'),
        action: SnackBarAction(
          label: 'Emulators',
          onPressed: () => navigator.push(
              MaterialPageRoute(builder: (_) => const EmulatorsScreen())),
        ),
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
        vsync: this, duration: const Duration(milliseconds: 2600))
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
    if (!_playedInsert && t >= 0.52) {
      _playedInsert = true;
      _play('sfx/insert.wav');
    }
    if (!_playedPower && t >= 0.82) {
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
          final glow = _seg(t, 0.82, 1.0);
          // Box hinges open from the top like a lid, then fades.
          final open = Curves.easeIn.transform(_seg(t, 0.16, 0.44));
          final boxOpacity = 1 - _seg(t, 0.46, 0.6);
          final lid = Matrix4.identity()
            ..setEntry(3, 2, 0.0018)
            ..rotateX(-1.35 * open);
          // Cartridge emerges from the box then rises into the console.
          final cartFade = _seg(t, 0.42, 0.52);
          final travel = Curves.easeInOut.transform(_seg(t, 0.52, 0.82));
          final cartDy = 40.0 + (-250.0 - 40.0) * travel;
          final cartScale = 1.0 - 0.45 * travel;
          final cartOpacity = cartFade * (1 - _seg(t, 0.8, 0.9));
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConsoleArt(platform: widget.platform, size: 160, glow: glow),
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
                    : (t > 0.5 ? 'Inserting cartridge…' : 'Opening case…'),
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          );
        },
      ),
    );
  }
}

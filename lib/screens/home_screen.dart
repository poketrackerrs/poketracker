import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/games_data.dart';
import '../data/region_theme.dart';
import '../models/game.dart';
import '../state/app_state.dart';
import '../widgets/game_box_art.dart';
import 'game_screen.dart';
import 'updates_screen.dart';
import 'pokedex_list_screen.dart';
import 'emulators_screen.dart';
import 'settings_screen.dart';

/// Root scaffold with a bottom nav switching between the game tracker and the
/// built-in Pokedex.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  static const _titles = ['PokeTracker', 'Pokedex', 'Settings'];
  static const _icons = [Icons.catching_pokemon, Icons.menu_book, Icons.settings];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(_icons[_index]),
            const SizedBox(width: 8),
            Text(_titles[_index]),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Emulators',
            icon: const Icon(Icons.sports_esports),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const EmulatorsScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Check for updates',
            icon: const Icon(Icons.system_update),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const UpdatesScreen()),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: const [
          _GamesTab(),
          PokedexListScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.videogame_asset), label: 'Games'),
          NavigationDestination(icon: Icon(Icons.menu_book), label: 'Pokedex'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}

class _GamesTab extends StatelessWidget {
  const _GamesTab();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final byGen = gamesByGeneration();
    final gens = byGen.keys.toList()..sort();

    if (!state.isLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _OverallCard(),
        _LibraryBar(),
        for (final gen in gens) ...[
          _SectionHeader(gen: gen, games: byGen[gen]!),
          for (final game in byGen[gen]!) _GameTile(game: game),
        ],
      ],
    );
  }
}

/// A generation section header: region-colored dot, region name(s), and a
/// summary of game count and average completion.
class _SectionHeader extends StatelessWidget {
  final int gen;
  final List<Game> games;
  const _SectionHeader({required this.gen, required this.games});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final regions = <String>[];
    for (final g in games) {
      if (!regions.contains(g.region)) regions.add(g.region);
    }
    final avg = games.map(state.completion).reduce((a, b) => a + b) / games.length;
    final tint = state.regionTint
        ? regionColor(regions.first, state.accent)
        : state.accent;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Text(regions.join(' · '),
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const Spacer(),
          Text('Gen $gen · ${games.length} games · ${(avg * 100).round()}%',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _OverallCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final avg = kGames.isEmpty
        ? 0.0
        : kGames.map(state.completion).reduce((a, b) => a + b) / kGames.length;
    final muted = Theme.of(context).textTheme.bodySmall?.color;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            _CompletionRing(value: avg, color: state.accent, size: 78, stroke: 8),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Overall completion',
                      style: TextStyle(fontSize: 12, color: muted)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _Stat(value: '${state.startedCount}', label: 'started'),
                      _Stat(value: '${state.totalCaught}', label: 'caught'),
                      _Stat(value: '${state.totalBadges}', label: 'badges'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  const _Stat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style:
                  const TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).textTheme.bodySmall?.color)),
        ],
      ),
    );
  }
}

class _GameTile extends StatelessWidget {
  final Game game;
  const _GameTile({required this.game});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final pct = state.completion(game);
    final tint =
        state.regionTint ? regionColor(game.region, state.accent) : state.accent;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => GameScreen(game: game)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              GameBoxArt(game: game, height: 76),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(game.title,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _MetaChip(text: game.region),
                        _MetaChip(text: '${game.releaseYear}'),
                        _MetaChip(text: game.category.label),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _CompletionRing(value: pct, color: tint, size: 46, stroke: 5),
              const SizedBox(width: 6),
              _DownloadControl(game: game),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final String text;
  const _MetaChip({required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text,
          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
    );
  }
}

/// A circular completion ring with the percentage in the middle.
class _CompletionRing extends StatelessWidget {
  final double value; // 0..1
  final Color color;
  final double size;
  final double stroke;
  const _CompletionRing({
    required this.value,
    required this.color,
    this.size = 46,
    this.stroke = 5,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _RingPainter(
              value: value.clamp(0.0, 1.0),
              color: color,
              track: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.8),
              stroke: stroke,
            ),
          ),
          Text('${(value * 100).round()}%',
              style: TextStyle(
                  fontSize: size * 0.26, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double value;
  final Color color;
  final Color track;
  final double stroke;
  _RingPainter({
    required this.value,
    required this.color,
    required this.track,
    required this.stroke,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.width - stroke) / 2;
    final bg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawCircle(center, radius, bg);
    final fg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2, 2 * math.pi * value, false, fg);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.color != color || old.track != track;
}

/// Clickable line showing the games library folder; opens it in Explorer.
class _LibraryBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: ListTile(
        leading: const Icon(Icons.folder),
        title: const Text('Games folder'),
        subtitle: Text(
          state.libraryPath.isEmpty ? '…' : state.libraryPath,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Refresh (rescan folder)',
              icon: const Icon(Icons.refresh),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final s = context.read<AppState>();
                await s.refreshInstalled();
                await s.refreshEmulators();
                messenger.showSnackBar(
                  const SnackBar(content: Text('Library & emulators refreshed')),
                );
              },
            ),
            IconButton(
              tooltip: 'Open folder',
              icon: const Icon(Icons.open_in_new),
              onPressed: () => context.read<AppState>().openLibraryFolder(),
            ),
          ],
        ),
        onTap: () => context.read<AppState>().openLibraryFolder(),
      ),
    );
  }
}

/// Per-game download button / status, driven by AppState.
class _DownloadControl extends StatelessWidget {
  final Game game;
  const _DownloadControl({required this.game});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final prog = state.downloadProgress(game.id);

    if (prog != null) {
      return SizedBox(
        width: 34,
        height: 34,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(value: prog == 0 ? null : prog, strokeWidth: 3),
            Text('${(prog * 100).round()}', style: const TextStyle(fontSize: 9)),
          ],
        ),
      );
    }
    if (state.isInstalled(game.id)) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Play',
            icon: const Icon(Icons.play_circle_fill,
                color: Colors.green, size: 28),
            visualDensity: VisualDensity.compact,
            onPressed: () async {
              final s = context.read<AppState>();
              final messenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(context);
              final launched = await s.tryLaunchGame(game);
              if (launched) {
                messenger.showSnackBar(
                  SnackBar(content: Text('Launching ${game.title}…')),
                );
              } else {
                messenger.showSnackBar(SnackBar(
                  content: Text(
                      'No emulator found for ${game.title}. Install one to play.'),
                  action: SnackBarAction(
                    label: 'Emulators',
                    onPressed: () => navigator.push(MaterialPageRoute(
                        builder: (_) => const EmulatorsScreen())),
                  ),
                ));
              }
            },
          ),
          IconButton(
            tooltip: 'Show file in folder',
            icon: const Icon(Icons.folder_open),
            visualDensity: VisualDensity.compact,
            onPressed: () => context.read<AppState>().revealGameFile(game.id),
          ),
        ],
      );
    }
    if (state.canDownload(game.id)) {
      return IconButton(
        tooltip: 'Download from your Drive',
        icon: const Icon(Icons.download),
        visualDensity: VisualDensity.compact,
        onPressed: () async {
          final messenger = ScaffoldMessenger.of(context);
          try {
            await context.read<AppState>().downloadGame(game.id);
            messenger.showSnackBar(
              SnackBar(content: Text('Downloaded ${game.title}')),
            );
          } catch (e) {
            messenger.showSnackBar(
              SnackBar(content: Text('Download failed: $e')),
            );
          }
        },
      );
    }
    return const SizedBox.shrink();
  }
}

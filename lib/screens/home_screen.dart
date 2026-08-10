import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/games_data.dart';
import '../data/region_theme.dart';
import '../models/game.dart';
import '../state/app_state.dart';
import '../widgets/completion_ring.dart';
import '../widgets/console_art.dart';
import '../widgets/game_box_art.dart';
import 'console_shelf_screen.dart';
import 'game_screen.dart';
import 'updates_screen.dart';
import 'pokedex_list_screen.dart';
import 'emulators_screen.dart';
import 'emulator_screen.dart';
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
        _ModeToggle(consoleMode: state.consoleMode),
        if (state.consoleMode)
          _ConsoleGrid()
        else ...[
          _LibraryBar(),
          for (final gen in gens) ...[
            _SectionHeader(gen: gen, games: byGen[gen]!),
            for (final game in byGen[gen]!) _GameTile(game: game),
          ],
        ],
      ],
    );
  }
}

/// Toggle between the console shelf and the classic list.
class _ModeToggle extends StatelessWidget {
  final bool consoleMode;
  const _ModeToggle({required this.consoleMode});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Align(
        alignment: Alignment.centerRight,
        child: SegmentedButton<bool>(
          showSelectedIcon: false,
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          segments: const [
            ButtonSegment(
                value: true,
                label: Text('Consoles'),
                icon: Icon(Icons.videogame_asset, size: 18)),
            ButtonSegment(
                value: false,
                label: Text('List'),
                icon: Icon(Icons.view_list, size: 18)),
          ],
          selected: {consoleMode},
          onSelectionChanged: (s) =>
              context.read<AppState>().setConsoleMode(s.first),
        ),
      ),
    );
  }
}

/// The assortment of consoles the library spans; tap one to open its shelf.
class _ConsoleGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final byPlatform = <BoxPlatform, List<Game>>{};
    for (final g in kGames) {
      byPlatform.putIfAbsent(platformForGame(g), () => []).add(g);
    }
    final platforms =
        kConsoleOrder.where((p) => byPlatform.containsKey(p)).toList();
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 0.92,
      children: [
        for (final p in platforms)
          _ConsoleCard(platform: p, games: byPlatform[p]!),
      ],
    );
  }
}

class _ConsoleCard extends StatelessWidget {
  final BoxPlatform platform;
  final List<Game> games;
  const _ConsoleCard({required this.platform, required this.games});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                ConsoleShelfScreen(platform: platform, games: games),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: Center(
                  child: ConsoleArt(platform: platform, size: 96, preview: true),
                ),
              ),
              const SizedBox(height: 8),
              Text(kConsoleNames[platform] ?? '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
              Text('${games.length} games',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
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
            CompletionRing(value: avg, color: state.accent, size: 78, stroke: 8),
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
              CompletionRing(value: pct, color: tint, size: 46, stroke: 5),
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
              if (s.canPlayBuiltIn(game)) {
                final rom = s.builtInRomPath(game);
                if (rom != null) {
                  navigator.push(MaterialPageRoute(
                      builder: (_) =>
                          EmulatorScreen(game: game, romPath: rom)));
                  return;
                }
              }
              final outcome = await s.tryLaunchGame(game);
              void toEmulators() => navigator.push(MaterialPageRoute(
                  builder: (_) => const EmulatorsScreen()));
              switch (outcome) {
                case LaunchOutcome.launched:
                  messenger.showSnackBar(
                    SnackBar(content: Text('Launching ${game.title}…')),
                  );
                case LaunchOutcome.handoffFailed:
                  final emu = s.emulatorNameFor(game) ?? 'the emulator';
                  messenger.showSnackBar(SnackBar(
                    content: Text(
                        'Opened $emu, but it won\'t load ${game.title} '
                        'automatically. Load it from inside $emu, or install '
                        'My Boy!/My OldBoy! for one-tap launch.'),
                    duration: const Duration(seconds: 7),
                    action: SnackBarAction(
                        label: 'Emulators', onPressed: toEmulators),
                  ));
                case LaunchOutcome.noEmulator:
                  messenger.showSnackBar(SnackBar(
                    content: Text(
                        'No emulator found for ${game.title}. Install one to play.'),
                    action: SnackBarAction(
                        label: 'Emulators', onPressed: toEmulators),
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

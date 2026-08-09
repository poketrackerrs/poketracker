import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/games_data.dart';
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text(
              'Generation $gen',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          for (final game in byGen[gen]!) _GameTile(game: game),
        ],
      ],
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
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Overall completion',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: avg,
                minHeight: 12,
              ),
            ),
            const SizedBox(height: 8),
            Text('${(avg * 100).toStringAsFixed(1)}% across ${kGames.length} games'),
          ],
        ),
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

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => GameScreen(game: game)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              GameBoxArt(game: game, height: 80),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(game.title,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      '${game.region} • ${game.releaseYear} • ${game.category.label}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(value: pct, minHeight: 6),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${(pct * 100).round()}%',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 6),
                  _DownloadControl(game: game),
                ],
              ),
            ],
          ),
        ),
      ),
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

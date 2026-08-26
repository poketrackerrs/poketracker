import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/games_data.dart';
import '../models/game.dart';
import '../state/app_state.dart';
import '../widgets/completion_ring.dart';
import '../widgets/game_box_art.dart';
import '../widgets/cartridge_nav.dart';
import 'achievements_screen.dart';
import 'game_screen.dart';
import 'updates_screen.dart';
import 'pokedex_list_screen.dart';
import 'settings_screen.dart';
import 'vault_screen.dart';

/// Root scaffold with a bottom nav switching between the game tracker and the
/// built-in Pokedex.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  static const _titles = ['PokeTracker', 'Pokedex', 'Vault', 'Settings'];
  static const _icons = [
    Icons.catching_pokemon,
    Icons.menu_book,
    Icons.inventory_2,
    Icons.settings,
  ];

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
            tooltip: 'Achievements',
            icon: const Icon(Icons.military_tech),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AchievementsScreen()),
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
          VaultScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: CartridgeNavBar(
        index: _index,
        onSelect: (i) => setState(() => _index = i),
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
        for (final gen in gens) _GenShelf(gen: gen, games: byGen[gen]!),
      ],
    );
  }
}

/// One generation's games as 3D boxes standing on a wooden shelf.
class _GenShelf extends StatelessWidget {
  final int gen;
  final List<Game> games;
  const _GenShelf({required this.gen, required this.games});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 2),
            child: Row(
              children: [
                Text('GEN $gen',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        letterSpacing: 1.5,
                        color: scheme.onSurface)),
                const SizedBox(width: 8),
                Text(games.first.region.toUpperCase(),
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                        letterSpacing: 1,
                        color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          SizedBox(
            height: 200,
            child: Stack(
              children: [
                // wooden plank the boxes stand on
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 16,
                  child: Container(
                    height: 22,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0xFF8A6440),
                          Color(0xFF5A3A22),
                          Color(0xFF3E2818)
                        ],
                      ),
                      borderRadius: BorderRadius.circular(3),
                      boxShadow: const [
                        BoxShadow(
                            color: Color(0x66000000),
                            blurRadius: 12,
                            offset: Offset(0, 8)),
                      ],
                    ),
                  ),
                ),
                Positioned.fill(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final g in games)
                          Padding(
                            padding: const EdgeInsets.only(right: 14, bottom: 36),
                            child: GestureDetector(
                              onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                      builder: (_) => GameScreen(game: g))),
                              child: GameBoxArt(game: g, height: 150),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A generation section header: region-colored dot, region name(s), and a
/// summary of game count and average completion.
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

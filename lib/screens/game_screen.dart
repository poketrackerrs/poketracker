import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../data/pokeapi_maps.dart';
import '../models/game.dart';
import '../models/pokedex_models.dart';
import '../services/pokedex_service.dart';
import '../state/app_state.dart';
import '../widgets/game_box_art.dart';
import 'pokemon_detail_screen.dart';

class GameScreen extends StatelessWidget {
  final Game game;
  const GameScreen({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(title: Text(game.title)),
        body: Column(
          children: [
            _GameHeader(game: game),
            Material(
              color: Theme.of(context).colorScheme.surface,
              child: const TabBar(
                isScrollable: true,
                tabs: [
                  Tab(icon: Icon(Icons.emoji_events), text: 'Badges'),
                  Tab(icon: Icon(Icons.menu_book), text: 'Pokedex'),
                  Tab(icon: Icon(Icons.groups), text: 'Team'),
                  Tab(icon: Icon(Icons.auto_awesome), text: 'Shiny'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _MilestonesTab(game: game),
                  _DexTab(game: game),
                  _TeamTab(game: game),
                  _ShinyTab(game: game),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GameHeader extends StatelessWidget {
  final Game game;
  const _GameHeader({required this.game});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _showBoxPopout(context, game),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GameBoxArt(game: game, height: 130),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.zoom_out_map,
                        size: 12,
                        color: Theme.of(context).textTheme.bodySmall?.color),
                    const SizedBox(width: 3),
                    Text('Tap to view',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(game.title,
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text('${game.region} • ${game.releaseYear}'),
                Text('${game.category.label} • Generation ${game.generation}'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Pops the game's box into an enlarged, drag-to-rotate overlay above the page.
void _showBoxPopout(BuildContext context, Game game) {
  showDialog(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.88),
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GameBoxArt(game: game, height: 400, interactive: true),
          const SizedBox(height: 20),
          const Text(
            'Drag to rotate  •  tap outside to close',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    ),
  );
}

// --------------------------------------------------------------- Badges
class _MilestonesTab extends StatelessWidget {
  final Game game;
  const _MilestonesTab({required this.game});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final p = state.progressFor(game.id);
    final done = p.milestones.values.where((v) => v).length;

    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text('$done / ${game.milestones.length} completed',
              style: Theme.of(context).textTheme.titleMedium),
        ),
        for (final m in game.milestones)
          CheckboxListTile(
            title: Text(m),
            value: p.milestones[m] ?? false,
            onChanged: (v) => state.setMilestone(game.id, m, v ?? false),
          ),
      ],
    );
  }
}

// --------------------------------------------------------------- Pokedex
/// Per-game Pokedex: only this game's species, with obtainability tags and a
/// caught checkbox that feeds completion.
class _DexTab extends StatefulWidget {
  final Game game;
  const _DexTab({required this.game});

  @override
  State<_DexTab> createState() => _DexTabState();
}

enum _DexFilter { all, caught, missing }

class _DexTabState extends State<_DexTab> {
  final _service = PokedexService();
  GameDex? _dex;
  bool _loading = true;
  String? _error;
  _DexFilter _filter = _DexFilter.all;

  // Memoized obtainability futures so rebuilds (checkbox taps) don't refetch.
  final Map<int, Future<ObtainInfo>> _obtain = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dex = await _service.loadGameDex(widget.game.versionGroup);
      if (!mounted) return;
      setState(() {
        _dex = dex;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load this game\'s Pokedex.\nCheck your connection and retry.';
        _loading = false;
      });
    }
  }

  Future<ObtainInfo> _obtainFor(int id, List<String> versions) =>
      _obtain.putIfAbsent(id, () => _service.loadObtainability(id, versions));

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    final dex = _dex!;
    if (dex.species.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            "Pokedex data for this game isn't available yet.",
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final state = context.watch<AppState>();
    final caught = state.caughtCount(widget.game.id);
    final total = dex.species.length;

    final visible = dex.species.where((s) {
      final isCaught = state.isCaught(widget.game.id, s.id);
      switch (_filter) {
        case _DexFilter.all:
          return true;
        case _DexFilter.caught:
          return isCaught;
        case _DexFilter.missing:
          return !isCaught;
      }
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Caught $caught / $total',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: total == 0 ? 0 : caught / total,
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final f in _DexFilter.values)
                    ChoiceChip(
                      label: Text(f.name[0].toUpperCase() + f.name.substring(1)),
                      selected: _filter == f,
                      onSelected: (_) => setState(() => _filter = f),
                    ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: visible.length,
            itemBuilder: (context, i) {
              final s = visible[i];
              final isCaught = state.isCaught(widget.game.id, s.id);
              return ListTile(
                leading: SizedBox(
                  width: 44,
                  height: 44,
                  child: CachedNetworkImage(
                    imageUrl: s.spriteUrl,
                    fit: BoxFit.contain,
                    errorWidget: (_, _, _) =>
                        const Icon(Icons.catching_pokemon, color: Colors.grey),
                    placeholder: (_, _) => const SizedBox(),
                  ),
                ),
                title: Text(prettifyName(s.name)),
                subtitle: FutureBuilder<ObtainInfo>(
                  future: _obtainFor(s.id, [widget.game.version]),
                  builder: (context, snap) {
                    return Row(
                      children: [
                        Text('#${s.entryNumber.toString().padLeft(3, '0')}'),
                        const SizedBox(width: 8),
                        if (snap.hasData)
                          _ObtainChip(info: snap.data!)
                        else
                          const Text('…', style: TextStyle(color: Colors.grey)),
                      ],
                    );
                  },
                ),
                trailing: Checkbox(
                  value: isCaught,
                  onChanged: (v) =>
                      state.setCaught(widget.game.id, s.id, v ?? false),
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PokemonDetailScreen(
                      id: s.id,
                      name: s.name,
                      generation: widget.game.generation,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Colored chip summarizing obtainability.
class _ObtainChip extends StatelessWidget {
  final ObtainInfo info;
  const _ObtainChip({required this.info});

  @override
  Widget build(BuildContext context) {
    late Color color;
    late String label;
    switch (info.kind) {
      case ObtainKind.wild:
        color = Colors.green;
        label = 'Wild';
        break;
      case ObtainKind.partial:
        color = Colors.blue;
        label = 'Wild: ${info.versions.map(prettifyName).join(', ')}';
        break;
      case ObtainKind.none:
        color = Colors.orange;
        label = 'Not in wild';
        break;
      case ObtainKind.unknown:
        color = Colors.grey;
        label = 'Unknown';
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(label,
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

// --------------------------------------------------------------- Team
class _TeamTab extends StatelessWidget {
  final Game game;
  const _TeamTab({required this.game});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final team = state.progressFor(game.id).team;

    return Scaffold(
      body: team.isEmpty
          ? const Center(child: Text('No team members yet. Tap + to add one.'))
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: team.length,
              itemBuilder: (context, i) {
                final member = team[i];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextFormField(
                            initialValue: member.species,
                            decoration:
                                const InputDecoration(labelText: 'Species'),
                            onChanged: (v) {
                              member.species = v;
                              state.updateTeamMember(game.id, i, member);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 3,
                          child: TextFormField(
                            initialValue: member.nickname,
                            decoration:
                                const InputDecoration(labelText: 'Nickname'),
                            onChanged: (v) {
                              member.nickname = v;
                              state.updateTeamMember(game.id, i, member);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 64,
                          child: TextFormField(
                            initialValue: member.level.toString(),
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Lv'),
                            onChanged: (v) {
                              member.level = int.tryParse(v) ?? member.level;
                              state.updateTeamMember(game.id, i, member);
                            },
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => state.removeTeamMember(game.id, i),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: team.length < 6
          ? FloatingActionButton.extended(
              onPressed: () => state.addTeamMember(game.id),
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            )
          : null,
    );
  }
}

// --------------------------------------------------------------- Shiny
class _ShinyTab extends StatelessWidget {
  final Game game;
  const _ShinyTab({required this.game});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final hunts = state.progressFor(game.id).shinyHunts;

    return Scaffold(
      body: hunts.isEmpty
          ? const Center(child: Text('No shiny hunts yet. Tap + to start one.'))
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: hunts.length,
              itemBuilder: (context, i) {
                final hunt = hunts[i];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                initialValue: hunt.species,
                                decoration:
                                    const InputDecoration(labelText: 'Species'),
                                onChanged: (v) {
                                  hunt.species = v;
                                  state.updateShinyHunt(game.id, i, hunt);
                                },
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () =>
                                  state.removeShinyHunt(game.id, i),
                            ),
                          ],
                        ),
                        TextFormField(
                          initialValue: hunt.method,
                          decoration: const InputDecoration(labelText: 'Method'),
                          onChanged: (v) {
                            hunt.method = v;
                            state.updateShinyHunt(game.id, i, hunt);
                          },
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Text('Encounters: ${hunt.count}',
                                style: Theme.of(context).textTheme.titleMedium),
                            const Spacer(),
                            IconButton.filledTonal(
                              onPressed: hunt.count > 0
                                  ? () {
                                      hunt.count--;
                                      state.updateShinyHunt(game.id, i, hunt);
                                    }
                                  : null,
                              icon: const Icon(Icons.remove),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filled(
                              onPressed: () {
                                hunt.count++;
                                state.updateShinyHunt(game.id, i, hunt);
                              },
                              icon: const Icon(Icons.add),
                            ),
                          ],
                        ),
                        SwitchListTile(
                          title: const Text('Caught!'),
                          value: hunt.caught,
                          onChanged: (v) {
                            hunt.caught = v;
                            state.updateShinyHunt(game.id, i, hunt);
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => state.addShinyHunt(game.id),
        icon: const Icon(Icons.add),
        label: const Text('New hunt'),
      ),
    );
  }
}

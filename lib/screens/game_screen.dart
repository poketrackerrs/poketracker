import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../data/pokeapi_maps.dart';
import '../data/region_theme.dart';
import '../models/game.dart';
import '../models/pokedex_models.dart';
import '../models/progress.dart';
import '../models/save_models.dart';
import '../services/pokedex_service.dart';
import '../state/app_state.dart';
import '../widgets/completion_ring.dart';
import '../widgets/game_box_art.dart';
import 'pokemon_detail_screen.dart';

class GameScreen extends StatelessWidget {
  final Game game;
  const GameScreen({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final tint =
        state.regionTint ? regionColor(game.region, state.accent) : state.accent;
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: tint,
          foregroundColor: Colors.white,
          title: Text(game.title),
          actions: [
            IconButton(
              tooltip: 'Sync from save file',
              icon: const Icon(Icons.sync),
              onPressed: () => _startSaveSync(context, game),
            ),
          ],
        ),
        body: Column(
          children: [
            _GameHeader(game: game, tint: tint),
            Material(
              color: Theme.of(context).colorScheme.surface,
              child: TabBar(
                isScrollable: true,
                indicatorColor: tint,
                labelColor: tint,
                tabs: const [
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
                  _MilestonesTab(game: game, tint: tint),
                  _DexTab(game: game, tint: tint),
                  _TeamTab(game: game, tint: tint),
                  _ShinyTab(game: game, tint: tint),
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
  final Color tint;
  const _GameHeader({required this.game, required this.tint});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final pct = state.completion(game);
    return Container(
      width: double.infinity,
      color: tint,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: () => _showBoxPopout(context, game),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GameBoxArt(game: game, height: 118),
                const SizedBox(height: 3),
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.zoom_out_map, size: 11, color: Colors.white70),
                    SizedBox(width: 3),
                    Text('Tap to rotate',
                        style: TextStyle(color: Colors.white70, fontSize: 11)),
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
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _HeaderChip(text: game.region),
                    _HeaderChip(text: '${game.releaseYear}'),
                    _HeaderChip(text: game.category.label),
                    _HeaderChip(text: 'Gen ${game.generation}'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          CompletionRing(
            value: pct,
            color: Colors.white,
            size: 62,
            stroke: 6,
            trackColor: Colors.white.withValues(alpha: 0.3),
            textColor: Colors.white,
          ),
        ],
      ),
    );
  }
}

class _HeaderChip extends StatelessWidget {
  final String text;
  const _HeaderChip({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text,
          style: const TextStyle(color: Colors.white, fontSize: 12)),
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
  final Color tint;
  const _MilestonesTab({required this.game, required this.tint});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final p = state.progressFor(game.id);
    bool done(String m) => p.milestones[m] ?? false;
    void toggle(String m) => state.setMilestone(game.id, m, !done(m));

    final badges = game.milestones.where((m) => m.contains('Badge')).toList();
    final others = game.milestones.where((m) => !m.contains('Badge')).toList();
    final badgesDone = badges.where(done).length;
    final allDone = game.milestones.where(done).length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (badges.isNotEmpty) ...[
          Text('$badgesDone / ${badges.length} badges',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          _progressBar(badgesDone / badges.length),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 16,
            children: [
              for (final m in badges)
                _BadgeDisc(
                    name: m,
                    earned: done(m),
                    tint: tint,
                    onTap: () => toggle(m)),
            ],
          ),
          if (others.isNotEmpty) const Divider(height: 34),
        ] else ...[
          Text('$allDone / ${game.milestones.length} completed',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          _progressBar(game.milestones.isEmpty
              ? 0
              : allDone / game.milestones.length),
          const SizedBox(height: 8),
        ],
        for (final m in others)
          _MilestoneRow(label: m, done: done(m), tint: tint, onTap: () => toggle(m)),
      ],
    );
  }

  Widget _progressBar(double v) => ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
          value: v.clamp(0.0, 1.0),
          minHeight: 8,
          color: tint,
          backgroundColor: tint.withValues(alpha: 0.15),
        ),
      );
}

class _BadgeDisc extends StatelessWidget {
  final String name;
  final bool earned;
  final Color tint;
  final VoidCallback onTap;
  const _BadgeDisc({
    required this.name,
    required this.earned,
    required this.tint,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 66,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Column(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: earned ? tint : scheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.workspace_premium,
                  size: 26,
                  color: earned ? Colors.white : scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Text(
              name.replaceAll(' Badge', ''),
              textAlign: TextAlign.center,
              maxLines: 2,
              style: TextStyle(
                  fontSize: 11,
                  color: earned ? scheme.onSurface : scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _MilestoneRow extends StatelessWidget {
  final String label;
  final bool done;
  final Color tint;
  final VoidCallback onTap;
  const _MilestoneRow({
    required this.label,
    required this.done,
    required this.tint,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: done ? tint : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: done ? null : Border.all(color: scheme.outline),
              ),
              child: done
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(label)),
          ],
        ),
      ),
    );
  }
}

// --------------------------------------------------------------- Pokedex
/// Per-game Pokedex: only this game's species, with obtainability tags and a
/// caught checkbox that feeds completion.
class _DexTab extends StatefulWidget {
  final Game game;
  final Color tint;
  const _DexTab({required this.game, required this.tint});

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
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: total == 0 ? 0 : caught / total,
                  minHeight: 8,
                  color: widget.tint,
                  backgroundColor: widget.tint.withValues(alpha: 0.15),
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
                      selectedColor: widget.tint,
                      showCheckmark: false,
                      labelStyle: TextStyle(
                        color: _filter == f
                            ? Colors.white
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
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
                tileColor:
                    isCaught ? widget.tint.withValues(alpha: 0.07) : null,
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
                  activeColor: widget.tint,
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
class _TeamTab extends StatefulWidget {
  final Game game;
  final Color tint;
  const _TeamTab({required this.game, required this.tint});

  @override
  State<_TeamTab> createState() => _TeamTabState();
}

class _TeamTabState extends State<_TeamTab> {
  final Map<String, int> _nameToId = {};

  @override
  void initState() {
    super.initState();
    _loadIndex();
  }

  Future<void> _loadIndex() async {
    try {
      final index = await PokedexService().loadIndex();
      if (!mounted) return;
      setState(() {
        for (final s in index) {
          _nameToId[s.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')] =
              s.id;
        }
      });
    } catch (_) {}
  }

  int? _dexIdFor(String species) {
    final s = species.trim();
    if (s.isEmpty) return null;
    if (s.startsWith('#')) return int.tryParse(s.substring(1));
    return _nameToId[s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')];
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final team = state.progressFor(widget.game.id).team;

    return Scaffold(
      body: team.isEmpty
          ? const Center(child: Text('No team members yet. Tap + to add one.'))
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
              itemCount: team.length,
              itemBuilder: (context, i) =>
                  _memberCard(context, state, i, team[i]),
            ),
      floatingActionButton: team.length < 6
          ? FloatingActionButton.extended(
              backgroundColor: widget.tint,
              foregroundColor: Colors.white,
              onPressed: () async {
                final s = context.read<AppState>();
                s.addTeamMember(widget.game.id);
                final list = s.progressFor(widget.game.id).team;
                await _editMember(context, s, list.length - 1, list.last);
              },
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            )
          : null,
    );
  }

  Widget _memberCard(
      BuildContext context, AppState state, int i, TeamMember member) {
    final id = _dexIdFor(member.species);
    final scheme = Theme.of(context).colorScheme;
    final title = member.species.trim().isEmpty
        ? 'Tap to choose'
        : prettifyName(member.species);
    final sub = member.nickname.trim().isEmpty ? null : '"${member.nickname}"';
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: InkWell(
        onTap: () => _editMember(context, state, i, member),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                clipBehavior: Clip.antiAlias,
                child: id == null
                    ? Icon(Icons.catching_pokemon,
                        color: scheme.onSurfaceVariant)
                    : CachedNetworkImage(
                        imageUrl:
                            'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/$id.png',
                        errorWidget: (_, _, _) => Icon(Icons.catching_pokemon,
                            color: scheme.onSurfaceVariant),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    if (sub != null)
                      Text(sub,
                          style: TextStyle(
                              fontSize: 12, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('Lv ${member.level}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editMember(
      BuildContext context, AppState state, int index, TeamMember member) async {
    final species = TextEditingController(text: member.species);
    final nickname = TextEditingController(text: member.nickname);
    final level = TextEditingController(text: member.level.toString());
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            16, 4, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Edit Pokémon',
                style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: species,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                  labelText: 'Species', border: OutlineInputBorder()),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nickname,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                  labelText: 'Nickname (optional)',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: level,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Level', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () {
                    state.removeTeamMember(widget.game.id, index);
                    Navigator.pop(ctx);
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Remove'),
                ),
                const Spacer(),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: widget.tint),
                  onPressed: () {
                    member.species = species.text.trim();
                    member.nickname = nickname.text.trim();
                    member.level = int.tryParse(level.text) ?? member.level;
                    state.updateTeamMember(widget.game.id, index, member);
                    Navigator.pop(ctx);
                  },
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (mounted) setState(() {});
  }
}

// --------------------------------------------------------------- Shiny
/// Common shiny-hunting methods and their approximate base odds denominator.
const List<({String name, int rate})> _shinyMethods = [
  (name: 'Random encounter', rate: 4096),
  (name: 'Full Odds', rate: 4096),
  (name: 'Masuda Method', rate: 683),
  (name: 'Masuda + Shiny Charm', rate: 512),
  (name: 'SOS chain', rate: 683),
  (name: 'Soft reset', rate: 4096),
  (name: 'Shiny Charm', rate: 1365),
  (name: 'Gen 2 (1/8192)', rate: 8192),
];

int _shinyRate(String method) {
  final m = method.toLowerCase();
  if (m.contains('masuda') && m.contains('charm')) return 512;
  if (m.contains('masuda')) return 683;
  if (m.contains('sos') || m.contains('chain') || m.contains('combo')) {
    return 683;
  }
  if (m.contains('charm')) return 1365;
  if (m.contains('8192') || m.contains('gen 2')) return 8192;
  return 4096;
}

class _ShinyTab extends StatefulWidget {
  final Game game;
  final Color tint;
  const _ShinyTab({required this.game, required this.tint});

  @override
  State<_ShinyTab> createState() => _ShinyTabState();
}

class _ShinyTabState extends State<_ShinyTab> {
  final Map<String, int> _nameToId = {};

  @override
  void initState() {
    super.initState();
    _loadIndex();
  }

  Future<void> _loadIndex() async {
    try {
      final index = await PokedexService().loadIndex();
      if (!mounted) return;
      setState(() {
        for (final s in index) {
          _nameToId[s.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')] =
              s.id;
        }
      });
    } catch (_) {}
  }

  int? _dexIdFor(String species) {
    final s = species.trim();
    if (s.isEmpty) return null;
    if (s.startsWith('#')) return int.tryParse(s.substring(1));
    return _nameToId[s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')];
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final hunts = state.progressFor(widget.game.id).shinyHunts;

    return Scaffold(
      body: hunts.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No shiny hunts yet. Tap + to start one.',
                    textAlign: TextAlign.center),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
              itemCount: hunts.length,
              itemBuilder: (context, i) => _huntCard(context, state, i, hunts[i]),
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: widget.tint,
        foregroundColor: Colors.white,
        onPressed: () async {
          final s = context.read<AppState>();
          s.addShinyHunt(widget.game.id);
          final list = s.progressFor(widget.game.id).shinyHunts;
          await _editHunt(context, s, list.length - 1, list.last);
        },
        icon: const Icon(Icons.auto_awesome),
        label: const Text('New hunt'),
      ),
    );
  }

  Widget _huntCard(
      BuildContext context, AppState state, int i, ShinyHunt hunt) {
    final scheme = Theme.of(context).colorScheme;
    final tint = widget.tint;
    final id = _dexIdFor(hunt.species);
    final rate = _shinyRate(hunt.method);
    final chance = 1 - math.pow(1 - 1 / rate, hunt.count).toDouble();
    final chanceText = hunt.count == 0
        ? '1/$rate base odds'
        : '≈ ${(chance * 100).toStringAsFixed(chance < 0.1 ? 1 : 0)}% by now · 1/$rate';
    final title = hunt.species.trim().isEmpty
        ? 'Tap to set species'
        : prettifyName(hunt.species);

    void update() => state.updateShinyHunt(widget.game.id, i, hunt);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: hunt.caught
            ? BorderSide(color: tint, width: 2)
            : BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: () => _editHunt(context, state, i, hunt),
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      shape: BoxShape.circle,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: id == null
                        ? Icon(Icons.auto_awesome, color: tint)
                        : CachedNetworkImage(
                            imageUrl:
                                'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/shiny/$id.png',
                            errorWidget: (_, _, _) =>
                                Icon(Icons.auto_awesome, color: tint),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _editHunt(context, state, i, hunt),
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600)),
                            ),
                            if (hunt.caught) ...[
                              const SizedBox(width: 6),
                              Icon(Icons.check_circle, size: 18, color: tint),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(hunt.method,
                            style: TextStyle(
                                fontSize: 12, color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => state.removeShinyHunt(widget.game.id, i),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Encounters',
                        style: TextStyle(
                            fontSize: 11, color: scheme.onSurfaceVariant)),
                    Text('${hunt.count}',
                        style: const TextStyle(
                            fontSize: 28, fontWeight: FontWeight.w700)),
                  ],
                ),
                const Spacer(),
                _RoundBtn(
                  icon: Icons.remove,
                  color: tint,
                  filled: false,
                  onTap: hunt.count > 0
                      ? () {
                          hunt.count--;
                          update();
                        }
                      : null,
                ),
                const SizedBox(width: 10),
                _RoundBtn(
                  icon: Icons.add,
                  color: tint,
                  filled: true,
                  onTap: () {
                    hunt.count++;
                    update();
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.percent, size: 14, color: scheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(chanceText,
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant)),
                const Spacer(),
                FilterChip(
                  label: const Text('Caught!'),
                  avatar: Icon(Icons.auto_awesome,
                      size: 16,
                      color: hunt.caught ? Colors.white : tint),
                  selected: hunt.caught,
                  showCheckmark: false,
                  selectedColor: tint,
                  labelStyle: TextStyle(
                    color: hunt.caught ? Colors.white : scheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                  onSelected: (v) {
                    hunt.caught = v;
                    update();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editHunt(
      BuildContext context, AppState state, int index, ShinyHunt hunt) async {
    final species = TextEditingController(text: hunt.species);
    final method = TextEditingController(text: hunt.method);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
              16, 4, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Shiny hunt', style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 12),
              TextField(
                controller: species,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                    labelText: 'Species', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: method,
                decoration: const InputDecoration(
                    labelText: 'Method', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final m in _shinyMethods)
                    ActionChip(
                      label: Text(m.name),
                      onPressed: () => setSheet(() => method.text = m.name),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () {
                      state.removeShinyHunt(widget.game.id, index);
                      Navigator.pop(ctx);
                    },
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Remove'),
                  ),
                  const Spacer(),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: widget.tint),
                    onPressed: () {
                      hunt.species = species.text.trim();
                      hunt.method = method.text.trim().isEmpty
                          ? 'Random encounter'
                          : method.text.trim();
                      state.updateShinyHunt(widget.game.id, index, hunt);
                      Navigator.pop(ctx);
                    },
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }
}

class _RoundBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool filled;
  final VoidCallback? onTap;
  const _RoundBtn({
    required this.icon,
    required this.color,
    required this.filled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    final bg = filled
        ? (enabled ? color : scheme.surfaceContainerHighest)
        : scheme.surfaceContainerHighest;
    final fg = filled
        ? Colors.white
        : (enabled ? color : scheme.onSurfaceVariant.withValues(alpha: 0.4));
    return Material(
      color: bg,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: fg),
        ),
      ),
    );
  }
}

// -------------------------------------------------- Save-file auto-tracker

Future<void> _startSaveSync(BuildContext context, Game game) async {
  final state = context.read<AppState>();
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(const SnackBar(content: Text('Reading save file…')));
  SaveData? data;
  try {
    data = await state.scanSave(game);
  } on SaveParseException catch (e) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return;
  } catch (e) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text('Could not read save: $e')));
    return;
  }
  messenger.hideCurrentSnackBar();
  if (!context.mounted) return;

  if (data == null) {
    final locate = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('No save file found'),
        content: Text(
            'I looked next to ${game.title}\'s ROM but found no save (.sav). '
            'Play the game once so the emulator writes a save, or point me to '
            'the save file.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Close')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Locate save…')),
        ],
      ),
    );
    if (locate == true && context.mounted) await _locateSave(context, game);
    return;
  }

  await showDialog(
    context: context,
    builder: (_) => _SaveSyncDialog(game: game, data: data!),
  );
}

Future<void> _locateSave(BuildContext context, Game game) async {
  final controller = TextEditingController();
  final path = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Locate save file'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: r'C:\...\game.sav',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Use file')),
      ],
    ),
  );
  if (path == null || path.isEmpty || !context.mounted) return;
  await context.read<AppState>().setSavePath(game.id, path);
  if (context.mounted) await _startSaveSync(context, game);
}

class _SaveSyncDialog extends StatefulWidget {
  final Game game;
  final SaveData data;
  const _SaveSyncDialog({required this.game, required this.data});

  @override
  State<_SaveSyncDialog> createState() => _SaveSyncDialogState();
}

class _SaveSyncDialogState extends State<_SaveSyncDialog> {
  late bool _dex = widget.data.caughtCount > 0;
  late bool _badges = widget.data.badgeCount != null;
  late bool _team = widget.data.team.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final muted = Theme.of(context).textTheme.bodySmall;
    return AlertDialog(
      title: const Text('Sync from save'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (d.trainerName != null && d.trainerName!.isNotEmpty)
              Text(
                  'Trainer: ${d.trainerName}'
                  '${d.trainerId != null ? '  (ID ${d.trainerId})' : ''}',
                  style: muted),
            if (d.playTime != null)
              Text('Play time: ${d.playTimeText}', style: muted),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _dex,
              onChanged: d.caughtCount == 0
                  ? null
                  : (v) => setState(() => _dex = v ?? false),
              title: Text('Caught Pokedex — ${d.caughtCount} species'),
              subtitle: d.seenCount > 0
                  ? Text('${d.seenCount} seen', style: muted)
                  : null,
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _badges,
              onChanged: d.badgeCount == null
                  ? null
                  : (v) => setState(() => _badges = v ?? false),
              title: Text(d.badgeCount == null
                  ? 'Badges — not available for this save'
                  : 'Badges — ${d.badgeCount}'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _team,
              onChanged: d.team.isEmpty
                  ? null
                  : (v) => setState(() => _team = v ?? false),
              title: Text(d.team.isEmpty
                  ? 'Team — not available for this save'
                  : 'Team — ${d.team.length} Pokemon'),
              subtitle: d.team.isEmpty
                  ? null
                  : Text(
                      d.team
                          .map((m) =>
                              '${m.name ?? (m.dexId != null ? '#${m.dexId}' : '?')} Lv${m.level}')
                          .join(', '),
                      style: muted),
            ),
            for (final note in d.notes)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('• $note', style: muted),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: (_dex || _badges || _team)
              ? () async {
                  await context.read<AppState>().applySaveData(
                        widget.game,
                        d,
                        dex: _dex,
                        badges: _badges,
                        team: _team,
                      );
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Progress synced from save.')),
                  );
                }
              : null,
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

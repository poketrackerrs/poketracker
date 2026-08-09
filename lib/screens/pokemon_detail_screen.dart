import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../data/pokeapi_maps.dart';
import '../models/pokedex_models.dart';
import '../services/pokedex_service.dart';

/// Type -> color for the type chips.
const Map<String, Color> _typeColors = {
  'normal': Color(0xFFA8A77A), 'fire': Color(0xFFEE8130),
  'water': Color(0xFF6390F0), 'electric': Color(0xFFF7D02C),
  'grass': Color(0xFF7AC74C), 'ice': Color(0xFF96D9D6),
  'fighting': Color(0xFFC22E28), 'poison': Color(0xFFA33EA1),
  'ground': Color(0xFFE2BF65), 'flying': Color(0xFFA98FF3),
  'psychic': Color(0xFFF95587), 'bug': Color(0xFFA6B91A),
  'rock': Color(0xFFB6A136), 'ghost': Color(0xFF735797),
  'dragon': Color(0xFF6F35FC), 'dark': Color(0xFF705746),
  'steel': Color(0xFFB7B7CE), 'fairy': Color(0xFFD685AD),
};

class PokemonDetailScreen extends StatefulWidget {
  final int id;
  final String name;

  /// When opened from a specific game, scopes movepool/typing/dex to that
  /// game's generation. Null when opened from the global Pokedex.
  final int? generation;

  const PokemonDetailScreen({
    super.key,
    required this.id,
    required this.name,
    this.generation,
  });

  @override
  State<PokemonDetailScreen> createState() => _PokemonDetailScreenState();
}

class _PokemonDetailScreenState extends State<PokemonDetailScreen> {
  final _service = PokedexService();
  PokemonDetail? _detail;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await _service.fetchDetail(widget.id);
      if (!mounted) return;
      setState(() {
        _detail = d;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load this Pokemon.\nCheck your connection and retry.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${prettifyName(widget.name)}  #${widget.id}'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, textAlign: TextAlign.center))
              : _buildContent(_detail!),
    );
  }

  Widget _buildContent(PokemonDetail d) {
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          _Header(detail: d, generation: widget.generation),
          const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Stats'),
              Tab(text: 'Info'),
              Tab(text: 'Moves'),
              Tab(text: 'Dex'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _StatsTab(detail: d),
                _InfoTab(detail: d, generation: widget.generation),
                _MovesTab(detail: d, generation: widget.generation),
                _DexTab(detail: d, generation: widget.generation),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final PokemonDetail detail;
  final int? generation;
  const _Header({required this.detail, this.generation});

  @override
  Widget build(BuildContext context) {
    final types = detail.typesForGeneration(generation);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            height: 120,
            child: CachedNetworkImage(
              imageUrl: detail.artworkUrl,
              fit: BoxFit.contain,
              errorWidget: (_, _, _) =>
                  const Icon(Icons.catching_pokemon, size: 64, color: Colors.grey),
              placeholder: (_, _) =>
                  const Center(child: CircularProgressIndicator()),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(prettifyName(detail.name),
                    style: Theme.of(context).textTheme.headlineSmall),
                if (generation != null)
                  Text('Gen $generation view',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final t in types)
                      Chip(
                        label: Text(
                          prettifyName(t),
                          style: const TextStyle(color: Colors.white),
                        ),
                        backgroundColor:
                            _typeColors[t] ?? Colors.grey,
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Base stat total: ${detail.statTotal}'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsTab extends StatelessWidget {
  final PokemonDetail detail;
  const _StatsTab({required this.detail});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: SizedBox(
            width: 260,
            height: 260,
            child: CustomPaint(
              painter: _StatHexPainter(
                stats: [
                  for (final k in kStatLabels.keys) detail.stats[k] ?? 0,
                ],
                labels: kStatLabels.values.toList(),
                color: color,
                gridColor: Theme.of(context).dividerColor,
                textColor:
                    Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        for (final entry in kStatLabels.entries)
          _StatBar(
            label: entry.value,
            value: detail.stats[entry.key] ?? 0,
          ),
      ],
    );
  }
}

/// Hexagonal radar chart of the six base stats.
class _StatHexPainter extends CustomPainter {
  final List<int> stats;
  final List<String> labels;
  final Color color;
  final Color gridColor;
  final Color textColor;
  static const double _maxStat = 200; // scale reference

  _StatHexPainter({
    required this.stats,
    required this.labels,
    required this.color,
    required this.gridColor,
    required this.textColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 34; // leave room for labels
    const n = 6;
    // Start at top (-90 deg) and go clockwise.
    Offset pointAt(double frac, int i) {
      final angle = -math.pi / 2 + (2 * math.pi * i / n);
      return Offset(
        center.dx + radius * frac * math.cos(angle),
        center.dy + radius * frac * math.sin(angle),
      );
    }

    // Grid rings
    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = gridColor
      ..strokeWidth = 1;
    for (final ring in [0.25, 0.5, 0.75, 1.0]) {
      final path = Path();
      for (var i = 0; i < n; i++) {
        final p = pointAt(ring, i);
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      path.close();
      canvas.drawPath(path, gridPaint);
    }
    // Spokes
    for (var i = 0; i < n; i++) {
      canvas.drawLine(center, pointAt(1.0, i), gridPaint);
    }

    // Data polygon
    final dataPath = Path();
    for (var i = 0; i < n; i++) {
      final frac = (stats[i] / _maxStat).clamp(0.05, 1.0);
      final p = pointAt(frac.toDouble(), i);
      i == 0 ? dataPath.moveTo(p.dx, p.dy) : dataPath.lineTo(p.dx, p.dy);
    }
    dataPath.close();
    canvas.drawPath(dataPath, Paint()..color = color.withValues(alpha: 0.25));
    canvas.drawPath(
      dataPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = color
        ..strokeWidth = 2,
    );

    // Labels + values
    for (var i = 0; i < n; i++) {
      final p = pointAt(1.22, i);
      final tp = TextPainter(
        text: TextSpan(
          children: [
            TextSpan(
                text: '${labels[i]}\n',
                style: TextStyle(color: textColor, fontSize: 10)),
            TextSpan(
                text: '${stats[i]}',
                style: TextStyle(
                    color: textColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          ],
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _StatHexPainter old) => old.stats != stats;
}

class _StatBar extends StatelessWidget {
  final String label;
  final int value;
  const _StatBar({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    // Base stats cap around 255; scale bar against a friendly 200 max.
    final frac = (value / 200).clamp(0.0, 1.0);
    final color = Color.lerp(Colors.red, Colors.green, frac)!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(width: 72, child: Text(label)),
          SizedBox(
            width: 40,
            child: Text('$value',
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: frac,
                minHeight: 12,
                color: color,
                backgroundColor: color.withValues(alpha: 0.15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoTab extends StatelessWidget {
  final PokemonDetail detail;
  final int? generation;
  const _InfoTab({required this.detail, this.generation});

  String _mult(double m) {
    if (m == 0) return '0x';
    if (m == 0.25) return '¼x';
    if (m == 0.5) return '½x';
    if (m == 2) return '2x';
    if (m == 4) return '4x';
    return '${m}x';
  }

  @override
  Widget build(BuildContext context) {
    final weak = detail.matchups.entries.where((e) => e.value > 1).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final resist = detail.matchups.entries
        .where((e) => e.value < 1 && e.value > 0)
        .toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final immune = detail.matchups.entries.where((e) => e.value == 0).toList();

    Widget chips(List<MapEntry<String, double>> list) => Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in list)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (_typeColors[e.key] ?? Colors.grey),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('${prettifyName(e.key)}  ${_mult(e.value)}',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
              ),
          ],
        );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Abilities', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final a in detail.abilities)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(prettifyName(a.name),
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      if (a.isHidden) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.purple.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('Hidden',
                              style: TextStyle(
                                  fontSize: 10, color: Colors.purple)),
                        ),
                      ],
                    ],
                  ),
                  if (a.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(a.description,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ],
              ),
            ),
          ),
        const SizedBox(height: 24),
        Text('Type matchups', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (weak.isNotEmpty) ...[
          const Text('Weak to'),
          const SizedBox(height: 6),
          chips(weak),
          const SizedBox(height: 12),
        ],
        if (resist.isNotEmpty) ...[
          const Text('Resists'),
          const SizedBox(height: 6),
          chips(resist),
          const SizedBox(height: 12),
        ],
        if (immune.isNotEmpty) ...[
          const Text('Immune to'),
          const SizedBox(height: 6),
          chips(immune),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 12),
        Text('Evolution', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (detail.evolution.length < 2)
          const Text('This Pokemon does not evolve.')
        else
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (var i = 0; i < detail.evolution.length; i++) ...[
                if (i > 0)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(Icons.arrow_forward, size: 18),
                  ),
                Column(
                  children: [
                    SizedBox(
                      width: 64,
                      height: 64,
                      child: CachedNetworkImage(
                        imageUrl: detail.evolution[i].spriteUrl,
                        errorWidget: (_, _, _) =>
                            const Icon(Icons.catching_pokemon),
                      ),
                    ),
                    Text(prettifyName(detail.evolution[i].name),
                        style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ],
            ],
          ),
      ],
    );
  }
}

class _MovesTab extends StatefulWidget {
  final PokemonDetail detail;
  final int? generation;
  const _MovesTab({required this.detail, this.generation});

  @override
  State<_MovesTab> createState() => _MovesTabState();
}

class _MovesTabState extends State<_MovesTab> {
  int? _gen;

  @override
  void initState() {
    super.initState();
    final gens = widget.detail.moveGenerations;
    // Default to the game's generation when scoped, else the newest.
    if (widget.generation != null && gens.contains(widget.generation)) {
      _gen = widget.generation;
    } else {
      _gen = gens.isNotEmpty ? gens.last : null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final gens = widget.detail.moveGenerations;
    if (gens.isEmpty) {
      return const Center(child: Text('No movepool data available.'));
    }

    // Dedup within the selected generation by (name, method), keeping min level.
    final map = <String, MoveEntry>{};
    for (final m in widget.detail.moves.where((m) => m.generation == _gen)) {
      final key = '${m.name}|${m.method}';
      final existing = map[key];
      if (existing == null || m.level < existing.level) map[key] = m;
    }
    final moves = map.values.toList()
      ..sort((a, b) {
        // Level-up first (by level), then other methods alphabetically.
        if (a.method == 'level-up' && b.method == 'level-up') {
          return a.level.compareTo(b.level);
        }
        if (a.method == 'level-up') return -1;
        if (b.method == 'level-up') return 1;
        return a.method.compareTo(b.method);
      });

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Text('Generation: '),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: _gen,
                items: [
                  for (final g in gens)
                    DropdownMenuItem(value: g, child: Text('Gen $g')),
                ],
                onChanged: (v) => setState(() => _gen = v),
              ),
              const Spacer(),
              Text('${moves.length} moves'),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: moves.length,
            itemBuilder: (context, i) {
              final m = moves[i];
              final method = kLearnMethodLabels[m.method] ?? m.method;
              return ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 14,
                  child: Text(
                    m.method == 'level-up' ? '${m.level}' : method[0],
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
                title: Text(prettifyName(m.name)),
                trailing: Text(
                  m.method == 'level-up' ? 'Lv ${m.level}' : method,
                  style: TextStyle(color: Theme.of(context).colorScheme.primary),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DexTab extends StatelessWidget {
  final PokemonDetail detail;
  final int? generation;
  const _DexTab({required this.detail, this.generation});

  @override
  Widget build(BuildContext context) {
    final gens = detail.dexEntriesByGen.keys.toList()..sort();
    if (gens.isEmpty) {
      return const Center(child: Text('No Pokedex entries available.'));
    }
    // Expand the scoped generation when opened from a game, else the newest.
    final expandGen =
        (generation != null && gens.contains(generation)) ? generation : gens.last;
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        for (final g in gens)
          Card(
            child: ExpansionTile(
              initiallyExpanded: g == expandGen,
              title: Text('Generation $g',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              children: [
                for (final entry in detail.dexEntriesByGen[g]!)
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: Text(entry),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

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

  /// When set, auto-selects this form (variety) id after the species loads.
  final int? initialFormId;

  const PokemonDetailScreen({
    super.key,
    required this.id,
    required this.name,
    this.generation,
    this.initialFormId,
  });

  @override
  State<PokemonDetailScreen> createState() => _PokemonDetailScreenState();
}

class _PokemonDetailScreenState extends State<PokemonDetailScreen> {
  final _service = PokedexService();
  PokemonDetail? _detail;
  bool _loading = true;
  String? _error;

  // Form switcher state.
  PokemonForm? _selectedForm; // null = base/default
  FormOverride? _override;
  bool _formLoading = false;

  /// The detail with the selected form's overrides applied (base if none).
  PokemonDetail get _active =>
      _override == null ? _detail! : _detail!.copyWithForm(_override!);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _selectForm(PokemonForm form) async {
    if (form.isDefault) {
      setState(() {
        _selectedForm = form;
        _override = null;
      });
      return;
    }
    setState(() {
      _selectedForm = form;
      _formLoading = true;
    });
    try {
      final o = await _service.fetchForm(form.id);
      if (!mounted) return;
      setState(() {
        _override = o;
        _formLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _formLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load the ${form.label} form.')),
      );
    }
  }

  Future<void> _load() async {
    try {
      final d = await _service.fetchDetail(widget.id);
      if (!mounted) return;
      setState(() {
        _detail = d;
        _loading = false;
      });
      if (widget.initialFormId != null) {
        final match = d.forms.where((f) => f.id == widget.initialFormId);
        if (match.isNotEmpty && !match.first.isDefault) {
          _selectForm(match.first);
        }
      }
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
    final d = _detail;
    // Tint the app bar with the active form's primary type once loaded.
    final Color? banner = d == null
        ? null
        : _typeColors[_active.typesForGeneration(widget.generation).first];
    return Scaffold(
      appBar: AppBar(
        backgroundColor: banner,
        foregroundColor: banner == null ? null : Colors.white,
        title: Text('${prettifyName(widget.name)}  #${widget.id}'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, textAlign: TextAlign.center))
              : _buildContent(_active),
    );
  }

  Widget _buildContent(PokemonDetail d) {
    final defaultId =
        d.forms.isEmpty ? d.id : d.forms.firstWhere((f) => f.isDefault, orElse: () => d.forms.first).id;
    final currentFormId = _selectedForm?.id ?? defaultId;
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _HeaderBanner(detail: d, generation: widget.generation),
        if (d.forms.length > 1)
          _FormSwitcher(
            forms: d.forms,
            currentId: currentFormId,
            loading: _formLoading,
            color: _typeColors[d.typesForGeneration(widget.generation).first] ??
                Colors.grey,
            onSelect: _selectForm,
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _InfoboxCard(detail: d),
              _sectionTitle(context, 'Base stats'),
              _StatsSection(detail: d),
              _sectionTitle(context, 'Type defenses'),
              _TypeDefenses(detail: d),
              _sectionTitle(context, 'Evolution'),
              _EvolutionLine(detail: d, generation: widget.generation),
              _sectionTitle(context, 'Pokedex entries'),
              _DexEntries(detail: d, generation: widget.generation),
              _sectionTitle(context, 'Moves'),
              _MovesSection(detail: d, generation: widget.generation),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Text(
          text,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
      );
}

/// Horizontal chips to switch between a species' forms (regional, mega, etc.).
class _FormSwitcher extends StatelessWidget {
  final List<PokemonForm> forms;
  final int currentId;
  final bool loading;
  final Color color;
  final void Function(PokemonForm) onSelect;
  const _FormSwitcher({
    required this.forms,
    required this.currentId,
    required this.loading,
    required this.color,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final f in forms)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(f.label),
                  selected: f.id == currentId,
                  showCheckmark: false,
                  selectedColor: color,
                  labelStyle: TextStyle(
                    color: f.id == currentId
                        ? Colors.white
                        : scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  onSelected: loading ? null : (_) => onSelect(f),
                ),
              ),
            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              ),
          ],
        ),
      ),
    );
  }
}

/// Type-colored header: artwork, national number, name, genus, type badges.
class _HeaderBanner extends StatelessWidget {
  final PokemonDetail detail;
  final int? generation;
  const _HeaderBanner({required this.detail, this.generation});

  @override
  Widget build(BuildContext context) {
    final types = detail.typesForGeneration(generation);
    final banner = _typeColors[types.first] ?? Colors.grey;
    return Container(
      width: double.infinity,
      color: banner,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 104,
            height: 104,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              shape: BoxShape.circle,
            ),
            padding: const EdgeInsets.all(6),
            child: CachedNetworkImage(
              imageUrl: detail.artworkUrl,
              fit: BoxFit.contain,
              errorWidget: (_, _, _) => const Icon(Icons.catching_pokemon,
                  size: 56, color: Colors.white70),
              placeholder: (_, _) => const Center(
                  child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white70))),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('No. ${detail.id.toString().padLeft(4, '0')}',
                    style: const TextStyle(color: Colors.white70, fontSize: 13)),
                Text(prettifyName(detail.name),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold)),
                if (detail.genus.isNotEmpty)
                  Text(detail.genus,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 13)),
                if (generation != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('Gen $generation view',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final t in types)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: _typeColors[t] ?? Colors.grey,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.7)),
                        ),
                        child: Text(prettifyName(t),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Bulbapedia-style at-a-glance box.
class _InfoboxCard extends StatelessWidget {
  final PokemonDetail detail;
  const _InfoboxCard({required this.detail});

  @override
  Widget build(BuildContext context) {
    final abilities = [
      for (final a in detail.abilities)
        a.isHidden ? '${prettifyName(a.name)} (hidden)' : prettifyName(a.name),
    ].join(' · ');

    String fmt1(double v) => v.toStringAsFixed(1);

    final rows = <List<String>>[
      ['Height', detail.height > 0 ? '${fmt1(detail.height)} m' : '—'],
      ['Weight', detail.weight > 0 ? '${fmt1(detail.weight)} kg' : '—'],
      if (abilities.isNotEmpty) ['Abilities', abilities],
      ['Catch rate', '${detail.captureRate}'],
      ['Gender', detail.genderText],
      if (detail.eggGroups.isNotEmpty)
        ['Egg groups', detail.eggGroups.map(prettifyName).join(' · ')],
      if (detail.growthRate.isNotEmpty)
        ['Growth', prettifyName(detail.growthRate)],
      ['Base friendship', '${detail.baseHappiness}'],
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          children: [
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 108,
                      child: Text(r[0],
                          style: TextStyle(
                              color: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.color)),
                    ),
                    Expanded(
                      child: Text(r[1], textAlign: TextAlign.right),
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

/// Base stats with a Bars/Hexagon toggle and a total row.
class _StatsSection extends StatefulWidget {
  final PokemonDetail detail;
  const _StatsSection({required this.detail});

  @override
  State<_StatsSection> createState() => _StatsSectionState();
}

class _StatsSectionState extends State<_StatsSection> {
  bool _hex = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.detail;
    final color = Theme.of(context).colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                segments: const [
                  ButtonSegment(
                      value: false,
                      label: Text('Bars'),
                      icon: Icon(Icons.bar_chart, size: 18)),
                  ButtonSegment(
                      value: true,
                      label: Text('Hexagon'),
                      icon: Icon(Icons.hexagon_outlined, size: 18)),
                ],
                selected: {_hex},
                onSelectionChanged: (s) => setState(() => _hex = s.first),
              ),
            ),
            const SizedBox(height: 12),
            if (_hex)
              Center(
                child: SizedBox(
                  width: 260,
                  height: 260,
                  child: CustomPaint(
                    painter: _StatHexPainter(
                      stats: [
                        for (final k in kStatLabels.keys) d.stats[k] ?? 0,
                      ],
                      labels: kStatLabels.values.toList(),
                      color: color,
                      gridColor: Theme.of(context).dividerColor,
                      textColor: Theme.of(context).textTheme.bodySmall?.color ??
                          Colors.grey,
                    ),
                  ),
                ),
              )
            else
              for (final entry in kStatLabels.entries)
                _StatBar(label: entry.value, value: d.stats[entry.key] ?? 0),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Text('${d.statTotal}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Defensive type multipliers grouped weak / resist / immune.
class _TypeDefenses extends StatelessWidget {
  final PokemonDetail detail;
  const _TypeDefenses({required this.detail});

  String _mult(double m) {
    if (m == 0) return '×0';
    if (m == 0.25) return '×¼';
    if (m == 0.5) return '×½';
    if (m == 2) return '×2';
    if (m == 4) return '×4';
    final s = m.toStringAsFixed(m == m.roundToDouble() ? 0 : 2);
    return '×$s';
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final weak = detail.matchups.entries.where((e) => e.value > 1).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final resist = detail.matchups.entries
        .where((e) => e.value < 1 && e.value > 0)
        .toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final immune = detail.matchups.entries.where((e) => e.value == 0).toList();

    Widget chip(String label, Color bg, Color fg) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
              color: bg, borderRadius: BorderRadius.circular(999)),
          child: Text(label,
              style: TextStyle(
                  color: fg, fontSize: 12.5, fontWeight: FontWeight.w600)),
        );

    Widget group(String title, List<MapEntry<String, double>> list, Color base) {
      if (list.isEmpty) return const SizedBox.shrink();
      final bg = base.withValues(alpha: dark ? 0.22 : 0.14);
      final fg = dark ? base : Color.lerp(base, Colors.black, 0.35)!;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 6),
            child: Text(title,
                style: Theme.of(context).textTheme.bodySmall),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in list)
                chip('${prettifyName(e.key)} ${_mult(e.value)}', bg, fg),
            ],
          ),
          const SizedBox(height: 10),
        ],
      );
    }

    if (weak.isEmpty && resist.isEmpty && immune.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(14),
          child: Text('No type data available.'),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            group('Weak to', weak, Colors.red),
            group('Resists', resist, Colors.green),
            group('Immune to', immune, Colors.blueGrey),
          ],
        ),
      ),
    );
  }
}

/// Evolution chain with conditions; each stage is tappable.
class _EvolutionLine extends StatelessWidget {
  final PokemonDetail detail;
  final int? generation;
  const _EvolutionLine({required this.detail, this.generation});

  @override
  Widget build(BuildContext context) {
    if (detail.evolution.length < 2) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(14),
          child: Text('This Pokemon does not evolve.'),
        ),
      );
    }
    final muted = Theme.of(context).textTheme.bodySmall?.color;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < detail.evolution.length; i++) ...[
                if (i > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.chevron_right, color: muted),
                        if (detail.evolution[i].condition.isNotEmpty)
                          SizedBox(
                            width: 74,
                            child: Text(detail.evolution[i].condition,
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 11, color: muted)),
                          ),
                      ],
                    ),
                  ),
                _EvoNode(stage: detail.evolution[i], generation: generation),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EvoNode extends StatelessWidget {
  final EvoStage stage;
  final int? generation;
  const _EvoNode({required this.stage, this.generation});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PokemonDetailScreen(
            id: stage.id,
            name: stage.name,
            generation: generation,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 64,
              height: 64,
              child: CachedNetworkImage(
                imageUrl: stage.spriteUrl,
                errorWidget: (_, _, _) => const Icon(Icons.catching_pokemon),
              ),
            ),
            SizedBox(
              width: 72,
              child: Text(prettifyName(stage.name),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pokedex entries grouped by generation (scoped one expanded first).
class _DexEntries extends StatelessWidget {
  final PokemonDetail detail;
  final int? generation;
  const _DexEntries({required this.detail, this.generation});

  @override
  Widget build(BuildContext context) {
    final gens = detail.dexEntriesByGen.keys.toList()..sort();
    if (gens.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(14),
          child: Text('No Pokedex entries available.'),
        ),
      );
    }
    final expandGen = (generation != null && gens.contains(generation))
        ? generation
        : gens.last;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final g in gens)
            ExpansionTile(
              initiallyExpanded: g == expandGen,
              tilePadding: const EdgeInsets.symmetric(horizontal: 14),
              title: Text('Generation $g',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              children: [
                for (final entry in detail.dexEntriesByGen[g]!)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(entry,
                          style: Theme.of(context).textTheme.bodyMedium),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Movepool: filter by learn method and generation (game-scoped by default).
class _MovesSection extends StatefulWidget {
  final PokemonDetail detail;
  final int? generation;
  const _MovesSection({required this.detail, this.generation});

  @override
  State<_MovesSection> createState() => _MovesSectionState();
}

class _MovesSectionState extends State<_MovesSection> {
  int? _gen;
  String _method = 'level-up';

  @override
  void initState() {
    super.initState();
    final gens = widget.detail.moveGenerations;
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
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(14),
          child: Text('No movepool data available.'),
        ),
      );
    }

    final inGen = widget.detail.moves.where((m) => m.generation == _gen).toList();
    final methods = <String>[
      for (final k in kLearnMethodLabels.keys)
        if (inGen.any((m) => m.method == k)) k,
    ];
    if (methods.isNotEmpty && !methods.contains(_method)) _method = methods.first;

    final map = <String, MoveEntry>{};
    for (final m in inGen.where((m) => m.method == _method)) {
      final existing = map[m.name];
      if (existing == null || m.level < existing.level) map[m.name] = m;
    }
    final moves = map.values.toList()
      ..sort((a, b) => a.method == 'level-up'
          ? a.level.compareTo(b.level)
          : prettifyName(a.name).compareTo(prettifyName(b.name)));

    final accent = Theme.of(context).colorScheme.primary;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Generation'),
                const SizedBox(width: 10),
                DropdownButton<int>(
                  value: _gen,
                  isDense: true,
                  items: [
                    for (final g in gens)
                      DropdownMenuItem(value: g, child: Text('Gen $g')),
                  ],
                  onChanged: (v) => setState(() => _gen = v),
                ),
                const Spacer(),
                Text('${moves.length} moves',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                for (final k in methods)
                  ChoiceChip(
                    label: Text(kLearnMethodLabels[k] ?? k),
                    selected: _method == k,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => setState(() => _method = k),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            if (moves.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('No moves for this filter.'),
              )
            else
              for (final m in moves)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 44,
                        child: Text(
                          m.method == 'level-up' ? 'Lv ${m.level}' : '—',
                          style: TextStyle(color: accent, fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(prettifyName(m.name))),
                    ],
                  ),
                ),
          ],
        ),
      ),
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

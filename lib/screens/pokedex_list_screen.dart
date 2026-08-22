import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../data/pokeapi_maps.dart';
import '../models/pokedex_models.dart';
import '../services/pokedex_service.dart';
import '../state/app_state.dart';
import 'pokemon_detail_screen.dart';

/// Inclusive national-dex id range for each generation.
const List<({int gen, int start, int end})> _genRanges = [
  (gen: 1, start: 1, end: 151),
  (gen: 2, start: 152, end: 251),
  (gen: 3, start: 252, end: 386),
  (gen: 4, start: 387, end: 493),
  (gen: 5, start: 494, end: 649),
  (gen: 6, start: 650, end: 721),
  (gen: 7, start: 722, end: 809),
  (gen: 8, start: 810, end: 905),
  (gen: 9, start: 906, end: 1025),
];

/// One grid cell: a base species or one of its alternate forms.
class _GridItem {
  final int id; // /pokemon id (base dex, or 10000+ for a form)
  final int baseDex; // owning species' national dex
  final String baseName;
  final bool isForm;
  final String? formLabel;
  const _GridItem({
    required this.id,
    required this.baseDex,
    required this.baseName,
    required this.isForm,
    this.formLabel,
  });

  String get spriteUrl =>
      'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/$id.png';
}

class PokedexListScreen extends StatefulWidget {
  const PokedexListScreen({super.key});

  @override
  State<PokedexListScreen> createState() => _PokedexListScreenState();
}

class _PokedexListScreenState extends State<PokedexListScreen> {
  final _service = PokedexService();
  List<PokemonSummary> _base = [];
  final Map<int, List<_GridItem>> _formsByDex = {};
  String _query = '';
  int? _gen; // null = all generations
  bool _showForms = true;
  bool _loading = true;
  String? _error;

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
      final base = await _service.loadIndex();
      final baseNameToDex = {for (final s in base) s.name: s.id};
      final varieties = await _service.loadAllVarieties();
      final formsByDex = <int, List<_GridItem>>{};
      for (final v in varieties) {
        if (v.id < 10000) continue; // base species handled by loadIndex
        final baseDex = _baseDexForForm(v.name, baseNameToDex);
        if (baseDex == null) continue;
        final baseName = base[baseDex - 1].name;
        formsByDex.putIfAbsent(baseDex, () => []).add(_GridItem(
              id: v.id,
              baseDex: baseDex,
              baseName: baseName,
              isForm: true,
              formLabel: _service.labelForForm(v.name, baseName),
            ));
      }
      for (final list in formsByDex.values) {
        list.sort((a, b) => a.id.compareTo(b.id));
      }
      if (!mounted) return;
      setState(() {
        _base = base;
        _formsByDex
          ..clear()
          ..addAll(formsByDex);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error =
            'Could not load the Pokedex index.\nCheck your connection and retry.';
        _loading = false;
      });
    }
  }

  /// Finds a form's owning species by longest base-name prefix match.
  int? _baseDexForForm(String formName, Map<String, int> baseNameToDex) {
    final parts = formName.split('-');
    for (var take = parts.length - 1; take >= 1; take--) {
      final dex = baseNameToDex[parts.take(take).join('-')];
      if (dex != null) return dex;
    }
    return null;
  }

  List<_GridItem> get _filtered {
    final q = _query.toLowerCase();
    final out = <_GridItem>[];
    for (final s in _base) {
      if (_gen != null) {
        final r = _genRanges[_gen! - 1];
        if (s.id < r.start || s.id > r.end) continue;
      }
      final base = _GridItem(
          id: s.id, baseDex: s.id, baseName: s.name, isForm: false);
      final group = <_GridItem>[base, if (_showForms) ...?_formsByDex[s.id]];
      for (final item in group) {
        if (q.isEmpty ||
            item.baseName.toLowerCase().contains(q) ||
            (item.formLabel?.toLowerCase().contains(q) ?? false) ||
            item.baseDex.toString() == q ||
            '#${item.baseDex}'.contains(q)) {
          out.add(item);
        }
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.watch<AppState>().accent;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search by name or number…',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _query = v.trim()),
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              _genChip(context,
                  label: 'All',
                  selected: _gen == null,
                  accent: accent,
                  onTap: () => setState(() => _gen = null)),
              for (final r in _genRanges)
                _genChip(context,
                    label: 'Gen ${r.gen}',
                    selected: _gen == r.gen,
                    accent: accent,
                    onTap: () => setState(() => _gen = r.gen)),
              Padding(
                padding: const EdgeInsets.only(left: 4, right: 8),
                child: FilterChip(
                  label: const Text('Forms'),
                  selected: _showForms,
                  showCheckmark: true,
                  checkmarkColor: Colors.white,
                  selectedColor: accent,
                  labelStyle: TextStyle(
                    color: _showForms ? Colors.white : scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  onSelected: (v) => setState(() => _showForms = v),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(child: _buildBody(accent)),
      ],
    );
  }

  Widget _genChip(BuildContext context,
      {required String label,
      required bool selected,
      required Color accent,
      required VoidCallback onTap}) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        selectedColor: accent,
        labelStyle: TextStyle(
          color: selected ? Colors.white : scheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        onSelected: (_) => onTap(),
      ),
    );
  }

  Widget _buildBody(Color accent) {
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
    final items = _filtered;
    if (items.isEmpty) {
      return const Center(child: Text('No Pokémon match your search.'));
    }
    final caught = context.watch<AppState>().allCaughtSpecies;
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 128,
        childAspectRatio: 0.82,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) => _DexCard(
        item: items[i],
        caught: !items[i].isForm && caught.contains(items[i].baseDex),
        accent: accent,
      ),
    );
  }
}

class _DexCard extends StatelessWidget {
  final _GridItem item;
  final bool caught;
  final Color accent;
  const _DexCard({
    required this.item,
    required this.caught,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PokemonDetailScreen(
              id: item.baseDex,
              name: item.baseName,
              initialFormId: item.isForm ? item.id : null,
            ),
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.6)),
          ),
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CachedNetworkImage(
                        imageUrl: item.spriteUrl,
                        fit: BoxFit.contain,
                        errorWidget: (_, _, _) => Icon(Icons.catching_pokemon,
                            color: scheme.onSurfaceVariant),
                        placeholder: (_, _) => const SizedBox(),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      left: 2,
                      child: Text('#${item.baseDex.toString().padLeft(4, '0')}',
                          style: TextStyle(
                              fontSize: 10, color: scheme.onSurfaceVariant)),
                    ),
                    if (caught)
                      Positioned(
                        top: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                              color: accent, shape: BoxShape.circle),
                          child: const Icon(Icons.check,
                              size: 12, color: Colors.white),
                        ),
                      ),
                    if (item.isForm && item.formLabel != null)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: accent,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(item.formLabel!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 9,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                prettifyName(item.baseName),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

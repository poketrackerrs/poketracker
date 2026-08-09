import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../data/pokeapi_maps.dart';
import '../models/pokedex_models.dart';
import '../services/pokedex_service.dart';
import 'pokemon_detail_screen.dart';

class PokedexListScreen extends StatefulWidget {
  const PokedexListScreen({super.key});

  @override
  State<PokedexListScreen> createState() => _PokedexListScreenState();
}

class _PokedexListScreenState extends State<PokedexListScreen> {
  final _service = PokedexService();
  List<PokemonSummary> _all = [];
  String _query = '';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await _service.loadIndex();
      if (!mounted) return;
      setState(() {
        _all = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load the Pokedex index.\nCheck your connection and retry.';
        _loading = false;
      });
    }
  }

  List<PokemonSummary> get _filtered {
    if (_query.isEmpty) return _all;
    final q = _query.toLowerCase();
    return _all.where((p) {
      return p.name.toLowerCase().contains(q) || p.id.toString() == q ||
          '#${p.id}'.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search by name or number…',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _query = v.trim()),
          ),
        ),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                setState(() {
                  _loading = true;
                  _error = null;
                });
                _load();
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    final items = _filtered;
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, i) {
        final p = items[i];
        return ListTile(
          leading: SizedBox(
            width: 48,
            height: 48,
            child: CachedNetworkImage(
              imageUrl: p.spriteUrl,
              fit: BoxFit.contain,
              errorWidget: (_, _, _) =>
                  const Icon(Icons.catching_pokemon, color: Colors.grey),
              placeholder: (_, _) => const SizedBox(),
            ),
          ),
          title: Text(prettifyName(p.name)),
          subtitle: Text('#${p.id.toString().padLeft(4, '0')}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => PokemonDetailScreen(id: p.id, name: p.name),
            ),
          ),
        );
      },
    );
  }
}

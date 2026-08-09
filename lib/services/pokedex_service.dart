import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../data/pokeapi_maps.dart';
import '../models/pokedex_models.dart';

/// Fetches Pokedex data from PokeAPI, caching raw responses in
/// shared_preferences so anything you've viewed once loads instantly offline.
class PokedexService {
  static const _base = 'https://pokeapi.co/api/v2';

  // National dex count through Gen 9 (base forms only, avoids alt-form clutter).
  static const int nationalDexCount = 1025;

  final Map<int, PokemonDetail> _memCache = {};

  /// GET with a persistent cache keyed by URL (Pokedex data is effectively
  /// static, so cached entries never expire). Returns decoded JSON, which may
  /// be a Map or a List depending on the endpoint.
  Future<dynamic> _cachedGetJson(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'pokecache:$url';
    final cached = prefs.getString(key);
    if (cached != null) return jsonDecode(cached);
    final resp =
        await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) {
      throw Exception('PokeAPI error ${resp.statusCode} for $url');
    }
    await prefs.setString(key, resp.body);
    return jsonDecode(resp.body);
  }

  Future<Map<String, dynamic>> _cachedGet(String url) async =>
      (await _cachedGetJson(url)) as Map<String, dynamic>;

  /// The full national-dex list (id + name). Built locally — no network needed,
  /// since ids are sequential and sprites load lazily by id.
  List<PokemonSummary> fullList() {
    // Names are resolved lazily on the detail screen; the list only needs ids.
    // We still show a readable placeholder name derived from the id until the
    // sprite loads — but to show real names without 1025 requests, we fetch the
    // index once via [loadIndex].
    return List.generate(
      nationalDexCount,
      (i) => PokemonSummary(i + 1, '#${i + 1}'),
    );
  }

  /// Loads the id->name index in a single request (cached thereafter).
  Future<List<PokemonSummary>> loadIndex() async {
    final json =
        await _cachedGet('$_base/pokemon?limit=$nationalDexCount&offset=0');
    final results = (json['results'] as List).cast<Map<String, dynamic>>();
    final list = <PokemonSummary>[];
    for (var i = 0; i < results.length; i++) {
      list.add(PokemonSummary(i + 1, results[i]['name'] as String));
    }
    return list;
  }

  int? _idFromUrl(String url) {
    final parts = url.split('/').where((p) => p.isNotEmpty).toList();
    return parts.isEmpty ? null : int.tryParse(parts.last);
  }

  /// Resolves the regional Pokedex (species list) for a game's version group.
  Future<GameDex> loadGameDex(String versionGroup) async {
    final versions = <String>{};
    final pokedexNames = <String>[];
    try {
      final data = await _cachedGet('$_base/version-group/$versionGroup');
      for (final v in (data['versions'] as List)) {
        versions.add(v['name'] as String);
      }
      for (final p in (data['pokedexes'] as List)) {
        final n = p['name'] as String;
        if (!pokedexNames.contains(n)) pokedexNames.add(n);
      }
    } catch (_) {
      // Version group not in PokeAPI yet (e.g. an unreleased game).
      return const GameDex(species: [], versions: []);
    }

    final seen = <int>{};
    final species = <GameSpecies>[];
    for (final dexName in pokedexNames) {
      try {
        final dex = await _cachedGet('$_base/pokedex/$dexName');
        final entries =
            (dex['pokemon_entries'] as List).cast<Map<String, dynamic>>()
              ..sort((a, b) =>
                  (a['entry_number'] as int).compareTo(b['entry_number'] as int));
        for (final e in entries) {
          final sp = e['pokemon_species'] as Map<String, dynamic>;
          final id = _idFromUrl(sp['url'] as String);
          if (id == null || id > nationalDexCount || seen.contains(id)) continue;
          seen.add(id);
          species.add(GameSpecies(
            id: id,
            name: sp['name'] as String,
            entryNumber: e['entry_number'] as int,
          ));
        }
      } catch (_) {}
    }
    return GameDex(species: species, versions: versions.toList());
  }

  /// Classifies how a species is obtained in a game, from its wild encounters.
  Future<ObtainInfo> loadObtainability(
      int speciesId, List<String> gameVersions) async {
    if (gameVersions.isEmpty) {
      return const ObtainInfo(kind: ObtainKind.unknown, versions: []);
    }
    try {
      final data =
          await _cachedGetJson('$_base/pokemon/$speciesId/encounters') as List;
      final present = <String>{};
      for (final area in data) {
        for (final vd in (area['version_details'] as List)) {
          final v = vd['version']['name'] as String;
          if (gameVersions.contains(v)) present.add(v);
        }
      }
      if (present.isEmpty) {
        return const ObtainInfo(kind: ObtainKind.none, versions: []);
      }
      if (present.length >= gameVersions.length) {
        return ObtainInfo(kind: ObtainKind.wild, versions: gameVersions);
      }
      return ObtainInfo(kind: ObtainKind.partial, versions: present.toList());
    } catch (_) {
      return const ObtainInfo(kind: ObtainKind.unknown, versions: []);
    }
  }

  Future<PokemonDetail> fetchDetail(int id) async {
    if (_memCache.containsKey(id)) return _memCache[id]!;

    final pokemon = await _cachedGet('$_base/pokemon/$id');
    final species = await _cachedGet('$_base/pokemon-species/$id');

    // Types
    final types = (pokemon['types'] as List)
        .map((t) => (t['type']['name'] as String))
        .toList();

    // Base stats
    final stats = <String, int>{};
    for (final s in (pokemon['stats'] as List)) {
      stats[s['stat']['name'] as String] = s['base_stat'] as int;
    }

    // Movepool -> flatten (move x version-group) into per-generation entries
    final moves = <MoveEntry>[];
    for (final m in (pokemon['moves'] as List)) {
      final moveName = m['move']['name'] as String;
      for (final d in (m['version_group_details'] as List)) {
        final vg = d['version_group']['name'] as String;
        final gen = kVersionGroupToGen[vg];
        if (gen == null) continue;
        moves.add(MoveEntry(
          name: moveName,
          method: d['move_learn_method']['name'] as String,
          level: (d['level_learned_at'] as int?) ?? 0,
          generation: gen,
        ));
      }
    }

    // Pokedex entries (English), grouped by generation, de-duplicated
    final dexByGen = <int, List<String>>{};
    final seen = <String>{};
    for (final f in (species['flavor_text_entries'] as List)) {
      if (f['language']['name'] != 'en') continue;
      final version = f['version']['name'] as String;
      final gen = kVersionToGen[version];
      if (gen == null) continue;
      final text = (f['flavor_text'] as String)
          .replaceAll('\n', ' ')
          .replaceAll('\f', ' ')
          .replaceAll('­', '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final dedupKey = '$gen|$text';
      if (seen.contains(dedupKey)) continue;
      seen.add(dedupKey);
      dexByGen.putIfAbsent(gen, () => []).add(text);
    }

    // Abilities (with effect descriptions)
    final abilities = <AbilityInfo>[];
    for (final a in (pokemon['abilities'] as List)) {
      final aname = a['ability']['name'] as String;
      String desc = '';
      try {
        final ad = await _cachedGet('$_base/ability/$aname');
        final effs = (ad['effect_entries'] as List)
            .where((e) => e['language']['name'] == 'en')
            .toList();
        if (effs.isNotEmpty) {
          desc = (effs.first['short_effect'] ?? effs.first['effect'] ?? '')
              .toString();
        }
        if (desc.isEmpty) {
          final fte = (ad['flavor_text_entries'] as List)
              .where((e) => e['language']['name'] == 'en')
              .toList();
          if (fte.isNotEmpty) desc = (fte.first['flavor_text'] ?? '').toString();
        }
        desc = desc.replaceAll('\n', ' ').replaceAll('\f', ' ').trim();
      } catch (_) {}
      abilities.add(AbilityInfo(
        name: aname,
        isHidden: a['is_hidden'] as bool? ?? false,
        description: desc,
      ));
    }

    // Historical typings
    final pastTypes = <PastType>[];
    for (final pt in (pokemon['past_types'] as List? ?? [])) {
      final gen = _romanGenToInt(pt['generation']['name'] as String);
      final tps =
          (pt['types'] as List).map((t) => t['type']['name'] as String).toList();
      if (gen != null) pastTypes.add(PastType(generation: gen, types: tps));
    }

    // Type matchups (defensive): combine damage_from across this Pokemon's types
    final matchups = await _typeMatchups(types);

    // Evolution chain
    final evolution = await _evolutionChain(species);

    // Species "infobox" fields
    final eggGroups = (species['egg_groups'] as List? ?? [])
        .map((g) => g['name'] as String)
        .toList();

    final detail = PokemonDetail(
      id: id,
      name: pokemon['name'] as String,
      types: types,
      stats: stats,
      moves: moves,
      dexEntriesByGen: dexByGen,
      abilities: abilities,
      evolution: evolution,
      matchups: matchups,
      pastTypes: pastTypes,
      height: ((pokemon['height'] as int?) ?? 0) / 10.0, // decimetres -> m
      weight: ((pokemon['weight'] as int?) ?? 0) / 10.0, // hectograms -> kg
      genus: _englishGenus(species),
      captureRate: (species['capture_rate'] as int?) ?? 0,
      genderRate: (species['gender_rate'] as int?) ?? -1,
      eggGroups: eggGroups,
      baseHappiness: (species['base_happiness'] as int?) ?? 0,
      growthRate: (species['growth_rate']?['name'] as String?) ?? '',
    );
    _memCache[id] = detail;
    return detail;
  }

  static String _englishGenus(Map<String, dynamic> species) {
    for (final g in (species['genera'] as List? ?? [])) {
      if (g['language']?['name'] == 'en') return (g['genus'] as String?) ?? '';
    }
    return '';
  }

  /// A short, human-readable evolution condition from a node's details.
  static String _evoCondition(List details) {
    if (details.isEmpty) return '';
    final d = details.first as Map<String, dynamic>;
    final lvl = d['min_level'] as int?;
    if (lvl != null) return 'Lv. $lvl';
    final item = d['item']?['name'] as String?;
    if (item != null) return 'Use ${prettifyName(item)}';
    if ((d['min_happiness'] as int?) != null) return 'Happiness';
    final trigger = d['trigger']?['name'] as String?;
    if (trigger == 'trade') {
      final held = d['held_item']?['name'] as String?;
      return held != null ? 'Trade w/ ${prettifyName(held)}' : 'Trade';
    }
    final move = d['known_move']?['name'] as String?;
    if (move != null) return 'Learn ${prettifyName(move)}';
    final loc = d['location']?['name'] as String?;
    if (loc != null) return 'At ${prettifyName(loc)}';
    final time = d['time_of_day'] as String?;
    if (time != null && time.isNotEmpty) return prettifyName(time);
    if (trigger != null && trigger != 'level-up') return prettifyName(trigger);
    return '';
  }

  static int? _romanGenToInt(String generationName) {
    // e.g. "generation-v" -> 5
    const roman = {
      'i': 1, 'ii': 2, 'iii': 3, 'iv': 4, 'v': 5,
      'vi': 6, 'vii': 7, 'viii': 8, 'ix': 9,
    };
    final parts = generationName.split('-');
    return parts.length == 2 ? roman[parts[1]] : null;
  }

  /// Combined defensive multiplier per attacking type (2.0/0.5/0.0 etc.).
  Future<Map<String, double>> _typeMatchups(List<String> defTypes) async {
    final result = <String, double>{};
    for (final t in defTypes) {
      try {
        final data = await _cachedGet('$_base/type/$t');
        final rel = data['damage_relations'] as Map<String, dynamic>;
        void apply(String key, double factor) {
          for (final e in (rel[key] as List)) {
            final atk = e['name'] as String;
            result[atk] = (result[atk] ?? 1.0) * factor;
          }
        }

        apply('double_damage_from', 2.0);
        apply('half_damage_from', 0.5);
        apply('no_damage_from', 0.0);
      } catch (_) {}
    }
    return result;
  }

  /// Flattens the species' evolution chain into an ordered list.
  Future<List<EvoStage>> _evolutionChain(Map<String, dynamic> species) async {
    try {
      final url = species['evolution_chain']?['url'] as String?;
      if (url == null) return [];
      final data = await _cachedGetJson(url) as Map<String, dynamic>;
      final stages = <EvoStage>[];
      void walk(Map<String, dynamic> node) {
        final sp = node['species'] as Map<String, dynamic>;
        final id = _idFromUrl(sp['url'] as String);
        if (id != null && id <= nationalDexCount) {
          stages.add(EvoStage(
            id: id,
            name: sp['name'] as String,
            condition: _evoCondition(node['evolution_details'] as List? ?? []),
          ));
        }
        for (final next in (node['evolves_to'] as List)) {
          walk(next as Map<String, dynamic>);
        }
      }

      walk(data['chain'] as Map<String, dynamic>);
      return stages;
    } catch (_) {
      return [];
    }
  }
}

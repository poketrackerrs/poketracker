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

  List<({int id, String name})>? _varietiesCache;

  /// Every Pokemon variety (base species + alternate forms). Alternate forms
  /// have ids >= 10000. One cached request.
  Future<List<({int id, String name})>> loadAllVarieties() async {
    if (_varietiesCache != null) return _varietiesCache!;
    final json = await _cachedGet('$_base/pokemon?limit=100000&offset=0');
    final results = (json['results'] as List).cast<Map<String, dynamic>>();
    final out = <({int id, String name})>[];
    for (final r in results) {
      final id = _idFromUrl(r['url'] as String);
      if (id == null) continue;
      out.add((id: id, name: r['name'] as String));
    }
    return _varietiesCache = out;
  }

  /// Public form-label helper (e.g. "raichu-alola" + "raichu" -> "Alolan").
  String labelForForm(String formName, String baseName) =>
      _formLabel(formName, baseName);

  Map<String, List<({int id, String name, String label})>>? _formsByBaseCache;

  /// Maps each base species name to its varieties (base + forms), each with an
  /// id, variety name, and display label. Base form's label is "Normal".
  Future<Map<String, List<({int id, String name, String label})>>>
      loadFormsByBase() async {
    if (_formsByBaseCache != null) return _formsByBaseCache!;
    final base = await loadIndex();
    final baseNameToDex = {for (final s in base) s.name: s.id};
    final varieties = await loadAllVarieties();
    final out = <String, List<({int id, String name, String label})>>{};
    for (final s in base) {
      out[s.name] = [(id: s.id, name: s.name, label: 'Normal')];
    }
    for (final v in varieties) {
      if (v.id < 10000) continue;
      final baseDex = _baseDexByPrefix(v.name, baseNameToDex);
      if (baseDex == null) continue;
      final baseName = base[baseDex - 1].name;
      out[baseName]!.add((
        id: v.id,
        name: v.name,
        label: _formLabel(v.name, baseName),
      ));
    }
    return _formsByBaseCache = out;
  }

  int? _baseDexByPrefix(String formName, Map<String, int> baseNameToDex) {
    final parts = formName.split('-');
    for (var take = parts.length - 1; take >= 1; take--) {
      final dex = baseNameToDex[parts.take(take).join('-')];
      if (dex != null) return dex;
    }
    return null;
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

  /// Where a Pokémon can be caught in a specific game [version]: one entry per
  /// (location area, method), with the level range and total encounter chance.
  /// Empty when it isn't found in the wild in that game.
  Future<List<({String area, String method, int minLevel, int maxLevel, int chance})>>
      encountersIn(int id, String version) async {
    try {
      final data =
          await _cachedGetJson('$_base/pokemon/$id/encounters') as List;
      final out =
          <({String area, String method, int minLevel, int maxLevel, int chance})>[];
      for (final area in data) {
        final areaName = area['location_area']['name'] as String;
        for (final vd in (area['version_details'] as List)) {
          if (vd['version']['name'] != version) continue;
          // Aggregate the raw slots by method → level span + summed chance.
          final byMethod = <String, (int, int, int)>{}; // min,max,chance
          for (final ed in (vd['encounter_details'] as List)) {
            final m = ed['method']['name'] as String;
            final mn = ed['min_level'] as int;
            final mx = ed['max_level'] as int;
            final ch = ed['chance'] as int;
            final cur = byMethod[m];
            byMethod[m] = cur == null
                ? (mn, mx, ch)
                : (mn < cur.$1 ? mn : cur.$1, mx > cur.$2 ? mx : cur.$2,
                    cur.$3 + ch);
          }
          byMethod.forEach((m, v) => out.add((
                area: areaName,
                method: m,
                minLevel: v.$1,
                maxLevel: v.$2,
                chance: v.$3 > 100 ? 100 : v.$3,
              )));
        }
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// A Pokémon's (or form's) current types — lightweight, cached. For the
  /// per-game dex list's type chips.
  Future<List<String>> typesOf(int id) async {
    try {
      final p = await _cachedGet('$_base/pokemon/$id');
      return [
        for (final t in (p['types'] as List)) t['type']['name'] as String
      ];
    } catch (_) {
      return const [];
    }
  }

  /// The base (first-stage) species of an evolution line — e.g. Pidgey for
  /// Pidgeot — by walking `evolves_from_species`. Cached per hop.
  Future<int> baseSpeciesOf(int dex) async {
    var cur = dex;
    for (var i = 0; i < 4; i++) {
      try {
        final sp = await _cachedGet('$_base/pokemon-species/$cur');
        final from = sp['evolves_from_species'];
        if (from == null) break;
        final id = _idFromUrl(from['url'] as String);
        if (id == null || id == cur) break;
        cur = id;
      } catch (_) {
        break;
      }
    }
    return cur;
  }

  /// A species' EXP growth-rate name (for computing level<->exp). Cached.
  Future<String> growthRate(int dex) async {
    try {
      final sp = await _cachedGet('$_base/pokemon-species/$dex');
      return (sp['growth_rate']?['name'] as String?) ?? 'medium';
    } catch (_) {
      return 'medium';
    }
  }

  /// Base PP of a move — to set a freshly-taught move to full (legal) PP. Cached.
  Future<int> movePP(int moveId) async {
    try {
      final j = await _cachedGet('$_base/move/$moveId');
      return (j['pp'] as int?) ?? 5;
    } catch (_) {
      return 5;
    }
  }

  /// Full display info for a move (power / PP / type / category / accuracy).
  /// Cached via the same HTTP cache as movePP.
  Future<({int power, int pp, int accuracy, String type, String damageClass})>
      moveInfo(int moveId) async {
    try {
      final j = await _cachedGet('$_base/move/$moveId');
      return (
        power: (j['power'] as int?) ?? 0,
        pp: (j['pp'] as int?) ?? 0,
        accuracy: (j['accuracy'] as int?) ?? 0,
        type: (j['type']?['name'] as String?) ?? '',
        damageClass: (j['damage_class']?['name'] as String?) ?? '',
      );
    } catch (_) {
      return (power: 0, pp: 0, accuracy: 0, type: '', damageClass: '');
    }
  }

  Future<PokemonDetail> fetchDetail(int id) async {
    if (_memCache.containsKey(id)) return _memCache[id]!;

    final pokemon = await _cachedGet('$_base/pokemon/$id');
    final species = await _cachedGet('$_base/pokemon-species/$id');
    final core = await _buildCore(pokemon);

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

    final evolution = await _evolutionChain(species);
    final eggGroups = (species['egg_groups'] as List? ?? [])
        .map((g) => g['name'] as String)
        .toList();
    final forms = _parseForms(species, pokemon['name'] as String);

    final detail = PokemonDetail(
      id: id,
      name: pokemon['name'] as String,
      types: core.types,
      stats: core.stats,
      moves: core.moves,
      dexEntriesByGen: dexByGen,
      abilities: core.abilities,
      evolution: evolution,
      matchups: core.matchups,
      pastTypes: core.pastTypes,
      height: core.height,
      weight: core.weight,
      genus: _englishGenus(species),
      captureRate: (species['capture_rate'] as int?) ?? 0,
      genderRate: (species['gender_rate'] as int?) ?? -1,
      eggGroups: eggGroups,
      baseHappiness: (species['base_happiness'] as int?) ?? 0,
      growthRate: (species['growth_rate']?['name'] as String?) ?? '',
      forms: forms,
    );
    _memCache[id] = detail;
    return detail;
  }

  /// Fetches the form-specific data for a variety (e.g. Alolan, Mega).
  Future<FormOverride> fetchForm(int formId) async {
    final pokemon = await _cachedGet('$_base/pokemon/$formId');
    final core = await _buildCore(pokemon);
    return FormOverride(
      id: formId,
      types: core.types,
      stats: core.stats,
      abilities: core.abilities,
      moves: core.moves,
      matchups: core.matchups,
      height: core.height,
      weight: core.weight,
      artworkUrl: core.artworkUrl,
    );
  }

  /// Builds the form-level data (types/stats/moves/abilities/matchups/size/art)
  /// shared by both a species' default form and its alternate forms.
  Future<
      ({
        List<String> types,
        Map<String, int> stats,
        List<MoveEntry> moves,
        List<AbilityInfo> abilities,
        Map<String, double> matchups,
        List<PastType> pastTypes,
        double height,
        double weight,
        String artworkUrl,
      })> _buildCore(Map<String, dynamic> pokemon) async {
    final types = (pokemon['types'] as List)
        .map((t) => (t['type']['name'] as String))
        .toList();

    final stats = <String, int>{};
    for (final s in (pokemon['stats'] as List)) {
      stats[s['stat']['name'] as String] = s['base_stat'] as int;
    }

    final moves = <MoveEntry>[];
    for (final m in (pokemon['moves'] as List)) {
      final moveName = m['move']['name'] as String;
      final moveId = _idFromUrl(m['move']['url'] as String) ?? 0;
      for (final d in (m['version_group_details'] as List)) {
        final vg = d['version_group']['name'] as String;
        final gen = kVersionGroupToGen[vg];
        if (gen == null) continue;
        moves.add(MoveEntry(
          id: moveId,
          name: moveName,
          method: d['move_learn_method']['name'] as String,
          level: (d['level_learned_at'] as int?) ?? 0,
          generation: gen,
        ));
      }
    }

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
        id: _idFromUrl(a['ability']['url'] as String) ?? 0,
        slot: (a['slot'] as num?)?.toInt() ?? 1,
        name: aname,
        isHidden: a['is_hidden'] as bool? ?? false,
        description: desc,
      ));
    }

    final pastTypes = <PastType>[];
    for (final pt in (pokemon['past_types'] as List? ?? [])) {
      final gen = _romanGenToInt(pt['generation']['name'] as String);
      final tps =
          (pt['types'] as List).map((t) => t['type']['name'] as String).toList();
      if (gen != null) pastTypes.add(PastType(generation: gen, types: tps));
    }

    final matchups = await _typeMatchups(types);

    final sprites = pokemon['sprites'] as Map<String, dynamic>?;
    final art = (sprites?['other']?['official-artwork']?['front_default']) ??
        sprites?['front_default'];
    final artworkUrl = (art as String?) ??
        'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/other/official-artwork/${pokemon['id']}.png';

    return (
      types: types,
      stats: stats,
      moves: moves,
      abilities: abilities,
      matchups: matchups,
      pastTypes: pastTypes,
      height: ((pokemon['height'] as int?) ?? 0) / 10.0,
      weight: ((pokemon['weight'] as int?) ?? 0) / 10.0,
      artworkUrl: artworkUrl,
    );
  }

  static const Map<String, String> _formWords = {
    'alola': 'Alolan', 'galar': 'Galarian', 'hisui': 'Hisuian',
    'paldea': 'Paldean', 'mega': 'Mega', 'gmax': 'Gigantamax',
    'primal': 'Primal', 'origin': 'Origin', 'therian': 'Therian',
    'incarnate': 'Incarnate', 'zen': 'Zen', 'standard': 'Standard',
    'attack': 'Attack', 'defense': 'Defense', 'speed': 'Speed',
    'sunshine': 'Sunshine', 'plant': 'Plant', 'sandy': 'Sandy', 'trash': 'Trash',
    'heat': 'Heat', 'wash': 'Wash', 'frost': 'Frost', 'fan': 'Fan', 'mow': 'Mow',
    'black': 'Black', 'white': 'White', 'x': 'X', 'y': 'Y',
    'blaze': 'Blaze', 'aqua': 'Aqua', 'crowned': 'Crowned', 'eternamax': 'Eternamax',
  };

  static String _formLabel(String formName, String base) {
    if (formName == base) return 'Normal';
    final q =
        formName.startsWith('$base-') ? formName.substring(base.length + 1) : formName;
    return q
        .split('-')
        .map((t) => _formWords[t] ?? prettifyName(t))
        .join(' ');
  }

  /// Parses a species' varieties into a form list. Returns [] when there's only
  /// the base form (so the UI shows no switcher).
  List<PokemonForm> _parseForms(Map<String, dynamic> species, String baseName) {
    final out = <PokemonForm>[];
    for (final v in (species['varieties'] as List? ?? [])) {
      final p = v['pokemon'] as Map<String, dynamic>;
      final id = _idFromUrl(p['url'] as String);
      if (id == null) continue;
      final name = p['name'] as String;
      out.add(PokemonForm(
        id: id,
        name: name,
        isDefault: v['is_default'] == true,
        label: _formLabel(name, baseName),
      ));
    }
    out.sort((a, b) => (a.isDefault ? 0 : 1).compareTo(b.isDefault ? 0 : 1));
    return out.length <= 1 ? const [] : out;
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

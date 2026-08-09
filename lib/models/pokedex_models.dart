/// Lightweight list entry for the Pokedex grid/list.
class PokemonSummary {
  final int id;
  final String name;
  const PokemonSummary(this.id, this.name);

  /// Small pixel sprite (fast to load, good for lists).
  String get spriteUrl =>
      'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/$id.png';

  /// High-res official artwork (for the detail header).
  String get artworkUrl =>
      'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/other/official-artwork/$id.png';
}

/// A species as it appears in a specific game's regional Pokedex.
class GameSpecies {
  final int id;
  final String name;
  final int entryNumber;
  const GameSpecies({
    required this.id,
    required this.name,
    required this.entryNumber,
  });

  String get spriteUrl =>
      'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/$id.png';
}

/// The resolved Pokedex + versions for one game.
class GameDex {
  final List<GameSpecies> species;
  final List<String> versions; // e.g. ['sword', 'shield']
  const GameDex({required this.species, required this.versions});
}

/// How obtainable a species is in a given game, derived from encounter data.
enum ObtainKind { wild, partial, none, unknown }

class ObtainInfo {
  final ObtainKind kind;
  final List<String> versions; // versions it's wild in (for partial)
  const ObtainInfo({required this.kind, required this.versions});
}

/// One way a Pokemon learns a move, within one generation.
class MoveEntry {
  final String name;
  final String method; // level-up, machine, egg, tutor
  final int level; // 0 when not applicable
  final int generation;
  const MoveEntry({
    required this.name,
    required this.method,
    required this.level,
    required this.generation,
  });
}

/// An ability with its hidden flag and effect description.
class AbilityInfo {
  final String name;
  final bool isHidden;
  final String description;
  const AbilityInfo({
    required this.name,
    required this.isHidden,
    this.description = '',
  });
}

/// A historical typing that applied up to a given generation.
class PastType {
  final int generation; // last generation these types applied
  final List<String> types;
  const PastType({required this.generation, required this.types});
}

/// One species in an evolution chain.
class EvoStage {
  final int id;
  final String name;
  const EvoStage({required this.id, required this.name});

  String get spriteUrl =>
      'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/$id.png';
}

/// Full detail for one Pokemon.
class PokemonDetail {
  final int id;
  final String name;
  final List<String> types;
  final Map<String, int> stats; // keyed by PokeAPI stat name
  final List<MoveEntry> moves;
  final Map<int, List<String>> dexEntriesByGen; // generation -> entries
  final List<AbilityInfo> abilities;
  final List<EvoStage> evolution;
  final Map<String, double> matchups; // attacking type -> damage multiplier
  final List<PastType> pastTypes;

  const PokemonDetail({
    required this.id,
    required this.name,
    required this.types,
    required this.stats,
    required this.moves,
    required this.dexEntriesByGen,
    required this.abilities,
    required this.evolution,
    required this.matchups,
    this.pastTypes = const [],
  });

  /// Types as they were in [gen] (applies historical type changes if known).
  List<String> typesForGeneration(int? gen) {
    if (gen == null || pastTypes.isEmpty) return types;
    PastType? best;
    for (final pt in pastTypes) {
      if (pt.generation >= gen) {
        if (best == null || pt.generation < best.generation) best = pt;
      }
    }
    return best?.types ?? types;
  }

  String get artworkUrl =>
      'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/other/official-artwork/$id.png';

  int get statTotal => stats.values.fold(0, (a, b) => a + b);

  /// Generations for which this Pokemon has any movepool data, sorted.
  List<int> get moveGenerations {
    final gens = moves.map((m) => m.generation).toSet().toList()..sort();
    return gens;
  }
}

/// Static definition of a Pokemon game (does not change at runtime).
class Game {
  final String id;
  final String title;
  final int generation;
  final String region;
  final int releaseYear;
  final GameCategory category;

  /// Ordered progression milestones (gym badges, trials, story beats).
  final List<String> milestones;

  /// Completion target for the Pokedex (species count goal).
  final int dexTotal;

  /// PokeAPI "version group" name (resolves this game's regional Pokedex).
  final String versionGroup;

  /// PokeAPI "version" name (used to filter wild encounters to this game).
  final String version;

  /// Where box art is loaded from. Drop a file named `<id>.png` into
  /// assets/games/ and it will be shown; otherwise a styled card is used.
  String get boxArtAsset => 'assets/games/$id.png';

  const Game({
    required this.id,
    required this.title,
    required this.generation,
    required this.region,
    required this.releaseYear,
    required this.category,
    required this.milestones,
    required this.dexTotal,
    required this.versionGroup,
    required this.version,
  });
}

enum GameCategory { mainline, legends }

extension GameCategoryLabel on GameCategory {
  String get label {
    switch (this) {
      case GameCategory.mainline:
        return 'Mainline';
      case GameCategory.legends:
        return 'Legends';
    }
  }
}

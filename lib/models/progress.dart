/// A single Pokemon on the current team.
class TeamMember {
  String species;
  String nickname;
  int level;

  TeamMember({this.species = '', this.nickname = '', this.level = 1});

  Map<String, dynamic> toJson() => {
        'species': species,
        'nickname': nickname,
        'level': level,
      };

  factory TeamMember.fromJson(Map<String, dynamic> j) => TeamMember(
        species: j['species'] ?? '',
        nickname: j['nickname'] ?? '',
        level: j['level'] ?? 1,
      );
}

/// A shiny hunt in progress or completed.
class ShinyHunt {
  String species;
  String method;
  int count;
  bool caught;

  ShinyHunt({
    this.species = '',
    this.method = 'Random encounter',
    this.count = 0,
    this.caught = false,
  });

  Map<String, dynamic> toJson() => {
        'species': species,
        'method': method,
        'count': count,
        'caught': caught,
      };

  factory ShinyHunt.fromJson(Map<String, dynamic> j) => ShinyHunt(
        species: j['species'] ?? '',
        method: j['method'] ?? 'Random encounter',
        count: j['count'] ?? 0,
        caught: j['caught'] ?? false,
      );
}

/// All the user-tracked progress for one game, keyed by the game's id.
class GameProgress {
  final String gameId;

  /// Milestone label -> completed.
  Map<String, bool> milestones;

  int dexSeen;
  int dexCaught;

  /// National-dex ids the user has marked caught in this game.
  Set<int> caughtSpecies;

  List<TeamMember> team;
  List<ShinyHunt> shinyHunts;

  /// Ids of achievements the user manually checked off (ones the app can't
  /// auto-detect from a save).
  Set<String> unlockedAchievements;

  GameProgress({
    required this.gameId,
    Map<String, bool>? milestones,
    this.dexSeen = 0,
    this.dexCaught = 0,
    Set<int>? caughtSpecies,
    List<TeamMember>? team,
    List<ShinyHunt>? shinyHunts,
    Set<String>? unlockedAchievements,
  })  : milestones = milestones ?? {},
        caughtSpecies = caughtSpecies ?? {},
        team = team ?? [],
        shinyHunts = shinyHunts ?? [],
        unlockedAchievements = unlockedAchievements ?? {};

  Map<String, dynamic> toJson() => {
        'gameId': gameId,
        'milestones': milestones,
        'dexSeen': dexSeen,
        'dexCaught': dexCaught,
        'caughtSpecies': caughtSpecies.toList(),
        'team': team.map((t) => t.toJson()).toList(),
        'shinyHunts': shinyHunts.map((s) => s.toJson()).toList(),
        'unlockedAchievements': unlockedAchievements.toList(),
      };

  factory GameProgress.fromJson(Map<String, dynamic> j) => GameProgress(
        gameId: j['gameId'],
        milestones: Map<String, bool>.from(j['milestones'] ?? {}),
        dexSeen: j['dexSeen'] ?? 0,
        dexCaught: j['dexCaught'] ?? 0,
        caughtSpecies: ((j['caughtSpecies'] as List?) ?? [])
            .map((e) => e as int)
            .toSet(),
        team: (j['team'] as List? ?? [])
            .map((t) => TeamMember.fromJson(Map<String, dynamic>.from(t)))
            .toList(),
        shinyHunts: (j['shinyHunts'] as List? ?? [])
            .map((s) => ShinyHunt.fromJson(Map<String, dynamic>.from(s)))
            .toList(),
        unlockedAchievements: ((j['unlockedAchievements'] as List?) ?? [])
            .map((e) => e as String)
            .toSet(),
      );
}

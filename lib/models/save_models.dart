/// One Pokemon read from a save's party.
class SaveTeamMon {
  final int? dexId; // national dex id, if resolvable
  final int level;
  final String? nickname;

  /// Filled in later from the national-dex index (id -> slug/name).
  String? name;

  SaveTeamMon({this.dexId, required this.level, this.nickname, this.name});
}

/// Everything the auto-tracker managed to read out of a save file. Fields left
/// null/empty mean "this save format doesn't expose it yet" — the UI only shows
/// and applies what's actually present.
class SaveData {
  final int generation;
  final String versionId; // the game it was parsed as (e.g. "emerald")

  /// National-dex ids flagged as owned/caught.
  final Set<int> caughtDex;
  final int seenCount;

  /// Number of badges earned (null if not read for this format).
  final int? badgeCount;

  final List<SaveTeamMon> team;

  final String? trainerName;
  final int? trainerId;

  /// Gen 3 hidden "secret ID" (null if not read for this format).
  final int? secretId;
  final int? money;
  final Duration? playTime;

  /// Notes surfaced to the user (e.g. "team not read for this format yet").
  final List<String> notes;

  const SaveData({
    required this.generation,
    required this.versionId,
    this.caughtDex = const {},
    this.seenCount = 0,
    this.badgeCount,
    this.team = const [],
    this.trainerName,
    this.trainerId,
    this.secretId,
    this.money,
    this.playTime,
    this.notes = const [],
  });

  int get caughtCount => caughtDex.length;

  String get playTimeText {
    final t = playTime;
    if (t == null) return '';
    final h = t.inHours;
    final m = t.inMinutes % 60;
    return '${h}h ${m}m';
  }
}

/// Thrown when a save can't be read (wrong size, unsupported format, etc.).
class SaveParseException implements Exception {
  final String message;
  const SaveParseException(this.message);
  @override
  String toString() => message;
}

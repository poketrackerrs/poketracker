/// One cheat code for the built-in player. [code] is the raw code text
/// (GameShark / Action Replay / CodeBreaker for GBA; Action Replay DS for NDS),
/// one line per line — the core auto-detects the format. [builtIn] marks a code
/// that ships with the app (from assets/config/cheats.json) vs one the user
/// added. [enabled] is whether it's currently applied.
class Cheat {
  final String name;
  final String code;
  final bool builtIn;
  bool enabled;

  Cheat({
    required this.name,
    required this.code,
    this.builtIn = false,
    this.enabled = false,
  });

  /// Stable per-game key used to persist the enabled flag and to de-dupe.
  String get key => '${builtIn ? 'b' : 'u'}:$name';

  Map<String, dynamic> toJson() => {'name': name, 'code': code};

  factory Cheat.fromJson(Map<String, dynamic> j, {bool builtIn = false}) =>
      Cheat(
        name: '${j['name'] ?? ''}',
        code: '${j['code'] ?? ''}',
        builtIn: builtIn,
      );
}

import 'dart:convert';
import 'dart:typed_data';

/// One Pokémon stored in the app-side Vault — a game-independent 80-byte PK3
/// block plus cached display fields. The block is what gets injected/cloned
/// into a game; the rest is just for showing it in the list.
class VaultMon {
  /// The Pokémon's native boxed block: an 80-byte PK3 for [gen] 3, a 136-byte
  /// PK4 for gen 4, a 136-byte PK5 for gen 5, etc. Stored in its own format and
  /// converted on withdraw when the target game is a later generation.
  final Uint8List block;
  final int gen; // source generation (3, 4, 5 …) — defaults to 3 for old entries
  final int dex; // National dex
  final String name;
  final int level;
  final bool shiny;
  final String origin; // title of the game it was pulled from ('' if unknown)

  VaultMon({
    required this.block,
    this.gen = 3,
    required this.dex,
    required this.name,
    required this.level,
    required this.shiny,
    this.origin = '',
  });

  Map<String, dynamic> toJson() => {
        'b': base64Encode(block),
        'g': gen,
        'd': dex,
        'n': name,
        'l': level,
        's': shiny,
        'o': origin,
      };

  factory VaultMon.fromJson(Map<String, dynamic> m) => VaultMon(
        block: base64Decode(m['b'] as String),
        gen: (m['g'] as int?) ?? 3, // pre-gen entries were all Gen 3
        dex: (m['d'] as int?) ?? 0,
        name: (m['n'] as String?) ?? '#${m['d']}',
        level: (m['l'] as int?) ?? 0,
        shiny: (m['s'] as bool?) ?? false,
        origin: (m['o'] as String?) ?? '',
      );
}

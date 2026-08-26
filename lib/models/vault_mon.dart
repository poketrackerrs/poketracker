import 'dart:convert';
import 'dart:typed_data';

/// One Pokémon stored in the app-side Vault — a game-independent 80-byte PK3
/// block plus cached display fields. The block is what gets injected/cloned
/// into a game; the rest is just for showing it in the list.
class VaultMon {
  final Uint8List block; // 80-byte boxed PK3
  final int dex; // National dex
  final String name;
  final int level;
  final bool shiny;

  VaultMon({
    required this.block,
    required this.dex,
    required this.name,
    required this.level,
    required this.shiny,
  });

  Map<String, dynamic> toJson() => {
        'b': base64Encode(block),
        'd': dex,
        'n': name,
        'l': level,
        's': shiny,
      };

  factory VaultMon.fromJson(Map<String, dynamic> m) => VaultMon(
        block: base64Decode(m['b'] as String),
        dex: (m['d'] as int?) ?? 0,
        name: (m['n'] as String?) ?? '#${m['d']}',
        level: (m['l'] as int?) ?? 0,
        shiny: (m['s'] as bool?) ?? false,
      );
}

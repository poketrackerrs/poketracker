import 'dart:typed_data';

import 'pk3.dart';
import 'gen4_pkx.dart';
import 'pokedex_service.dart';

/// Cross-generation Pokémon transfer, replicating the official transforms so a
/// legitimately-caught Pokémon stays legal all the way up (Pal Park, then
/// Poké Transfer). It cannot make an illegal Pokémon legal — HOME checks the
/// encounter data server-side.

/// Gen 3 → Gen 4 via **Pal Park**: an 80-byte PK3 box block becomes a 136-byte
/// PK4 box block. Pal Park sets met location = Pal Park (55) and met level = the
/// Pokémon's level at transfer, strips any held item (you can't transfer a
/// Pokémon that's holding something), and keeps PID/IVs/nature/shiny/gender/OT.
Future<Uint8List> palParkGen3ToGen4(
    Uint8List pk3Block, PokedexService pokedex) async {
  final m = Pk3.decode(pk3Block);
  final dex = m.nationalDex;
  final detail = await pokedex.fetchDetail(dex);
  final growth = await pokedex.growthRate(dex);
  final level = gen3LevelFromExp(growth, m.exp);

  // Ability: Gen 3 picks the slot by PID bit 0; Gen 4 stores the ability id.
  final abils = detail.abilities;
  final slot = m.pid & 1;
  final abilityId = abils.isEmpty
      ? 0
      : (slot < abils.length ? abils[slot] : abils.first).id;

  final gender = gen3GenderOf(m.pid, detail.genderRate);

  // Base PP for each move (0 for empty slots).
  final pp = <int>[];
  for (final mv in m.moves) {
    pp.add(mv == 0 ? 0 : await pokedex.movePP(mv));
  }

  // Nicknamed if the Gen 3 nickname isn't just the species name.
  final nicknamed =
      m.nickname.trim().toUpperCase() != detail.name.trim().toUpperCase();

  final pk4 = Pkx.create(
    species: dex,
    pid: m.pid,
    tid: m.otid & 0xFFFF,
    sid: (m.otid >> 16) & 0xFFFF,
    exp: m.exp,
    moves: m.moves,
    pp: pp,
    ivs: m.ivs,
    ability: abilityId,
    nickname: m.nickname,
    otName: m.otName,
    heldItem: 0, // Pal Park requires an empty hand
    ball: m.ball == 0 ? 4 : m.ball, // keep the ball it was caught in
    metLocation: 55, // Pal Park (DP location table)
    metLevel: level,
    otGender: m.otGender,
    gender: gender,
    language: m.language == 0 ? 2 : m.language,
    friendship: m.friendship,
    // Pal Park keeps the Gen 3 game of origin (Sapphire 1 … LeafGreen 5), which
    // uses the same values in Gen 4's hometown byte.
    originGame:
        (m.gameOfOrigin >= 1 && m.gameOfOrigin <= 5) ? m.gameOfOrigin : 3,
    fateful: m.fatefulEncounter,
    nicknamed: nicknamed,
  );
  pk4.setEVs(m.evs);
  return Uint8List.fromList(pk4.encode());
}

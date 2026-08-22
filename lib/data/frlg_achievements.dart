import '../models/achievement.dart';

/// Evaluation context for a FireRed/LeafGreen achievement's auto-unlock check.
class AchContext {
  final int badges; // 0..8, in gym order
  final bool champion;
  final Set<int> caught; // national-dex ids owned (from the save's caught dex)
  final int caughtCount;
  const AchContext({
    required this.badges,
    required this.champion,
    required this.caught,
    required this.caughtCount,
  });
  bool has(int id) => caught.contains(id);
}

/// One FRLG achievement definition.
/// - [auto]: unlocked from tracked data (badges/champion/caught-dex).
/// - [flags]: unlocked when ANY of these save event-flag numbers is set
///   (rival/gym/Rocket battles use TRAINER_FLAGS_START + trainerId; story
///   beats use their event-flag numbers). Read live from the save.
/// - neither: a manual tap-to-check achievement (challenge runs, most trades).
class FrlgAch {
  final String id;
  final String title;
  final String description;
  final int points;
  final AchGroup group;
  final bool Function(AchContext)? auto;
  final List<int>? flags;
  const FrlgAch(this.id, this.title, this.description, this.points, this.group,
      {this.auto, this.flags});
  bool get isManual => auto == null && flags == null;
}

// pokefirered: defeating trainer N sets event flag TRAINER_FLAGS_START + N.
const int _tf = 0x500;
// The game-clear (became Champion) system flag.
const int kFrlgGameClearFlag = 0x82C;

// The RetroAchievements "Base Set" for Pokémon FireRed (used as a curated
// source; nothing is synced to RetroAchievements). Auto-unlocks map to badge
// order, the champion milestone, the save's caught-dex, and save event flags
// (rival/Rocket/story beats). Challenge runs, in-game trades and Trainer Tower
// stay as manual check-offs.
final List<FrlgAch> kFrlgAchievements = [
  // --- Progression: rival / gyms / rockets / story ---
  FrlgAch('frlg-rival-1', 'I Choose You!',
      "Defeat your rival in Professor Oak's Lab.", 1, AchGroup.progression,
      flags: [_tf + 326, _tf + 327, _tf + 328]),
  FrlgAch('frlg-rival-r22', 'Champ In The Making!',
      'Win the optional battle against your rival on Route 22.', 5,
      AchGroup.progression,
      flags: [_tf + 329, _tf + 330, _tf + 331]),
  FrlgAch('frlg-brock', 'The Rock-Solid Trainer!',
      'Defeat Brock and earn the Boulder Badge.', 5, AchGroup.progression,
      auto: (c) => c.badges >= 1),
  FrlgAch('frlg-brock-challenge', 'A Rocky Battle',
      'Defeat Brock in Set Mode using 2 or fewer Pokémon at level 14 or less.',
      10, AchGroup.progression),
  FrlgAch('frlg-rival-cerulean', 'Always Plodding Behind',
      'Defeat your rival in Cerulean City.', 5, AchGroup.progression,
      flags: [_tf + 332, _tf + 333, _tf + 334]),
  FrlgAch('frlg-misty', 'The Tomboyish Mermaid!',
      'Defeat Misty and earn the Cascade Badge.', 5, AchGroup.progression,
      auto: (c) => c.badges >= 2),
  FrlgAch('frlg-misty-challenge', 'Stealing the Star',
      'Defeat Misty in Set Mode using 2 or fewer Pokémon at level 21 or less.',
      10, AchGroup.progression),
  FrlgAch('frlg-rival-ssanne', 'Smell Ya Later!',
      'Defeat your rival on the S.S. Anne.', 5, AchGroup.progression,
      flags: [_tf + 426, _tf + 427, _tf + 428]),
  FrlgAch('frlg-surge', 'The Lightning American!',
      'Defeat Lt. Surge and earn the Thunder Badge.', 5, AchGroup.progression,
      auto: (c) => c.badges >= 3),
  FrlgAch('frlg-surge-challenge', 'Dodging Thunderbolts',
      'Defeat Lt. Surge in Set Mode using 3 or fewer Pokémon at level 24 or less.',
      10, AchGroup.progression),
  FrlgAch('frlg-rival-tower', 'Make Them Faint!',
      'Defeat your rival in the Pokémon Tower.', 5, AchGroup.progression,
      flags: [_tf + 429, _tf + 430, _tf + 431]),
  FrlgAch('frlg-erika', 'The Nature-Loving Princess!',
      'Defeat Erika and earn the Rainbow Badge.', 5, AchGroup.progression,
      auto: (c) => c.badges >= 4),
  FrlgAch('frlg-erika-challenge', 'Plants are no Problem',
      'Defeat Erika in Set Mode using 3 or fewer Pokémon at level 29 or less.',
      10, AchGroup.progression),
  FrlgAch('frlg-rocket-celadon', 'Rigged Slots',
      'Stop Team Rocket in Celadon City.', 5, AchGroup.progression,
      flags: [_tf + 348]),
  FrlgAch('frlg-koga', 'The Poisonous Ninja Master!',
      'Defeat Koga and earn the Soul Badge.', 5, AchGroup.progression,
      auto: (c) => c.badges >= 5),
  FrlgAch('frlg-koga-challenge', "Don't Get Poisoned",
      'Defeat Koga in Set Mode using 4 or fewer Pokémon at level 43 or less.',
      10, AchGroup.progression),
  FrlgAch('frlg-rival-saffron', "Don't Sweat It!",
      'Defeat your rival in Saffron City.', 5, AchGroup.progression,
      flags: [_tf + 432, _tf + 433, _tf + 434]),
  FrlgAch('frlg-rocket-saffron', "One Ball to Catch 'em All",
      'Stop Team Rocket in Saffron City.', 10, AchGroup.progression,
      flags: [_tf + 349]),
  FrlgAch('frlg-sabrina', 'The Mistress of Psychic Pokemon!',
      'Defeat Sabrina and earn the Marsh Badge.', 5, AchGroup.progression,
      auto: (c) => c.badges >= 6),
  FrlgAch('frlg-sabrina-challenge', 'Her Psychic Powers Are Not Strong Enough',
      'Defeat Sabrina in Set Mode using 4 or fewer Pokémon at level 43 or less.',
      10, AchGroup.progression),
  FrlgAch('frlg-blaine', 'The Hotheaded Quiz Master!',
      'Defeat Blaine and earn the Volcano Badge.', 5, AchGroup.progression,
      auto: (c) => c.badges >= 7),
  FrlgAch('frlg-blaine-challenge', "When You're Hot, You're Hot",
      'Defeat Blaine in Set Mode using 4 or fewer Pokémon at level 47 or less.',
      10, AchGroup.progression),
  FrlgAch('frlg-lostelle', 'No Tears, Only Dreams',
      'Rescue Lostelle on Three Island.', 5, AchGroup.progression,
      flags: [0x2A3]),
  FrlgAch('frlg-giovanni', 'The Self-Proclaimed Strongest Trainer!',
      'Defeat Giovanni and earn the Earth Badge.', 5, AchGroup.progression,
      auto: (c) => c.badges >= 8),
  FrlgAch('frlg-giovanni-challenge', 'Well Grounded',
      'Defeat Giovanni in Set Mode using 5 or fewer Pokémon at level 50 or less.',
      10, AchGroup.progression),
  FrlgAch('frlg-rival-league', 'A Warm-Up!',
      'Defeat your rival on your way to the Pokémon League.', 5,
      AchGroup.progression,
      flags: [_tf + 435, _tf + 436, _tf + 437]),
  FrlgAch('frlg-champ-1', 'The Real Champ I', 'Become the League Champion.', 25,
      AchGroup.progression, flags: [kFrlgGameClearFlag]),
  FrlgAch('frlg-solo-1', 'Solo Mastery',
      'Defeat the first round of the Elite Four with only one Pokémon in your party.',
      25, AchGroup.progression),
  FrlgAch('frlg-lorelei', 'Helping Hand',
      'Help Lorelei in stopping Team Rocket on Island 4.', 5,
      AchGroup.progression,
      flags: [0x2D4]),
  FrlgAch('frlg-selphy', 'Resort Gorgeous', 'Rescue Selphy on Island 5.', 5,
      AchGroup.progression),
  FrlgAch('frlg-rocket-island5', 'Blasting Off Again',
      'Stop Team Rocket in their warehouse on Island 5.', 5,
      AchGroup.progression,
      flags: [0x2D5]),
  FrlgAch('frlg-champ-2', 'The Real Champ II',
      'Return stronger and become the League Champion again.', 25,
      AchGroup.progression),
  FrlgAch('frlg-solo-2', 'The True Solo Master',
      'Defeat the second round of the Elite Four with only one Pokémon in your party.',
      25, AchGroup.progression),
  // --- Collection: catches / legendaries / fossils / trades ---
  FrlgAch('frlg-mewtwo', 'Psyched!', 'Catch Mewtwo.', 10, AchGroup.collection,
      auto: (c) => c.has(150)),
  FrlgAch('frlg-tower-single', 'One at a Time',
      'Complete the Single Battle challenge at the Trainer Tower.', 5,
      AchGroup.collection),
  FrlgAch('frlg-tower-double', 'Seeing Double',
      'Complete the Double Battle challenge at the Trainer Tower.', 5,
      AchGroup.collection),
  FrlgAch('frlg-tower-knockout', 'Half the Pokémon, Thrice the Battles',
      'Complete the Knockout Battle challenge at the Trainer Tower.', 5,
      AchGroup.collection),
  FrlgAch('frlg-tower-mixed', 'Mix It All Up',
      'Complete the Mixed Battle challenge at the Trainer Tower.', 5,
      AchGroup.collection),
  FrlgAch('frlg-chansey', 'Lucky Egg', 'Catch a Chansey.', 5,
      AchGroup.collection, auto: (c) => c.has(113)),
  FrlgAch('frlg-articuno', 'Frozen Solid', 'Catch Articuno.', 5,
      AchGroup.collection, auto: (c) => c.has(144)),
  FrlgAch('frlg-zapdos', 'Zapped', 'Catch Zapdos.', 5, AchGroup.collection,
      auto: (c) => c.has(145)),
  FrlgAch('frlg-moltres', 'Molten', 'Catch Moltres.', 5, AchGroup.collection,
      auto: (c) => c.has(146)),
  FrlgAch('frlg-beasts', 'The Legendary Beasts',
      'Catch Raikou, Entei or Suicune.', 10, AchGroup.collection,
      auto: (c) => c.has(243) || c.has(244) || c.has(245)),
  FrlgAch('frlg-magikarp', 'Fishy Scam',
      "Buy the Magikarp from the man just outside Mt. Moon's Pokemon Center.", 3,
      AchGroup.collection),
  FrlgAch('frlg-fossil', 'Lord or Retainer',
      'Pick either the Helix Fossil or the Dome Fossil inside Mt. Moon.', 3,
      AchGroup.collection, auto: (c) => c.has(138) || c.has(140)),
  FrlgAch('frlg-trade-farfetchd', 'The Far-Fetched Trade',
      "Trade a Spearow for a Farfetch'd in Vermillion City.", 3,
      AchGroup.collection),
  FrlgAch('frlg-trade-nidoran', 'Baby Prince for a Baby Princess',
      'Trade a male Nidoran for a female Nidoran on Route 5.', 3,
      AchGroup.collection),
  FrlgAch('frlg-trade-mrmime', 'The Odd Mime',
      'Trade an Abra for a Mr. Mime on Route 2.', 3, AchGroup.collection),
  FrlgAch('frlg-oldamber', 'An Extinct Flying Type',
      'Obtain the Old Amber at the Pewter City Museum.', 3, AchGroup.collection,
      auto: (c) => c.has(142)),
  FrlgAch('frlg-eevee', 'Take Your Pick', 'Find the Eevee in Celadon City.', 3,
      AchGroup.collection, auto: (c) => c.has(133)),
  FrlgAch('frlg-snorlax', 'Sleeping Roadblock',
      'Catch a Snorlax on Route 12 or 16.', 5, AchGroup.collection,
      auto: (c) => c.has(143)),
  FrlgAch('frlg-trade-nidorina', 'Young King for a Young Queen',
      'Trade a Nidorino for a Nidorina on Route 11.', 3, AchGroup.collection),
  FrlgAch('frlg-dojo', 'Karate Master',
      'Defeat the Head of the Dojo in Saffron City.', 5, AchGroup.collection,
      auto: (c) => c.has(106) || c.has(107)),
  FrlgAch('frlg-lapras', 'The Transporter',
      'Obtain the Lapras in Silph Co. after defeating your rival.', 3,
      AchGroup.collection, auto: (c) => c.has(131)),
  FrlgAch('frlg-trade-lickitung', 'Long Lick of the Tongue',
      'Trade a Golduck for a Lickitung in the gate between Route 18 and Fuschia City.',
      3, AchGroup.collection),
  FrlgAch('frlg-trade-tangela', 'Tangled Mess',
      'Trade a Venonat for a Tangela on Cinnabar Island.', 3,
      AchGroup.collection),
  FrlgAch('frlg-trade-electrode', 'The Spherical Electric Type',
      'Trade a Raichu for an Electrode on Cinnabar Island.', 3,
      AchGroup.collection),
  FrlgAch('frlg-egg', 'New and Eggciting Things',
      'Obtain the Egg from the old man in the Water Labyrinth.', 5,
      AchGroup.collection, auto: (c) => c.has(175)),
  FrlgAch('frlg-trade-seel', 'Just Trying to Seel the Deal',
      'Trade a Ponyta for a Seel on Cinnabar Island.', 3, AchGroup.collection),
  FrlgAch('frlg-trade-jynx', 'Trying Not to Jynx Myself',
      'Trade a Poliwhirl for a Jynx in Cerulean City.', 3, AchGroup.collection),
  FrlgAch('frlg-catchem', "Gotta Catch 'em All: FireRed!",
      'Catch all 170 obtainable Pokémon.', 50, AchGroup.collection,
      auto: (c) => c.caughtCount >= 150),
];

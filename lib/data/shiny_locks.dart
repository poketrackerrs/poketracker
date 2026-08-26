// National-dex ids that are shiny-locked in each game (by version group).
// Shiny locking didn't exist until Gen 5, so Gens I–IV have no locks and are
// simply absent from this map (isShinyLocked returns false for them).
//
// Covers the established static/gift/box-legendary/Paradox locks. A handful of
// form-only locks (Cosplay Pikachu, Totems, Galarian Slowpoke, Bloodmoon
// Ursaluna) are intentionally omitted so their base species aren't mislabeled.
const Map<String, Set<int>> kShinyLockedByGroup = {
  // Gen 5 — only Victini.
  'black-white': {494},
  'black-2-white-2': {494},
  // Gen 6 — XY locks its box legends + Mewtwo + the birds; ORAS locks ~none.
  'x-y': {144, 145, 146, 150, 716, 717, 718},
  // Gen 7 — Cosmog line, Necrozma, event mythicals.
  'sun-moon': {789, 790, 791, 792, 800, 801},
  'ultra-sun-ultra-moon': {789, 790, 791, 792, 800, 802, 803, 807},
  // Gen 8 — SwSh box trio + DLC gifts/steeds + Keldeo + Cosmog.
  'sword-shield': {647, 789, 888, 889, 890, 891, 892, 896, 897, 898},
  // BDSP — save-data gifts + event mythicals (box legends are huntable).
  'brilliant-diamond-and-shining-pearl': {151, 385, 491, 492, 493},
  // Legends: Arceus — starters, Dialga/Palkia, Arceus, event mythicals.
  'legends-arceus': {
    155, 156, 157, 483, 484, 490, 491, 492, 493, 501, 502, 503, 722, 723, 724
  },
  // Legends: Z-A — gift/partner starters + Mewtwo.
  'legends-z-a': {1, 4, 7, 150, 152, 158},
  // Gen 9 — box legends, Treasures of Ruin, every Paradox mon, DLC.
  'scarlet-violet': {
    891, 984, 985, 986, 987, 988, 989, 990, 991, 992, 993, 994, 995, //
    1001, 1002, 1003, 1004, 1005, 1006, 1007, 1008, 1009, 1010, //
    1014, 1015, 1016, 1017, 1020, 1021, 1022, 1023, 1024, 1025
  },
};

/// True if [dex] can't be shiny in the given [versionGroup].
bool isShinyLocked(String versionGroup, int dex) =>
    kShinyLockedByGroup[versionGroup]?.contains(dex) ?? false;

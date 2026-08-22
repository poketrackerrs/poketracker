/// A known emulator the app can detect and link to.
class Emulator {
  final String name;
  final String systems; // human-readable systems/generations it covers
  final List<int> generations; // Pokemon generations it can play
  final List<String> exeNames; // executables to look for
  final List<String> hints; // install-folder name hints under Program Files etc.
  final List<String> androidPackages; // Android app package ids to detect
  final String downloadUrl; // official download page
  final String note;

  /// Whether the app can hand a ROM to this emulator via a launch (file intent
  /// on Android, CLI arg on desktop). Library-only emulators like Lemuroid have
  /// no external-launch support, so the Play button must not pick them.
  final bool launchable;

  const Emulator({
    required this.name,
    required this.systems,
    required this.generations,
    required this.exeNames,
    required this.hints,
    required this.downloadUrl,
    this.androidPackages = const [],
    this.note = '',
    this.launchable = true,
  });
}

/// Emulators relevant to the mainline + Legends Pokemon games.
const List<Emulator> kEmulators = [
  Emulator(
    name: 'mGBA',
    systems: 'Game Boy · Color · Advance',
    generations: [1, 2, 3],
    exeNames: ['mGBA.exe'],
    hints: ['mGBA'],
    // No official Android build exists; desktop only.
    androidPackages: [],
    downloadUrl: 'https://mgba.io/downloads.html',
    note: 'Best for Gen 1–3 (.gb / .gbc / .gba).',
  ),
  Emulator(
    name: 'My OldBoy!',
    systems: 'Game Boy · Color',
    generations: [1, 2],
    exeNames: [],
    hints: [],
    androidPackages: ['com.fastemulator.gbcfree', 'com.fastemulator.gbc'],
    downloadUrl:
        'https://play.google.com/store/apps/details?id=com.fastemulator.gbcfree',
    note: 'Android GB/GBC emulator; opens ROMs handed to it (one-tap launch).',
  ),
  Emulator(
    name: 'My Boy!',
    systems: 'Game Boy Advance',
    generations: [3],
    exeNames: [],
    hints: [],
    androidPackages: ['com.fastemulator.gbafree', 'com.fastemulator.gba'],
    downloadUrl:
        'https://play.google.com/store/apps/details?id=com.fastemulator.gbafree',
    note: 'Android GBA emulator; opens ROMs handed to it (one-tap launch).',
  ),
  Emulator(
    name: 'melonDS',
    systems: 'Nintendo DS',
    generations: [4, 5],
    exeNames: ['melonDS.exe'],
    hints: ['melonDS', 'melonDS-x64'],
    androidPackages: ['me.magnum.melonds'],
    downloadUrl: 'https://melonds.kuribo64.net/downloads.php',
    note: 'Accurate DS emulator for Gen 4–5 (.nds).',
  ),
  Emulator(
    name: 'DeSmuME',
    systems: 'Nintendo DS',
    generations: [4, 5],
    exeNames: ['DeSmuME.exe', 'DeSmuME_x64.exe'],
    hints: ['DeSmuME'],
    downloadUrl: 'https://desmume.org/download/',
    note: 'Alternative DS emulator for Gen 4–5 (.nds).',
  ),
  Emulator(
    name: 'Azahar',
    systems: 'Nintendo 3DS',
    generations: [6, 7],
    exeNames: ['azahar.exe', 'lime3ds.exe', 'citra-qt.exe'],
    hints: ['Azahar', 'Lime3DS', 'Citra'],
    androidPackages: [
      'org.azahar.azahar',
      'io.github.lime3ds.android',
      'org.citra.citra_emu',
    ],
    downloadUrl: 'https://azahar-emu.org/',
    note: 'Successor to Citra for Gen 6–7 (3DS). Detects Citra/Lime3DS too.',
  ),
  Emulator(
    name: 'Lemuroid',
    systems: 'Multi-system (GB → DS)',
    generations: [1, 2, 3, 4, 5],
    exeNames: [],
    hints: [],
    androidPackages: ['com.swordfish.lemuroid'],
    downloadUrl: 'https://play.google.com/store/apps/details?id=com.swordfish.lemuroid',
    note: 'Android all-in-one; plays GB/GBC/GBA/DS. Browse its own library — '
        'it can\'t be launched into directly, so use the Lemuroid folder sync.',
    launchable: false,
  ),
  Emulator(
    name: 'Pizza Boy (GBA/GBC)',
    systems: 'Game Boy · Color · Advance',
    generations: [1, 2, 3],
    exeNames: [],
    hints: [],
    androidPackages: [
      'it.dbtecno.pizzaboygba',
      'it.dbtecno.pizzaboygbapro',
      'it.dbtecno.pizzaboygbc',
      'it.dbtecno.pizzaboygbcpro',
    ],
    downloadUrl: 'https://play.google.com/store/apps/details?id=it.dbtecno.pizzaboygba',
    note: 'Maintained Android GB/GBC/GBA emulator.',
  ),
  Emulator(
    name: 'RetroArch',
    systems: 'Multi-system (GB → DS)',
    generations: [1, 2, 3, 4, 5],
    exeNames: ['retroarch.exe'],
    hints: ['RetroArch-Win64', 'RetroArch'],
    androidPackages: ['com.retroarch', 'com.retroarch.aarch64'],
    downloadUrl: 'https://www.retroarch.com/?page=platforms',
    note: 'All-in-one frontend; loads GB/GBC/GBA/DS via cores.',
  ),
];

/// A known emulator the app can detect and link to.
class Emulator {
  final String name;
  final String systems; // human-readable systems/generations it covers
  final List<int> generations; // Pokemon generations it can play
  final List<String> exeNames; // executables to look for
  final List<String> hints; // install-folder name hints under Program Files etc.
  final String downloadUrl; // official download page
  final String note;

  const Emulator({
    required this.name,
    required this.systems,
    required this.generations,
    required this.exeNames,
    required this.hints,
    required this.downloadUrl,
    this.note = '',
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
    downloadUrl: 'https://mgba.io/downloads.html',
    note: 'Best for Gen 1–3 (.gb / .gbc / .gba).',
  ),
  Emulator(
    name: 'melonDS',
    systems: 'Nintendo DS',
    generations: [4, 5],
    exeNames: ['melonDS.exe'],
    hints: ['melonDS', 'melonDS-x64'],
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
    downloadUrl: 'https://azahar-emu.org/',
    note: 'Successor to Citra for Gen 6–7 (3DS). Detects Citra/Lime3DS too.',
  ),
  Emulator(
    name: 'RetroArch',
    systems: 'Multi-system (GB → DS)',
    generations: [1, 2, 3, 4, 5],
    exeNames: ['retroarch.exe'],
    hints: ['RetroArch-Win64', 'RetroArch'],
    downloadUrl: 'https://www.retroarch.com/?page=platforms',
    note: 'All-in-one frontend; loads GB/GBC/GBA/DS via cores.',
  ),
];

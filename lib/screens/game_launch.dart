import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/game.dart';
import '../state/app_state.dart';
import 'emulator_screen.dart';
import 'emulators_screen.dart';

/// Launches [game]: opens the built-in emulator when the ROM can play in-app,
/// otherwise hands off to an installed external emulator. Shared by the console
/// shelf and the game detail page so "Play" behaves identically everywhere.
Future<void> launchGame(BuildContext context, Game game) async {
  final state = context.read<AppState>();
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);

  final builtInRom =
      state.canPlayBuiltIn(game) ? state.builtInRomPath(game) : null;
  if (builtInRom != null) {
    navigator.push(MaterialPageRoute(
        builder: (_) => EmulatorScreen(game: game, romPath: builtInRom)));
    return;
  }

  final outcome = await state.tryLaunchGame(game);
  if (!context.mounted) return;
  void toEmulators() => navigator.push(
      MaterialPageRoute(builder: (_) => const EmulatorsScreen()));
  switch (outcome) {
    case LaunchOutcome.launched:
      messenger.showSnackBar(
          SnackBar(content: Text('Launching ${game.title}…')));
    case LaunchOutcome.handoffFailed:
      final emu = state.emulatorNameFor(game) ?? 'the emulator';
      messenger.showSnackBar(SnackBar(
        content: Text(
            'Opened $emu, but it won\'t load ${game.title} automatically. '
            'Load it from inside $emu, or install My Boy!/My OldBoy! for '
            'one-tap launch.'),
        duration: const Duration(seconds: 7),
        action: SnackBarAction(label: 'Emulators', onPressed: toEmulators),
      ));
    case LaunchOutcome.noEmulator:
      messenger.showSnackBar(SnackBar(
        content: Text('No emulator found for ${game.title}.'),
        action: SnackBarAction(label: 'Emulators', onPressed: toEmulators),
      ));
  }
}

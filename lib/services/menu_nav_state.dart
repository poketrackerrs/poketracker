import 'package:flutter/foundation.dart';

/// When true, the global gamepad→menu-navigation bridge stops moving focus and
/// swallowing buttons — set while the in-game emulator is running so the
/// controller drives the game, not the menus behind it.
final ValueNotifier<bool> gGamepadMenuNavPaused = ValueNotifier<bool>(false);

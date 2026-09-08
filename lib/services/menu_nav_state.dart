import 'package:flutter/foundation.dart';

/// When true, the global gamepad→menu-navigation bridge stops moving focus and
/// swallowing buttons — set while the in-game emulator is running so the
/// controller drives the game, not the menus behind it.
final ValueNotifier<bool> gGamepadMenuNavPaused = ValueNotifier<bool>(false);

/// Registered by the root screen so the shoulder buttons / triggers can cycle
/// the bottom-nav tabs from the global gamepad bridge (delta −1 = previous tab,
/// +1 = next tab). Null when no screen with tabs is on top.
void Function(int delta)? gCycleTab;

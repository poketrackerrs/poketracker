// Remappable input bindings for the built-in emulator. Each binding maps to one
// keyboard key and one gamepad token. Bindings are the 10 GBA buttons plus
// emulator actions (fast-forward). Persisted in shared_preferences.
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:gamepads/gamepads.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'gba_emulator.dart';

/// Special binding id for the fast-forward action (no RetroPad button).
const String kFastForwardId = 'ffwd';

/// A bindable input. [retroId] is null for emulator actions like fast-forward.
class BindDef {
  final String id;
  final String label;
  final int? retroId;
  const BindDef(this.id, this.label, [this.retroId]);
}

const List<BindDef> kBindings = [
  BindDef('up', 'D-pad Up', retroUp),
  BindDef('down', 'D-pad Down', retroDown),
  BindDef('left', 'D-pad Left', retroLeft),
  BindDef('right', 'D-pad Right', retroRight),
  BindDef('a', 'A', retroA),
  BindDef('b', 'B', retroB),
  BindDef('l', 'L', retroL),
  BindDef('r', 'R', retroR),
  BindDef('start', 'Start', retroStart),
  BindDef('select', 'Select', retroSelect),
  BindDef(kFastForwardId, 'Fast-forward'),
];

/// Turns a gamepad event into a stable token. Buttons -> key name; strongly
/// deflected axes/triggers -> "key+" / "key-". Returns null for a neutral axis.
String? gamepadTokenFor(GamepadEvent e, {double axisThreshold = 0.6}) {
  final key = e.key.toLowerCase();
  if (e.type == KeyType.analog) {
    if (e.value > axisThreshold) return '$key+';
    if (e.value < -axisThreshold) return '$key-';
    return null;
  }
  return e.value.abs() > 0.5 ? key : null;
}

class ControlsConfig {
  static const _prefsKey = 'emu_controls_v2';

  /// bindingId -> keyboard LogicalKeyboardKey.keyId
  final Map<String, int> keyboard;

  /// bindingId -> gamepad token ('a', 'leftshoulder', 'righttrigger+', …)
  final Map<String, String> gamepad;

  ControlsConfig({required this.keyboard, required this.gamepad});

  factory ControlsConfig.defaults() => ControlsConfig(
        keyboard: {
          'up': LogicalKeyboardKey.arrowUp.keyId,
          'down': LogicalKeyboardKey.arrowDown.keyId,
          'left': LogicalKeyboardKey.arrowLeft.keyId,
          'right': LogicalKeyboardKey.arrowRight.keyId,
          'a': LogicalKeyboardKey.keyX.keyId,
          'b': LogicalKeyboardKey.keyZ.keyId,
          'l': LogicalKeyboardKey.keyA.keyId,
          'r': LogicalKeyboardKey.keyS.keyId,
          'start': LogicalKeyboardKey.enter.keyId,
          'select': LogicalKeyboardKey.backspace.keyId,
          kFastForwardId: LogicalKeyboardKey.tab.keyId,
        },
        gamepad: {
          'a': 'a',
          'b': 'b',
          'l': 'leftshoulder',
          'r': 'rightshoulder',
          'start': 'start',
          'select': 'back',
          'up': 'dpadup',
          'down': 'dpaddown',
          'left': 'dpadleft',
          'right': 'dpadright',
          kFastForwardId: 'righttrigger+',
        },
      );

  static Future<ControlsConfig> load() async {
    final defaults = ControlsConfig.defaults();
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return defaults;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final kb = Map<String, int>.from(defaults.keyboard);
      final gp = Map<String, String>.from(defaults.gamepad);
      (map['keyboard'] as Map?)?.forEach((k, v) => kb[k as String] = v as int);
      (map['gamepad'] as Map?)?.forEach((k, v) => gp[k as String] = v as String);
      return ControlsConfig(keyboard: kb, gamepad: gp);
    } catch (_) {
      return defaults;
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _prefsKey, jsonEncode({'keyboard': keyboard, 'gamepad': gamepad}));
  }

  void resetToDefaults() {
    final d = ControlsConfig.defaults();
    keyboard
      ..clear()
      ..addAll(d.keyboard);
    gamepad
      ..clear()
      ..addAll(d.gamepad);
  }

  int? retroIdFor(String bindingId) {
    for (final b in kBindings) {
      if (b.id == bindingId) return b.retroId;
    }
    return null;
  }

  /// Which binding a keyboard key triggers (a GBA button id or an action id).
  String? bindingIdForKey(LogicalKeyboardKey key) {
    for (final b in kBindings) {
      if (keyboard[b.id] == key.keyId) return b.id;
    }
    return null;
  }

  /// Applies a gamepad event to every matching binding via [set].
  void applyGamepad(GamepadEvent e, void Function(String bindingId, bool on) set) {
    final key = e.key.toLowerCase();
    for (final b in kBindings) {
      final token = gamepad[b.id];
      if (token == null) continue;
      if (token.endsWith('+') || token.endsWith('-')) {
        final base = token.substring(0, token.length - 1);
        if (base != key || e.type != KeyType.analog) continue;
        set(b.id, token.endsWith('+') ? e.value > 0.5 : e.value < -0.5);
      } else {
        if (token != key || e.type == KeyType.analog) continue;
        set(b.id, e.value.abs() > 0.5);
      }
    }
  }

  String keyboardLabel(String bindingId) {
    final id = keyboard[bindingId];
    if (id == null) return '—';
    final k = LogicalKeyboardKey(id);
    return k.debugName ?? k.keyLabel;
  }

  String gamepadLabel(String bindingId) => gamepad[bindingId] ?? '—';
}

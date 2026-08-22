import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gamepads/gamepads.dart';
import '../services/emulator_controls.dart';

/// Remap the built-in emulator's keyboard and gamepad bindings. Tap a cell,
/// then press the key / controller button you want bound to that GBA button.
class ControlsSettingsScreen extends StatefulWidget {
  final ControlsConfig config;
  const ControlsSettingsScreen({super.key, required this.config});

  @override
  State<ControlsSettingsScreen> createState() => _ControlsSettingsScreenState();
}

class _ControlsSettingsScreenState extends State<ControlsSettingsScreen> {
  final FocusNode _focus = FocusNode();
  StreamSubscription<GamepadEvent>? _padSub;
  String? _listeningKb; // gbaId awaiting a key press
  String? _listeningPad; // gbaId awaiting a controller input

  @override
  void initState() {
    super.initState();
    _padSub = Gamepads.events.listen(_onGamepad);
  }

  @override
  void dispose() {
    _padSub?.cancel();
    _focus.dispose();
    super.dispose();
  }

  void _startKb(String gbaId) {
    setState(() {
      _listeningPad = null;
      _listeningKb = gbaId;
    });
    _focus.requestFocus();
  }

  void _startPad(String gbaId) {
    setState(() {
      _listeningKb = null;
      _listeningPad = gbaId;
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final target = _listeningKb;
    if (target == null || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      setState(() => _listeningKb = null);
      return KeyEventResult.handled;
    }
    // ignore lone modifier presses
    final mods = <LogicalKeyboardKey>{
      LogicalKeyboardKey.shiftLeft,
      LogicalKeyboardKey.shiftRight,
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.controlRight,
      LogicalKeyboardKey.altLeft,
      LogicalKeyboardKey.altRight,
    };
    if (mods.contains(event.logicalKey)) return KeyEventResult.handled;
    widget.config.keyboard[target] = event.logicalKey.keyId;
    widget.config.save();
    setState(() => _listeningKb = null);
    return KeyEventResult.handled;
  }

  void _onGamepad(GamepadEvent e) {
    final target = _listeningPad;
    if (target == null) return;
    final token = gamepadTokenFor(e);
    if (token == null) return;
    widget.config.gamepad[target] = token;
    widget.config.save();
    setState(() => _listeningPad = null);
  }

  Widget _cell({
    required bool listening,
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(
        listening ? 'Press…' : label,
        overflow: TextOverflow.ellipsis,
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor:
            listening ? Theme.of(context).colorScheme.primary : null,
        minimumSize: const Size(120, 40),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cfg = widget.config;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Controls'),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                cfg.resetToDefaults();
                _listeningKb = null;
                _listeningPad = null;
              });
              cfg.save();
            },
            child: const Text('Reset'),
          ),
        ],
      ),
      body: Focus(
        focusNode: _focus,
        onKeyEvent: _onKey,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
              child: Text(
                'Tap a keyboard or controller cell, then press the input you want to bind to that button.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            for (final b in kBindings)
              Card(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 96,
                        child: Text(b.label,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(width: 8),
                      _cell(
                        listening: _listeningKb == b.id,
                        label: cfg.keyboardLabel(b.id),
                        icon: Icons.keyboard,
                        onTap: () => _startKb(b.id),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _cell(
                          listening: _listeningPad == b.id,
                          label: cfg.gamepadLabel(b.id),
                          icon: Icons.sports_esports,
                          onTap: () => _startPad(b.id),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

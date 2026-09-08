import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gamepads/gamepads.dart';

import '../services/menu_nav_state.dart';

/// Lets a game controller drive the app's *menus* (not just the in-game
/// emulator): the D-pad / left stick move focus, A activates the focused
/// control, B goes back. It wraps the whole app (via `MaterialApp.builder`) and
/// translates gamepad events into Flutter focus traversal, so existing buttons,
/// list tiles and tabs become controller-navigable without a redesign.
///
/// It pauses itself (via [gGamepadMenuNavPaused]) while the built-in emulator is
/// running, so gameplay input isn't stolen by the menus behind it. Button/axis
/// names differ across platforms (Apple's GameController uses `buttonA`,
/// `dpad - yAxis`; SDL-style desktop/Android use `a`, `dpadup`, `lefty`) — both
/// vocabularies are handled.
class GamepadMenuNavigator extends StatefulWidget {
  final Widget child;
  final GlobalKey<NavigatorState> navKey;
  const GamepadMenuNavigator(
      {super.key, required this.child, required this.navKey});

  @override
  State<GamepadMenuNavigator> createState() => _GamepadMenuNavigatorState();
}

enum _NavDir { up, down, left, right }

class _GamepadMenuNavigatorState extends State<GamepadMenuNavigator> {
  StreamSubscription<GamepadEvent>? _sub;

  // Per-axis sign (-1/0/1) for edge detection on analog dpad/sticks.
  final Map<String, int> _axis = {};
  // Held digital buttons, for edge detection.
  final Set<String> _down = {};
  // Auto-repeat while a direction is held.
  _NavDir? _heldDir;
  Timer? _repeat;

  static const double _thresh = 0.5;
  static const Map<_NavDir, TraversalDirection> _traversal = {
    _NavDir.up: TraversalDirection.up,
    _NavDir.down: TraversalDirection.down,
    _NavDir.left: TraversalDirection.left,
    _NavDir.right: TraversalDirection.right,
  };

  @override
  void initState() {
    super.initState();
    _sub = Gamepads.events.listen(_onEvent);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _stopRepeat();
    super.dispose();
  }

  void _onEvent(GamepadEvent e) {
    if (gGamepadMenuNavPaused.value) {
      _axis.clear();
      _down.clear();
      _stopRepeat();
      return;
    }
    final key = e.key.toLowerCase();
    if (e.type == KeyType.analog) {
      _handleAnalog(key, e.value);
    } else {
      _handleButton(key, e.value.abs() > 0.5);
    }
  }

  void _handleAnalog(String key, double value) {
    if (key.contains('trigger')) {
      // Analog triggers cycle the bottom-nav tabs (edge-detected: fire once per
      // pull). Rest at 0, pull toward 1.
      final pressed = value > _thresh ? 1 : 0;
      if ((_axis[key] ?? 0) == pressed) return;
      _axis[key] = pressed;
      if (pressed == 1) _cycleTab(key.contains('left') ? -1 : 1);
      return;
    }
    final sign = value > _thresh ? 1 : (value < -_thresh ? -1 : 0);
    if ((_axis[key] ?? 0) == sign) return; // no edge
    _axis[key] = sign;
    if (sign == 0) {
      _stopRepeat();
      return;
    }
    final dir = _dirForAxis(key, sign);
    if (dir == null) return;
    _move(dir);
    _startRepeat(dir);
  }

  void _handleButton(String key, bool down) {
    if (_down.contains(key) == down) return; // no edge
    if (down) {
      _down.add(key);
    } else {
      _down.remove(key);
    }
    if (!down) {
      if (_dirForButton(key) != null) _stopRepeat();
      return;
    }
    final dir = _dirForButton(key);
    if (dir != null) {
      _move(dir);
      _startRepeat(dir);
      return;
    }
    // Shoulder bumpers cycle the bottom-nav tabs (previous / next).
    if (key == 'leftshoulder') {
      _cycleTab(-1);
    } else if (key == 'rightshoulder') {
      _cycleTab(1);
    } else if (key == 'a' || key == 'buttona') {
      _activate();
    } else if (key == 'b' || key == 'buttonb') {
      _back();
    }
  }

  void _cycleTab(int delta) => gCycleTab?.call(delta);

  /// Maps an analog axis + sign to a direction. Only the vertical convention
  /// differs by vocabulary: Apple's `… - yAxis` is +up/−down; SDL `lefty` is
  /// −up/+down. Horizontal is +right/−left in both.
  _NavDir? _dirForAxis(String key, int sign) {
    final vertical = key.contains('yaxis') || key.endsWith('y');
    if (vertical) {
      final appleStyle = key.contains('yaxis'); // + = up
      if (appleStyle) return sign > 0 ? _NavDir.up : _NavDir.down;
      return sign < 0 ? _NavDir.up : _NavDir.down;
    }
    final horizontal = key.contains('xaxis') || key.endsWith('x');
    if (horizontal) return sign > 0 ? _NavDir.right : _NavDir.left;
    return null;
  }

  _NavDir? _dirForButton(String key) {
    switch (key) {
      case 'dpadup':
        return _NavDir.up;
      case 'dpaddown':
        return _NavDir.down;
      case 'dpadleft':
        return _NavDir.left;
      case 'dpadright':
        return _NavDir.right;
    }
    return null;
  }

  void _move(_NavDir dir) {
    // Show focus rings once a controller is in use, even on a touch device.
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    if (!mounted) return;
    final scope = FocusScope.of(context);
    final primary = FocusManager.instance.primaryFocus;
    final back = dir == _NavDir.up || dir == _NavDir.left;
    // Nothing focused yet (primary is just a scope) — grab the first control so
    // the very first press lands somewhere.
    if (primary == null || primary is FocusScopeNode) {
      back ? scope.previousFocus() : scope.nextFocus();
      return;
    }
    // Try geometric traversal; if it dead-ends (edge of a row/list), fall back
    // to linear order so you can still get to the next control (e.g. from the
    // last shelf down into the bottom nav).
    if (!primary.focusInDirection(_traversal[dir]!)) {
      back ? scope.previousFocus() : scope.nextFocus();
    }
  }

  void _activate() {
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx != null) Actions.maybeInvoke(ctx, const ActivateIntent());
  }

  void _back() => widget.navKey.currentState?.maybePop();

  void _startRepeat(_NavDir dir) {
    _heldDir = dir;
    _repeat?.cancel();
    // Wait, then auto-repeat so holding a direction scrolls a long list.
    _repeat = Timer(const Duration(milliseconds: 420), () {
      _repeat = Timer.periodic(const Duration(milliseconds: 130), (_) {
        if (gGamepadMenuNavPaused.value || _heldDir == null) {
          _stopRepeat();
          return;
        }
        _move(_heldDir!);
      });
    });
  }

  void _stopRepeat() {
    _heldDir = null;
    _repeat?.cancel();
    _repeat = null;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

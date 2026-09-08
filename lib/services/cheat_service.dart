import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/cheat.dart';

/// Loads/saves cheat codes per game. Built-in codes come from the bundled
/// `assets/config/cheats.json`; the user can add their own, and each code's
/// enabled flag is persisted. [enabledCodes] feeds `GbaEmulator.applyCheats`.
class CheatService {
  static Map<String, List<Map<String, dynamic>>>? _bundled;

  static Future<void> _ensureBundled() async {
    if (_bundled != null) return;
    try {
      final raw = await rootBundle.loadString('assets/config/cheats.json');
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final out = <String, List<Map<String, dynamic>>>{};
      map.forEach((k, v) {
        // Skip non-list entries (e.g. the "_comment" note) so one bad value
        // can't wipe the whole database.
        if (v is List) {
          out[k] =
              v.cast<Map>().map((e) => e.cast<String, dynamic>()).toList();
        }
      });
      _bundled = out;
    } catch (_) {
      _bundled = {};
    }
  }

  static Future<Set<String>> _enabledKeys(String gameId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('cheaton:$gameId') ?? '[]';
    try {
      return (jsonDecode(raw) as List).cast<String>().toSet();
    } catch (_) {
      return {};
    }
  }

  /// Every cheat for a game — bundled first, then user-added — with each one's
  /// current enabled flag.
  static Future<List<Cheat>> forGame(String gameId) async {
    await _ensureBundled();
    final prefs = await SharedPreferences.getInstance();
    final enabled = await _enabledKeys(gameId);
    final list = <Cheat>[];
    for (final j in _bundled![gameId] ?? const []) {
      final c = Cheat.fromJson(j, builtIn: true)..enabled = false;
      c.enabled = enabled.contains(c.key);
      list.add(c);
    }
    final userRaw = prefs.getString('usercheats:$gameId');
    if (userRaw != null) {
      try {
        for (final j in (jsonDecode(userRaw) as List).cast<Map>()) {
          final c = Cheat.fromJson(j.cast<String, dynamic>(), builtIn: false);
          c.enabled = enabled.contains(c.key);
          list.add(c);
        }
      } catch (_) {}
    }
    return list;
  }

  static Future<void> _saveUser(String gameId, List<Cheat> user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('usercheats:$gameId',
        jsonEncode(user.map((c) => c.toJson()).toList()));
  }

  /// Adds (or replaces, by name) a user cheat.
  static Future<void> addUserCheat(
      String gameId, String name, String code) async {
    final user = (await forGame(gameId)).where((c) => !c.builtIn).toList()
      ..removeWhere((c) => c.name == name)
      ..add(Cheat(name: name, code: code, builtIn: false));
    await _saveUser(gameId, user);
  }

  static Future<void> removeUserCheat(String gameId, String name) async {
    final user = (await forGame(gameId))
        .where((c) => !c.builtIn && c.name != name)
        .toList();
    await _saveUser(gameId, user);
    await _setEnabledKey(gameId, 'u:$name', false);
  }

  static Future<void> setEnabled(String gameId, Cheat cheat, bool on) =>
      _setEnabledKey(gameId, cheat.key, on);

  static Future<void> _setEnabledKey(
      String gameId, String key, bool on) async {
    final prefs = await SharedPreferences.getInstance();
    final set = await _enabledKeys(gameId);
    if (on) {
      set.add(key);
    } else {
      set.remove(key);
    }
    await prefs.setString('cheaton:$gameId', jsonEncode(set.toList()));
  }

  /// The raw code text of every enabled cheat — pass to applyCheats.
  static Future<List<String>> enabledCodes(String gameId) async {
    final all = await forGame(gameId);
    return all.where((c) => c.enabled).map((c) => c.code).toList();
  }
}

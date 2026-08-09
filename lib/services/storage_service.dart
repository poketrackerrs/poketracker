import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/progress.dart';

/// Persists all game progress as a single JSON blob in shared_preferences.
/// Works identically on Windows, Android, and web.
class StorageService {
  static const _key = 'poketracker_progress_v1';

  Future<Map<String, GameProgress>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return {};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map(
      (id, value) => MapEntry(
        id,
        GameProgress.fromJson(Map<String, dynamic>.from(value)),
      ),
    );
  }

  Future<void> save(Map<String, GameProgress> progress) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(
      progress.map((id, p) => MapEntry(id, p.toJson())),
    );
    await prefs.setString(_key, encoded);
  }
}

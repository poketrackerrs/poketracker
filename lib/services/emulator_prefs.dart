// Persisted playback preferences for the built-in emulator: audio volume,
// mute, and the fast-forward multiplier.
import 'package:shared_preferences/shared_preferences.dart';

/// Selectable fast-forward multipliers.
const List<int> kFfSpeeds = [2, 3, 4, 6, 8, 16];

/// DS landscape screen layouts (index persisted in [EmulatorPrefs.dsLayout]).
/// even = both equal side-by-side; topBig = large top + smaller touch beside it;
/// topFocus = top fills the area with the touch screen as a small corner inset.
enum DsLayout { even, topBig, topFocus }

const List<String> kDsLayoutNames = ['Even', 'Top priority', 'Top focus'];

class EmulatorPrefs {
  double volume; // 0.0 – 1.0
  bool muted;
  int ffSpeed;
  int dsLayout; // index into DsLayout.values

  EmulatorPrefs(
      {this.volume = 1.0,
      this.muted = false,
      this.ffSpeed = 6,
      this.dsLayout = 0});

  static const _key = 'emu_prefs_v1';

  double get effectiveVolume => muted ? 0.0 : volume.clamp(0.0, 1.0);

  DsLayout get dsLayoutMode =>
      DsLayout.values[dsLayout.clamp(0, DsLayout.values.length - 1)];

  static Future<EmulatorPrefs> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      return EmulatorPrefs(
        volume: p.getDouble('${_key}_vol') ?? 1.0,
        muted: p.getBool('${_key}_mute') ?? false,
        ffSpeed: p.getInt('${_key}_ff') ?? 6,
        dsLayout: p.getInt('${_key}_dslayout') ?? 0,
      );
    } catch (_) {
      return EmulatorPrefs();
    }
  }

  Future<void> save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setDouble('${_key}_vol', volume);
      await p.setBool('${_key}_mute', muted);
      await p.setInt('${_key}_ff', ffSpeed);
      await p.setInt('${_key}_dslayout', dsLayout);
    } catch (_) {}
  }
}

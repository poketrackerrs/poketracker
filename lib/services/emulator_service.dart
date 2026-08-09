import 'dart:io';
import '../data/emulators.dart';

/// One emulator plus where (if anywhere) it was found on this machine.
class DetectedEmulator {
  final Emulator emu;
  final String? path; // null => not installed
  const DetectedEmulator(this.emu, this.path);
  bool get installed => path != null;
}

/// Detects installed emulators (Windows-focused) and opens download pages.
class EmulatorService {
  Future<List<DetectedEmulator>> detectAll() async {
    final out = <DetectedEmulator>[];
    for (final e in kEmulators) {
      out.add(DetectedEmulator(e, await _find(e)));
    }
    return out;
  }

  Future<String?> _find(Emulator e) async {
    final sep = Platform.pathSeparator;
    final dirs = <String>[];
    void add(String? d) {
      if (d != null && d.isNotEmpty) dirs.add(d);
    }

    final env = Platform.environment;
    add(env['ProgramFiles']);
    add(env['ProgramFiles(x86)']);
    add(env['LOCALAPPDATA']);
    final la = env['LOCALAPPDATA'];
    if (la != null) add('$la${sep}Programs');
    // Common Steam location for mGBA / RetroArch.
    add('C:${sep}Program Files (x86)${sep}Steam${sep}steamapps${sep}common');

    for (final exe in e.exeNames) {
      // 1) On PATH?
      final onPath = await _which(exe);
      if (onPath != null) return onPath;

      // 2) In common install directories (directly or under a hint folder).
      for (final d in dirs) {
        final direct = File('$d$sep$exe');
        if (direct.existsSync()) return direct.path;
        for (final h in e.hints) {
          final nested = File('$d$sep$h$sep$exe');
          if (nested.existsSync()) return nested.path;
        }
      }
    }
    return null;
  }

  Future<String?> _which(String exe) async {
    try {
      final cmd = Platform.isWindows ? 'where' : 'which';
      final r = await Process.run(cmd, [exe]);
      if (r.exitCode == 0) {
        final line = (r.stdout as String)
            .split('\n')
            .map((l) => l.trim())
            .firstWhere((l) => l.isNotEmpty, orElse: () => '');
        if (line.isNotEmpty) return line;
      }
    } catch (_) {}
    return null;
  }

  /// Opens a URL (emulator download page) in the default browser.
  Future<void> openUrl(String url) async {
    if (Platform.isWindows) {
      await Process.start('explorer.exe', [url]);
    } else if (Platform.isMacOS) {
      await Process.start('open', [url]);
    } else if (Platform.isLinux) {
      await Process.start('xdg-open', [url]);
    }
  }

  /// Launches an installed emulator, optionally opening a ROM file.
  Future<void> launch(String emulatorPath, [String? romPath]) async {
    await Process.start(
      emulatorPath,
      romPath != null ? [romPath] : const [],
      mode: ProcessStartMode.detached,
    );
  }
}

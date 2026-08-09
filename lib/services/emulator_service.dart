import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
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
    final prefs = await SharedPreferences.getInstance();
    final out = <DetectedEmulator>[];
    for (final e in kEmulators) {
      final manual = prefs.getString('emupath:${e.name}');
      out.add(DetectedEmulator(e, await _find(e, manual)));
    }
    return out;
  }

  /// Saves a user-picked emulator executable path (from "Locate…").
  Future<void> setManualPath(String emulatorName, String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('emupath:$emulatorName', path);
  }

  Future<String?> _find(Emulator e, String? manualPath) async {
    // 1) User-specified path wins.
    if (manualPath != null && File(manualPath).existsSync()) return manualPath;

    final sep = Platform.pathSeparator;
    final env = Platform.environment;
    final dirs = <String>[];
    void add(String? d) {
      if (d != null && d.isNotEmpty) dirs.add(d);
    }

    add(env['ProgramFiles']);
    add(env['ProgramFiles(x86)']);
    add(env['LOCALAPPDATA']);
    final la = env['LOCALAPPDATA'];
    if (la != null) {
      add('$la${sep}Programs');
      add('$la${sep}Microsoft${sep}WinGet${sep}Links'); // winget shims
    }
    add(env['USERPROFILE']);
    final up = env['USERPROFILE'];
    if (up != null) {
      add('$up${sep}scoop${sep}shims'); // scoop
      add('$up${sep}Desktop');
      add('$up${sep}Downloads');
    }
    add('C:${sep}Program Files (x86)${sep}Steam${sep}steamapps${sep}common');
    add('C:${sep}ProgramData${sep}chocolatey${sep}bin');

    for (final exe in e.exeNames) {
      // 2) On PATH?
      final onPath = await _which(exe);
      if (onPath != null) return onPath;

      // 3) Registry App Paths (installers register the exe here).
      final regPath = await _regAppPath(exe);
      if (regPath != null) return regPath;

      // 4) Common install directories (directly or under a hint folder).
      for (final d in dirs) {
        final direct = File('$d$sep$exe');
        if (direct.existsSync()) return direct.path;
        for (final h in e.hints) {
          final nested = File('$d$sep$h$sep$exe');
          if (nested.existsSync()) return nested.path;
        }
      }
    }

    // 5) Registry uninstall InstallLocation for this emulator's name.
    final loc = await _regInstallLocation(e.name);
    if (loc != null) {
      for (final exe in e.exeNames) {
        final f = File('$loc$sep$exe');
        if (f.existsSync()) return f.path;
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

  /// Reads HKLM/HKCU App Paths for an executable and returns its full path.
  Future<String?> _regAppPath(String exe) async {
    if (!Platform.isWindows) return null;
    const roots = [
      r'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths',
      r'HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths',
      r'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths',
    ];
    for (final root in roots) {
      try {
        final r = await Process.run('reg', ['query', '$root\\$exe', '/ve']);
        if (r.exitCode == 0) {
          final m = RegExp(r'REG_SZ\s+(.+)').firstMatch(r.stdout as String);
          final path = m?.group(1)?.trim();
          if (path != null && File(path).existsSync()) return path;
        }
      } catch (_) {}
    }
    return null;
  }

  /// Searches uninstall entries for a display name and returns InstallLocation.
  Future<String?> _regInstallLocation(String name) async {
    if (!Platform.isWindows) return null;
    const roots = [
      r'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
      r'HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
      r'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    ];
    for (final root in roots) {
      try {
        // Find subkeys whose data mentions the emulator, then read their
        // InstallLocation.
        final r = await Process.run(
            'reg', ['query', root, '/s', '/f', name, '/d']);
        if (r.exitCode != 0) continue;
        final m = RegExp(r'InstallLocation\s+REG_SZ\s+(.+)')
            .firstMatch(r.stdout as String);
        final loc = m?.group(1)?.trim();
        if (loc != null && loc.isNotEmpty && Directory(loc).existsSync()) {
          return loc;
        }
      } catch (_) {}
    }
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

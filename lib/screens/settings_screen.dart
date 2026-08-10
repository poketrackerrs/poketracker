import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../data/region_theme.dart';
import '../state/app_state.dart';
import 'emulators_screen.dart';
import 'updates_screen.dart';

/// A recommended emulator link (store page or download page).
class _EmuLink {
  final String name;
  final String systems;
  final String url;
  const _EmuLink(this.name, this.systems, this.url);
}

// Android → Google Play pages (maintained, modern-Android compatible).
// Launchers first (the Play button boots ROMs straight into these), then
// Lemuroid, which is a library browser used via the folder sync below.
const _androidEmus = [
  _EmuLink('My OldBoy! Lite', 'Gen 1–2 · GB · GBC · one-tap launch',
      'https://play.google.com/store/apps/details?id=com.fastemulator.gbcfree'),
  _EmuLink('My Boy! Lite', 'Gen 3 · Game Boy Advance · one-tap launch',
      'https://play.google.com/store/apps/details?id=com.fastemulator.gbafree'),
  _EmuLink('melonDS', 'Gen 4–5 · Nintendo DS',
      'https://play.google.com/store/apps/details?id=me.magnum.melonds'),
  _EmuLink('Lemuroid', 'Library browser · GB → DS',
      'https://play.google.com/store/apps/details?id=com.swordfish.lemuroid'),
];

// iOS / iPadOS → App Store pages.
const _iosEmus = [
  _EmuLink('Delta', 'GB · GBC · GBA · DS · N64 · SNES',
      'https://apps.apple.com/us/app/delta-game-emulator/id1048524688'),
  _EmuLink('RetroArch', 'multi-system',
      'https://apps.apple.com/us/app/retroarch/id6499539433'),
];

// Windows → official download pages.
const _windowsEmus = [
  _EmuLink('mGBA', 'GB · GBC · GBA', 'https://mgba.io/downloads.html'),
  _EmuLink('melonDS', 'DS', 'https://melonds.kuribo64.net/downloads.php'),
  _EmuLink('DeSmuME', 'DS', 'https://desmume.org/download/'),
  _EmuLink('Azahar', '3DS', 'https://azahar-emu.org/'),
  _EmuLink('RetroArch', 'multi-system',
      'https://www.retroarch.com/?page=platforms'),
];

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _header(context, 'Appearance'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                  value: ThemeMode.system,
                  label: Text('System'),
                  icon: Icon(Icons.brightness_auto)),
              ButtonSegment(
                  value: ThemeMode.light,
                  label: Text('Light'),
                  icon: Icon(Icons.light_mode)),
              ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text('Dark'),
                  icon: Icon(Icons.dark_mode)),
            ],
            selected: {state.themeMode},
            onSelectionChanged: (s) =>
                context.read<AppState>().setThemeMode(s.first),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Text('Accent color',
                  style: Theme.of(context).textTheme.bodyMedium),
              const Spacer(),
              for (final c in kAccentChoices)
                GestureDetector(
                  onTap: () => context.read<AppState>().setAccent(c),
                  child: Container(
                    width: 28,
                    height: 28,
                    margin: const EdgeInsets.only(left: 10),
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: state.accent.toARGB32() == c.toARGB32()
                            ? Theme.of(context).colorScheme.onSurface
                            : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        SwitchListTile(
          title: const Text('Region color tinting'),
          subtitle: const Text(
              'Tint section headers and completion rings by region'),
          value: state.regionTint,
          onChanged: (v) => context.read<AppState>().setRegionTint(v),
        ),

        _header(context, 'Emulators'),
        ListTile(
          leading: const Icon(Icons.sports_esports),
          title: const Text('Detect installed emulators'),
          subtitle: const Text('Scan this device, or get one below'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const EmulatorsScreen()),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Text(
            _emuStoreBlurb(),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        for (final e in _emusForPlatform())
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: ListTile(
              leading: Icon(_platformIcon()),
              title: Text(e.name),
              subtitle: Text(e.systems),
              trailing: FilledButton.icon(
                icon: Icon(_storeButtonIcon(), size: 16),
                label: Text(_storeButtonLabel()),
                onPressed: () => context.read<AppState>().openExternal(e.url),
              ),
            ),
          ),
        if (!Platform.isWindows)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text(
              'Note: 3DS games (Gen 6–7) are best played on a desktop emulator '
              'like Azahar.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),

        _header(context, 'Game downloads'),
        ListTile(
          leading: const Icon(Icons.cloud_download),
          title: const Text('Link your Google Drive folder'),
          subtitle: const Text(
              'Paste your shared "Pokemon" folder link to turn on per-game '
              'download buttons on this device'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _importDrive(context),
        ),
        if (Platform.isAndroid)
          ListTile(
            leading: const Icon(Icons.drive_file_move),
            title: const Text('Sync games to Lemuroid folder'),
            subtitle: const Text(
                'Copy downloaded games to a shared folder so Lemuroid can '
                'scan them (Lemuroid can\'t be launched into directly)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _syncLemuroid(context),
          ),

        _header(context, 'Library'),
        ListTile(
          leading: const Icon(Icons.folder),
          title: const Text('Games folder'),
          subtitle: Text(state.libraryPath.isEmpty ? '…' : state.libraryPath),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh),
                onPressed: () => context.read<AppState>().refreshInstalled(),
              ),
              IconButton(
                tooltip: 'Open',
                icon: const Icon(Icons.open_in_new),
                onPressed: () => context.read<AppState>().openLibraryFolder(),
              ),
            ],
          ),
        ),

        _header(context, 'Updates'),
        ListTile(
          leading: const Icon(Icons.system_update),
          title: const Text('Check for updates'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const UpdatesScreen()),
          ),
        ),

        _header(context, 'About'),
        FutureBuilder<PackageInfo>(
          future: PackageInfo.fromPlatform(),
          builder: (context, snap) {
            final v = snap.hasData
                ? '${snap.data!.version}+${snap.data!.buildNumber}'
                : '…';
            return ListTile(
              leading: const Icon(Icons.catching_pokemon),
              title: const Text('PokeTracker'),
              subtitle: Text('Version $v'),
            );
          },
        ),
      ],
    );
  }

  Future<void> _importDrive(BuildContext context) async {
    final controller = TextEditingController();
    final link = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Link your Drive folder'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Paste the share link to your "Pokemon" Drive folder — the one '
              'that has a subfolder for each game. It must be shared '
              '"anyone with the link". This is stored only on this device.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'https://drive.google.com/drive/folders/…',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Link')),
        ],
      ),
    );
    if (link == null || link.isEmpty || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final state = context.read<AppState>();
    messenger.showSnackBar(
        const SnackBar(content: Text('Linking your Drive folder…')));
    try {
      final n = await state.importDriveSources(link);
      messenger.showSnackBar(SnackBar(
          content: Text(
              'Linked $n games — download buttons now appear on the Games tab.')));
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
          content: Text('$e'.replaceFirst('Exception: ', '')),
          duration: const Duration(seconds: 6)));
    }
  }

  Future<void> _syncLemuroid(BuildContext context) async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);

    // 1) Make sure we can write shared storage.
    if (!await state.lemuroidHasAccess()) {
      final granted = await state.lemuroidRequestAccess();
      if (!granted) {
        if (!context.mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Allow file access'),
            content: const Text(
                'PokeTracker needs "All files access" to place your games in a '
                'folder Lemuroid can scan.\n\nOn the screen that just opened, '
                'turn on "Allow access to manage all files" for PokeTracker, '
                'then come back and tap "Sync games to Lemuroid folder" again.'),
            actions: [
              FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('OK')),
            ],
          ),
        );
        return;
      }
    }

    // 2) Copy every downloaded ROM into the shared folder.
    messenger.showSnackBar(
        const SnackBar(content: Text('Syncing games to the Lemuroid folder…')));
    final count = await state.lemuroidSyncAll();
    final folder = await state.lemuroidFolder();
    if (!context.mounted) return;
    messenger.hideCurrentSnackBar();

    if (count == 0) {
      messenger.showSnackBar(const SnackBar(
          content: Text(
              'No downloaded games to sync yet. Download some first, then sync.')));
      return;
    }

    // 3) Tell the user exactly what to pick inside Lemuroid.
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$count game${count == 1 ? '' : 's'} ready for Lemuroid'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Your games are now in this folder:',
                style: TextStyle(fontSize: 13)),
            const SizedBox(height: 6),
            SelectableText(
              folder ?? 'PokeTracker',
              style: const TextStyle(
                  fontFamily: 'monospace', fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 14),
            const Text('In Lemuroid:', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 4),
            const Text(
              '1. Open Settings → Directories.\n'
              '2. Choose the "PokeTracker" folder above.\n'
              '3. Lemuroid scans it and your games appear.\n\n'
              'New downloads are copied here automatically.',
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Done')),
          FilledButton.icon(
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('Open Lemuroid'),
            onPressed: () {
              Navigator.pop(ctx);
              state.openExternal(
                  'https://play.google.com/store/apps/details?id=com.swordfish.lemuroid');
            },
          ),
        ],
      ),
    );
  }

  List<_EmuLink> _emusForPlatform() {
    if (Platform.isAndroid) return _androidEmus;
    if (Platform.isIOS) return _iosEmus;
    return _windowsEmus;
  }

  String _emuStoreBlurb() {
    if (Platform.isAndroid) return 'Get an emulator from Google Play:';
    if (Platform.isIOS) return 'Get an emulator from the App Store:';
    return 'Download an emulator for Windows:';
  }

  IconData _platformIcon() {
    if (Platform.isAndroid) return Icons.android;
    if (Platform.isIOS) return Icons.phone_iphone;
    return Icons.desktop_windows;
  }

  IconData _storeButtonIcon() =>
      (Platform.isAndroid || Platform.isIOS) ? Icons.shop : Icons.download;

  String _storeButtonLabel() {
    if (Platform.isAndroid) return 'Play Store';
    if (Platform.isIOS) return 'App Store';
    return 'Download';
  }

  Widget _header(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
        child: Text(
          text,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
        ),
      );
}

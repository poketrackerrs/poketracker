import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../data/region_theme.dart';
import '../state/app_state.dart';
import 'emulators_screen.dart';
import 'updates_screen.dart';

/// A recommended emulator for a given platform's app store.
class _StoreEmu {
  final String platform;
  final IconData icon;
  final String emulator;
  final String covers;
  final String url;
  const _StoreEmu(this.platform, this.icon, this.emulator, this.covers, this.url);
}

const _storeEmulators = [
  _StoreEmu('Android — Google Play', Icons.android, 'RetroArch',
      'GB · GBC · GBA · DS (via cores)',
      'https://play.google.com/store/apps/details?id=com.retroarch'),
  _StoreEmu('iOS / iPadOS — App Store', Icons.phone_iphone, 'Delta',
      'GB · GBC · GBA · DS',
      'https://apps.apple.com/us/app/delta-game-emulator/id1048524688'),
  _StoreEmu('Windows', Icons.desktop_windows, 'RetroArch',
      'GB · GBC · GBA · DS (via cores)',
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
          subtitle: const Text('Scan this PC and launch or install emulators'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const EmulatorsScreen()),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Text(
            'Get a recommended emulator for your device:',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        for (final e in _storeEmulators)
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: ListTile(
              leading: Icon(e.icon),
              title: Text('${e.platform}  •  ${e.emulator}'),
              subtitle: Text(e.covers),
              trailing: FilledButton.icon(
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Get'),
                onPressed: () => context.read<AppState>().openExternal(e.url),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Text(
            'Note: 3DS games (Gen 6–7) need a desktop emulator like Azahar — '
            'see "Detect installed emulators".',
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

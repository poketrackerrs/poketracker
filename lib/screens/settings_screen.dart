import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
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

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/game.dart';
import '../services/rom_patcher.dart';
import '../state/app_state.dart';
import 'game_launch.dart';

/// Your own ROMs + ROM hacks. Import a ROM directly, or apply an IPS/UPS/BPS
/// patch to a clean base ROM (you supply both — no downloads). The result is a
/// playable custom game in the built-in emulator. No dex/badge tracking yet.
class CustomGamesScreen extends StatefulWidget {
  const CustomGamesScreen({super.key});
  @override
  State<CustomGamesScreen> createState() => _CustomGamesScreenState();
}

class _CustomGamesScreenState extends State<CustomGamesScreen> {
  bool _busy = false;

  static const _romGroup =
      XTypeGroup(label: 'ROM', extensions: ['gb', 'gbc', 'gba', 'nds']);
  static const _patchGroup =
      XTypeGroup(label: 'Patch', extensions: ['ips', 'ups', 'bps']);

  static String _extOf(String name) {
    final dot = name.lastIndexOf('.');
    return dot >= 0 ? name.substring(dot + 1).toLowerCase() : 'gba';
  }

  static String _stripExt(String name) {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  static String _systemOf(int gen) => switch (gen) {
        1 => 'Game Boy',
        2 => 'Game Boy Color',
        4 => 'Nintendo DS',
        _ => 'Game Boy Advance',
      };

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 4)));
  }

  Future<void> _importRom() async {
    final state = context.read<AppState>();
    final file = await openFile(acceptedTypeGroups: [_romGroup]);
    if (file == null || !mounted) return;
    final title = await _askName(_stripExt(file.name));
    if (title == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final bytes = await file.readAsBytes();
      await state.addCustomGame(
          title: title, ext: _extOf(file.name), bytes: bytes);
      _snack('Added "$title".');
    } catch (e) {
      _snack('Could not import that ROM.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _applyPatch() async {
    final state = context.read<AppState>();
    final base = await openFile(acceptedTypeGroups: [_romGroup]);
    if (base == null || !mounted) return;
    final patch = await openFile(acceptedTypeGroups: [_patchGroup]);
    if (patch == null || !mounted) return;
    final title = await _askName(_stripExt(patch.name));
    if (title == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final baseBytes = await base.readAsBytes();
      final patchBytes = await patch.readAsBytes();
      final result = applyRomPatch(baseBytes, patchBytes);
      await state.addCustomGame(
          title: title, ext: _extOf(base.name), bytes: result.output);
      _snack('Applied ${result.format.label} patch'
          '${result.verified ? ' (checksum verified)' : ''} — added "$title".');
    } on RomPatchException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('Could not apply that patch.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askName(String initial) {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Name this game'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
              labelText: 'Name', border: OutlineInputBorder()),
          onSubmitted: (_) => Navigator.pop(ctx, ctrl.text.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Add')),
        ],
      ),
    );
  }

  void _addSheet() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.file_open),
              title: const Text('Import a ROM'),
              subtitle: const Text('Add your own .gb / .gbc / .gba / .nds'),
              onTap: () {
                Navigator.pop(context);
                _importRom();
              },
            ),
            ListTile(
              leading: const Icon(Icons.auto_fix_high),
              title: const Text('Apply a patch (ROM hack)'),
              subtitle:
                  const Text('Base ROM + .ips / .ups / .bps → playable hack'),
              onTap: () {
                Navigator.pop(context);
                _applyPatch();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _remove(Game g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove "${g.title}"?'),
        content: const Text('This deletes the ROM file from the app library.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (ok == true && mounted) {
      await context.read<AppState>().removeCustomGame(g.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final games = context.watch<AppState>().customGames;
    return Scaffold(
      appBar: AppBar(
        title: const Text('My games & ROM hacks'),
        actions: [
          IconButton(
            tooltip: 'Add',
            icon: const Icon(Icons.add),
            onPressed: _busy ? null : _addSheet,
          ),
        ],
      ),
      floatingActionButton: games.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _busy ? null : _addSheet,
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            ),
      body: Stack(
        children: [
          if (games.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.videogame_asset_outlined,
                        size: 56, color: Colors.grey),
                    const SizedBox(height: 16),
                    const Text(
                      'Add your own ROMs or ROM hacks.\n\nImport a ROM directly, '
                      'or apply an IPS/UPS/BPS patch to a clean base ROM you '
                      'supply — the patched game plays in the built-in emulator.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _busy ? null : _addSheet,
                      icon: const Icon(Icons.add),
                      label: const Text('Add a game'),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.separated(
              itemCount: games.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final g = games[i];
                return ListTile(
                  leading: const Icon(Icons.videogame_asset),
                  title: Text(g.title),
                  subtitle: Text(_systemOf(g.generation)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Play',
                        icon: const Icon(Icons.play_arrow),
                        onPressed: _busy ? null : () => launchGame(context, g),
                      ),
                      IconButton(
                        tooltip: 'Remove',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: _busy ? null : () => _remove(g),
                      ),
                    ],
                  ),
                  onTap: _busy ? null : () => launchGame(context, g),
                );
              },
            ),
          if (_busy)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x66000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import '../services/emulator_bios.dart';

/// Import screen for the Nintendo DS BIOS/firmware files. When all three are
/// present, the built-in melonDS player can boot encrypted retail DS ROMs.
class DsBiosScreen extends StatefulWidget {
  const DsBiosScreen({super.key});

  @override
  State<DsBiosScreen> createState() => _DsBiosScreenState();
}

class _DsBiosScreenState extends State<DsBiosScreen> {
  final _bios = EmulatorBios();
  final Map<String, int?> _sizes = {}; // slot.key -> file size (null = missing)
  String _sysDir = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    _sysDir = await _bios.sysDirPath();
    for (final s in kNdsBiosSlots) {
      _sizes[s.key] = await _bios.sizeOf(s);
    }
    if (mounted) setState(() {});
  }

  Future<void> _import(BiosSlot s) async {
    setState(() => _busy = true);
    try {
      final file = await openFile();
      if (file == null) return;
      final bytes = await file.readAsBytes();
      await _bios.importBytes(s, bytes);
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Imported ${s.fileName}')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(BiosSlot s) async {
    await _bios.remove(s);
    await _refresh();
  }

  bool _sizeOk(BiosSlot s, int? size) => size != null && s.sizes.contains(size);

  @override
  Widget build(BuildContext context) {
    final allPresent =
        kNdsBiosSlots.every((s) => _sizes[s.key] != null);
    return Scaffold(
      appBar: AppBar(title: const Text('Nintendo DS BIOS')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: (allPresent ? Colors.green : Colors.orange)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: (allPresent ? Colors.green : Colors.orange)
                      .withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                Icon(allPresent ? Icons.check_circle : Icons.info_outline,
                    color: allPresent ? Colors.green : Colors.orange),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    allPresent
                        ? 'All files present — encrypted DS ROMs will boot in '
                            'the built-in player.'
                        : 'Import all three files below to boot encrypted DS '
                            'ROMs. Decrypted ROMs already work without them.',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(
              'These are copyrighted Nintendo files and are NOT included with '
              'the app. Dump bios7.bin, bios9.bin and firmware.bin from your '
              'own Nintendo DS (e.g. with a homebrew BIOS dumper), then import '
              'each one here.',
              style: TextStyle(fontSize: 12, height: 1.4),
            ),
          ),
          for (final s in kNdsBiosSlots) _slotTile(s),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Stored in:\n$_sysDir',
                style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }

  Widget _slotTile(BiosSlot s) {
    final size = _sizes[s.key];
    final present = size != null;
    final ok = _sizeOk(s, size);
    final subtitle = !present
        ? 'Not imported · ${s.hint}'
        : ok
            ? '$size bytes · looks right'
            : '$size bytes · unexpected size (${s.hint})';
    return ListTile(
      leading: Icon(
        !present
            ? Icons.radio_button_unchecked
            : ok
                ? Icons.check_circle
                : Icons.warning_amber,
        color: !present
            ? null
            : ok
                ? Colors.green
                : Colors.orange,
      ),
      title: Text('${s.label}  (${s.fileName})'),
      subtitle: Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (present)
            IconButton(
              tooltip: 'Remove',
              icon: const Icon(Icons.delete_outline),
              onPressed: _busy ? null : () => _remove(s),
            ),
          FilledButton(
            onPressed: _busy ? null : () => _import(s),
            child: Text(present ? 'Replace' : 'Import'),
          ),
        ],
      ),
    );
  }
}

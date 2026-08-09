import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/emulator_service.dart';
import '../state/app_state.dart';

class EmulatorsScreen extends StatefulWidget {
  const EmulatorsScreen({super.key});

  @override
  State<EmulatorsScreen> createState() => _EmulatorsScreenState();
}

class _EmulatorsScreenState extends State<EmulatorsScreen> {
  final _service = EmulatorService();
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    // Re-scan on open so this and the Games tab share fresh, consistent state.
    WidgetsBinding.instance.addPostFrameCallback((_) => _rescan());
  }

  Future<void> _rescan() async {
    setState(() => _scanning = true);
    await context.read<AppState>().refreshEmulators();
    if (mounted) setState(() => _scanning = false);
  }

  @override
  Widget build(BuildContext context) {
    final list = context.watch<AppState>().detectedEmulators;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Emulators'),
        actions: [
          IconButton(
            tooltip: 'Rescan',
            icon: const Icon(Icons.refresh),
            onPressed: _scanning ? null : _rescan,
          ),
        ],
      ),
      body: (list.isEmpty && _scanning)
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    _scanning
                        ? 'Scanning…'
                        : 'Detected emulators on this PC. Install any you need, '
                            'then rescan.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                for (final d in list)
                  _EmulatorCard(detected: d, service: _service),
              ],
            ),
    );
  }
}

class _EmulatorCard extends StatelessWidget {
  final DetectedEmulator detected;
  final EmulatorService service;
  const _EmulatorCard({required this.detected, required this.service});

  Future<void> _locate(BuildContext context, String name) async {
    final controller = TextEditingController();
    final path = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Locate $name'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Paste the full path to the emulator executable, e.g.\n'
              'C:\\Program Files\\mGBA\\mGBA.exe',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: r'C:\...\emulator.exe',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (path != null && path.isNotEmpty && context.mounted) {
      await context.read<AppState>().setEmulatorPath(name, path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = detected.emu;
    final installed = detected.installed;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: installed
                  ? Colors.green.withValues(alpha: 0.15)
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Icon(
                installed ? Icons.check_circle : Icons.videogame_asset,
                color: installed ? Colors.green : Colors.grey,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.name,
                      style: Theme.of(context).textTheme.titleMedium),
                  Text(e.systems,
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Text(
                    installed ? 'Installed\n${detected.path}' : e.note,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: installed ? Colors.green : null,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            installed
                ? OutlinedButton(
                    onPressed: () => service.launch(detected.path!),
                    child: const Text('Open'),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FilledButton.icon(
                        onPressed: () => service.openUrl(e.downloadUrl),
                        icon: const Icon(Icons.download, size: 18),
                        label: const Text('Get'),
                      ),
                      TextButton.icon(
                        onPressed: () => _locate(context, e.name),
                        icon: const Icon(Icons.folder_open, size: 16),
                        label: const Text('Locate…'),
                      ),
                    ],
                  ),
          ],
        ),
      ),
    );
  }
}

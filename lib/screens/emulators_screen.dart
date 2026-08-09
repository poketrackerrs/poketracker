import 'package:flutter/material.dart';
import '../services/emulator_service.dart';

class EmulatorsScreen extends StatefulWidget {
  const EmulatorsScreen({super.key});

  @override
  State<EmulatorsScreen> createState() => _EmulatorsScreenState();
}

class _EmulatorsScreenState extends State<EmulatorsScreen> {
  final _service = EmulatorService();
  List<DetectedEmulator>? _emulators;

  @override
  void initState() {
    super.initState();
    _detect();
  }

  Future<void> _detect() async {
    setState(() => _emulators = null);
    final list = await _service.detectAll();
    if (!mounted) return;
    setState(() => _emulators = list);
  }

  @override
  Widget build(BuildContext context) {
    final list = _emulators;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Emulators'),
        actions: [
          IconButton(
            tooltip: 'Rescan',
            icon: const Icon(Icons.refresh),
            onPressed: _detect,
          ),
        ],
      ),
      body: list == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    'Detected emulators on this PC. Install any you need, then '
                    'rescan.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                for (final d in list) _EmulatorCard(detected: d, service: _service),
              ],
            ),
    );
  }
}

class _EmulatorCard extends StatelessWidget {
  final DetectedEmulator detected;
  final EmulatorService service;
  const _EmulatorCard({required this.detected, required this.service});

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
                : FilledButton.icon(
                    onPressed: () => service.openUrl(e.downloadUrl),
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text('Get'),
                  ),
          ],
        ),
      ),
    );
  }
}

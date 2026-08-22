import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/save_server.dart';

/// Developer tools (iPhone). Runs a local, token-guarded, read-only web server
/// so a dev machine on the same Wi-Fi can pull the device's saves/ROMs.
class DeveloperScreen extends StatefulWidget {
  const DeveloperScreen({super.key});
  @override
  State<DeveloperScreen> createState() => _DeveloperScreenState();
}

class _DeveloperScreenState extends State<DeveloperScreen> {
  final _server = SaveServer();
  String? _url;
  bool _busy = false;

  @override
  void dispose() {
    _server.stop();
    super.dispose();
  }

  Future<void> _toggle() async {
    setState(() => _busy = true);
    if (_server.running) {
      await _server.stop();
      setState(() {
        _url = null;
        _busy = false;
      });
      return;
    }
    await _server.start();
    await _server.lanIp();
    if (!mounted) return;
    setState(() {
      _url = _server.url;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final running = _server.running;
    return Scaffold(
      appBar: AppBar(title: const Text('Developer')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Save server',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 6),
          const Text(
            'Serve this device\'s saves & ROMs read-only over the local Wi-Fi '
            'so the paired Mac can pull them. Only reachable on your network, '
            'guarded by a one-time token, and only while this is on.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _busy ? null : _toggle,
            icon: Icon(running ? Icons.stop : Icons.play_arrow),
            label: Text(running ? 'Stop server' : 'Start server'),
          ),
          if (running && _url != null) ...[
            const SizedBox(height: 18),
            const Text('Server address',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            SelectableText(_url!,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _url!));
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Address copied')));
              },
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copy address'),
            ),
            const SizedBox(height: 14),
            const Text(
              'On the Mac:\n'
              '  curl "<address>/list"           → list files\n'
              '  curl "<address base>/get?t=…&path=REL" -o out.sav',
              style: TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ],
          if (running && _url == null)
            const Padding(
              padding: EdgeInsets.only(top: 14),
              child: Text('Started, but no Wi-Fi address found — '
                  'is the device on Wi-Fi?'),
            ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/games_data.dart';
import '../models/game.dart';
import '../state/app_state.dart';

/// Move a game's save between two devices on the same Wi-Fi. One device
/// **Receives** (shows an IP + code), the other **Sends** (enters them, picks a
/// game, uploads). The receiver backs up its existing save before overwriting.
class SaveTransferScreen extends StatelessWidget {
  const SaveTransferScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Transfer saves (Wi-Fi)'),
          bottom: const TabBar(tabs: [
            Tab(icon: Icon(Icons.download), text: 'Receive'),
            Tab(icon: Icon(Icons.upload), text: 'Send'),
          ]),
        ),
        body: const TabBarView(children: [_ReceiveTab(), _SendTab()]),
      ),
    );
  }
}

class _ReceiveTab extends StatefulWidget {
  const _ReceiveTab();
  @override
  State<_ReceiveTab> createState() => _ReceiveTabState();
}

class _ReceiveTabState extends State<_ReceiveTab> {
  String? _ip, _token, _error;
  bool _busy = false;

  Future<void> _start() async {
    setState(() => _busy = true);
    final r = await context.read<AppState>().startSaveReceiver();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r == null) {
        _error = 'Could not start — check you are on Wi-Fi.';
      } else {
        _error = null;
        _ip = r.ip;
        _token = r.token;
      }
    });
  }

  Future<void> _stop() async {
    await context.read<AppState>().stopSaveReceiver();
    if (mounted) setState(() => _ip = null);
  }

  @override
  void dispose() {
    // stop the server when leaving the screen
    context.read<AppState>().stopSaveReceiver();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Turn this on, then on your other device open Send and enter the '
            'IP and code shown here. Both devices must be on the same Wi-Fi.',
          ),
          const SizedBox(height: 20),
          if (_ip == null) ...[
            FilledButton.icon(
              onPressed: _busy ? null : _start,
              icon: const Icon(Icons.wifi_tethering),
              label: const Text('Start receiving'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!,
                    style: const TextStyle(color: Colors.red)),
              ),
          ] else ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Text('Waiting for a save…'),
                    const SizedBox(height: 12),
                    _bigField('IP address', _ip!),
                    const SizedBox(height: 8),
                    _bigField('Code', _token!),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: _stop, child: const Text('Stop')),
          ],
        ],
      ),
    );
  }

  Widget _bigField(String label, String value) => Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          SelectableText(value,
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 1)),
        ],
      );
}

class _SendTab extends StatefulWidget {
  const _SendTab();
  @override
  State<_SendTab> createState() => _SendTabState();
}

class _SendTabState extends State<_SendTab> {
  final _ip = TextEditingController();
  final _code = TextEditingController();
  Game? _game;
  bool _busy = false;
  String? _status;

  List<Game> get _installed {
    final s = context.read<AppState>();
    return [for (final g in kGames) if (s.isInstalled(g.id)) g];
  }

  Future<void> _send() async {
    if (_game == null) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    final msg = await context
        .read<AppState>()
        .sendSaveToPeer(_game!, _ip.text, _code.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = msg;
    });
  }

  @override
  void dispose() {
    _ip.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final installed = _installed;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Enter the IP and code from the other device (its Receive '
              'tab), pick the game, and send its save.'),
          const SizedBox(height: 16),
          TextField(
            controller: _ip,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'Receiver IP', hintText: 'e.g. 192.168.1.42'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _code,
            decoration: const InputDecoration(labelText: 'Code'),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<Game>(
            initialValue: _game,
            decoration: const InputDecoration(labelText: 'Game'),
            items: [
              for (final g in installed)
                DropdownMenuItem(value: g, child: Text(g.title)),
            ],
            onChanged: (g) => setState(() => _game = g),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: (_busy || _game == null) ? null : _send,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send),
            label: const Text('Send save'),
          ),
          if (installed.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text('No installed games with saves on this device.',
                  style: TextStyle(color: Colors.grey)),
            ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(_status!),
            ),
        ],
      ),
    );
  }
}

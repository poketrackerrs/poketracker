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
  bool _busy = false, _scanning = false, _manual = false;
  String? _status;
  List<({String ip, String name, String token})> _found = const [];
  ({String ip, String name, String token})? _picked;

  List<Game> get _installed {
    final s = context.read<AppState>();
    return [for (final g in kGames) if (s.isInstalled(g.id)) g];
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _status = null;
    });
    final r = await context.read<AppState>().discoverReceivers();
    if (!mounted) return;
    setState(() {
      _scanning = false;
      _found = r;
      if (r.length == 1) _picked = r.first;
      if (r.isEmpty) {
        _status = 'No devices found. Make sure the other device has its '
            'Receive tab open on the same Wi-Fi.';
      }
    });
  }

  Future<void> _send() async {
    if (_game == null) return;
    final host = _manual ? _ip.text : (_picked?.ip ?? '');
    final code = _manual ? _code.text : (_picked?.token ?? '');
    if (host.isEmpty || code.isEmpty) {
      setState(() => _status = 'Pick a device (or enter it manually) first.');
      return;
    }
    setState(() {
      _busy = true;
      _status = null;
    });
    final msg =
        await context.read<AppState>().sendSaveToPeer(_game!, host, code);
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
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Find the other device (it must have its Receive tab open '
            'on the same Wi-Fi), pick a game, and send.'),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _scanning ? null : _scan,
          icon: _scanning
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.wifi_find),
          label: Text(_scanning ? 'Searching…' : 'Find devices'),
        ),
        for (final d in _found)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.smartphone),
            title: Text(d.name),
            subtitle: Text(d.ip),
            trailing: _picked?.ip == d.ip
                ? const Icon(Icons.check_circle, color: Colors.green)
                : null,
            selected: _picked?.ip == d.ip,
            onTap: () => setState(() {
              _picked = d;
              _manual = false;
            }),
          ),
        const SizedBox(height: 6),
        DropdownButtonFormField<Game>(
          initialValue: _game,
          decoration: const InputDecoration(labelText: 'Game'),
          items: [
            for (final g in installed)
              DropdownMenuItem(value: g, child: Text(g.title)),
          ],
          onChanged: (g) => setState(() => _game = g),
        ),
        if (installed.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('No installed games with saves on this device.',
                style: TextStyle(color: Colors.grey)),
          ),
        const SizedBox(height: 16),
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
        if (_status != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(_status!),
          ),
        const Divider(height: 32),
        // Fallback: type it in if discovery can't reach the device.
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Enter manually',
              style: TextStyle(fontSize: 13, color: Colors.grey)),
          onExpansionChanged: (v) => setState(() => _manual = v),
          children: [
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
            const SizedBox(height: 8),
          ],
        ),
      ],
    );
  }
}

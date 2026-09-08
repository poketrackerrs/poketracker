import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/game_cast.dart';

/// Displays a game streamed from another PokeTracker on the LAN (the phone plays
/// + is the controller; this device is the big screen). Enter the address shown
/// on the playing device, then it paints the incoming frames full-screen.
class GameCastDisplayScreen extends StatefulWidget {
  const GameCastDisplayScreen({super.key});

  @override
  State<GameCastDisplayScreen> createState() => _GameCastDisplayScreenState();
}

class _GameCastDisplayScreenState extends State<GameCastDisplayScreen> {
  final _ipCtrl = TextEditingController();
  GameCastClient? _client;
  ui.Image? _frame;
  bool _connecting = false;
  String _status = '';

  bool get _live => _client != null;

  Future<void> _connect() async {
    final text = _ipCtrl.text.trim();
    if (text.isEmpty) return;
    var ip = text;
    var port = kGameCastPort;
    if (text.contains(':')) {
      final parts = text.split(':');
      ip = parts[0].trim();
      port = int.tryParse(parts[1].trim()) ?? kGameCastPort;
    }
    setState(() {
      _connecting = true;
      _status = 'Connecting to $ip:$port…';
    });
    final client = GameCastClient(
      onFrame: (img) {
        if (!mounted) {
          img.dispose();
          return;
        }
        setState(() {
          _frame?.dispose();
          _frame = img;
        });
      },
      onError: (_) {
        if (mounted) setState(() => _status = 'Connection error.');
      },
      onDone: () {
        if (mounted) {
          setState(() {
            _client = null;
            _status = 'Disconnected.';
          });
        }
      },
    );
    try {
      await client.connect(ip, port: port);
      if (!mounted) {
        await client.close();
        return;
      }
      setState(() {
        _client = client;
        _connecting = false;
        _status = 'Connected — waiting for video…';
      });
    } catch (e) {
      setState(() {
        _connecting = false;
        _status = 'Could not connect. Check the address and Wi-Fi.';
      });
    }
  }

  Future<void> _disconnect() async {
    await _client?.close();
    if (!mounted) return;
    setState(() {
      _client = null;
      _frame?.dispose();
      _frame = null;
      _status = 'Disconnected.';
    });
  }

  @override
  void dispose() {
    _client?.close();
    _frame?.dispose();
    _ipCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frame = _frame;
    if (_live && frame != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: const Text('Streaming'),
          actions: [
            TextButton.icon(
              onPressed: _disconnect,
              icon: const Icon(Icons.stop, color: Colors.white),
              label: const Text('Disconnect',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
        body: Center(
          child: RawImage(
            image: frame,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.none,
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Display a streamed game')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.cast, size: 48),
                const SizedBox(height: 16),
                Text(
                  'On the device that\'s playing, open the game, tap the Cast '
                  'button in the toolbar, and enter the address it shows here.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _ipCtrl,
                  autofocus: true,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Address',
                    hintText: 'e.g. 192.168.1.102',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.wifi),
                  ),
                  onSubmitted: (_) => _connect(),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _connecting ? null : _connect,
                  icon: _connecting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.play_arrow),
                  label: Text(_connecting ? 'Connecting…' : 'Connect'),
                ),
                if (_status.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(_status,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

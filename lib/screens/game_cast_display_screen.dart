import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import '../services/game_cast.dart';

/// Displays a game streamed from another PokeTracker on the LAN (the phone plays
/// + is the controller; this device is the big screen). Pick a discovered device
/// (or type its address), then it paints the incoming frames, scaled to fill the
/// window with an optional smoothing upscaler.
class GameCastDisplayScreen extends StatefulWidget {
  /// Prefill the address field (e.g. from auto-detect) …
  final String? initialAddress;

  /// … and connect to it immediately on open (the accept-cast popup uses this).
  final bool autoConnect;

  const GameCastDisplayScreen({
    super.key,
    this.initialAddress,
    this.autoConnect = false,
  });

  @override
  State<GameCastDisplayScreen> createState() => _GameCastDisplayScreenState();
}

class _GameCastDisplayScreenState extends State<GameCastDisplayScreen> {
  final _ipCtrl = TextEditingController();
  GameCastClient? _client;
  ui.Image? _frame;
  bool _connecting = false;
  bool _smooth = true; // upscaler: smooth (bilinear/cubic) vs sharp (nearest)
  bool _scanning = false;
  bool _muted = false;
  List<String> _found = const [];
  String _status = '';

  // Audio playback of the cast stream (mirrors the emulator's soloud setup).
  AudioSource? _pcmStream;
  bool _soloudReady = false;
  int _audioRate = 0;

  bool get _live => _client != null;

  @override
  void initState() {
    super.initState();
    _initAudio();
    if (widget.initialAddress != null) {
      _ipCtrl.text = widget.initialAddress!;
    }
    if (widget.autoConnect && widget.initialAddress != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
    }
  }

  Future<void> _initAudio() async {
    try {
      await SoLoud.instance.init();
      _soloudReady = true;
    } catch (_) {/* no audio device — video still works */}
  }

  void _onAudio(Uint8List pcm, int sampleRate) {
    if (!_soloudReady || _muted) return;
    var s = _pcmStream;
    if (s == null || _audioRate != sampleRate) {
      _teardownAudio();
      try {
        s = _pcmStream = SoLoud.instance.setBufferStream(
          format: BufferType.s16le,
          channels: Channels.stereo,
          sampleRate: sampleRate,
          maxBufferSizeBytes: 1024 * 1024 * 4,
          bufferingType: BufferingType.released,
          bufferingTimeNeeds: 0.2,
        );
        _audioRate = sampleRate;
        SoLoud.instance.play(s);
      } catch (_) {
        return;
      }
    }
    try {
      SoLoud.instance.addAudioDataStream(s, pcm);
    } catch (_) {/* buffer hiccup — drop this chunk */}
  }

  void _teardownAudio() {
    final s = _pcmStream;
    _pcmStream = null;
    _audioRate = 0;
    if (s != null) {
      try {
        SoLoud.instance.disposeSource(s);
      } catch (_) {}
    }
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _status = 'Looking for devices casting on this Wi-Fi…';
    });
    final hosts = await discoverGameCastHosts();
    if (!mounted) return;
    setState(() {
      _scanning = false;
      _found = hosts;
      _status = hosts.isEmpty
          ? 'No casting devices found. Make sure the phone is casting and on '
              'the same Wi-Fi.'
          : '';
    });
  }

  Future<void> _connect([String? address]) async {
    final text = (address ?? _ipCtrl.text).trim();
    if (text.isEmpty) return;
    if (address != null) _ipCtrl.text = address;
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
      onAudio: _onAudio,
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
    _teardownAudio();
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
    _teardownAudio();
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
            IconButton(
              tooltip: _muted ? 'Sound: Off' : 'Sound: On',
              icon: Icon(_muted ? Icons.volume_off : Icons.volume_up,
                  color: Colors.white),
              onPressed: () {
                setState(() => _muted = !_muted);
                if (_muted) _teardownAudio();
              },
            ),
            IconButton(
              tooltip: _smooth ? 'Upscaler: Smooth' : 'Upscaler: Sharp',
              icon: Icon(_smooth ? Icons.blur_on : Icons.grid_on,
                  color: Colors.white),
              onPressed: () => setState(() => _smooth = !_smooth),
            ),
            TextButton.icon(
              onPressed: _disconnect,
              icon: const Icon(Icons.stop, color: Colors.white),
              label: const Text('Disconnect',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
        // AspectRatio inside Center fills the window while keeping the frame's
        // shape; RawImage(fit: fill) then samples to that size with the chosen
        // upscaler quality (none = crisp pixels, high = smooth).
        body: Center(
          child: AspectRatio(
            aspectRatio: frame.width / frame.height,
            child: RawImage(
              image: frame,
              fit: BoxFit.fill,
              filterQuality:
                  _smooth ? FilterQuality.high : FilterQuality.none,
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Display a streamed game')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.cast, size: 48),
                const SizedBox(height: 16),
                Text(
                  'On the device that\'s playing, open the game and tap the Cast '
                  'button in the toolbar. Then pick it below, or enter the '
                  'address it shows.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: _scanning ? null : _scan,
                  icon: _scanning
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.search),
                  label: Text(_scanning ? 'Scanning…' : 'Find devices'),
                ),
                if (_found.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  for (final ip in _found)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.smartphone),
                        title: Text(ip),
                        subtitle: const Text('Casting on this network'),
                        trailing: const Icon(Icons.play_arrow),
                        onTap: () => _connect(ip),
                      ),
                    ),
                ],
                const SizedBox(height: 16),
                const Row(children: [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('or', style: TextStyle(color: Colors.grey)),
                  ),
                  Expanded(child: Divider()),
                ]),
                const SizedBox(height: 16),
                TextField(
                  controller: _ipCtrl,
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
                  onPressed: _connecting ? null : () => _connect(),
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

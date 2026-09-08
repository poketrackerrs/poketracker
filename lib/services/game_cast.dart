import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Streams the built-in player's video to another PokeTracker instance on the
/// same Wi-Fi ("cast the game to my PC"). The HOST (the device playing) runs a
/// WebSocket server and pushes RGBA frames; a CLIENT connects and paints them.
/// Input stays on the host, so this is one-way video — the lowest-latency setup.
///
/// Wire format (binary WebSocket messages), two packet kinds by byte 0:
///   VIDEO  0x46 'F' : [1..2] width u16 LE, [3..4] height u16 LE,
///                     [5..] width*height*4 RGBA8888 pixels
///   AUDIO  0x41 'A' : [1..4] sampleRate u32 LE,
///                     [5..] int16 stereo little-endian PCM
const int kGameCastPort = 8724;

/// HOST side: a WebSocket server that fan-outs frames to connected displays.
class GameCastHost {
  HttpServer? _server;
  final Set<WebSocket> _clients = {};
  String? _ip;

  /// Fired whenever the connected-display count changes (a viewer connects or
  /// disconnects), so the UI can react — e.g. collapse to the touch screen.
  void Function()? onViewersChanged;

  bool get running => _server != null;
  int get viewers => _clients.length;
  String? get ip => _ip;
  int get port => kGameCastPort;

  void _viewersChanged() {
    try {
      onViewersChanged?.call();
    } catch (_) {}
  }

  /// Starts the server; returns the LAN IP to show the user, or null on failure.
  Future<String?> start() async {
    if (_server != null) return _ip;
    try {
      _ip = await _lanIp();
      _server = await HttpServer.bind(InternetAddress.anyIPv4, kGameCastPort);
      _server!.listen((req) async {
        if (WebSocketTransformer.isUpgradeRequest(req)) {
          try {
            final ws = await WebSocketTransformer.upgrade(req);
            _clients.add(ws);
            _viewersChanged();
            ws.listen((_) {}, onDone: () {
              _clients.remove(ws);
              _viewersChanged();
            }, onError: (_) {
              _clients.remove(ws);
              _viewersChanged();
            }, cancelOnError: true);
          } catch (_) {}
        } else {
          req.response.statusCode = HttpStatus.upgradeRequired;
          await req.response.close();
        }
      }, onError: (_) {});
      return _ip;
    } catch (_) {
      _server = null;
      return null;
    }
  }

  /// Sends one RGBA frame to every connected display. No-op with no viewers, so
  /// it's cheap to call each emulator frame; throttle at the call site.
  void sendFrame(Uint8List rgba, int width, int height) {
    if (_clients.isEmpty) return;
    if (rgba.length < width * height * 4) return;
    final packet = Uint8List(5 + rgba.length);
    packet[0] = 0x46; // 'F'
    packet[1] = width & 0xff;
    packet[2] = (width >> 8) & 0xff;
    packet[3] = height & 0xff;
    packet[4] = (height >> 8) & 0xff;
    packet.setRange(5, 5 + rgba.length, rgba);
    for (final ws in _clients.toList()) {
      try {
        ws.add(packet);
      } catch (_) {
        _clients.remove(ws);
      }
    }
  }

  /// Sends a chunk of int16 stereo LE PCM to every display, tagged with the
  /// core's [sampleRate] so the client can match playback. No-op with no
  /// viewers. Audio is not throttled (unlike video) — dropping it causes gaps.
  void sendAudio(Uint8List pcm, int sampleRate) {
    if (_clients.isEmpty || pcm.isEmpty) return;
    final packet = Uint8List(5 + pcm.length);
    packet[0] = 0x41; // 'A'
    packet[1] = sampleRate & 0xff;
    packet[2] = (sampleRate >> 8) & 0xff;
    packet[3] = (sampleRate >> 16) & 0xff;
    packet[4] = (sampleRate >> 24) & 0xff;
    packet.setRange(5, 5 + pcm.length, pcm);
    for (final ws in _clients.toList()) {
      try {
        ws.add(packet);
      } catch (_) {
        _clients.remove(ws);
      }
    }
  }

  Future<void> stop() async {
    for (final ws in _clients.toList()) {
      try {
        await ws.close();
      } catch (_) {}
    }
    _clients.clear();
    try {
      await _server?.close(force: true);
    } catch (_) {}
    _server = null;
  }
}

/// CLIENT side: connects to a host and decodes incoming frames into [ui.Image]s.
class GameCastClient {
  WebSocket? _ws;
  bool _decoding = false;

  /// Called with each decoded frame; the previous image should be disposed by
  /// the receiver after it's swapped out of the widget tree.
  final void Function(ui.Image image) onFrame;

  /// Called with each incoming audio chunk (int16 stereo LE PCM) + its sample
  /// rate. Null if the display doesn't play audio.
  final void Function(Uint8List pcm, int sampleRate)? onAudio;
  final void Function(Object error)? onError;
  final void Function()? onDone;

  GameCastClient(
      {required this.onFrame, this.onAudio, this.onError, this.onDone});

  Future<void> connect(String ip, {int port = kGameCastPort}) async {
    final ws = await WebSocket.connect('ws://$ip:$port/')
        .timeout(const Duration(seconds: 6));
    _ws = ws;
    ws.listen(
      _onData,
      onError: (e) => onError?.call(e),
      onDone: () => onDone?.call(),
      cancelOnError: true,
    );
  }

  void _onData(dynamic data) {
    if (data is! List<int> || data.length < 5) return;
    final type = data[0];
    if (type == 0x41) {
      // 'A' audio — feed straight through (no drop; gaps are audible).
      final rate = data[1] | (data[2] << 8) | (data[3] << 16) | (data[4] << 24);
      onAudio?.call(Uint8List.fromList(data.sublist(5)), rate);
      return;
    }
    if (type != 0x46) return; // 'F' video only past here
    if (_decoding) return; // drop frames we can't keep up with
    final w = data[1] | (data[2] << 8);
    final h = data[3] | (data[4] << 8);
    if (w <= 0 || h <= 0 || data.length < 5 + w * h * 4) return;
    _decoding = true;
    final pixels = Uint8List.fromList(data.sublist(5, 5 + w * h * 4));
    ui.decodeImageFromPixels(pixels, w, h, ui.PixelFormat.rgba8888, (img) {
      _decoding = false;
      onFrame(img);
    });
  }

  Future<void> close() async {
    try {
      await _ws?.close();
    } catch (_) {}
    _ws = null;
  }
}

/// Scans the local /24 subnet(s) for devices listening on the cast port and
/// returns their IPs. Host-independent — just a quick TCP probe — so it finds a
/// phone that's casting right now without any extra advertise endpoint.
///
/// The timeout is generous on purpose: firing ~254 connects at once (most to
/// dead hosts that sit until they time out) can delay the real host's handshake,
/// so a too-short window silently misses a device that's plainly reachable.
Future<List<String>> discoverGameCastHosts({
  Duration timeout = const Duration(milliseconds: 900),
}) async {
  final prefixes = <String>{}; // e.g. "192.168.68."
  final selfIps = <String>{};
  try {
    for (final iface in await NetworkInterface.list(
        type: InternetAddressType.IPv4, includeLoopback: false)) {
      for (final a in iface.addresses) {
        if (a.isLoopback) continue;
        final ip = a.address;
        final priv = ip.startsWith('192.168.') ||
            ip.startsWith('10.') ||
            RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(ip);
        if (!priv) continue;
        selfIps.add(ip);
        prefixes.add(ip.substring(0, ip.lastIndexOf('.') + 1));
      }
    }
  } catch (_) {}

  final found = <String>{};
  for (final prefix in prefixes) {
    final probes = <Future<void>>[];
    for (var i = 1; i <= 254; i++) {
      final ip = '$prefix$i';
      if (selfIps.contains(ip)) continue;
      probes.add(() async {
        try {
          final s = await Socket.connect(ip, kGameCastPort, timeout: timeout);
          s.destroy();
          found.add(ip);
        } catch (_) {/* nothing listening here */}
      }());
    }
    await Future.wait(probes);
  }
  final list = found.toList()
    ..sort((a, b) {
      // numeric sort by last octet within a subnet
      int last(String ip) => int.tryParse(ip.split('.').last) ?? 0;
      return a.substring(0, a.lastIndexOf('.')) ==
              b.substring(0, b.lastIndexOf('.'))
          ? last(a).compareTo(last(b))
          : a.compareTo(b);
    });
  return list;
}

/// Picks the real Wi-Fi LAN IPv4 (not cellular/VPN/link-local). Mirrors the
/// scoring in SaveServer so both features agree on the address to advertise.
Future<String?> _lanIp() async {
  int score(String name, String ip) {
    final wifi = name.startsWith('en');
    final private = ip.startsWith('192.168.') ||
        ip.startsWith('10.') ||
        RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(ip);
    final bad = ip.startsWith('169.254.') || ip.startsWith('192.0.0.');
    if (bad) return 0;
    return (wifi ? 2 : 0) + (private ? 1 : 0);
  }

  String? best;
  var bestScore = -1;
  try {
    for (final iface in await NetworkInterface.list(
        type: InternetAddressType.IPv4, includeLoopback: false)) {
      for (final a in iface.addresses) {
        if (a.isLoopback) continue;
        final s = score(iface.name, a.address);
        if (s > bestScore) {
          bestScore = s;
          best = a.address;
        }
      }
    }
  } catch (_) {}
  return best;
}

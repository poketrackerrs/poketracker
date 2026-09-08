import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Streams the built-in player's video to another PokeTracker instance on the
/// same Wi-Fi ("cast the game to my PC"). The HOST (the device playing) runs a
/// WebSocket server and pushes RGBA frames; a CLIENT connects and paints them.
/// Input stays on the host, so this is one-way video — the lowest-latency setup.
///
/// Frame wire format (binary WebSocket message):
///   byte 0      : 0x46 'F'
///   bytes 1..2  : width  (little-endian uint16)
///   bytes 3..4  : height (little-endian uint16)
///   bytes 5..   : width*height*4 RGBA8888 pixels
const int kGameCastPort = 8724;

/// HOST side: a WebSocket server that fan-outs frames to connected displays.
class GameCastHost {
  HttpServer? _server;
  final Set<WebSocket> _clients = {};
  String? _ip;

  bool get running => _server != null;
  int get viewers => _clients.length;
  String? get ip => _ip;
  int get port => kGameCastPort;

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
            ws.listen((_) {}, onDone: () => _clients.remove(ws),
                onError: (_) => _clients.remove(ws), cancelOnError: true);
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
  final void Function(Object error)? onError;
  final void Function()? onDone;

  GameCastClient({required this.onFrame, this.onError, this.onDone});

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
    if (data is! List<int> || data.length < 5 || data[0] != 0x46) return;
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

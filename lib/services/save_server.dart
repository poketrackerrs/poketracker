import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';

/// A tiny read-only HTTP server that exposes the app's documents directory over
/// the local Wi-Fi network, so a paired dev machine can pull the saves/ROMs off
/// the device. Developer-mode only (the UI gates it to iOS). Access is guarded
/// by a random per-session token in the query string; the server binds only
/// while explicitly started and never writes anything.
class SaveServer {
  static const int port = 8723;
  HttpServer? _server;
  late final String token =
      List.generate(8, (_) => Random.secure().nextInt(256))
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();

  bool get running => _server != null;

  /// Set to accept incoming saves (device→device transfer). Given the game id,
  /// suggested filename and bytes, it should back up + write and return a short
  /// status string. When null, /put is refused.
  Future<String> Function(String gameId, String name, List<int> bytes)?
      onReceive;

  /// Starts the server and returns the base URL (with token), or null on error.
  Future<String?> start() async {
    if (_server != null) return url;
    try {
      final dir = await getApplicationDocumentsDirectory();
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      _server!.listen((req) => _handle(req, dir.path));
      return url;
    } catch (_) {
      _server = null;
      return null;
    }
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  String? _ip; // cached LAN address
  String? get url => _ip == null ? null : 'http://$_ip:$port/?t=$token';

  Future<String?> lanIp() async {
    // Score each IPv4 so we pick the real Wi-Fi LAN address, not a cellular
    // (pdp_ip), VPN (utun), link-local (169.254) or special (192.0.0.x) one.
    int score(String name, String ip) {
      final wifi = name.startsWith('en'); // en0 = Wi-Fi on iOS
      final private = ip.startsWith('192.168.') ||
          ip.startsWith('10.') ||
          RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(ip);
      final bad = ip.startsWith('169.254.') || ip.startsWith('192.0.0.');
      if (bad) return 0;
      return (wifi ? 2 : 0) + (private ? 1 : 0);
    }

    String? best;
    var bestScore = -1;
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
    _ip = best;
    return _ip;
  }

  Future<void> _handle(HttpRequest req, String root) async {
    final res = req.response;
    if (req.uri.queryParameters['t'] != token) {
      res.statusCode = HttpStatus.forbidden;
      await res.close();
      return;
    }
    try {
      switch (req.uri.path) {
        case '/list':
          final files = <Map<String, Object>>[];
          await for (final e in Directory(root).list(recursive: true)) {
            if (e is File) {
              files.add({
                'path': e.path.substring(root.length + 1),
                'size': await e.length(),
              });
            }
          }
          res.headers.contentType = ContentType.json;
          res.write(jsonEncode(files));
        case '/get':
          final rel = req.uri.queryParameters['path'] ?? '';
          final f = File('$root/$rel');
          // Path-traversal guard: the resolved file must stay under root.
          if (!f.absolute.path.startsWith(Directory(root).absolute.path) ||
              !f.existsSync()) {
            res.statusCode = HttpStatus.notFound;
            break;
          }
          res.headers.contentType = ContentType.binary;
          await res.addStream(f.openRead());
        case '/put':
          if (req.method != 'POST' || onReceive == null) {
            res.statusCode = HttpStatus.methodNotAllowed;
            break;
          }
          final game = req.uri.queryParameters['game'] ?? '';
          final name = req.uri.queryParameters['name'] ?? 'save.sav';
          final body = <int>[];
          await for (final chunk in req) {
            body.addAll(chunk);
          }
          final msg = await onReceive!(game, name, body);
          res.headers.contentType = ContentType.text;
          res.write(msg);
        default:
          res.headers.contentType = ContentType.html;
          res.write('<h3>PokeTracker save server</h3>'
              '<p>GET <code>/list?t=…</code> and '
              '<code>/get?t=…&amp;path=…</code></p>');
      }
    } catch (_) {
      res.statusCode = HttpStatus.internalServerError;
    }
    await res.close();
  }
}

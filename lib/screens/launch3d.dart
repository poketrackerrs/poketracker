import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:webview_flutter/webview_flutter.dart' as wf;
import 'package:webview_windows/webview_windows.dart' as ww;

/// Shows the layered-3D launch: the real console + cartridge in one webview,
/// the cartridge slides into the slot, the screen powers on, then [onLaunch]
/// runs and the overlay closes.
Future<void> showLaunch3D(
  BuildContext context, {
  required Future<void> Function() onLaunch,
}) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.88),
    builder: (_) => _Launch3D(onLaunch: onLaunch),
  );
}

class _Launch3D extends StatefulWidget {
  final Future<void> Function() onLaunch;
  const _Launch3D({required this.onLaunch});

  @override
  State<_Launch3D> createState() => _Launch3DState();
}

class _Launch3DState extends State<_Launch3D> {
  HttpServer? _server;
  ww.WebviewController? _win;
  wf.WebViewController? _mob;
  bool _ready = false;
  Timer? _timer;
  static const _total = Duration(milliseconds: 3600);

  static const _html = '''<!doctype html><html><head><meta charset="utf-8">
<style>
 html,body{margin:0;height:100%;background:transparent;overflow:hidden;
   font-family:-apple-system,Segoe UI,Roboto,sans-serif}
 #stage{position:relative;width:100%;height:100vh}
 model-viewer{background:transparent;--poster-color:transparent;position:absolute}
 #console{left:8%;top:16%;width:84%;height:72%}
 #cart{left:34%;top:-34%;width:32%;height:44%;
   transition:transform 1.25s cubic-bezier(.45,0,.2,1), opacity .35s ease-in}
 #cart.in{transform:translateY(150%) scale(.62)}
 #cart.gone{opacity:0}
 #flash{position:absolute;inset:0;opacity:0;transition:opacity .6s;
   background:radial-gradient(circle at 50% 42%, rgba(155,224,76,.55), rgba(0,0,0,0) 55%)}
 #flash.on{opacity:1}
 #label{position:absolute;bottom:6%;left:0;right:0;text-align:center;
   color:#fff;opacity:.85;font-size:16px}
</style>
<script type="module" src="/model-viewer.min.js" defer></script></head>
<body><div id="stage">
 <model-viewer id="console" src="/console.glb" interaction-prompt="none"
   camera-orbit="25deg 72deg 108%" disable-tap disable-zoom></model-viewer>
 <model-viewer id="cart" src="/cart.glb" interaction-prompt="none"
   camera-orbit="0deg 80deg 105%" disable-tap disable-zoom></model-viewer>
 <div id="flash"></div>
 <div id="label">Inserting cartridge…</div>
</div>
<script>
 const cart=document.getElementById('cart'),flash=document.getElementById('flash'),
   label=document.getElementById('label'),con=document.getElementById('console');
 function run(){
   setTimeout(()=>cart.classList.add('in'),450);
   setTimeout(()=>{cart.classList.add('gone');label.textContent='Booting…';},1750);
   setTimeout(()=>{con.cameraOrbit='0deg 78deg 108%';},1900);
   setTimeout(()=>{flash.classList.add('on');label.textContent='Now loading…';},2400);
 }
 window.addEventListener('load',run);
</script></body></html>''';

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<Uint8List> _asset(String p) async =>
      (await rootBundle.load(p)).buffer.asUint8List();

  Future<void> _start() async {
    try {
      final lib = await _asset('assets/web/model-viewer.min.js');
      final console = await _asset('assets/models/gameboy_classic.glb');
      final cart = await _asset('assets/models/gameboy_cartridge.glb');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) {
        final res = req.response;
        void send(String type, List<int> bytes) {
          final i = type.indexOf('/');
          res.headers.contentType = ContentType(
              type.substring(0, i), type.substring(i + 1));
          res.add(bytes);
        }

        switch (req.uri.path) {
          case '/model-viewer.min.js':
            send('text/javascript', lib);
          case '/console.glb':
            send('model/gltf-binary', console);
          case '/cart.glb':
            send('model/gltf-binary', cart);
          default:
            res.headers.contentType = ContentType.html;
            res.write(_html);
        }
        res.close();
      });
      _server = server;
      final url = 'http://127.0.0.1:${server.port}/';

      if (Platform.isWindows) {
        final c = ww.WebviewController();
        await c.initialize();
        await c.setBackgroundColor(Colors.transparent);
        await c.loadUrl(url);
        _win = c;
      } else {
        final c = wf.WebViewController()
          ..setJavaScriptMode(wf.JavaScriptMode.unrestricted)
          ..setBackgroundColor(Colors.transparent)
          ..loadRequest(Uri.parse(url));
        _mob = c;
      }
      if (mounted) setState(() => _ready = true);
      _timer = Timer(_total, _finish);
    } catch (_) {
      // If the 3D layer fails, don't hang — launch anyway.
      _finish();
    }
  }

  bool _finished = false;
  Future<void> _finish() async {
    if (_finished) return;
    _finished = true;
    await widget.onLaunch();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _win?.dispose();
    _server?.close(force: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final side = size.shortestSide * 0.92;
    Widget view;
    if (!_ready) {
      view = const Center(child: CircularProgressIndicator());
    } else if (Platform.isWindows) {
      view = ww.Webview(_win!);
    } else {
      view = wf.WebViewWidget(controller: _mob!);
    }
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(width: side, height: side * 1.15, child: view),
    );
  }
}

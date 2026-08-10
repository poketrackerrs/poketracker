import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:webview_flutter/webview_flutter.dart' as wf;
import 'package:webview_windows/webview_windows.dart' as ww;
import '../models/game.dart';

/// Shows the layered-3D launch: the cartridge comes out of the game box, slides
/// into the back of the real Game Boy, then the console turns to the front and
/// powers on before [onLaunch] runs.
Future<void> showLaunch3D(
  BuildContext context, {
  required Game game,
  required Future<void> Function() onLaunch,
}) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.9),
    builder: (_) => _Launch3D(game: game, onLaunch: onLaunch),
  );
}

class _Launch3D extends StatefulWidget {
  final Game game;
  final Future<void> Function() onLaunch;
  const _Launch3D({required this.game, required this.onLaunch});

  @override
  State<_Launch3D> createState() => _Launch3DState();
}

class _Launch3DState extends State<_Launch3D> {
  HttpServer? _server;
  ww.WebviewController? _win;
  wf.WebViewController? _mob;
  bool _ready = false;
  Timer? _timer;
  static const _total = Duration(milliseconds: 4500);

  static const _html = '''<!doctype html><html><head><meta charset="utf-8">
<style>
 html,body{margin:0;height:100%;background:transparent;overflow:hidden;
   font-family:-apple-system,Segoe UI,Roboto,sans-serif}
 #stage{position:relative;width:100%;height:100vh}
 model-viewer{background:transparent;--poster-color:transparent;position:absolute}
 #box{position:absolute;left:30%;top:2vh;width:40%;height:34vh;object-fit:contain;
   filter:drop-shadow(0 10px 18px rgba(0,0,0,.55));transition:opacity .5s}
 #box.gone{opacity:0}
 #console{left:10%;top:30vh;width:80%;height:66vh}
 #cart{left:38%;top:7vh;width:24%;height:30vh;opacity:0;z-index:3;
   transition:transform 1.15s cubic-bezier(.45,0,.2,1), opacity .4s}
 #cart.out{opacity:1;transform:translateY(6vh)}
 #cart.travel{transform:translateY(28vh)}
 #cart.in{transform:translateY(38vh) scale(.6)}
 #cart.gone{opacity:0}
 #flash{position:absolute;inset:0;opacity:0;transition:opacity .6s;
   background:radial-gradient(circle at 50% 60%, rgba(155,224,76,.55), rgba(0,0,0,0) 55%)}
 #flash.on{opacity:1}
 #label{position:absolute;bottom:5%;left:0;right:0;text-align:center;
   color:#fff;opacity:.85;font-size:16px}
</style>
<script type="module" src="/model-viewer.min.js" defer></script></head>
<body><div id="stage">
 <img id="box" src="/box.png" onerror="this.style.display='none'">
 <model-viewer id="console" src="/console.glb" interaction-prompt="none"
   camera-orbit="180deg 90deg 110%" disable-tap disable-zoom></model-viewer>
 <model-viewer id="cart" src="/cart.glb" interaction-prompt="none"
   camera-orbit="0deg 90deg 105%" disable-tap disable-zoom></model-viewer>
 <div id="flash"></div>
 <div id="label">Opening case…</div>
</div>
<script>
 const box=document.getElementById('box'),cart=document.getElementById('cart'),
   con=document.getElementById('console'),flash=document.getElementById('flash'),
   label=document.getElementById('label');
 function run(){
   setTimeout(()=>{cart.classList.add('out');label.textContent='Cartridge out';},450);
   setTimeout(()=>{box.classList.add('gone');cart.classList.add('travel');
     label.textContent='Inserting cartridge…';},1500);
   setTimeout(()=>{cart.classList.add('in');},2700);
   setTimeout(()=>{cart.classList.add('gone');label.textContent='Booting…';},3400);
   setTimeout(()=>{con.cameraOrbit='0deg 90deg 110%';},3600);
   setTimeout(()=>{flash.classList.add('on');label.textContent='Now loading…';},4100);
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
      Uint8List? box;
      try {
        box = await _asset(widget.game.boxArtAsset);
      } catch (_) {}

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) {
        final res = req.response;
        void send(String type, List<int> bytes) {
          final i = type.indexOf('/');
          res.headers.contentType =
              ContentType(type.substring(0, i), type.substring(i + 1));
          res.add(bytes);
        }

        switch (req.uri.path) {
          case '/model-viewer.min.js':
            send('text/javascript', lib);
          case '/console.glb':
            send('model/gltf-binary', console);
          case '/cart.glb':
            send('model/gltf-binary', cart);
          case '/box.png':
            if (box != null) {
              send('image/png', box);
            } else {
              res.statusCode = 404;
            }
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
    final w = size.width * 0.94;
    final h = size.height * 0.9;
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
      insetPadding: const EdgeInsets.all(12),
      child: SizedBox(width: w, height: h, child: view),
    );
  }
}

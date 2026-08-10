import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:webview_windows/webview_windows.dart' as ww;

/// A rotatable 3D viewer for a bundled .glb model.
/// - Android/iOS: model_viewer_plus (WebView + `model-viewer`).
/// - Windows: webview_windows (WebView2) pointed at a tiny local server that
///   serves the model, with `model-viewer` loaded from a CDN.
class ModelViewerScreen extends StatelessWidget {
  final String src; // asset path, e.g. assets/models/gameboy_classic.glb
  final String title;
  const ModelViewerScreen({super.key, required this.src, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Platform.isWindows
          ? _WindowsModelView(assetPath: src)
          : ModelViewer(
              src: src,
              alt: title,
              autoRotate: true,
              cameraControls: true,
              backgroundColor: const Color(0xFF101013),
            ),
    );
  }
}

class _WindowsModelView extends StatefulWidget {
  final String assetPath;
  const _WindowsModelView({required this.assetPath});

  @override
  State<_WindowsModelView> createState() => _WindowsModelViewState();
}

class _WindowsModelViewState extends State<_WindowsModelView> {
  final _controller = ww.WebviewController();
  HttpServer? _server;
  bool _ready = false;
  String? _error;

  static const _html = '''<!doctype html><html><head><meta charset="utf-8">
<style>html,body{margin:0;height:100%;background:#101013;overflow:hidden}
model-viewer{width:100%;height:100vh}</style>
<script type="module" src="/model-viewer.min.js" defer></script>
</head><body>
<model-viewer src="/model.glb" camera-controls auto-rotate touch-action="pan-y"
  shadow-intensity="1" exposure="1.1"></model-viewer>
</body></html>''';

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final glb =
          (await rootBundle.load(widget.assetPath)).buffer.asUint8List();
      final lib = (await rootBundle.load('assets/web/model-viewer.min.js'))
          .buffer
          .asUint8List();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) {
        final res = req.response;
        if (req.uri.path == '/model.glb') {
          res.headers.contentType = ContentType('model', 'gltf-binary');
          res.add(glb);
        } else if (req.uri.path == '/model-viewer.min.js') {
          res.headers.contentType =
              ContentType('text', 'javascript', charset: 'utf-8');
          res.add(lib);
        } else {
          res.headers.contentType = ContentType.html;
          res.write(_html);
        }
        res.close();
      });
      _server = server;
      await _controller.initialize();
      await _controller.loadUrl('http://127.0.0.1:${server.port}/');
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            'Could not start the 3D viewer.\nMake sure the WebView2 runtime is installed.');
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _server?.close(force: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(child: Text(_error!, textAlign: TextAlign.center));
    }
    if (!_ready) return const Center(child: CircularProgressIndicator());
    return ww.Webview(_controller);
  }
}

import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:webview_windows/webview_windows.dart' as ww;

/// Shows the 3D model floating over the page (like the box popout): dim
/// backdrop, drag to rotate, tap outside to close.
Future<void> showModelViewerDialog(
  BuildContext context, {
  required String src,
  required String title,
}) {
  final size = MediaQuery.of(context).size;
  final side = math.min(size.shortestSide * 0.86, 440.0);
  return showDialog(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.85),
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: side,
            height: side,
            child: ModelView(src: src, alt: title),
          ),
          const SizedBox(height: 16),
          const Text('Drag to rotate · tap outside to close',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
        ],
      ),
    ),
  );
}

/// Platform-appropriate 3D model content (no Scaffold), for embedding in a
/// dialog or page. Android/iOS → model_viewer_plus; Windows → WebView2.
class ModelView extends StatelessWidget {
  final String src;
  final String alt;
  const ModelView({super.key, required this.src, required this.alt});

  @override
  Widget build(BuildContext context) {
    if (Platform.isWindows) return _WindowsModelView(assetPath: src);
    return ModelViewer(
      src: src,
      alt: alt,
      autoRotate: true,
      cameraControls: true,
      backgroundColor: Colors.transparent,
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
<style>html,body{margin:0;height:100%;background:transparent;overflow:hidden}
model-viewer{width:100%;height:100vh;--poster-color:transparent}</style>
<script type="module" src="/model-viewer.min.js" defer></script>
</head><body>
<model-viewer src="/model.glb" camera-controls auto-rotate touch-action="pan-y"
  style="background-color:transparent" shadow-intensity="1" exposure="1.1">
</model-viewer>
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
      await _controller.setBackgroundColor(Colors.transparent);
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
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(child: Text(_error!, textAlign: TextAlign.center)),
      );
    }
    if (!_ready) return const Center(child: CircularProgressIndicator());
    return ww.Webview(_controller);
  }
}

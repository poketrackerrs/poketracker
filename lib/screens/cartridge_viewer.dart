import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

/// A rotatable 3D viewer for a bundled .glb model. Uses model_viewer_plus
/// (a webview + `model-viewer`), so it's intended for Android/iOS.
class ModelViewerScreen extends StatelessWidget {
  final String src; // asset path, e.g. assets/models/gameboy_classic.glb
  final String title;
  const ModelViewerScreen({super.key, required this.src, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ModelViewer(
        src: src,
        alt: title,
        autoRotate: true,
        cameraControls: true,
        backgroundColor: const Color(0xFF101013),
      ),
    );
  }
}

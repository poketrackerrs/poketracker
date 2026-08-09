import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

/// A rotatable 3D view of the Game Boy cartridge model. Uses model_viewer_plus
/// (a webview + `model-viewer`), so it's intended for Android/iOS.
class CartridgeViewer extends StatelessWidget {
  final String title;
  const CartridgeViewer({super.key, this.title = 'Cartridge'});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: const ModelViewer(
        src: 'assets/models/gameboy_cartridge.glb',
        alt: 'Game Boy cartridge',
        autoRotate: true,
        cameraControls: true,
        backgroundColor: Color(0xFF101013),
      ),
    );
  }
}

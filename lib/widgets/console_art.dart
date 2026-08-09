import 'package:flutter/material.dart';
import 'game_box_art.dart' show BoxPlatform;

/// Display name for each console platform.
const Map<BoxPlatform, String> kConsoleNames = {
  BoxPlatform.gb: 'Game Boy',
  BoxPlatform.gbc: 'Game Boy Color',
  BoxPlatform.gba: 'Game Boy Advance',
  BoxPlatform.ds: 'Nintendo DS',
  BoxPlatform.n3ds: 'Nintendo 3DS',
  BoxPlatform.nswitch: 'Nintendo Switch',
};

/// Consoles in shelf display order.
const List<BoxPlatform> kConsoleOrder = [
  BoxPlatform.gb,
  BoxPlatform.gbc,
  BoxPlatform.gba,
  BoxPlatform.ds,
  BoxPlatform.n3ds,
  BoxPlatform.nswitch,
];

/// A stylized vector drawing of a console. [glow] (0..1) lights the screen for
/// the power-on animation.
class ConsoleArt extends StatelessWidget {
  final BoxPlatform platform;
  final double size;
  final double glow;
  const ConsoleArt({
    super.key,
    required this.platform,
    this.size = 120,
    this.glow = 0,
  });

  /// Landscape consoles are wider than tall.
  bool get _landscape =>
      platform == BoxPlatform.gba ||
      platform == BoxPlatform.ds ||
      platform == BoxPlatform.n3ds ||
      platform == BoxPlatform.nswitch;

  @override
  Widget build(BuildContext context) {
    final w = _landscape ? size : size * 0.72;
    final h = _landscape ? size * 0.72 : size;
    return SizedBox(
      width: w,
      height: h,
      child: CustomPaint(painter: _ConsolePainter(platform, glow)),
    );
  }
}

class _ConsolePainter extends CustomPainter {
  final BoxPlatform platform;
  final double glow;
  _ConsolePainter(this.platform, this.glow);

  @override
  void paint(Canvas canvas, Size size) {
    switch (platform) {
      case BoxPlatform.gb:
        _handheld(canvas, size, const Color(0xFFC9CCD0), const Color(0xFF9BBCA0));
        break;
      case BoxPlatform.gbc:
        _handheld(canvas, size, const Color(0xFF3AA0C9), const Color(0xFF9BBCA0));
        break;
      case BoxPlatform.gba:
        _gba(canvas, size);
        break;
      case BoxPlatform.ds:
        _clamshell(canvas, size, const Color(0xFFCFD3D8), const Color(0xFF7FA9D8));
        break;
      case BoxPlatform.n3ds:
        _clamshell(canvas, size, const Color(0xFFCC3333), const Color(0xFF7FA9D8));
        break;
      case BoxPlatform.nswitch:
        _switch(canvas, size);
        break;
    }
  }

  Paint _fill(Color c) => Paint()..color = c;

  RRect _rr(double l, double t, double w, double h, double r) =>
      RRect.fromRectAndRadius(Rect.fromLTWH(l, t, w, h), Radius.circular(r));

  Color get _screenColor =>
      Color.lerp(const Color(0xFF35424A), const Color(0xFF8FD0FF), glow)!;

  void _screen(Canvas c, Rect r, {double radius = 3}) {
    c.drawRRect(
        RRect.fromRectAndRadius(r, Radius.circular(radius)), _fill(_screenColor));
    if (glow > 0.05) {
      c.drawRRect(
        RRect.fromRectAndRadius(r.inflate(2), Radius.circular(radius + 2)),
        Paint()
          ..color = const Color(0xFF8FD0FF).withValues(alpha: 0.5 * glow)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 * glow),
      );
    }
  }

  // Portrait handheld (GB / GBC).
  void _handheld(Canvas c, Size s, Color body, Color screenBezel) {
    final w = s.width, h = s.height;
    c.drawRRect(_rr(w * 0.08, 0, w * 0.84, h, w * 0.12), _fill(body));
    c.drawRRect(
        _rr(w * 0.18, h * 0.08, w * 0.64, h * 0.36, w * 0.05),
        _fill(const Color(0xFF4a5550)));
    _screen(c, Rect.fromLTWH(w * 0.26, h * 0.13, w * 0.48, h * 0.26));
    // D-pad
    c.drawRRect(_rr(w * 0.22, h * 0.62, w * 0.06, h * 0.16, 2),
        _fill(const Color(0xFF33383e)));
    c.drawRRect(_rr(w * 0.15, h * 0.67, w * 0.20, h * 0.06, 2),
        _fill(const Color(0xFF33383e)));
    // A/B
    c.drawCircle(Offset(w * 0.70, h * 0.66), w * 0.05, _fill(const Color(0xFFAA3355)));
    c.drawCircle(Offset(w * 0.60, h * 0.72), w * 0.05, _fill(const Color(0xFFAA3355)));
  }

  void _gba(Canvas c, Size s) {
    final w = s.width, h = s.height;
    c.drawRRect(_rr(0, h * 0.1, w, h * 0.8, h * 0.28), _fill(const Color(0xFF5B3FB0)));
    c.drawRRect(_rr(w * 0.3, h * 0.22, w * 0.4, h * 0.56, 6),
        _fill(const Color(0xFF2a2340)));
    _screen(c, Rect.fromLTWH(w * 0.34, h * 0.3, w * 0.32, h * 0.4));
    // D-pad left
    c.drawRRect(_rr(w * 0.1, h * 0.42, w * 0.1, h * 0.16, 3),
        _fill(const Color(0xFF2a2340)));
    // A/B right
    c.drawCircle(Offset(w * 0.86, h * 0.46), h * 0.06, _fill(const Color(0xFF2a2340)));
    c.drawCircle(Offset(w * 0.80, h * 0.56), h * 0.06, _fill(const Color(0xFF2a2340)));
  }

  // Clamshell (DS / 3DS) — two stacked screens.
  void _clamshell(Canvas c, Size s, Color body, Color bezel) {
    final w = s.width, h = s.height;
    c.drawRRect(_rr(w * 0.1, 0, w * 0.8, h * 0.46, w * 0.06), _fill(body));
    _screen(c, Rect.fromLTWH(w * 0.2, h * 0.06, w * 0.6, h * 0.34));
    c.drawRRect(_rr(w * 0.1, h * 0.52, w * 0.8, h * 0.46, w * 0.06), _fill(body));
    _screen(c, Rect.fromLTWH(w * 0.24, h * 0.58, w * 0.52, h * 0.34));
  }

  void _switch(Canvas c, Size s) {
    final w = s.width, h = s.height;
    // Joy-cons
    c.drawRRect(_rr(0, h * 0.05, w * 0.16, h * 0.9, w * 0.07),
        _fill(const Color(0xFF2A7DE1)));
    c.drawRRect(_rr(w * 0.84, h * 0.05, w * 0.16, h * 0.9, w * 0.07),
        _fill(const Color(0xFFE14F5A)));
    // Tablet
    c.drawRRect(_rr(w * 0.14, h * 0.05, w * 0.72, h * 0.9, w * 0.04),
        _fill(const Color(0xFF1c1c1c)));
    _screen(c, Rect.fromLTWH(w * 0.2, h * 0.13, w * 0.6, h * 0.74), radius: 4);
  }

  @override
  bool shouldRepaint(_ConsolePainter old) =>
      old.platform != platform || old.glow != glow;
}

/// A game cartridge/card whose shape matches the console, colored by [color].
class CartridgeArt extends StatelessWidget {
  final Color color;
  final BoxPlatform platform;
  final double size;
  const CartridgeArt({
    super.key,
    required this.color,
    required this.platform,
    this.size = 40,
  });

  /// Media aspect (w/h) by console: GB carts are tall, DS/3DS cards flat,
  /// Switch carts small and squarish.
  double get _aspect {
    switch (platform) {
      case BoxPlatform.gb:
      case BoxPlatform.gbc:
        return 0.80;
      case BoxPlatform.gba:
        return 0.92;
      case BoxPlatform.ds:
      case BoxPlatform.n3ds:
        return 1.28; // flat wide card
      case BoxPlatform.nswitch:
        return 0.9;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size * _aspect,
      height: size,
      child: CustomPaint(painter: _CartPainter(color, platform)),
    );
  }
}

class _CartPainter extends CustomPainter {
  final Color color;
  final BoxPlatform platform;
  _CartPainter(this.color, this.platform);

  @override
  void paint(Canvas canvas, Size s) {
    switch (platform) {
      case BoxPlatform.gb:
      case BoxPlatform.gbc:
        _gbCart(canvas, s);
        break;
      case BoxPlatform.gba:
        _gbaCart(canvas, s);
        break;
      case BoxPlatform.ds:
      case BoxPlatform.n3ds:
        _dsCard(canvas, s);
        break;
      case BoxPlatform.nswitch:
        _switchCart(canvas, s);
        break;
    }
  }

  Paint get _label => Paint()..color = Colors.white.withValues(alpha: 0.85);

  // Classic Game Boy / Color cartridge: chunky, ridged top, notched corner.
  void _gbCart(Canvas c, Size s) {
    final w = s.width, h = s.height;
    final body = Path()
      ..moveTo(w * 0.08, h * 0.14)
      ..lineTo(w * 0.92, h * 0.14)
      ..lineTo(w * 0.92, h * 0.88)
      ..lineTo(w * 0.66, h) // clipped bottom-right corner
      ..lineTo(w * 0.08, h)
      ..close();
    c.drawPath(body, Paint()..color = color);
    // Ridged grip at top
    for (var i = 0; i < 4; i++) {
      final x = w * (0.16 + i * 0.19);
      c.drawRect(Rect.fromLTWH(x, 0, w * 0.1, h * 0.14),
          Paint()..color = color);
    }
    c.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.2, h * 0.28, w * 0.6, h * 0.4),
            const Radius.circular(2)),
        _label);
  }

  void _gbaCart(Canvas c, Size s) {
    final w = s.width, h = s.height;
    c.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.06, h * 0.06, w * 0.88, h * 0.94),
            Radius.circular(w * 0.12)),
        Paint()..color = color);
    c.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.2, h * 0.24, w * 0.6, h * 0.44),
            const Radius.circular(2)),
        _label);
    // grip notches
    c.drawRect(Rect.fromLTWH(w * 0.0, h * 0.2, w * 0.06, h * 0.2),
        Paint()..color = color);
    c.drawRect(Rect.fromLTWH(w * 0.94, h * 0.2, w * 0.06, h * 0.2),
        Paint()..color = color);
  }

  // Flat DS / 3DS game card.
  void _dsCard(Canvas c, Size s) {
    final w = s.width, h = s.height;
    final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.04, h * 0.08, w * 0.92, h * 0.84),
        Radius.circular(h * 0.14));
    c.drawRRect(r, Paint()..color = color);
    // notch (top-right)
    c.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.8, h * 0.08, w * 0.16, h * 0.22),
            const Radius.circular(2)),
        Paint()..color = Colors.black.withValues(alpha: 0.35));
    c.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.12, h * 0.34, w * 0.6, h * 0.4),
            const Radius.circular(2)),
        _label);
  }

  // Small Switch cartridge.
  void _switchCart(Canvas c, Size s) {
    final w = s.width, h = s.height;
    final body = Path()
      ..moveTo(w * 0.12, h * 0.06)
      ..lineTo(w * 0.72, h * 0.06)
      ..lineTo(w * 0.9, h * 0.24)
      ..lineTo(w * 0.9, h * 0.94)
      ..lineTo(w * 0.12, h * 0.94)
      ..close();
    c.drawPath(body, Paint()..color = color);
    c.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.24, h * 0.34, w * 0.5, h * 0.4),
            const Radius.circular(2)),
        _label);
  }

  @override
  bool shouldRepaint(_CartPainter old) =>
      old.color != color || old.platform != platform;
}

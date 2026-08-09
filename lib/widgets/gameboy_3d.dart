import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A constructed 3D Game Boy (DMG-01): an extruded slab with a detailed front
/// face, a back face (cartridge slot + battery cover), and grey edges. Uses the
/// same perspective + back-face culling technique as the 3D game boxes.
class GameBoy3D extends StatefulWidget {
  final double size; // overall height
  final bool interactive; // drag to rotate
  final double glow; // 0..1 lights the LCD
  final double initialYaw;
  final double initialPitch;

  const GameBoy3D({
    super.key,
    this.size = 130,
    this.interactive = false,
    this.glow = 0,
    this.initialYaw = -0.42,
    this.initialPitch = 0.16,
  });

  @override
  State<GameBoy3D> createState() => _GameBoy3DState();
}

class _GameBoy3DState extends State<GameBoy3D> {
  late double _yaw = widget.initialYaw;
  late double _pitch = widget.initialPitch;

  static const _edge = Color(0xFFB4B1A6);

  double _tz(List<double> p) {
    final z1 = -p[0] * math.sin(_yaw) + p[2] * math.cos(_yaw);
    return p[1] * math.sin(_pitch) + z1 * math.cos(_pitch);
  }

  Matrix4 _ry(double a) => Matrix4.identity()..rotateY(a);
  Matrix4 _rx(double a) => Matrix4.identity()..rotateX(a);

  Widget _place(double px, double py, double pz, Matrix4? rot, Widget child) {
    final t = Matrix4.translationValues(px, py, pz);
    if (rot != null) t.multiply(rot);
    return Transform(alignment: Alignment.center, transform: t, child: child);
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.size;
    final w = h * 0.62; // DMG proportions
    final d = w * 0.20; // thickness

    final raw = <({List<double> c, List<double> n, Matrix4? rot, Widget child})>[];
    raw.add((
      c: [0, 0, -d / 2],
      n: [0, 0, -1],
      rot: null,
      child: SizedBox(
          width: w,
          height: h,
          child: CustomPaint(painter: _GameBoyFront(widget.glow))),
    ));
    raw.add((
      c: [0, 0, d / 2],
      n: [0, 0, 1],
      rot: _ry(math.pi),
      child: SizedBox(
          width: w, height: h, child: CustomPaint(painter: _GameBoyBack())),
    ));
    raw.add((
      c: [w / 2, 0, 0],
      n: [1, 0, 0],
      rot: _ry(math.pi / 2),
      child: SizedBox(width: d, height: h, child: Container(color: _edge)),
    ));
    raw.add((
      c: [-w / 2, 0, 0],
      n: [-1, 0, 0],
      rot: _ry(-math.pi / 2),
      child: SizedBox(width: d, height: h, child: Container(color: _edge)),
    ));
    // Top edge shows the power switch + link port hints.
    raw.add((
      c: [0, -h / 2, 0],
      n: [0, -1, 0],
      rot: _rx(math.pi / 2),
      child: SizedBox(
          width: w, height: d, child: CustomPaint(painter: _GameBoyTop())),
    ));
    raw.add((
      c: [0, h / 2, 0],
      n: [0, 1, 0],
      rot: _rx(-math.pi / 2),
      child: SizedBox(width: w, height: d, child: Container(color: _edge)),
    ));

    final visible = raw.where((f) => _tz(f.n) < -0.001).toList()
      ..sort((a, b) => _tz(b.c).compareTo(_tz(a.c)));

    Widget model = Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.0009)
        ..rotateX(_pitch)
        ..rotateY(_yaw),
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          for (final f in visible) _place(f.c[0], f.c[1], f.c[2], f.rot, f.child),
        ],
      ),
    );

    if (widget.interactive) {
      model = GestureDetector(
        onPanUpdate: (dt) => setState(() {
          _yaw = (_yaw + dt.delta.dx * 0.01).clamp(-3.2, 3.2);
          _pitch = (_pitch - dt.delta.dy * 0.01).clamp(-0.8, 0.5);
        }),
        child: model,
      );
    }

    return SizedBox(
        width: w + d + 12, height: h + d + 10, child: Center(child: model));
  }
}

// ------------------------------------------------------------- front face
class _GameBoyFront extends CustomPainter {
  final double glow;
  _GameBoyFront(this.glow);

  @override
  void paint(Canvas c, Size s) {
    final w = s.width, h = s.height;
    Paint fill(Color col) => Paint()..color = col;
    RRect rr(double l, double t, double ww, double hh, double r) =>
        RRect.fromRectAndRadius(Rect.fromLTWH(l, t, ww, hh), Radius.circular(r));

    // Body
    c.drawRRect(rr(0, 0, w, h, w * 0.11), fill(const Color(0xFFC9C6BC)));

    // Power switch (top-left)
    c.drawRRect(rr(w * 0.14, h * 0.035, w * 0.26, h * 0.028, 2),
        fill(const Color(0xFFB6B3A9)));

    // Screen bezel (blue-grey), with a larger bottom-right rounded corner.
    final bezel = Path()
      ..addRRect(rr(w * 0.12, h * 0.125, w * 0.76, h * 0.335, w * 0.05));
    c.drawPath(bezel, fill(const Color(0xFF5F6D8A)));

    // Decorative stripes
    c.drawRect(Rect.fromLTWH(w * 0.16, h * 0.15, w * 0.14, h * 0.008),
        fill(const Color(0xFFC0344D)));
    c.drawRect(Rect.fromLTWH(w * 0.16, h * 0.164, w * 0.14, h * 0.008),
        fill(const Color(0xFF3556B0)));
    c.drawRect(Rect.fromLTWH(w * 0.72, h * 0.15, w * 0.12, h * 0.008),
        fill(const Color(0xFFC0344D)));
    c.drawRect(Rect.fromLTWH(w * 0.72, h * 0.164, w * 0.12, h * 0.008),
        fill(const Color(0xFF3556B0)));
    if (w >= 120) {
      _text(c, 'DOT MATRIX WITH STEREO SOUND',
          Offset(w * 0.5, h * 0.155), w * 0.032, const Color(0xFFDDE2EE),
          center: true);
    }

    // LCD (olive; brightens with glow)
    final screen = Color.lerp(
        const Color(0xFF94A277), const Color(0xFFC6E06A), glow)!;
    final scr = Rect.fromLTWH(w * 0.24, h * 0.19, w * 0.52, h * 0.225);
    if (glow > 0.05) {
      c.drawRRect(RRect.fromRectAndRadius(scr.inflate(4), const Radius.circular(4)),
          Paint()
            ..color = const Color(0xFF9BE04C).withValues(alpha: 0.5 * glow)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, 8 * glow));
    }
    c.drawRRect(RRect.fromRectAndRadius(scr, const Radius.circular(2)),
        fill(screen));

    // Battery LED
    c.drawCircle(Offset(w * 0.165, h * 0.30),
        w * 0.022, fill(glow > 0.1 ? const Color(0xFFE24B4B) : const Color(0xFF7a3a3a)));
    if (w >= 120) {
      _text(c, 'BATTERY', Offset(w * 0.165, h * 0.345), w * 0.03,
          const Color(0xFFE6E8F0), center: true);
    }

    // Wordmark
    if (w >= 110) {
      _text(c, 'Nintendo', Offset(w * 0.15, h * 0.485), w * 0.062,
          const Color(0xFF243A99), italic: true, bold: true);
      _text(c, 'GAME BOY', Offset(w * 0.46, h * 0.485), w * 0.062,
          const Color(0xFF1B2A70), bold: true);
    } else {
      c.drawRect(Rect.fromLTWH(w * 0.15, h * 0.49, w * 0.5, h * 0.02),
          fill(const Color(0xFF243A99)));
    }

    // D-pad (black plus)
    final dp = fill(const Color(0xFF2B2F36));
    c.drawRRect(rr(w * 0.19, h * 0.62, w * 0.09, h * 0.16, 3), dp);
    c.drawRRect(rr(w * 0.13, h * 0.665, w * 0.21, h * 0.07, 3), dp);
    c.drawCircle(Offset(w * 0.235, h * 0.70), w * 0.028,
        fill(const Color(0xFF1C2025)));

    // A / B buttons (diagonal)
    final btn = fill(const Color(0xFFB32048));
    c.drawCircle(Offset(w * 0.84, h * 0.655), w * 0.062, btn);
    c.drawCircle(Offset(w * 0.70, h * 0.71), w * 0.062, btn);
    if (w >= 110) {
      _text(c, 'A', Offset(w * 0.84, h * 0.725), w * 0.035,
          const Color(0xFF243A99), center: true, bold: true);
      _text(c, 'B', Offset(w * 0.70, h * 0.78), w * 0.035,
          const Color(0xFF243A99), center: true, bold: true);
    }

    // SELECT / START (angled pills)
    c.save();
    c.translate(w * 0.5, h * 0.83);
    c.rotate(-0.42);
    final pill = fill(const Color(0xFF8F8D84));
    c.drawRRect(rr(-w * 0.20, -h * 0.012, w * 0.13, h * 0.024, h * 0.012), pill);
    c.drawRRect(rr(w * 0.03, -h * 0.012, w * 0.13, h * 0.024, h * 0.012), pill);
    c.restore();

    // Speaker grille (diagonal lines, bottom-right)
    final gl = Paint()
      ..color = const Color(0xFFA7A498)
      ..strokeWidth = w * 0.02
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 5; i++) {
      final off = i * w * 0.05;
      c.drawLine(Offset(w * 0.66 + off, h * 0.93),
          Offset(w * 0.80 + off, h * 0.83), gl);
    }
  }

  void _text(Canvas c, String s, Offset at, double size, Color color,
      {bool center = false, bool bold = false, bool italic = false}) {
    final tp = TextPainter(
      text: TextSpan(
          text: s,
          style: TextStyle(
              color: color,
              fontSize: size,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              fontStyle: italic ? FontStyle.italic : FontStyle.normal)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, center ? at - Offset(tp.width / 2, tp.height / 2) : at);
  }

  @override
  bool shouldRepaint(_GameBoyFront old) => old.glow != glow;
}

// ------------------------------------------------------------- back face
class _GameBoyBack extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final w = s.width, h = s.height;
    Paint fill(Color col) => Paint()..color = col;
    RRect rr(double l, double t, double ww, double hh, double r) =>
        RRect.fromRectAndRadius(Rect.fromLTWH(l, t, ww, hh), Radius.circular(r));

    c.drawRRect(rr(0, 0, w, h, w * 0.11), fill(const Color(0xFFC4C1B7)));
    // Cartridge slot (top)
    c.drawRRect(rr(w * 0.2, h * 0.03, w * 0.6, h * 0.05, 2),
        fill(const Color(0xFF2A2A2A)));
    // Label plate
    c.drawRRect(rr(w * 0.16, h * 0.12, w * 0.68, h * 0.2, 3),
        fill(const Color(0xFFCFCCC3)));
    // 4 screws
    final screw = fill(const Color(0xFF6d6a62));
    for (final o in [
      Offset(w * 0.1, h * 0.1),
      Offset(w * 0.9, h * 0.1),
      Offset(w * 0.1, h * 0.9),
      Offset(w * 0.9, h * 0.9),
    ]) {
      c.drawCircle(o, w * 0.03, screw);
    }
    // Battery cover ridges (bottom half)
    final line = Paint()
      ..color = const Color(0xFFB2AFA4)
      ..strokeWidth = h * 0.008;
    for (var i = 0; i < 12; i++) {
      final y = h * (0.5 + i * 0.035);
      c.drawLine(Offset(w * 0.16, y), Offset(w * 0.84, y), line);
    }
  }

  @override
  bool shouldRepaint(_GameBoyBack old) => false;
}

// ------------------------------------------------------------- top edge
class _GameBoyTop extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final w = s.width, h = s.height;
    c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFFB4B1A6));
    // Power switch slot
    c.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.16, h * 0.28, w * 0.24, h * 0.44),
            const Radius.circular(2)),
        Paint()..color = const Color(0xFF6d6a62));
    // Cartridge slot
    c.drawRect(Rect.fromLTWH(w * 0.5, h * 0.2, w * 0.42, h * 0.6),
        Paint()..color = const Color(0xFF2A2A2A));
  }

  @override
  bool shouldRepaint(_GameBoyTop old) => false;
}

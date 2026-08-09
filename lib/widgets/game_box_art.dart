import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/game.dart';

/// Which console's retail box shape a game uses.
enum BoxPlatform { gb, gbc, gba, ds, n3ds, nswitch }

/// Public accessor for a game's console platform (used by console mode).
BoxPlatform platformForGame(Game g) => _platformFor(g);

BoxPlatform _platformFor(Game g) {
  if (g.id == 'lets-go-pikachu' || g.id == 'lets-go-eevee') {
    return BoxPlatform.nswitch;
  }
  switch (g.generation) {
    case 1:
      return BoxPlatform.gb;
    case 2:
      return BoxPlatform.gbc;
    case 3:
      return BoxPlatform.gba;
    case 4:
    case 5:
      return BoxPlatform.ds;
    case 6:
    case 7:
      return BoxPlatform.n3ds;
    default:
      return BoxPlatform.nswitch;
  }
}

/// Fallback proportions + spine colors when there's no full wrap to map.
class _BoxSpec {
  final double aspect;
  final double depth;
  final Color spine;
  final Color top;
  final Color labelColor;
  final String label;
  const _BoxSpec(this.aspect, this.depth, this.spine, this.top,
      this.labelColor, this.label);
}

const _cartSpine = Color(0xFF2E2E2E);
const _cartTop = Color(0xFF454545);

_BoxSpec _specFor(BoxPlatform p) {
  switch (p) {
    case BoxPlatform.gb:
      return const _BoxSpec(1.00, 0.19, _cartSpine, _cartTop, Colors.white, 'GAME BOY');
    case BoxPlatform.gbc:
      return const _BoxSpec(1.00, 0.19, _cartSpine, _cartTop, Colors.white, 'GBC');
    case BoxPlatform.gba:
      return const _BoxSpec(1.00, 0.20, _cartSpine, _cartTop, Colors.white, 'GBA');
    case BoxPlatform.ds:
      return const _BoxSpec(1.10, 0.12, Color(0xFFDCDCDC), Color(0xFFECECEC), Colors.black87, 'DS');
    case BoxPlatform.n3ds:
      return const _BoxSpec(1.10, 0.10, Color(0xFFE2E2E2), Color(0xFFF0F0F0), Colors.black87, '3DS');
    case BoxPlatform.nswitch:
      return const _BoxSpec(0.62, 0.10, Color(0xFFC20010), Color(0xFFE60012), Colors.white, 'SWITCH');
  }
}

/// Fractional panels of a full box wrap: [back | spine | front] left→right.
class WrapLayout {
  final Rect back;
  final Rect spine;
  final Rect front;
  const WrapLayout({required this.back, required this.spine, required this.front});
}

const WrapLayout _gbWrap = WrapLayout(
  back: Rect.fromLTRB(0.0, 0.0, 0.464, 1.0),
  spine: Rect.fromLTRB(0.464, 0.0, 0.527, 1.0),
  front: Rect.fromLTRB(0.527, 0.0, 0.995, 1.0),
);

// DS full wraps: back content ends ~46.3% (then a white fold), spine 47.5–53%.
const WrapLayout _dsWrap = WrapLayout(
  back: Rect.fromLTRB(0.0, 0.0, 0.463, 1.0),
  spine: Rect.fromLTRB(0.475, 0.0, 0.530, 1.0),
  front: Rect.fromLTRB(0.530, 0.0, 0.995, 1.0),
);

// 3DS horizontal wraps: back ends ~47.6%, spine 47.6–52.2%, front from 52.2%.
const WrapLayout _n3dsWrap = WrapLayout(
  back: Rect.fromLTRB(0.0, 0.0, 0.476, 1.0),
  spine: Rect.fromLTRB(0.476, 0.0, 0.522, 1.0),
  front: Rect.fromLTRB(0.522, 0.0, 0.995, 1.0),
);

WrapLayout? _wrapLayoutFor(BoxPlatform p) {
  switch (p) {
    case BoxPlatform.gb:
    case BoxPlatform.gbc:
    case BoxPlatform.gba:
      return _gbWrap;
    case BoxPlatform.ds:
      return _dsWrap;
    case BoxPlatform.n3ds:
      return _n3dsWrap;
    case BoxPlatform.nswitch:
      return null;
  }
}

/// A game's box as a real 3D box. When a full wrap image exists for the game,
/// its front/spine/back panels are textured onto the box faces (and depth-
/// sorted so spinning reveals the real back); otherwise a front cover + a
/// generated spine are used. Set [interactive] to drag-spin it.
class GameBoxArt extends StatefulWidget {
  final Game game;
  final double height;
  final bool interactive;

  const GameBoxArt({
    super.key,
    required this.game,
    this.height = 120,
    this.interactive = false,
  });

  @override
  State<GameBoxArt> createState() => _GameBoxArtState();
}

class _GameBoxArtState extends State<GameBoxArt> {
  late double _yaw;
  late double _pitch;
  double? _imgAspect; // front cover aspect (fallback path)
  ui.Image? _wrap; // full wrap image, if one exists

  String get _wrapAsset => 'assets/games/wraps/${widget.game.id}.png';

  @override
  void initState() {
    super.initState();
    _yaw = widget.interactive ? -0.5 : -0.35;
    _pitch = widget.interactive ? 0.18 : 0.14;
    _resolveAspect();
    _resolveWrap();
  }

  @override
  void didUpdateWidget(GameBoxArt old) {
    super.didUpdateWidget(old);
    if (old.game.id != widget.game.id) {
      _imgAspect = null;
      _wrap = null;
      _resolveAspect();
      _resolveWrap();
    }
  }

  void _resolveAspect() {
    final s = AssetImage(widget.game.boxArtAsset).resolve(ImageConfiguration.empty);
    late ImageStreamListener l;
    l = ImageStreamListener((info, _) {
      if (mounted && info.image.height > 0) {
        setState(() => _imgAspect = info.image.width / info.image.height);
      }
      s.removeListener(l);
    }, onError: (_, _) => s.removeListener(l));
    s.addListener(l);
  }

  void _resolveWrap() {
    if (_wrapLayoutFor(_platformFor(widget.game)) == null) return;
    final s = AssetImage(_wrapAsset).resolve(ImageConfiguration.empty);
    late ImageStreamListener l;
    l = ImageStreamListener((info, _) {
      if (mounted) setState(() => _wrap = info.image);
      s.removeListener(l);
    }, onError: (_, _) => s.removeListener(l));
    s.addListener(l);
  }

  // Transformed z of a point/direction (with our perspective, more-negative z
  // is nearer the viewer). Used for both back-face culling and depth sorting.
  double _tz(List<double> p) {
    final z1 = -p[0] * math.sin(_yaw) + p[2] * math.cos(_yaw);
    return p[1] * math.sin(_pitch) + z1 * math.cos(_pitch);
  }

  @override
  Widget build(BuildContext context) {
    final platform = _platformFor(widget.game);
    final layout = _wrapLayoutFor(platform);
    final h = widget.height;
    final wrap = _wrap;

    final double w, d;
    // Each face: center (c), outward normal (n), local rotation, child.
    final raw = <({List<double> c, List<double> n, Matrix4? rot, Widget child})>[];

    if (wrap != null && layout != null) {
      final iw = wrap.width.toDouble(), ih = wrap.height.toDouble();
      final frontFrac = layout.front.width;
      w = h * (frontFrac * iw / ih);
      d = w * (layout.spine.width / frontFrac);
      Widget panel(Rect r) => CustomPaint(painter: _PanelPainter(wrap, r));
      const edgeColor = Color(0xFF2B2B2B);

      raw.add((c: [0, 0, -d / 2], n: [0, 0, -1], rot: null,
          child: SizedBox(width: w, height: h, child: _shadow(panel(layout.front)))));
      raw.add((c: [0, 0, d / 2], n: [0, 0, 1], rot: _ry(math.pi),
          child: SizedBox(width: w, height: h, child: panel(layout.back))));
      raw.add((c: [w / 2, 0, 0], n: [1, 0, 0], rot: _ry(math.pi / 2),
          child: SizedBox(width: d, height: h, child: panel(layout.spine))));
      raw.add((c: [-w / 2, 0, 0], n: [-1, 0, 0], rot: _ry(-math.pi / 2),
          child: SizedBox(width: d, height: h, child: panel(layout.spine))));
      raw.add((c: [0, -h / 2, 0], n: [0, -1, 0], rot: _rx(math.pi / 2),
          child: SizedBox(width: w, height: d, child: Container(color: edgeColor))));
      raw.add((c: [0, h / 2, 0], n: [0, 1, 0], rot: _rx(-math.pi / 2),
          child: SizedBox(width: w, height: d, child: Container(color: edgeColor))));
    } else {
      final spec = _specFor(platform);
      w = h * (_imgAspect ?? spec.aspect);
      d = w * spec.depth;
      raw.add((c: [0, 0, -d / 2], n: [0, 0, -1], rot: null,
          child: SizedBox(width: w, height: h, child: _shadow(_frontCover(w, h)))));
      raw.add((c: [w / 2, 0, 0], n: [1, 0, 0], rot: _ry(math.pi / 2),
          child: _spineFace(spec, d, h)));
      raw.add((c: [-w / 2, 0, 0], n: [-1, 0, 0], rot: _ry(-math.pi / 2),
          child: _spineFace(spec, d, h)));
      raw.add((c: [0, -h / 2, 0], n: [0, -1, 0], rot: _rx(math.pi / 2),
          child: SizedBox(width: w, height: d, child: Container(color: spec.top))));
      raw.add((c: [0, h / 2, 0], n: [0, 1, 0], rot: _rx(-math.pi / 2),
          child: SizedBox(width: w, height: d, child: Container(color: spec.top))));
    }

    // Back-face culling: keep only faces whose outward normal points at the
    // viewer (transformed z < 0). Then paint far → near.
    final visible = raw.where((f) => _tz(f.n) < -0.001).toList()
      ..sort((a, b) => _tz(b.c).compareTo(_tz(a.c)));

    Widget box = Transform(
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
      box = GestureDetector(
        onPanUpdate: (details) => setState(() {
          _yaw = (_yaw + details.delta.dx * 0.01).clamp(-3.2, 3.2);
          _pitch = (_pitch - details.delta.dy * 0.01).clamp(-0.8, 0.4);
        }),
        child: box,
      );
    }

    return SizedBox(width: w + d + 16, height: h + d + 12, child: Center(child: box));
  }

  Matrix4 _ry(double a) => Matrix4.identity()..rotateY(a);
  Matrix4 _rx(double a) => Matrix4.identity()..rotateX(a);

  /// Positions a face at (px,py,pz) with an optional local rotation.
  Widget _place(double px, double py, double pz, Matrix4? rot, Widget child) {
    final t = Matrix4.translationValues(px, py, pz);
    if (rot != null) t.multiply(rot);
    return Transform(alignment: Alignment.center, transform: t, child: child);
  }

  Widget _shadow(Widget child) => DecoratedBox(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 10,
              offset: const Offset(6, 8),
            ),
          ],
        ),
        child: child,
      );

  Widget _frontCover(double w, double h) => ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: SizedBox(
          width: w,
          height: h,
          child: Image.asset(
            widget.game.boxArtAsset,
            fit: BoxFit.cover,
            cacheWidth: (w * 3).round(),
            errorBuilder: (_, _, _) => _fallback(),
          ),
        ),
      );

  Widget _spineFace(_BoxSpec spec, double d, double h) => Container(
        width: d,
        height: h,
        color: spec.spine,
        alignment: Alignment.center,
        child: d > 18
            ? RotatedBox(
                quarterTurns: 3,
                child: Text(spec.label,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: TextStyle(
                        color: spec.labelColor,
                        fontSize: (d * 0.26).clamp(6, 12),
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1)),
              )
            : null,
      );

  Widget _fallback() {
    const genGradients = {
      1: [Color(0xFFEE1515), Color(0xFF9E1313)],
      2: [Color(0xFFDAA520), Color(0xFFB8860B)],
      3: [Color(0xFF1E90FF), Color(0xFF104E8B)],
      4: [Color(0xFF8E9EAB), Color(0xFF54677A)],
      5: [Color(0xFF2C2C2C), Color(0xFF000000)],
      6: [Color(0xFF3B4CCA), Color(0xFF7B2FBE)],
      7: [Color(0xFFFF7F27), Color(0xFFF95587)],
      8: [Color(0xFF00A2E8), Color(0xFFED1C24)],
      9: [Color(0xFFB33A3A), Color(0xFF6A2C91)],
    };
    final colors = genGradients[widget.game.generation] ??
        [Colors.grey.shade600, Colors.grey.shade800];
    final isLegends = widget.game.category == GameCategory.legends;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
      ),
      child: Center(
        child: Icon(isLegends ? Icons.explore : Icons.catching_pokemon,
            color: Colors.white.withValues(alpha: 0.85), size: widget.height * 0.4),
      ),
    );
  }
}

/// Paints one fractional panel of a wrap image onto a face.
class _PanelPainter extends CustomPainter {
  final ui.Image image;
  final Rect srcFrac;
  _PanelPainter(this.image, this.srcFrac);

  @override
  void paint(Canvas canvas, Size size) {
    final src = Rect.fromLTRB(
      srcFrac.left * image.width,
      srcFrac.top * image.height,
      srcFrac.right * image.width,
      srcFrac.bottom * image.height,
    );
    canvas.drawImageRect(
        image, src, Offset.zero & size, Paint()..filterQuality = FilterQuality.medium);
  }

  @override
  bool shouldRepaint(covariant _PanelPainter old) =>
      old.image != image || old.srcFrac != srcFrac;
}

import 'dart:math' as math;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import '../models/game.dart';

/// Plays the pre-rendered real-3D launch: the cartridge slides out of the box
/// and into the back of the Game Boy, which turns to the front and powers on,
/// then [onLaunch] runs and the overlay closes.
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

const _frameCount = 68; // assets/launch/f00.png .. f67.png
const _sp3dFrames = 60; // assets/launch/sp3d/<game>/f00.png .. f59.png
const _fullFrames = 64; // assets/launch/full/<game>/f00.webp .. f63.webp (box→SP full flow)

class _Launch3D extends StatefulWidget {
  final Game game;
  final Future<void> Function() onLaunch;
  const _Launch3D({required this.game, required this.onLaunch});

  @override
  State<_Launch3D> createState() => _Launch3DState();
}

class _Launch3DState extends State<_Launch3D>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  final AudioPlayer _sfx = AudioPlayer();
  bool _insert = false, _power = false, _precached = false;

  // GBA (Gen 3) gets a dedicated launch: the cartridge slides into a Game Boy
  // Advance SP's front slot and the screen powers on. Others use the frame set.
  bool get _isGba => widget.game.generation == 3;

  // Games with the new pre-rendered box→SP full-flow launch (real box art, boot
  // screen baked in). Other GBA games fall back to the older per-game SP sequence
  // until their box scans are cut and rendered. Add ids here as games are baked.
  static const _fullFlowGames = {'firered'};
  bool get _isFullFlow => _fullFlowGames.contains(widget.game.id);

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: _isFullFlow ? 4600 : 2500))
      ..addListener(_sounds)
      ..addStatusListener((s) async {
        if (s == AnimationStatus.completed) {
          await widget.onLaunch();
          if (mounted) Navigator.of(context).pop();
        }
      });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_precached) return;
    _precached = true;
    Future(() async {
      if (!mounted) return;
      await precacheImage(const AssetImage('assets/launch/cart.png'), context);
      if (mounted) {
        await precacheImage(AssetImage(widget.game.boxArtAsset), context)
            .catchError((_) {});
      }
      if (_isFullFlow) {
        for (var i = 0; i < _fullFrames; i++) {
          if (!mounted) return;
          await precacheImage(
              AssetImage('assets/launch/full/${widget.game.id}/'
                  'f${i.toString().padLeft(2, '0')}.webp'),
              context);
        }
      } else if (_isGba) {
        for (var i = 0; i < _sp3dFrames; i++) {
          if (!mounted) return;
          await precacheImage(
              AssetImage('assets/launch/sp3d/${widget.game.id}/'
                  'f${i.toString().padLeft(2, '0')}.png'),
              context);
        }
      } else {
        for (var i = 0; i < _frameCount; i++) {
          if (!mounted) return;
          await precacheImage(
              AssetImage('assets/launch/f${i.toString().padLeft(2, '0')}.png'),
              context);
        }
      }
      if (mounted) _c.forward();
    });
  }

  void _sounds() {
    final t = _c.value;
    final insertT = _isFullFlow ? 0.60 : (_isGba ? 0.56 : 0.6);
    final powerT = _isFullFlow ? 0.80 : (_isGba ? 0.94 : 0.85);
    if (!_insert && t >= insertT) {
      _insert = true;
      _play('sfx/insert.wav');
    }
    if (!_power && t >= powerT) {
      _power = true;
      _play('sfx/poweron.wav');
    }
  }

  Future<void> _play(String a) async {
    try {
      await _sfx.stop();
      await _sfx.play(AssetSource(a));
    } catch (_) {}
  }

  @override
  void dispose() {
    _c.dispose();
    _sfx.dispose();
    super.dispose();
  }

  // Timeline: 0–0.16 box cover opens (left hinge); 0.14–0.30 cartridge lifts
  // out; 0.30–0.38 crossfade to the 3D scene; 0.38–0.84 insertion + turn;
  // 0.84–1.0 power-on.
  String _label(double t) {
    if (_isFullFlow) {
      if (t < 0.30) return 'Opening the box…';
      if (t < 0.50) return 'Taking out the cartridge…';
      if (t < 0.72) return 'Inserting cartridge…';
      if (t < 0.84) return 'Powering on…';
      return 'Now loading ${widget.game.title.replaceFirst(RegExp(r'^Pok[eé]mon\s+'), '')}…';
    }
    if (_isGba) {
      if (t < 0.58) return 'Inserting cartridge…';
      if (t < 0.94) return 'Powering on…';
      return 'Now loading ${widget.game.title.replaceFirst(RegExp(r'^Pok[eé]mon\s+'), '')}…';
    }
    if (t < 0.16) return 'Opening the box…';
    if (t < 0.32) return 'Taking out the cartridge…';
    if (t < 0.70) return 'Inserting cartridge…';
    if (t < 0.84) return 'Booting…';
    return 'Now loading ${widget.game.title.replaceFirst(RegExp(r'^Pok[eé]mon\s+'), '')}…';
  }

  double _seg(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);

  // The GBA SP scene: cartridge slides up into the front slot, screen powers on.
  // [spT] runs 0..1 over the insertion+power-on phase.
  Widget _spScene(double spT) {
    final ins = (spT / 0.62).clamp(0.0, 1.0);
    final ease = 1 - math.pow(1 - ins, 2).toDouble();
    final pw = ((spT - 0.58) / 0.42).clamp(0.0, 1.0);
    return Center(
      child: AspectRatio(
        aspectRatio: 1000 / 1036,
        child: LayoutBuilder(
          builder: (ctx, c) {
            final w = c.maxWidth, h = c.maxHeight;
            final cartW = w * 0.60;
            final cartH = cartW * 358 / 640;
            final slotY = h * 0.905; // cart hidden above this = "inside the slot"
            final startBottom = h + cartH + 20;
            final restBottom = slotY + cartH * 0.30;
            final cartBottom = startBottom + (restBottom - startBottom) * ease;
            final cartTop = cartBottom - cartH;
            final cartLeft = w * 0.505 - cartW / 2;
            return Stack(
              children: [
                Positioned.fill(
                  child: Image.asset('assets/launch/sp_body.png',
                      fit: BoxFit.contain),
                ),
                // cartridge, clipped so anything above the slot line disappears
                Positioned.fill(
                  child: ClipRect(
                    clipper: _BelowLine(slotY),
                    child: Stack(
                      children: [
                        Positioned(
                          left: cartLeft,
                          top: cartTop,
                          width: cartW,
                          height: cartH,
                          child: _cartWidget(cartW, cartH),
                        ),
                      ],
                    ),
                  ),
                ),
                // screen power-on glow
                if (pw > 0.01)
                  Positioned(
                    left: w * 0.215,
                    top: h * 0.075,
                    width: w * 0.577,
                    height: h * 0.417,
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: pw,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(w * 0.02),
                            gradient: const RadialGradient(colors: [
                              Color(0xCCB6F07A),
                              Color(0x33B6F07A),
                            ]),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _cartWidget(double cw, double ch) {
    // Label rect on the cartridge (fractions from the rendered model).
    final lx = cw * 0.144, ly = ch * 0.218, lw = cw * 0.710, lh = ch * 0.662;
    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset('assets/launch/gba_cart.png', fit: BoxFit.fill),
        ),
        Positioned(
          left: lx,
          top: ly,
          width: lw,
          height: lh,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(lh * 0.12),
            child: Image.asset(
              widget.game.boxArtAsset,
              fit: BoxFit.cover,
              alignment: const Alignment(0, -0.4),
              errorBuilder: (_, _, _) =>
                  const ColoredBox(color: Color(0xFF8a2020)),
            ),
          ),
        ),
      ],
    );
  }

  // Plays the pre-rendered 3D sequence for a GBA game (closed → insert → open),
  // then a screen power-on glow once the lid is open. Frames are square.
  Widget _sp3dScene(double t) {
    final idx = (t * (_sp3dFrames - 1)).round().clamp(0, _sp3dFrames - 1);
    final pw = _seg(t, 0.94, 1.0);
    return Center(
      child: AspectRatio(
        aspectRatio: 1,
        child: LayoutBuilder(
          builder: (ctx, c) {
            final w = c.maxWidth, h = c.maxHeight;
            return Stack(
              children: [
                Positioned.fill(
                  child: Image.asset(
                    'assets/launch/sp3d/${widget.game.id}/'
                    'f${idx.toString().padLeft(2, '0')}.png',
                    gaplessPlayback: true,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
                if (pw > 0.01)
                  Positioned(
                    left: w * 0.33,
                    top: h * 0.17,
                    width: w * 0.335,
                    height: h * 0.26,
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: pw,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(w * 0.02),
                            gradient: const RadialGradient(colors: [
                              Color(0xCCB6F07A),
                              Color(0x22B6F07A),
                            ]),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  // The full box→SP launch: one pre-rendered sequence (box pull → open → cart out →
  // SP rises → insert → screen reveal → zoom). Boot screen is baked into the frames,
  // so no power-on glow overlay here. Frames are portrait 640×800 (.webp).
  Widget _fullScene(double t) {
    final idx = (t * (_fullFrames - 1)).round().clamp(0, _fullFrames - 1);
    return Center(
      child: AspectRatio(
        aspectRatio: 640 / 800,
        child: Image.asset(
          'assets/launch/full/${widget.game.id}/'
          'f${idx.toString().padLeft(2, '0')}.webp',
          gaplessPlayback: true,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final side = size.shortestSide * 0.9;
    final coverH = side * 0.5;
    final coverW = side * 0.4;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(16),
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          if (_isFullFlow) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                    width: side, height: side * 1.25, child: _fullScene(t)),
                const SizedBox(height: 12),
                Text(_label(t),
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 15)),
              ],
            );
          }
          if (_isGba) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                    width: side, height: side * 1.15, child: _sp3dScene(t)),
                const SizedBox(height: 12),
                Text(_label(t),
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 15)),
              ],
            );
          }
          // Left-hinged cover swings OUTWARD toward the viewer (positive turns
          // the free right edge up and out), opening to ~110°.
          final coverAngle =
              1.92 * Curves.easeOut.transform(_seg(t, 0.0, 0.16));
          // Past 90° we're looking at the back of the cover — show it grey.
          final coverBackVisible = coverAngle > math.pi / 2;
          final cartOut = Curves.easeInOut.transform(_seg(t, 0.14, 0.30));
          final cartY = 0.12 + (-0.55 - 0.12) * cartOut;
          final boxOpacity = 1 - _seg(t, 0.30, 0.38);
          final seqOpacity = _seg(t, 0.30, 0.38);
          final seqProg = _seg(t, 0.38, 0.84);
          final idx = (seqProg * (_frameCount - 1)).round();
          final flash = _seg(t, 0.84, 1.0);
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: side,
                height: side * 1.15,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (t == 0)
                      const Center(child: CircularProgressIndicator()),
                    // ---- Phase A: the hinged box ----
                    if (boxOpacity > 0.01) ...[
                      // box interior (revealed as the cover opens) — grey
                      Align(
                        alignment: const Alignment(0, 0.05),
                        child: Opacity(
                          opacity: boxOpacity,
                          child: Container(
                            width: coverW,
                            height: coverH,
                            decoration: BoxDecoration(
                              color: const Color(0xFF9AA0A6),
                              borderRadius: BorderRadius.circular(6),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x55000000),
                                  blurRadius: 6,
                                  spreadRadius: -2,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // cartridge sitting inside / lifting out — GBA games use
                      // the GBA cart (wearing this game's label) so it matches
                      // the one that slides into the SP.
                      Align(
                        alignment: Alignment(0, cartY),
                        child: Opacity(
                          opacity: boxOpacity,
                          child: _isGba
                              ? SizedBox(
                                  width: side * 0.42,
                                  height: side * 0.42 * 358 / 640,
                                  child: _cartWidget(
                                      side * 0.42, side * 0.42 * 358 / 640),
                                )
                              : Image.asset('assets/launch/cart.png',
                                  height: side * 0.36),
                        ),
                      ),
                      // front cover, hinged on the left edge
                      Align(
                        alignment: const Alignment(0, 0.05),
                        child: Opacity(
                          opacity: boxOpacity,
                          child: Transform(
                            alignment: Alignment.centerLeft,
                            transform: Matrix4.identity()
                              ..setEntry(3, 2, 0.0016)
                              ..rotateY(coverAngle),
                            // Front = cover art; back (once past 90°) = grey.
                            child: coverBackVisible
                                ? Container(
                                    width: coverW,
                                    height: coverH,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF9AA0A6),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  )
                                : Image.asset(widget.game.boxArtAsset,
                                    width: coverW,
                                    height: coverH,
                                    fit: BoxFit.fill,
                                    errorBuilder: (_, _, _) => Container(
                                        width: coverW,
                                        height: coverH,
                                        color: const Color(0xFF8a2020))),
                          ),
                        ),
                      ),
                    ],
                    // ---- Phase B/C: insertion sequence ----
                    if (seqOpacity > 0.01)
                      Opacity(
                        opacity: seqOpacity,
                        child: _isGba
                            ? _spScene(_seg(t, 0.38, 1.0))
                            : Image.asset(
                                'assets/launch/f${idx.toString().padLeft(2, '0')}.png',
                                gaplessPlayback: true,
                                fit: BoxFit.contain,
                              ),
                      ),
                    if (flash > 0.01)
                      IgnorePointer(
                        child: Opacity(
                          opacity: flash,
                          child: Container(
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(colors: [
                                Color(0x8C9BE04C),
                                Color(0x009BE04C),
                              ]),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(_label(t),
                  style: const TextStyle(color: Colors.white70, fontSize: 15)),
            ],
          );
        },
      ),
    );
  }
}

/// Clips to everything at or below [y] — used so the cartridge vanishes "into"
/// the SP's slot as it slides up past the slot line.
class _BelowLine extends CustomClipper<Rect> {
  final double y;
  _BelowLine(this.y);
  @override
  Rect getClip(Size size) => Rect.fromLTRB(0, y, size.width, size.height);
  @override
  bool shouldReclip(covariant _BelowLine old) => old.y != y;
}

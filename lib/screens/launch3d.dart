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

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2500))
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
      for (var i = 0; i < _frameCount; i++) {
        if (!mounted) return;
        await precacheImage(
            AssetImage('assets/launch/f${i.toString().padLeft(2, '0')}.png'),
            context);
      }
      if (mounted) _c.forward();
    });
  }

  void _sounds() {
    final t = _c.value;
    if (!_insert && t >= 0.6) {
      _insert = true;
      _play('sfx/insert.wav');
    }
    if (!_power && t >= 0.85) {
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
    if (t < 0.16) return 'Opening the box…';
    if (t < 0.32) return 'Taking out the cartridge…';
    if (t < 0.70) return 'Inserting cartridge…';
    if (t < 0.84) return 'Booting…';
    return 'Now loading ${widget.game.title.replaceFirst(RegExp(r'^Pok[eé]mon\s+'), '')}…';
  }

  double _seg(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);

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
                      // cartridge sitting inside / lifting out
                      Align(
                        alignment: Alignment(0, cartY),
                        child: Opacity(
                          opacity: boxOpacity,
                          child: Image.asset('assets/launch/cart.png',
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
                    // ---- Phase B/C: 3D insertion sequence ----
                    if (seqOpacity > 0.01)
                      Opacity(
                        opacity: seqOpacity,
                        child: Image.asset(
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

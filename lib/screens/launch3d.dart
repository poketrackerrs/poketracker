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
        vsync: this, duration: const Duration(milliseconds: 3800))
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

  // Timeline: 0–0.24 cartridge slides out of the box; 0.24–0.32 crossfade to
  // the 3D scene; 0.32–0.86 insertion + turn; 0.86–1.0 power-on.
  String _label(double t) {
    if (t < 0.24) return 'Taking out the cartridge…';
    if (t < 0.62) return 'Inserting cartridge…';
    if (t < 0.86) return 'Booting…';
    return 'Now loading ${widget.game.title.replaceFirst(RegExp(r'^Pok[eé]mon\s+'), '')}…';
  }

  double _seg(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final side = size.shortestSide * 0.9;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(16),
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          final seqProg = _seg(t, 0.32, 0.86);
          final idx = (seqProg * (_frameCount - 1)).round();
          final seqOpacity = _seg(t, 0.24, 0.34);
          final boxOpacity = 1 - _seg(t, 0.22, 0.32);
          // cartridge slides up out of the box during phase A
          final aOut = Curves.easeOut.transform(_seg(t, 0.02, 0.24));
          final cartY = 0.55 + (-0.45 - 0.55) * aOut;
          final cartStillOpacity = boxOpacity;
          final flash = _seg(t, 0.86, 1.0);
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
                    // Phase A: cartridge coming out of the box (cart behind box).
                    if (cartStillOpacity > 0.01)
                      Align(
                        alignment: Alignment(0, cartY),
                        child: Opacity(
                          opacity: cartStillOpacity,
                          child: Image.asset('assets/launch/cart.png',
                              height: side * 0.42),
                        ),
                      ),
                    if (boxOpacity > 0.01)
                      Align(
                        alignment: const Alignment(0, 0.15),
                        child: Opacity(
                          opacity: boxOpacity,
                          child: Image.asset(widget.game.boxArtAsset,
                              height: side * 0.5,
                              errorBuilder: (_, _, _) =>
                                  const SizedBox.shrink()),
                        ),
                      ),
                    // Phase B/C: the 3D insertion sequence.
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

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:gamepads/gamepads.dart';
import 'package:window_manager/window_manager.dart';
import '../models/game.dart';
import '../services/gba_emulator.dart';
import '../services/emulator_controls.dart';
import '../services/emulator_prefs.dart';
import 'controls_settings_screen.dart';

/// The built-in GBA player. Runs the mGBA core, renders frames, plays audio,
/// maps keyboard + gamepad input, and persists the battery save next to the ROM
/// (the same `.sav` the save auto-tracker reads).
class EmulatorScreen extends StatefulWidget {
  final Game game;
  final String romPath;
  const EmulatorScreen({super.key, required this.game, required this.romPath});

  @override
  State<EmulatorScreen> createState() => _EmulatorScreenState();
}

class _EmulatorScreenState extends State<EmulatorScreen>
    with WidgetsBindingObserver {
  GbaEmulator? _emu;
  ControlsConfig? _controls;
  EmulatorPrefs? _prefs;
  Timer? _timer;
  Timer? _saveTimer;
  StreamSubscription<GamepadEvent>? _padSub;
  ui.Image? _image;
  AudioSource? _pcmStream;
  bool _soloudReady = false;
  bool _decoding = false;
  bool _turboHeld = false;
  bool _turboLatch = false;
  bool _fullscreen = false;
  int _fitMode = 0; // 0 = Fill (default), 1 = Fit, 2 = Zoom
  String _status = 'starting…';
  String? _savPath;

  static const int _defaultFf = 6;

  bool get _turbo => _turboHeld || _turboLatch;
  bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  bool get _isMobile => Platform.isAndroid || Platform.isIOS;
  BoxFit get _fit => const [BoxFit.fill, BoxFit.contain, BoxFit.cover][_fitMode];
  String get _fitName => const ['Fill', 'Fit', 'Zoom'][_fitMode];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_isMobile) {
      // Landscape (both ways, so it rotates with the phone) + immersive.
      _fullscreen = true;
      // Allow all orientations so it rotates freely (landscape and portrait).
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    _boot();
  }

  Future<void> _boot() async {
    try {
      _controls = await ControlsConfig.load();
      _prefs = await EmulatorPrefs.load();
      await _initAudio();
      _applyVolume();
      final (dll, sys) = await GbaEmulator.provision();
      final emu = GbaEmulator(dll);
      emu.init(sys);
      final ok = emu.loadRom(widget.romPath);
      if (!ok) {
        if (mounted) setState(() => _status = 'The core could not load this ROM.');
        return;
      }
      _emu = emu;
      final dot = widget.romPath.lastIndexOf('.');
      _savPath =
          '${dot > 0 ? widget.romPath.substring(0, dot) : widget.romPath}.sav';
      final sav = File(_savPath!);
      if (sav.existsSync()) {
        try {
          emu.writeSaveRam(await sav.readAsBytes());
        } catch (_) {}
      }
      _setupAudioStream(emu.sampleRate);
      _padSub = Gamepads.events.listen(_onGamepad);
      if (mounted) setState(() => _status = 'running');
      _startLoop();
      _saveTimer =
          Timer.periodic(const Duration(seconds: 15), (_) => _persistSave());
    } catch (e) {
      if (mounted) setState(() => _status = 'Emulator error: $e');
    }
  }

  Future<void> _initAudio() async {
    try {
      await SoLoud.instance.init();
      _soloudReady = true;
    } catch (_) {}
  }

  Future<void> _setupAudioStream(double rate) async {
    if (!_soloudReady || _pcmStream != null) return;
    try {
      _pcmStream = SoLoud.instance.setBufferStream(
        format: BufferType.s16le,
        channels: Channels.stereo,
        sampleRate: rate.round(),
        maxBufferSizeBytes: 1024 * 1024 * 4,
        bufferingType: BufferingType.released,
        bufferingTimeNeeds: 0.2,
      );
      SoLoud.instance.play(_pcmStream!);
    } catch (_) {}
  }

  void _onGamepad(GamepadEvent e) {
    _controls?.applyGamepad(e, (bindId, on) {
      if (bindId == kFastForwardId) {
        if (on != _turboHeld) setState(() => _turboHeld = on);
        return;
      }
      final retro = _controls!.retroIdFor(bindId);
      if (retro != null) gButtons[retro] = on ? 1 : 0;
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.f11 && event is KeyDownEvent) {
      _toggleFullscreen();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape &&
        event is KeyDownEvent) {
      if (_fullscreen) {
        _toggleFullscreen();
      } else {
        _exit();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyV && event is KeyDownEvent) {
      setState(() => _fitMode = (_fitMode + 1) % 3);
      return KeyEventResult.handled;
    }
    final bindId = _controls?.bindingIdForKey(event.logicalKey);
    if (bindId == null) return KeyEventResult.ignored;
    final down = event is KeyDownEvent || event is KeyRepeatEvent;
    final up = event is KeyUpEvent;
    if (bindId == kFastForwardId) {
      if (down && !_turboHeld) setState(() => _turboHeld = true);
      if (up && _turboHeld) setState(() => _turboHeld = false);
      return KeyEventResult.handled;
    }
    final retro = _controls!.retroIdFor(bindId);
    if (retro != null) {
      if (down) {
        gButtons[retro] = 1;
      } else if (up) {
        gButtons[retro] = 0;
      }
    }
    return KeyEventResult.handled;
  }

  Future<void> _toggleFullscreen() async {
    final f = !_fullscreen;
    setState(() => _fullscreen = f);
    if (_isDesktop) {
      try {
        await windowManager.setFullScreen(f);
      } catch (_) {}
    } else if (_isMobile) {
      SystemChrome.setEnabledSystemUIMode(
          f ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
    }
  }

  void _startLoop() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final emu = _emu;
      if (emu == null || !emu.loaded) return;
      final steps = _turbo ? (_prefs?.ffSpeed ?? _defaultFf) : 1;
      for (var i = 0; i < steps; i++) {
        emu.runFrame();
      }
      if (gAudioChunks.isNotEmpty) {
        final s = _pcmStream;
        if (!_turbo && s != null && _soloudReady) {
          for (final ch in gAudioChunks) {
            try {
              SoLoud.instance.addAudioDataStream(s, ch);
            } catch (_) {}
          }
        }
        gAudioChunks.clear();
      }
      if (gFrameReady && !_decoding) {
        gFrameReady = false;
        _decoding = true;
        final w = gFrameW, h = gFrameH;
        final buf = Uint8List.fromList(gRgba!.sublist(0, w * h * 4));
        ui.decodeImageFromPixels(buf, w, h, ui.PixelFormat.rgba8888, (img) {
          _decoding = false;
          if (!mounted) {
            img.dispose();
            return;
          }
          setState(() {
            _image?.dispose();
            _image = img;
          });
        });
      }
    });
  }

  Future<void> _persistSave() async {
    final emu = _emu;
    final path = _savPath;
    if (emu == null || path == null || !emu.loaded) return;
    final data = emu.readSaveRam();
    if (data == null || data.isEmpty) return;
    try {
      await File(path).writeAsBytes(data, flush: true);
    } catch (_) {}
  }

  Future<void> _exit() async {
    await _persistSave();
    if (_fullscreen && _isDesktop) {
      try {
        await windowManager.setFullScreen(false);
      } catch (_) {}
    }
    if (mounted) Navigator.of(context).pop();
  }

  void _openControls() {
    final c = _controls;
    if (c == null) return;
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ControlsSettingsScreen(config: c)));
  }

  void _applyVolume() {
    final p = _prefs;
    if (p == null || !_soloudReady) return;
    try {
      SoLoud.instance.setGlobalVolume(p.effectiveVolume);
    } catch (_) {}
  }

  void _openEmuSettings() {
    final p = _prefs;
    if (p == null) return;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SingleChildScrollView(
          child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Audio', style: Theme.of(ctx).textTheme.titleMedium),
              Row(
                children: [
                  IconButton(
                    icon: Icon(p.muted || p.volume == 0
                        ? Icons.volume_off
                        : Icons.volume_up),
                    tooltip: p.muted ? 'Unmute' : 'Mute',
                    onPressed: () {
                      setSheet(() => p.muted = !p.muted);
                      _applyVolume();
                      p.save();
                    },
                  ),
                  Expanded(
                    child: Slider(
                      value: p.volume,
                      onChanged: (v) {
                        setSheet(() {
                          p.volume = v;
                          p.muted = false;
                        });
                        _applyVolume();
                      },
                      onChangeEnd: (_) => p.save(),
                    ),
                  ),
                  SizedBox(
                    width: 46,
                    child: Text('${(p.effectiveVolume * 100).round()}%',
                        textAlign: TextAlign.end),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text('Fast-forward speed',
                  style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: [
                  for (final s in kFfSpeeds)
                    ChoiceChip(
                      label: Text('${s}x', style: const TextStyle(fontSize: 12)),
                      selected: p.ffSpeed == s,
                      showCheckmark: false,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                      onSelected: (_) {
                        setSheet(() => p.ffSpeed = s);
                        p.save();
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _persistSave();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _saveTimer?.cancel();
    _padSub?.cancel();
    // best-effort synchronous save on teardown
    try {
      final emu = _emu;
      final path = _savPath;
      if (emu != null && path != null && emu.loaded) {
        final d = emu.readSaveRam();
        if (d != null && d.isNotEmpty) File(path).writeAsBytesSync(d);
      }
    } catch (_) {}
    try {
      _pcmStream = null;
      SoLoud.instance.deinit();
    } catch (_) {}
    try {
      _emu?.unload();
    } catch (_) {}
    if (_isDesktop) {
      try {
        windowManager.setFullScreen(false);
      } catch (_) {}
    }
    if (_isMobile) {
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    _image?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ---- on-screen touch controls (mobile) ----
  Widget _padBtn(int retroId, {IconData? icon, String? label, double size = 56}) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => gButtons[retroId] = 1,
      onPointerUp: (_) => gButtons[retroId] = 0,
      onPointerCancel: (_) => gButtons[retroId] = 0,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24),
        ),
        alignment: Alignment.center,
        child: icon != null
            ? Icon(icon, color: Colors.white, size: 28)
            : Text(label ?? '',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 20)),
      ),
    );
  }

  Widget _pillBtn(int retroId, String label) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => gButtons[retroId] = 1,
      onPointerUp: (_) => gButtons[retroId] = 0,
      onPointerCancel: (_) => gButtons[retroId] = 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white24),
        ),
        child: Text(label,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _touchControls() {
    return Positioned.fill(
      child: SafeArea(
        child: Stack(
          children: [
            // D-pad, bottom-left
            Positioned(
              left: 18,
              bottom: 18,
              width: 168,
              height: 168,
              child: Stack(
                children: [
                  Align(
                      alignment: Alignment.topCenter,
                      child: _padBtn(retroUp, icon: Icons.keyboard_arrow_up)),
                  Align(
                      alignment: Alignment.bottomCenter,
                      child:
                          _padBtn(retroDown, icon: Icons.keyboard_arrow_down)),
                  Align(
                      alignment: Alignment.centerLeft,
                      child:
                          _padBtn(retroLeft, icon: Icons.keyboard_arrow_left)),
                  Align(
                      alignment: Alignment.centerRight,
                      child: _padBtn(retroRight,
                          icon: Icons.keyboard_arrow_right)),
                ],
              ),
            ),
            // A / B, bottom-right (A upper-right, B lower-left)
            Positioned(
              right: 18,
              bottom: 18,
              width: 156,
              height: 120,
              child: Stack(
                children: [
                  Align(
                      alignment: Alignment.bottomLeft,
                      child: _padBtn(retroB, label: 'B', size: 62)),
                  Align(
                      alignment: Alignment.topRight,
                      child: _padBtn(retroA, label: 'A', size: 62)),
                ],
              ),
            ),
            // shoulders, above each cluster
            Positioned(left: 18, bottom: 196, child: _pillBtn(retroL, 'L')),
            Positioned(right: 18, bottom: 146, child: _pillBtn(retroR, 'R')),
            // start / select, bottom-center
            Positioned(
              left: 0,
              right: 0,
              bottom: 18,
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _pillBtn(retroSelect, 'SELECT'),
                    const SizedBox(width: 14),
                    _pillBtn(retroStart, 'START'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _screen(BoxFit fit) {
    final img = _image;
    if (img == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(_status, style: const TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }
    return RawImage(image: img, fit: fit, filterQuality: FilterQuality.none);
  }

  @override
  Widget build(BuildContext context) {
    final portrait =
        _isMobile && MediaQuery.of(context).orientation == Orientation.portrait;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: Colors.black)),
            if (portrait)
              Positioned(
                top: 60,
                left: 0,
                right: 0,
                child: AspectRatio(
                    aspectRatio: 3 / 2, child: _screen(BoxFit.contain)),
              )
            else
              Positioned.fill(child: _screen(_fit)),
            if (_isMobile) _touchControls(),
            Align(
              alignment: Alignment.topCenter,
              child: Container(
                color: Colors.black45,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: SafeArea(
                  bottom: false,
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back),
                        color: Colors.white,
                        tooltip: 'Back (Esc)',
                        onPressed: _exit,
                      ),
                      Expanded(
                        child: Text(
                          widget.game.title,
                          style: const TextStyle(color: Colors.white),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: Icon(_turbo
                            ? Icons.fast_forward
                            : Icons.fast_forward_outlined),
                        color: _turbo ? Colors.orange : Colors.white,
                        tooltip: 'Fast-forward (hold Tab)',
                        onPressed: () =>
                            setState(() => _turboLatch = !_turboLatch),
                      ),
                      IconButton(
                        icon: const Icon(Icons.aspect_ratio),
                        color: Colors.white,
                        tooltip: 'Scale: $_fitName (V)',
                        onPressed: () =>
                            setState(() => _fitMode = (_fitMode + 1) % 3),
                      ),
                      IconButton(
                        icon: Icon(_fullscreen
                            ? Icons.fullscreen_exit
                            : Icons.fullscreen),
                        color: Colors.white,
                        tooltip: 'Fullscreen (F11)',
                        onPressed: _toggleFullscreen,
                      ),
                      IconButton(
                        icon: const Icon(Icons.tune),
                        color: Colors.white,
                        tooltip: 'Audio & speed',
                        onPressed: _openEmuSettings,
                      ),
                      IconButton(
                        icon: const Icon(Icons.videogame_asset),
                        color: Colors.white,
                        tooltip: 'Controls',
                        onPressed: _openControls,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

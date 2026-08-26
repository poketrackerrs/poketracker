// Drives the mGBA libretro core for the built-in GBA player.
// The libretro C callbacks must be top-level static functions, so the
// per-frame state they touch lives in top-level globals below. The UI reads
// gRgba/gFrameReady for video and writes gButtons for input.
import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'libretro.dart';

// ---- state shared with the static C callbacks ----
int gPixelFormat = pf0RGB1555;
int gFrameW = 0;
int gFrameH = 0;
Uint8List? gRgba; // latest frame as RGBA8888
bool gFrameReady = false;
int gVideoFrames = 0;
Pointer<Utf8> gSysDir = nullptr;

// Pending PCM chunks (int16 stereo, little-endian) to feed the audio engine.
final List<Uint8List> gAudioChunks = <Uint8List>[];

// RetroPad button state (index = RETRO_DEVICE_ID_JOYPAD_*). 1 = pressed.
final List<int> gButtons = List<int>.filled(16, 0);

// DS touch pointer (RETRO_DEVICE_POINTER). Coords normalized to -0x7fff..0x7fff
// over the full framebuffer; the core maps them to the touch screen.
int gPointerX = 0;
int gPointerY = 0;
int gPointerDown = 0;

// Core-option overrides answered via RETRO_ENVIRONMENT_GET_VARIABLE. Values are
// kept as persistent native strings. e.g. melonDS's touch cursor -> 'disabled'.
final Map<String, Pointer<Utf8>> gVarOverrides = {};

/// Sets (or clears, when [value] is null) a core-option override, freeing any
/// previously-allocated native string for that key.
void _setVar(String key, String? value) {
  final old = gVarOverrides.remove(key);
  if (old != null) malloc.free(old);
  if (value != null) gVarOverrides[key] = value.toNativeUtf8();
}

// RETRO_DEVICE_ID_JOYPAD_* ids
const int retroB = 0;
const int retroY = 1;
const int retroSelect = 2;
const int retroStart = 3;
const int retroUp = 4;
const int retroDown = 5;
const int retroLeft = 6;
const int retroRight = 7;
const int retroA = 8;
const int retroX = 9;
const int retroL = 10;
const int retroR = 11;

bool _env(int cmd, Pointer<Void> data) {
  switch (cmd) {
    case envSetPixelFormat:
      gPixelFormat = data.cast<Int32>().value;
      return true;
    case envGetSystemDirectory:
    case envGetSaveDirectory:
      if (gSysDir != nullptr) {
        data.cast<Pointer<Utf8>>().value = gSysDir;
        return true;
      }
      return false;
    case envGetCanDupe:
      data.cast<Uint8>().value = 1;
      return true;
    case envGetCoreOptionsVersion:
      data.cast<Uint32>().value = 2; // we speak the v2 core-options API
      return true;
    case envSetVariables:
    case envSetCoreOptions:
    case envSetCoreOptionsIntl:
    case envSetCoreOptionsV2:
    case envSetCoreOptionsV2Intl:
      return true; // acknowledge; specific values come back via GET_VARIABLE
    case envGetVariableUpdate:
      data.cast<Uint8>().value = 0; // no pending option changes
      return true;
    case envGetVariable:
      if (data == nullptr) return false;
      final v = data.cast<RetroVariable>();
      if (v.ref.key == nullptr) return false;
      final override = gVarOverrides[v.ref.key.toDartString()];
      if (override != null) {
        v.ref.value = override;
        return true;
      }
      return false;
    default:
      return false;
  }
}

void _video(Pointer<Void> data, int width, int height, int pitch) {
  gVideoFrames++;
  if (data == nullptr || width == 0 || height == 0) return;
  gFrameW = width;
  gFrameH = height;
  final out = (gRgba != null && gRgba!.length == width * height * 4)
      ? gRgba!
      : Uint8List(width * height * 4);
  final src = data.cast<Uint8>().asTypedList(pitch * height);
  int di = 0;
  if (gPixelFormat == pfXRGB8888) {
    for (int y = 0; y < height; y++) {
      final row = y * pitch;
      for (int x = 0; x < width; x++) {
        final si = row + x * 4;
        out[di++] = src[si + 2];
        out[di++] = src[si + 1];
        out[di++] = src[si];
        out[di++] = 255;
      }
    }
  } else if (gPixelFormat == pfRGB565) {
    for (int y = 0; y < height; y++) {
      final row = y * pitch;
      for (int x = 0; x < width; x++) {
        final si = row + x * 2;
        final px = src[si] | (src[si + 1] << 8);
        final r = (px >> 11) & 0x1F, g = (px >> 5) & 0x3F, b = px & 0x1F;
        out[di++] = (r << 3) | (r >> 2);
        out[di++] = (g << 2) | (g >> 4);
        out[di++] = (b << 3) | (b >> 2);
        out[di++] = 255;
      }
    }
  } else {
    for (int y = 0; y < height; y++) {
      final row = y * pitch;
      for (int x = 0; x < width; x++) {
        final si = row + x * 2;
        final px = src[si] | (src[si + 1] << 8);
        final r = (px >> 10) & 0x1F, g = (px >> 5) & 0x1F, b = px & 0x1F;
        out[di++] = (r << 3) | (r >> 2);
        out[di++] = (g << 3) | (g >> 2);
        out[di++] = (b << 3) | (b >> 2);
        out[di++] = 255;
      }
    }
  }
  gRgba = out;
  gFrameReady = true;
}

void _audioSample(int left, int right) {}

int _audioBatch(Pointer<Int16> data, int frames) {
  if (frames > 0) {
    final bytes = data.cast<Uint8>().asTypedList(frames * 4);
    gAudioChunks.add(Uint8List.fromList(bytes));
    if (gAudioChunks.length > 16) gAudioChunks.removeAt(0);
  }
  return frames;
}

void _inputPoll() {}

int _inputState(int port, int device, int index, int id) {
  if (device == 1 && id >= 0 && id < gButtons.length) return gButtons[id];
  if (device == 6) {
    // RETRO_DEVICE_POINTER: X, Y, PRESSED, COUNT
    switch (id) {
      case 0:
        return gPointerX;
      case 1:
        return gPointerY;
      case 2:
        return gPointerDown;
      case 3:
        return gPointerDown; // count: 1 while a finger is down
    }
  }
  return 0;
}

class GbaEmulator {
  final LibretroCore core;
  final List<Pointer> _keepAlive = [];
  bool loaded = false;
  double fps = 60;
  double sampleRate = 32768;
  String coreName = '';

  GbaEmulator(String dllPath) : core = LibretroCore(dllPath);

  /// Provisions a bundled libretro core and returns (coreHandle, systemDir).
  /// [coreBase] is e.g. 'mgba_libretro' (GB/GBC/GBA) or 'melondsds_libretro' (DS).
  /// Windows: copies `assets/cores/<coreBase>.dll` out to a runtime path.
  /// Android: the core ships in jniLibs and loads by soname `lib<coreBase>.so`.
  static Future<(String, String)> provision(String coreBase) async {
    final support = await getApplicationSupportDirectory();
    final coresPath = '${support.path}/cores';
    await Directory(coresPath).create(recursive: true);
    if (Platform.isAndroid) {
      return ('lib$coreBase.so', coresPath);
    }
    if (Platform.isIOS) {
      // iOS forbids dlopen of a lib written outside the signed bundle, so the
      // core ships as an embedded, code-signed framework in Runner.app/
      // Frameworks/<coreBase>.framework/<coreBase>. Load it in place; the
      // system dir (BIOS etc.) still lives in the writable support dir.
      final fwks = File(Platform.resolvedExecutable).parent.path;
      final core = '$fwks/Frameworks/$coreBase.framework/$coreBase';
      return (core, coresPath);
    }
    final dll = File('$coresPath/$coreBase.dll');
    final data = await rootBundle.load('assets/cores/$coreBase.dll');
    final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    if (!dll.existsSync() || dll.lengthSync() != bytes.length) {
      await dll.writeAsBytes(bytes, flush: true);
    }
    return (dll.path, coresPath);
  }

  int get apiVersion => core.retroApiVersion();

  void init(String systemDir) {
    gSysDir = systemDir.toNativeUtf8();
    // Hide melonDS's on-screen touch cursor (default 'always' leaves a lingering
    // square on the bottom screen). Registered before the core queries options.
    gVarOverrides.putIfAbsent(
        'melonds_show_cursor', () => 'disabled'.toNativeUtf8());
    // If the user has supplied real DS BIOS + firmware, switch melonDS to Native
    // mode with direct boot so encrypted retail ROMs decrypt and run. Without
    // them the core stays on built-in FreeBIOS (which only boots decrypted ROMs).
    // Require the expected byte sizes (must match kNdsBiosSlots) so a wrong file
    // falls back to the clean FreeBIOS path instead of crashing the core.
    bool okBios(String name, List<int> sizes) {
      final f = File('$systemDir/$name');
      return f.existsSync() && sizes.contains(f.lengthSync());
    }

    final hasNdsBios = okBios('bios7.bin', const [16384]) &&
        okBios('bios9.bin', const [4096]) &&
        okBios('firmware.bin', const [131072, 262144]);
    _setVar('melonds_sysfile_mode', hasNdsBios ? 'native' : null);
    _setVar('melonds_boot_mode', hasNdsBios ? 'direct' : null);
    _setVar('melonds_firmware_nds_path', hasNdsBios ? 'firmware.bin' : null);
    core.retroSetEnvironment(Pointer.fromFunction<EnvCbNative>(_env, false));
    core.retroInit();
    core.retroSetVideoRefresh(Pointer.fromFunction<VideoCbNative>(_video));
    core.retroSetAudioSample(
        Pointer.fromFunction<AudioSampleCbNative>(_audioSample));
    core.retroSetAudioSampleBatch(
        Pointer.fromFunction<AudioBatchCbNative>(_audioBatch, 0));
    core.retroSetInputPoll(Pointer.fromFunction<InputPollCbNative>(_inputPoll));
    core.retroSetInputState(
        Pointer.fromFunction<InputStateCbNative>(_inputState, 0));
    final info = calloc<RetroSystemInfo>();
    core.retroGetSystemInfo(info);
    coreName =
        '${info.ref.libraryName.toDartString()} ${info.ref.libraryVersion.toDartString()}';
    calloc.free(info);
  }

  bool loadRom(String path) {
    final info = calloc<RetroSystemInfo>();
    core.retroGetSystemInfo(info);
    final needFullpath = info.ref.needFullpath;
    calloc.free(info);

    final game = calloc<RetroGameInfo>();
    final pathPtr = path.toNativeUtf8();
    game.ref.path = pathPtr;
    game.ref.meta = nullptr;
    Pointer<Uint8> dataPtr = nullptr;
    if (!needFullpath) {
      final bytes = File(path).readAsBytesSync();
      dataPtr = calloc<Uint8>(bytes.length);
      dataPtr.asTypedList(bytes.length).setAll(0, bytes);
      game.ref.data = dataPtr.cast();
      game.ref.size = bytes.length;
    } else {
      game.ref.data = nullptr;
      game.ref.size = 0;
    }

    final ok = core.retroLoadGame(game);
    calloc.free(game);
    _keepAlive.add(pathPtr);
    if (dataPtr != nullptr) _keepAlive.add(dataPtr);

    if (ok) {
      final av = calloc<RetroSystemAvInfo>();
      core.retroGetSystemAvInfo(av);
      fps = av.ref.timing.fps;
      sampleRate = av.ref.timing.sampleRate;
      gFrameW = av.ref.geometry.baseWidth;
      gFrameH = av.ref.geometry.baseHeight;
      calloc.free(av);
      loaded = true;
    }
    return ok;
  }

  void runFrame() => core.retroRun();

  /// Power-cycle the core (retro_reset). The battery save RAM persists across a
  /// reset, so calling this AFTER [writeSaveRam] makes the DS core boot from the
  /// just-loaded save (melonDS reads its flash at load, before writeSaveRam, so
  /// without a reset a freshly-loaded save is ignored until next launch).
  void reset() {
    try {
      core.retroReset();
    } catch (_) {}
  }

  /// Reads the cartridge battery save (SRAM/Flash) out of the core.
  Uint8List? readSaveRam() {
    final size = core.retroGetMemorySize(retroMemorySaveRam);
    if (size <= 0) return null;
    final ptr = core.retroGetMemoryData(retroMemorySaveRam);
    if (ptr == nullptr) return null;
    return Uint8List.fromList(ptr.cast<Uint8>().asTypedList(size));
  }

  /// Reads the core's system/working RAM (GBA: EWRAM) — live game state,
  /// updated every frame. Used for real-time achievement detection.
  Uint8List? readSystemRam() {
    final size = core.retroGetMemorySize(retroMemorySystemRam);
    // Sanity-guard the size (GBA EWRAM is 256 KB) so a bogus value can't cause
    // an out-of-bounds read. Anything outside a sane range → skip (fall back).
    if (size < 0x1000 || size > 0x1000000) return null;
    final ptr = core.retroGetMemoryData(retroMemorySystemRam);
    if (ptr == nullptr) return null;
    return Uint8List.fromList(ptr.cast<Uint8>().asTypedList(size));
  }

  /// Loads a battery save file's bytes into the core's SaveRAM.
  void writeSaveRam(Uint8List bytes) {
    final size = core.retroGetMemorySize(retroMemorySaveRam);
    if (size <= 0) return;
    final ptr = core.retroGetMemoryData(retroMemorySaveRam);
    if (ptr == nullptr) return;
    final dst = ptr.cast<Uint8>().asTypedList(size);
    final n = min(bytes.length, size);
    dst.setRange(0, n, bytes.sublist(0, n));
  }

  void unload() {
    if (loaded) {
      try {
        core.retroUnloadGame();
      } catch (_) {}
      loaded = false;
    }
  }
}

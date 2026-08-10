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

  static String? _coreDllPath;
  static String? _systemDir;

  /// Copies the bundled mGBA core out of assets to a runtime path and returns
  /// (dllPath, systemDir). Works in dev and release without CMake bundling.
  static Future<(String, String)> provision() async {
    if (_coreDllPath != null && _systemDir != null) {
      return (_coreDllPath!, _systemDir!);
    }
    final support = await getApplicationSupportDirectory();
    final coresPath = '${support.path}/cores';
    await Directory(coresPath).create(recursive: true);
    final dll = File('$coresPath/mgba_libretro.dll');
    final data = await rootBundle.load('assets/cores/mgba_libretro.dll');
    final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    if (!dll.existsSync() || dll.lengthSync() != bytes.length) {
      await dll.writeAsBytes(bytes, flush: true);
    }
    _coreDllPath = dll.path;
    _systemDir = coresPath;
    return (_coreDllPath!, _systemDir!);
  }

  int get apiVersion => core.retroApiVersion();

  void init(String systemDir) {
    gSysDir = systemDir.toNativeUtf8();
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

  /// Reads the cartridge battery save (SRAM/Flash) out of the core.
  Uint8List? readSaveRam() {
    final size = core.retroGetMemorySize(retroMemorySaveRam);
    if (size <= 0) return null;
    final ptr = core.retroGetMemoryData(retroMemorySaveRam);
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

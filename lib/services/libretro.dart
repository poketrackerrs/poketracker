// ignore_for_file: library_private_types_in_public_api
// Minimal FFI bindings to the libretro C ABI — enough to run the mGBA core,
// read/write battery saves, and drive video/audio/input. Proven in the spike.
import 'dart:ffi';
import 'package:ffi/ffi.dart';

// ---- environment command constants ----
const int envGetCanDupe = 3;
const int envGetVariable = 15;
const int envSetVariables = 16;
const int envGetVariableUpdate = 17;
const int envGetSystemDirectory = 9;
const int envSetPixelFormat = 10;
const int envGetSaveDirectory = 31;
const int envGetCoreOptionsVersion = 52;
const int envSetCoreOptions = 53;
const int envSetCoreOptionsIntl = 54;
const int envSetCoreOptionsV2 = 67;
const int envSetCoreOptionsV2Intl = 68;

// pixel formats
const int pf0RGB1555 = 0;
const int pfXRGB8888 = 1;
const int pfRGB565 = 2;

// memory ids
const int retroMemorySaveRam = 0;
const int retroMemorySystemRam = 2; // GBA: EWRAM (live working memory)

// ---- structs ----
final class RetroSystemInfo extends Struct {
  external Pointer<Utf8> libraryName;
  external Pointer<Utf8> libraryVersion;
  external Pointer<Utf8> validExtensions;
  @Bool()
  external bool needFullpath;
  @Bool()
  external bool blockExtract;
}

final class RetroGameGeometry extends Struct {
  @Uint32()
  external int baseWidth;
  @Uint32()
  external int baseHeight;
  @Uint32()
  external int maxWidth;
  @Uint32()
  external int maxHeight;
  @Float()
  external double aspectRatio;
}

final class RetroSystemTiming extends Struct {
  @Double()
  external double fps;
  @Double()
  external double sampleRate;
}

final class RetroSystemAvInfo extends Struct {
  external RetroGameGeometry geometry;
  external RetroSystemTiming timing;
}

final class RetroGameInfo extends Struct {
  external Pointer<Utf8> path;
  external Pointer<Void> data;
  @IntPtr()
  external int size;
  external Pointer<Utf8> meta;
}

/// retro_variable — the core sets [key]; we fill [value] with our chosen option.
final class RetroVariable extends Struct {
  external Pointer<Utf8> key;
  external Pointer<Utf8> value;
}

// ---- callback native signatures ----
typedef EnvCbNative = Bool Function(Uint32 cmd, Pointer<Void> data);
typedef VideoCbNative = Void Function(
    Pointer<Void> data, Uint32 width, Uint32 height, IntPtr pitch);
typedef AudioSampleCbNative = Void Function(Int16 left, Int16 right);
typedef AudioBatchCbNative = IntPtr Function(Pointer<Int16> data, IntPtr frames);
typedef InputPollCbNative = Void Function();
typedef InputStateCbNative = Int16 Function(
    Uint32 port, Uint32 device, Uint32 index, Uint32 id);

// ---- core function signatures ----
typedef _VoidNative = Void Function();
typedef _VoidDart = void Function();
typedef _ApiVerNative = Uint32 Function();
typedef _ApiVerDart = int Function();
typedef _GetInfoNative = Void Function(Pointer<RetroSystemInfo>);
typedef _GetInfoDart = void Function(Pointer<RetroSystemInfo>);
typedef _GetAvNative = Void Function(Pointer<RetroSystemAvInfo>);
typedef _GetAvDart = void Function(Pointer<RetroSystemAvInfo>);
typedef _LoadGameNative = Bool Function(Pointer<RetroGameInfo>);
typedef _LoadGameDart = bool Function(Pointer<RetroGameInfo>);
typedef _MemDataNative = Pointer<Void> Function(Uint32);
typedef _MemDataDart = Pointer<Void> Function(int);
typedef _MemSizeNative = IntPtr Function(Uint32);
typedef _MemSizeDart = int Function(int);

typedef _SetEnvNative = Void Function(Pointer<NativeFunction<EnvCbNative>>);
typedef _SetEnvDart = void Function(Pointer<NativeFunction<EnvCbNative>>);
typedef _SetVideoNative = Void Function(Pointer<NativeFunction<VideoCbNative>>);
typedef _SetVideoDart = void Function(Pointer<NativeFunction<VideoCbNative>>);
typedef _SetAudSNative = Void Function(
    Pointer<NativeFunction<AudioSampleCbNative>>);
typedef _SetAudSDart = void Function(
    Pointer<NativeFunction<AudioSampleCbNative>>);
typedef _SetAudBNative = Void Function(
    Pointer<NativeFunction<AudioBatchCbNative>>);
typedef _SetAudBDart = void Function(
    Pointer<NativeFunction<AudioBatchCbNative>>);
typedef _SetPollNative = Void Function(
    Pointer<NativeFunction<InputPollCbNative>>);
typedef _SetPollDart = void Function(
    Pointer<NativeFunction<InputPollCbNative>>);
typedef _SetStateNative = Void Function(
    Pointer<NativeFunction<InputStateCbNative>>);
typedef _SetStateDart = void Function(
    Pointer<NativeFunction<InputStateCbNative>>);

/// Thin wrapper that dlopen's a libretro core and looks up its exports.
class LibretroCore {
  final DynamicLibrary lib;

  late final _VoidDart retroInit =
      lib.lookupFunction<_VoidNative, _VoidDart>('retro_init');
  late final _VoidDart retroDeinit =
      lib.lookupFunction<_VoidNative, _VoidDart>('retro_deinit');
  late final _ApiVerDart retroApiVersion =
      lib.lookupFunction<_ApiVerNative, _ApiVerDart>('retro_api_version');
  late final _GetInfoDart retroGetSystemInfo =
      lib.lookupFunction<_GetInfoNative, _GetInfoDart>('retro_get_system_info');
  late final _GetAvDart retroGetSystemAvInfo = lib
      .lookupFunction<_GetAvNative, _GetAvDart>('retro_get_system_av_info');
  late final _LoadGameDart retroLoadGame =
      lib.lookupFunction<_LoadGameNative, _LoadGameDart>('retro_load_game');
  late final _VoidDart retroRun =
      lib.lookupFunction<_VoidNative, _VoidDart>('retro_run');
  late final _VoidDart retroReset =
      lib.lookupFunction<_VoidNative, _VoidDart>('retro_reset');
  late final _VoidDart retroUnloadGame =
      lib.lookupFunction<_VoidNative, _VoidDart>('retro_unload_game');
  late final _MemDataDart retroGetMemoryData =
      lib.lookupFunction<_MemDataNative, _MemDataDart>('retro_get_memory_data');
  late final _MemSizeDart retroGetMemorySize =
      lib.lookupFunction<_MemSizeNative, _MemSizeDart>('retro_get_memory_size');
  late final _SetEnvDart retroSetEnvironment =
      lib.lookupFunction<_SetEnvNative, _SetEnvDart>('retro_set_environment');
  late final _SetVideoDart retroSetVideoRefresh = lib
      .lookupFunction<_SetVideoNative, _SetVideoDart>('retro_set_video_refresh');
  late final _SetAudSDart retroSetAudioSample = lib
      .lookupFunction<_SetAudSNative, _SetAudSDart>('retro_set_audio_sample');
  late final _SetAudBDart retroSetAudioSampleBatch =
      lib.lookupFunction<_SetAudBNative, _SetAudBDart>(
          'retro_set_audio_sample_batch');
  late final _SetPollDart retroSetInputPoll = lib
      .lookupFunction<_SetPollNative, _SetPollDart>('retro_set_input_poll');
  late final _SetStateDart retroSetInputState = lib
      .lookupFunction<_SetStateNative, _SetStateDart>('retro_set_input_state');

  LibretroCore(String path) : lib = DynamicLibrary.open(path);
}

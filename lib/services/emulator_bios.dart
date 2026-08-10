// Manages the optional Nintendo DS BIOS/firmware files for the built-in melonDS
// core. These are copyrighted Nintendo files that are NOT shipped with the app —
// the user dumps them from their own DS. When all three are present in the core's
// system directory, melonDS can boot encrypted retail DS ROMs (see GbaEmulator).
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// One required DS system file. [sizes] are the byte lengths a valid dump can be.
class BiosSlot {
  final String key;
  final String fileName;
  final String label;
  final String hint;
  final List<int> sizes;
  const BiosSlot(this.key, this.fileName, this.label, this.hint, this.sizes);
}

const List<BiosSlot> kNdsBiosSlots = [
  BiosSlot('bios7', 'bios7.bin', 'DS ARM7 BIOS', 'usually 16 KB', [16384]),
  BiosSlot('bios9', 'bios9.bin', 'DS ARM9 BIOS', 'usually 4 KB', [4096]),
  BiosSlot('firmware', 'firmware.bin', 'DS firmware', '128 or 256 KB',
      [131072, 262144]),
];

/// Reads/writes the DS system files in the melonDS system directory
/// (`<AppSupport>/cores`, the same folder GbaEmulator hands the core).
class EmulatorBios {
  Future<Directory> _sysDir() async {
    final support = await getApplicationSupportDirectory();
    final d = Directory('${support.path}/cores');
    await d.create(recursive: true);
    return d;
  }

  Future<String> sysDirPath() async => (await _sysDir()).path;

  Future<File> _fileFor(BiosSlot s) async =>
      File('${(await _sysDir()).path}${Platform.pathSeparator}${s.fileName}');

  Future<int?> sizeOf(BiosSlot s) async {
    final f = await _fileFor(s);
    return f.existsSync() ? f.lengthSync() : null;
  }

  Future<bool> hasAllNds() async {
    for (final s in kNdsBiosSlots) {
      if (!(await _fileFor(s)).existsSync()) return false;
    }
    return true;
  }

  /// Writes a picked file's bytes into the system dir under the slot's name.
  Future<void> importBytes(BiosSlot s, List<int> bytes) async {
    final dst = await _fileFor(s);
    await dst.writeAsBytes(bytes, flush: true);
  }

  Future<void> remove(BiosSlot s) async {
    final f = await _fileFor(s);
    if (f.existsSync()) await f.delete();
  }
}

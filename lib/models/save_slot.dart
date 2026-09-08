/// One save "slot" for a game — a self-contained battery save the user can pick
/// to play or edit. The slot with [id] == [SaveSlot.defaultId] is the legacy
/// save that lives directly alongside the ROM (untouched by the slot system, so
/// existing saves keep working). Every other slot is a `saves/<id>/` subfolder
/// under the ROM's game folder, holding its own `<rom>.sav`.
class SaveSlot {
  static const String defaultId = 'default';

  final String id;

  /// User-facing label ("Main save", "Nuzlocke run", …).
  final String name;

  /// Absolute directory that holds this slot's `<rom>.sav` (and its backups).
  final String dirPath;

  /// True for the alongside-the-ROM legacy slot.
  final bool isDefault;

  const SaveSlot({
    required this.id,
    required this.name,
    required this.dirPath,
    required this.isDefault,
  });
}

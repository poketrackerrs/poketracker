// Conditional import: use the real dart:io implementation on Windows/Android,
// and a harmless stub on web (where the preview runs).
import 'update_installer_stub.dart'
    if (dart.library.io) 'update_installer_io.dart' as impl;

/// Downloads the update from [url], reporting 0.0-1.0 progress.
///
/// On Windows this launches the downloaded installer and exits the app so it
/// can replace files (this call does not return in that case). On Android it
/// returns the saved file path so it can be opened to install.
Future<String> downloadAndInstall(
  String url,
  void Function(double progress) onProgress,
) =>
    impl.downloadAndInstall(url, onProgress);

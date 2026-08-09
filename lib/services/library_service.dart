import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages the on-device games library folder and downloads user-supplied files
/// into it. The app ships with NO sources — every download URL is provided by
/// the user (e.g. a share link to their own Google Drive file).
class LibraryService {
  Directory? _dir;

  /// The library directory, created on first use: `Documents/PokeTracker/Games`
  Future<Directory> libraryDir() async {
    if (_dir != null) return _dir!;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}${Platform.pathSeparator}'
        'PokeTracker${Platform.pathSeparator}Games');
    if (!await dir.exists()) await dir.create(recursive: true);
    _dir = dir;
    return dir;
  }

  /// Each game gets its own subfolder: `Games/<gameId>/`.
  Future<Directory> gameDir(String gameId) async {
    final lib = await libraryDir();
    final d = Directory('${lib.path}${Platform.pathSeparator}$gameId');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  /// The ROM stored for a game (the first file in its subfolder), if any.
  Future<File?> fileForGame(String gameId) async {
    final lib = await libraryDir();
    final d = Directory('${lib.path}${Platform.pathSeparator}$gameId');
    if (!d.existsSync()) return null;
    final files = d.listSync().whereType<File>().toList();
    return files.isEmpty ? null : files.first;
  }

  Future<void> deleteForGame(String gameId) async {
    final f = await fileForGame(gameId);
    if (f != null && await f.exists()) await f.delete();
  }

  // ---- Google Drive folder mapping (drive_folders.json) ---------------
  Map<String, String>? _driveFolders;

  /// Loads the per-game Drive folder-id map from
  /// `Documents/PokeTracker/drive_folders.json` (user data, not shipped).
  Future<Map<String, String>> loadDriveFolders() async {
    if (_driveFolders != null) return _driveFolders!;
    final docs = await getApplicationDocumentsDirectory();
    final f = File('${docs.path}${Platform.pathSeparator}'
        'PokeTracker${Platform.pathSeparator}drive_folders.json');
    if (!await f.exists()) return _driveFolders = {};
    try {
      final data = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return _driveFolders = data.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return _driveFolders = {};
    }
  }

  /// Finds the current file (id + name) inside a public Drive folder by reading
  /// its lightweight folder view. Returns null if the folder is empty.
  Future<({String id, String name})?> resolveDriveFile(String folderId) async {
    final r = await http
        .get(Uri.parse('https://drive.google.com/embeddedfolderview?id=$folderId#list'))
        .timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) return null;
    final idM = RegExp(r'id="entry-([-\w]{20,})"').firstMatch(r.body);
    if (idM == null) return null;
    final nameM = RegExp(r'flip-entry-title">([^<]*)<').firstMatch(r.body);
    return (id: idM.group(1)!, name: nameM?.group(1) ?? '');
  }

  /// Resolves the ROM in a game's Drive folder, then downloads it.
  Future<File> downloadFromFolder(
    String gameId,
    String folderId,
    void Function(double progress) onProgress,
  ) async {
    final file = await resolveDriveFile(folderId);
    if (file == null) {
      throw Exception("This game's Drive folder has no file yet.");
    }
    final url = 'https://drive.google.com/uc?export=download&id=${file.id}';
    return download(gameId, url, onProgress, nameHint: file.name);
  }

  // ---- User-configured per-game source URLs ---------------------------
  Future<String?> sourceUrl(String gameId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('romsrc:$gameId');
  }

  Future<void> setSourceUrl(String gameId, String url) async {
    final prefs = await SharedPreferences.getInstance();
    if (url.trim().isEmpty) {
      await prefs.remove('romsrc:$gameId');
    } else {
      await prefs.setString('romsrc:$gameId', url.trim());
    }
  }

  /// Downloads [url] into the library, naming the file `gameId.ext`.
  /// Handles Google Drive share links (incl. large-file confirm tokens).
  Future<File> download(
    String gameId,
    String url,
    void Function(double progress) onProgress, {
    String? nameHint,
  }) async {
    final client = http.Client();
    try {
      var uri = _normalizeDrive(url);
      var resp = await client.send(http.Request('GET', uri));

      // Google Drive large-file gate returns an HTML page. Read it ONCE, build
      // a fresh confirmed URL, and send a NEW request (never re-listen to the
      // already-consumed stream).
      if (_isHtml(resp) && uri.host.contains('google.com')) {
        final body = await resp.stream.bytesToString();
        final retry = _driveRetryUri(uri, body);
        if (retry == null) {
          throw Exception('Google Drive did not return the file (check the link '
              'is set to "anyone with the link", or try again later).');
        }
        uri = retry;
        resp = await client.send(http.Request('GET', uri));
        if (_isHtml(resp)) {
          throw Exception('Google Drive blocked this download (often a daily '
              'download-quota limit on the file). Try again later.');
        }
      }
      if (resp.statusCode != 200) {
        throw HttpException('Download failed: HTTP ${resp.statusCode}');
      }

      final ext = _extensionFrom(resp, uri, nameHint);
      // Remove any existing file for this game, then save into its subfolder.
      await deleteForGame(gameId);
      final dir = await gameDir(gameId);
      final fname = (nameHint != null && nameHint.trim().isNotEmpty)
          ? _sanitize(nameHint)
          : '$gameId$ext';
      final file = File('${dir.path}${Platform.pathSeparator}$fname');
      final sink = file.openWrite();
      final total = resp.contentLength ?? 0;
      var received = 0;
      await for (final chunk in resp.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress(received / total);
      }
      await sink.close();
      return file;
    } finally {
      client.close();
    }
  }

  // ---- helpers --------------------------------------------------------
  String _sanitize(String name) =>
      name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();

  String? _driveId(Uri uri) {
    final byQuery = uri.queryParameters['id'];
    if (byQuery != null && byQuery.isNotEmpty) return byQuery;
    final m = RegExp(r'/file/d/([^/]+)').firstMatch(uri.path);
    return m?.group(1);
  }

  Uri _normalizeDrive(String url) {
    final uri = Uri.parse(url);
    if (!uri.host.contains('google.com')) return uri;
    final id = _driveId(uri);
    if (id == null) return uri;
    // Use the current large-file endpoint with confirm=t, which serves most
    // files directly and avoids the interstitial.
    return Uri.https('drive.usercontent.google.com', '/download',
        {'id': id, 'export': 'download', 'confirm': 't'});
  }

  bool _isHtml(http.StreamedResponse resp) =>
      (resp.headers['content-type'] ?? '').contains('text/html');

  /// From a Drive interstitial page, builds the confirmed download URL, pulling
  /// the confirm token and uuid the page provides.
  Uri? _driveRetryUri(Uri uri, String html) {
    final id = _driveId(uri);
    if (id == null) return null;
    final confirm = RegExp(r'name="confirm"\s+value="([^"]+)"')
            .firstMatch(html)
            ?.group(1) ??
        RegExp(r'[?&]confirm=([0-9A-Za-z_\-]+)').firstMatch(html)?.group(1) ??
        't';
    final uuid =
        RegExp(r'name="uuid"\s+value="([^"]+)"').firstMatch(html)?.group(1);
    final params = <String, String>{
      'id': id,
      'export': 'download',
      'confirm': confirm,
    };
    if (uuid != null) params['uuid'] = uuid;
    return Uri.https('drive.usercontent.google.com', '/download', params);
  }

  String _extensionFrom(http.StreamedResponse resp, Uri uri, [String? nameHint]) {
    // Prefer an explicitly resolved filename (e.g. from the Drive folder view).
    if (nameHint != null) {
      final dot = nameHint.lastIndexOf('.');
      if (dot != -1 && nameHint.length - dot <= 6) return nameHint.substring(dot);
    }
    // Then filename from content-disposition.
    final cd = resp.headers['content-disposition'];
    if (cd != null) {
      final m = RegExp(r'filename="?([^"]+)"?').firstMatch(cd);
      if (m != null) {
        final name = m.group(1)!;
        final dot = name.lastIndexOf('.');
        if (dot != -1) return name.substring(dot);
      }
    }
    // Fall back to the URL path extension.
    final path = uri.path;
    final dot = path.lastIndexOf('.');
    if (dot != -1 && path.length - dot <= 6) return path.substring(dot);
    return '.bin';
  }
}

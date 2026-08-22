import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/games_data.dart';

/// Reserved key in the Drive folder map for the user's private BIOS subfolder.
const String kBiosFolderKey = '__bios__';

/// Reserved key for the user's private "3ds firmware" Drive subfolder (holds
/// 3DS system files + an "updates" subfolder of update CIAs).
const String k3dsFolderKey = '__3ds__';

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

  /// ROM file extensions we recognise (never a save/backup).
  static const romExts = ['.gba', '.gbc', '.gb', '.nds', '.3ds', '.cia', '.srl'];

  /// The ROM stored for a game, if any. Matches only real ROM extensions so a
  /// stray save (.sav) or editor backup (`.sav.bak-<ts>`) in the folder is never
  /// mistaken for the ROM.
  Future<File?> fileForGame(String gameId) async {
    final lib = await libraryDir();
    final d = Directory('${lib.path}${Platform.pathSeparator}$gameId');
    if (!d.existsSync()) return null;
    for (final f in d.listSync().whereType<File>()) {
      final lower = f.path.toLowerCase();
      if (romExts.any((e) => lower.endsWith(e))) return f;
    }
    return null;
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
    if (await f.exists()) {
      try {
        final data = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        return _driveFolders = data.map((k, v) => MapEntry(k, v.toString()));
      } catch (_) {
        // fall through to the bundled default
      }
    }
    // No local map yet (fresh install): fall back to the mapping shipped with
    // the app, and persist it so downloads work and the user can re-link later.
    return _driveFolders = await _loadBundledDriveFolders(f);
  }

  /// Reads the mapping bundled at `assets/config/drive_folders.json`, writes it
  /// to the user's data folder, and returns it. Returns {} if not present.
  Future<Map<String, String>> _loadBundledDriveFolders(File target) async {
    try {
      final raw = await rootBundle.loadString('assets/config/drive_folders.json');
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final map = data.map((k, v) => MapEntry(k, v.toString()));
      if (map.isNotEmpty) {
        if (!await target.parent.exists()) {
          await target.parent.create(recursive: true);
        }
        await target.writeAsString(jsonEncode(map));
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  /// Extracts a Drive folder id from a share link (…/folders/ID), a ?id= URL,
  /// or a raw id.
  String? _driveFolderId(String input) {
    final t = input.trim();
    final uri = Uri.tryParse(t);
    if (uri != null) {
      final m = RegExp(r'/folders/([-\w]{20,})').firstMatch(uri.path);
      if (m != null) return m.group(1);
      final q = uri.queryParameters['id'];
      if (q != null && q.isNotEmpty) return q;
    }
    if (RegExp(r'^[-\w]{20,}$').hasMatch(t)) return t;
    return null;
  }

  /// Reads a shared parent "Pokemon" folder, matches each game subfolder to a
  /// game id, and saves the game->folderId map. Returns how many matched.
  Future<int> importDriveFolderTree(String linkOrId) async {
    final parentId = _driveFolderId(linkOrId);
    if (parentId == null) {
      throw Exception('Could not read a Drive folder ID from that link.');
    }
    final r = await http
        .get(Uri.parse('https://drive.google.com/embeddedfolderview?id=$parentId#list'))
        .timeout(const Duration(seconds: 25));
    if (r.statusCode != 200) {
      throw Exception('Could not open that folder — make sure it is shared '
          '"anyone with the link".');
    }
    final ids = RegExp(r'id="entry-([-\w]{20,})"')
        .allMatches(r.body)
        .map((m) => m.group(1)!)
        .toList();
    final names = RegExp(r'flip-entry-title">([^<]*)<')
        .allMatches(r.body)
        .map((m) => m.group(1)!)
        .toList();
    final valid = kGames.map((g) => g.id).toSet();
    const alias = {'arceus': 'legends-arceus', 'z-a': 'legends-z-a'};
    final map = <String, String>{};
    var gameMatches = 0;
    for (var i = 0; i < ids.length && i < names.length; i++) {
      var norm = names[i]
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
          .replaceAll(RegExp(r'^-+|-+$'), '');
      // Private tooling subfolders (matched before games). Check 3DS first: its
      // "3ds firmware" name also contains "firmware", which would otherwise be
      // grabbed by the DS-BIOS matcher below.
      if (norm.contains('3ds')) {
        map[k3dsFolderKey] = ids[i];
        continue;
      }
      // "BIOS and Firmware" → the DS system files (fetched into the core system
      // dir; kept private — never bundled/shipped).
      if (norm.contains('bios')) {
        map[kBiosFolderKey] = ids[i];
        continue;
      }
      final gid = alias[norm] ?? norm;
      if (valid.contains(gid)) {
        map[gid] = ids[i];
        gameMatches++;
      }
    }
    if (gameMatches == 0) {
      throw Exception('No game folders matched. Is this the "Pokemon" folder '
          'with a subfolder per game?');
    }
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}${Platform.pathSeparator}PokeTracker');
    if (!await dir.exists()) await dir.create(recursive: true);
    final f = File('${dir.path}${Platform.pathSeparator}drive_folders.json');
    await f.writeAsString(jsonEncode(map));
    _driveFolders = map;
    return map.length;
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

  /// Lists every file (id + name) in a public Drive folder.
  Future<List<({String id, String name})>> resolveDriveFiles(
      String folderId) async {
    final r = await http
        .get(Uri.parse(
            'https://drive.google.com/embeddedfolderview?id=$folderId#list'))
        .timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) return const [];
    final ids = RegExp(r'id="entry-([-\w]{20,})"')
        .allMatches(r.body)
        .map((m) => m.group(1)!)
        .toList();
    final names = RegExp(r'flip-entry-title">([^<]*)<')
        .allMatches(r.body)
        .map((m) => m.group(1)!)
        .toList();
    final out = <({String id, String name})>[];
    for (var i = 0; i < ids.length && i < names.length; i++) {
      out.add((id: ids[i], name: names[i]));
    }
    return out;
  }

  /// Downloads a single Drive file (by id) straight to [dest], reusing the
  /// large-file confirm gate. Used for BIOS files (which go in the core system
  /// dir, not the games library).
  Future<void> downloadDriveFileTo(String fileId, File dest) async {
    final url = 'https://drive.google.com/uc?export=download&id=$fileId';
    final client = http.Client();
    try {
      var uri = _normalizeDrive(url);
      var resp = await client.send(http.Request('GET', uri));
      if (_isHtml(resp) && uri.host.contains('google.com')) {
        final body = await resp.stream.bytesToString();
        final retry = _driveRetryUri(uri, body);
        if (retry == null) throw Exception('Drive did not return the file.');
        uri = retry;
        resp = await client.send(http.Request('GET', uri));
        if (_isHtml(resp)) throw Exception('Drive blocked this download.');
      }
      if (resp.statusCode != 200) {
        throw HttpException('Download failed: HTTP ${resp.statusCode}');
      }
      if (!await dest.parent.exists()) await dest.parent.create(recursive: true);
      final tmp = File('${dest.path}.part');
      final sink = tmp.openWrite();
      await for (final chunk in resp.stream) {
        sink.add(chunk);
      }
      await sink.close();
      if (await dest.exists()) await dest.delete();
      await tmp.rename(dest.path);
    } finally {
      client.close();
    }
  }

  /// Downloads the DS BIOS/firmware from the linked Drive's BIOS subfolder into
  /// [coresDir], matching each file by name. Skips files already present with a
  /// valid size. Returns the target filenames now present. [expectedSizes] maps
  /// each target name to the byte lengths that count as a good file.
  Future<List<String>> fetchNdsBios(
    String coresDir,
    Map<String, List<int>> expectedSizes,
  ) async {
    final folders = await loadDriveFolders();
    final biosFolder = folders[kBiosFolderKey];
    if (biosFolder == null) return const [];
    final files = await resolveDriveFiles(biosFolder);
    if (files.isEmpty) return const [];
    // How to recognize each target file from its Drive name.
    bool matches(String target, String name) {
      final n = name.toLowerCase();
      if (target == 'bios7.bin') return n.contains('bios7') || n.contains('arm7');
      if (target == 'bios9.bin') return n.contains('bios9') || n.contains('arm9');
      if (target == 'firmware.bin') return n.contains('firmware');
      return false;
    }

    final present = <String>[];
    for (final target in expectedSizes.keys) {
      final dest = File('$coresDir${Platform.pathSeparator}$target');
      final ok = expectedSizes[target] ?? const [];
      if (dest.existsSync() && ok.contains(dest.lengthSync())) {
        present.add(target);
        continue;
      }
      final match = files.where((f) => matches(target, f.name)).firstOrNull;
      if (match == null) continue;
      await downloadDriveFileTo(match.id, dest);
      // Only count it if it downloaded at a sane size.
      if (dest.existsSync() && (ok.isEmpty || ok.contains(dest.lengthSync()))) {
        present.add(target);
      }
    }
    return present;
  }

  /// Records a direct link to a 3DS firmware/CIA Drive folder (its contents are
  /// fetched by [fetch3dsUpdates]). Unlike the game library, this points the app
  /// straight at the folder rather than a parent that contains it.
  Future<void> set3dsFolderFromLink(String linkOrId) async {
    final id = _driveFolderId(linkOrId);
    if (id == null) {
      throw Exception('Could not read a Drive folder ID from that link.');
    }
    final current = await loadDriveFolders();
    final map = Map<String, String>.from(current)..[k3dsFolderKey] = id;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}${Platform.pathSeparator}PokeTracker');
    if (!await dir.exists()) await dir.create(recursive: true);
    final f = File('${dir.path}${Platform.pathSeparator}drive_folders.json');
    await f.writeAsString(jsonEncode(map));
    _driveFolders = map;
  }

  /// The managed folder for 3DS files: `Documents/PokeTracker/3DS Firmware`.
  Future<Directory> threeDsDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final d = Directory('${docs.path}${Platform.pathSeparator}'
        'PokeTracker${Platform.pathSeparator}3DS Firmware');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  /// Mirrors the linked "3ds firmware" Drive folder into [threeDsDir]: any files
  /// sitting directly in it go to `3DS/`, and the nested "updates" subfolder of
  /// CIAs goes to `3DS/updates/`. Skips files already downloaded (same size).
  /// Reports each downloaded filename via [onFile]. Returns the count present.
  Future<int> fetch3dsUpdates({void Function(String name)? onFile}) async {
    final folders = await loadDriveFolders();
    final root = folders[k3dsFolderKey];
    if (root == null) return 0;
    final base = await threeDsDir();
    final entries = await resolveDriveFiles(root);
    var count = 0;

    Future<void> pull(({String id, String name}) e, Directory into) async {
      final dest = File('${into.path}${Platform.pathSeparator}${_sanitize(e.name)}');
      if (dest.existsSync() && dest.lengthSync() > 0) {
        count++;
        return;
      }
      onFile?.call(e.name);
      try {
        await downloadDriveFileTo(e.id, dest);
        if (dest.existsSync() && dest.lengthSync() > 0) count++;
      } catch (_) {
        // an entry that was actually a subfolder, or a transient error — skip
      }
    }

    for (final e in entries) {
      if (e.name.toLowerCase().contains('update')) {
        // The nested "updates" folder of CIAs.
        final subDir = Directory('${base.path}${Platform.pathSeparator}updates');
        if (!await subDir.exists()) await subDir.create(recursive: true);
        for (final c in await resolveDriveFiles(e.id)) {
          await pull(c, subDir);
        }
      } else if (e.name.contains('.')) {
        // A firmware/system file sitting directly in the folder.
        await pull(e, base);
      }
    }
    return count;
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

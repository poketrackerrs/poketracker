import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Streams the update to a temp file, then launches/returns it per platform.
Future<String> downloadAndInstall(
  String url,
  void Function(double progress) onProgress,
) async {
  final client = http.Client();
  try {
    final resp = await client.send(http.Request('GET', Uri.parse(url)));
    if (resp.statusCode != 200) {
      throw HttpException('Download failed: HTTP ${resp.statusCode}');
    }
    final total = resp.contentLength ?? 0;

    final dir = await getTemporaryDirectory();
    final name = url.split('/').last.split('?').first;
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    final sink = file.openWrite();

    var received = 0;
    await for (final chunk in resp.stream) {
      sink.add(chunk);
      received += chunk.length;
      if (total > 0) onProgress(received / total);
    }
    await sink.close();

    if (Platform.isWindows) {
      // Launch the installer detached, then quit so it can overwrite the app.
      await Process.start(file.path, const [],
          mode: ProcessStartMode.detached);
      await Future.delayed(const Duration(milliseconds: 400));
      exit(0);
    }
    // Android (and others): return the path; the caller prompts to open it.
    // A later pass can auto-launch the install intent via a plugin.
    return file.path;
  } finally {
    client.close();
  }
}

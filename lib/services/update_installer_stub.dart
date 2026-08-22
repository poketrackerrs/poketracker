/// Web stub: self-update isn't applicable to the browser preview.
Future<String> downloadAndInstall(
  String url,
  void Function(double progress) onProgress,
) async {
  throw UnsupportedError('In-app updates are only available in the installed app.');
}

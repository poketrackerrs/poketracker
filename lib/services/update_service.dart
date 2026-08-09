import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import '../config.dart';

/// Describes an available update pulled from the release manifest.
class UpdateInfo {
  final String version;
  final String notes;
  final String? downloadUrl; // for the current platform, may be null
  const UpdateInfo({
    required this.version,
    required this.notes,
    required this.downloadUrl,
  });
}

/// Result of a check: either up-to-date, an available update, or an error.
class UpdateCheckResult {
  final UpdateInfo? update; // non-null => newer version available
  final String currentVersion;
  final String? error;
  const UpdateCheckResult({
    this.update,
    required this.currentVersion,
    this.error,
  });

  bool get hasUpdate => update != null;
}

class UpdateService {
  /// Fetches the manifest and compares it to the running build.
  Future<UpdateCheckResult> checkForUpdate() async {
    final info = await PackageInfo.fromPlatform();
    final current = info.version;
    try {
      final resp = await http
          .get(Uri.parse(kUpdateManifestUrl))
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) {
        return UpdateCheckResult(
          currentVersion: current,
          error: 'Feed returned HTTP ${resp.statusCode}.',
        );
      }
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final latest = (json['version'] ?? '0.0.0').toString();
      if (_isNewer(latest, current)) {
        return UpdateCheckResult(
          currentVersion: current,
          update: UpdateInfo(
            version: latest,
            notes: (json['notes'] ?? '').toString(),
            downloadUrl: _urlForPlatform(json),
          ),
        );
      }
      return UpdateCheckResult(currentVersion: current); // up to date
    } catch (e) {
      return UpdateCheckResult(
        currentVersion: current,
        error: 'Could not reach the update feed.',
      );
    }
  }

  String? _urlForPlatform(Map<String, dynamic> json) {
    if (kIsWeb) return null;
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
        return json['windows_url']?.toString();
      case TargetPlatform.android:
        return json['android_url']?.toString();
      default:
        return null;
    }
  }

  /// Returns true if [candidate] is a higher semantic version than [current].
  /// Compares dot-separated numeric parts (e.g. "1.2.0" > "1.1.9").
  static bool _isNewer(String candidate, String current) {
    List<int> parts(String v) => v
        .split('+')
        .first
        .split('.')
        .map((p) => int.tryParse(p.trim()) ?? 0)
        .toList();
    final a = parts(candidate);
    final b = parts(current);
    final len = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < len; i++) {
      final ai = i < a.length ? a[i] : 0;
      final bi = i < b.length ? b[i] : 0;
      if (ai != bi) return ai > bi;
    }
    return false;
  }
}

import 'package:flutter/material.dart';
import '../services/update_service.dart';
import '../services/update_installer.dart';

class UpdatesScreen extends StatefulWidget {
  const UpdatesScreen({super.key});

  @override
  State<UpdatesScreen> createState() => _UpdatesScreenState();
}

class _UpdatesScreenState extends State<UpdatesScreen> {
  final _service = UpdateService();
  UpdateCheckResult? _result;
  bool _checking = false;
  bool _downloading = false;
  double _progress = 0;
  String? _message;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _message = null;
    });
    final result = await _service.checkForUpdate();
    if (!mounted) return;
    setState(() {
      _result = result;
      _checking = false;
    });
  }

  Future<void> _install() async {
    final url = _result?.update?.downloadUrl;
    if (url == null) {
      setState(() => _message = 'No download is available for this platform.');
      return;
    }
    setState(() {
      _downloading = true;
      _progress = 0;
      _message = null;
    });
    try {
      await downloadAndInstall(url, (p) {
        if (mounted) setState(() => _progress = p);
      });
      // On Windows the app exits before reaching here; this is the Android path.
      if (mounted) {
        setState(() {
          _downloading = false;
          _message = 'Update downloaded. Follow the installer prompt to finish.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloading = false;
          _message = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('Updates')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.system_update, size: 64),
            const SizedBox(height: 12),
            Center(
              child: Text(
                r == null
                    ? 'Current version: …'
                    : 'Current version: ${r.currentVersion}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 20),
            if (_checking)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (r != null && r.hasUpdate) ...[
              Text('Update available: v${r.update!.version}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              // The action stays at the top so it's always reachable, even when
              // the release notes are long.
              if (_downloading) ...[
                LinearProgressIndicator(value: _progress),
                const SizedBox(height: 8),
                Center(child: Text('${(_progress * 100).round()}%')),
              ] else
                FilledButton.icon(
                  onPressed: _install,
                  icon: const Icon(Icons.download),
                  label: const Text('Download & install'),
                ),
              if (_message != null) ...[
                const SizedBox(height: 12),
                Text(_message!, textAlign: TextAlign.center),
              ],
              if (r.update!.notes.isNotEmpty) ...[
                const SizedBox(height: 16),
                Expanded(
                  child: Card(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: SingleChildScrollView(
                        child: Text(r.update!.notes),
                      ),
                    ),
                  ),
                ),
              ] else
                const Spacer(),
            ] else if (r != null && r.error != null) ...[
              Expanded(
                child: Center(
                    child: Text(r.error!, textAlign: TextAlign.center)),
              ),
            ] else if (r != null) ...[
              const Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 40),
                      SizedBox(height: 8),
                      Text("You're on the latest version."),
                    ],
                  ),
                ),
              ),
              if (_message != null) ...[
                const SizedBox(height: 12),
                Text(_message!, textAlign: TextAlign.center),
              ],
            ] else
              const Spacer(),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _checking || _downloading ? null : _check,
              icon: const Icon(Icons.refresh),
              label: const Text('Check again'),
            ),
          ],
        ),
      ),
    );
  }
}

/// App-wide configuration.
///
/// The auto-updater reads a small JSON "manifest" from [kUpdateManifestUrl].
/// Host that file anywhere reachable over HTTPS — the natural choice is a
/// GitHub Releases asset or a raw file in your repo. Expected shape:
///
/// {
///   "version": "1.1.0",
///   "notes": "What changed in this release...",
///   "windows_url": "https://github.com/you/poketracker/releases/download/v1.1.0/PokeTracker-Setup-1.1.0.exe",
///   "android_url": "https://github.com/you/poketracker/releases/download/v1.1.0/poketracker-1.1.0.apk"
/// }
///
/// Leave it as the placeholder for now; "Check for updates" will simply report
/// that it can't reach a feed until you set a real URL and publish a release.
const String kUpdateManifestUrl =
    'https://raw.githubusercontent.com/poketrackerrs/poketracker/main/update.json';

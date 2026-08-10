---
tags: [poketracker, maintainer, constraints, legal]
---
# Constraints and Legal

> [!danger] Read before doing anything "helpful"
> These are the project's non-negotiable rules. They exist because this is a **personal, never-distributed** app.

## The rules
1. **Personal use only.** The owner has repeatedly said this "will never be distributed to anyone other than myself." The public GitHub repo exists only so they can build/sync between their own devices.
2. **Never build a ROM downloader / distribution pipeline.** ROM *downloading* has been declined multiple times. The app only manages the user's **own** legally-dumped ROMs — they supply their own source URLs / Drive links. See [[ROM Library and Downloads]].
3. **Box art is a private-use fair-use call.** Covers/wraps/models are committed because the repo is never distributed. If it's ever repackaged for distribution, the covers are **copyrighted** — revisit then.
4. **Never commit built binaries** (`*.apk`, `*.aab`, `*-Setup.exe`). Regenerable + large; `.gitignore` excludes them. Release binaries go **only** as GitHub Release assets. See [[Build and Release]].

## What's committed (and why it's OK for private use)
- All box art: covers, wraps, `.glb` models, launch frames — see [[Box Art System]]. A plain `git clone` yields the **complete, buildable** project; only `assets/games/dielines/*` is gitignored.

## Sensitive bundled data — review before any public release
> [!warning] The single biggest thing to review if this ever goes public
> `assets/config/drive_folders.json` ships **real Google Drive folder ids** (pointing at the owner's ROM sources) and is baked into every build via `LibraryService._loadBundledDriveFolders`. It also contains a stray `green` key matching no game id. See [[Services]] and [[Gotchas]].

## Platform choices that block store distribution (intentional for a sideloaded build)
- Android `MANAGE_EXTERNAL_STORAGE` (all-files access) — needed for the Lemuroid folder sync; would block a Play Store listing.
- `REQUEST_INSTALL_PACKAGES` — needed for in-app [[Auto-Update]].
- iOS ships **unsigned** via CI (sideload with AltStore/Sideloadly); no iOS auto-update. CI builds also lack the local covers.

## If distribution is ever reconsidered
- Strip/replace copyrighted covers (there's history for a **cover-less build** that backs up `assets/games` covers, builds, then restores them).
- Remove the bundled `drive_folders.json`.
- Revisit the Android permissions.

---
Related: [[Overview]] · [[ROM Library and Downloads]] · [[Build and Release]] · [[Gotchas]]

import 'dart:typed_data';

import 'gen3_save_editor.dart';

/// Live reads from the emulator's working RAM (EWRAM). Each field is null if
/// that SaveBlock couldn't be located + validated, so callers fall back safely.
class Gen3LiveRam {
  final Set<int>? caughtDex; // national ids owned (live), or null
  final bool Function(int flag)? flagOf; // live event-flag reader, or null
  const Gen3LiveRam({this.caughtDex, this.flagOf});
  bool get any => caughtDex != null || flagOf != null;
}

// Find [needle] in [hay]; -1 if absent. [verify] guards against false hits.
int _find(Uint8List hay, Uint8List needle, {bool Function(int) verify = _yes}) {
  if (needle.isEmpty) return -1;
  final first = needle[0];
  final maxI = hay.length - needle.length;
  outer:
  for (var i = 0; i <= maxI; i++) {
    if (hay[i] != first) continue;
    for (var j = 1; j < needle.length; j++) {
      if (hay[i + j] != needle[j]) continue outer;
    }
    if (verify(i)) return i;
  }
  return -1;
}

bool _yes(int _) => true;

/// Locate SaveBlock1 (event flags) and SaveBlock2 (owned dex) inside [ewram] by
/// fingerprinting stable bytes from the [committed] save (trainer id, party
/// PIDs), then read live progress. Version-independent — no hardcoded addresses.
Gen3LiveRam readGen3LiveRam(
    Uint8List ewram, Gen3SaveEditor committed, String version, int dexMax) {
  Set<int>? caught;
  bool Function(int)? flagOf;

  // SaveBlock2: anchor on OT name + trainer id (16 bytes, unique per save).
  try {
    final needle = committed.sb2Bytes(0x00, 16);
    final tid = needle[0x0A] | (needle[0x0B] << 8);
    // Require a non-empty OT name so we don't match a zero run.
    if (needle.take(7).any((b) => b != 0)) {
      final at = _find(ewram, needle,
          verify: (i) => (ewram[i + 0x0A] | (ewram[i + 0x0B] << 8)) == tid);
      if (at >= 0) {
        final base = at + Gen3SaveEditor.ownedDexOffset;
        final owned = <int>{};
        for (var d = 0; d < dexMax; d++) {
          final b = base + (d >> 3);
          if (b < ewram.length && (ewram[b] & (1 << (d & 7))) != 0) {
            owned.add(d + 1);
          }
        }
        caught = owned;
      }
    }
  } catch (_) {}

  // SaveBlock1: anchor on party slot-0 PID+OTID (8 bytes), verified by slot-1's
  // PID+OTID 100 bytes on. PIDs never change for a given Pokémon, so this holds
  // through gameplay.
  try {
    final s0 = committed.partySlot0Logical(version);
    final n0 = committed.sb1Logical(s0, 8);
    if (n0.any((b) => b != 0)) {
      final n1 = committed.sb1Logical(s0 + 100, 8);
      final hasSlot1 = n1.any((b) => b != 0);
      final at = _find(ewram, n0, verify: (i) {
        if (!hasSlot1) return true;
        for (var j = 0; j < 8; j++) {
          final k = i + 100 + j;
          if (k >= ewram.length || ewram[k] != n1[j]) return false;
        }
        return true;
      });
      if (at >= 0) {
        final flagBase = (at - s0) + committed.eventFlagLogical(version);
        flagOf = (flag) {
          final b = flagBase + (flag >> 3);
          if (b < 0 || b >= ewram.length) return false;
          return (ewram[b] & (1 << (flag & 7))) != 0;
        };
      }
    }
  } catch (_) {}

  return Gen3LiveRam(caughtDex: caught, flagOf: flagOf);
}

import 'dart:typed_data';

/// Gen 6/7 (3DS: X/Y, ORAS, Sun/Moon, Ultra Sun/Ultra Moon) text codec.
///
/// IMPORTANT DIFFERENCE FROM GEN 4/5: the 3DS games ABANDONED the proprietary
/// 0x01xx character table. Names are stored as raw **UTF-16 little-endian code
/// units**, terminated by 0x0000 and padded afterwards with 0x0000. (PKHeX's
/// `StringConverter6`.) A few glyphs use private-use remaps — full/half-width
/// punctuation and the ♂/♀ gender symbols (U+E08E / U+E08F in-game) — but the
/// entire ASCII/Latin printable set round-trips as plain UTF-16, which is all an
/// English SM/USUM nickname or OT name needs.
///
/// So this is NOT gen5_text: it is straight UTF-16LE. Do not reuse the Gen 5
/// table here.
const int _terminator = 0x0000;

// In-game private-use code points for the gender symbols (PKHeX maps these to
// the real Unicode ♂/♀ on display). Included so team names with them survive.
const int _inGameMale = 0xE08E;
const int _inGameFemale = 0xE08F;
const int _uniMale = 0x2642; // ♂
const int _uniFemale = 0x2640; // ♀

/// Decode up to [maxChars] UTF-16 code units starting at byte [start],
/// stopping at the 0x0000 terminator.
String gen7DecodeText(Uint8List bytes, int start, int maxChars) {
  final units = <int>[];
  for (var i = 0; i < maxChars; i++) {
    final o = start + i * 2;
    if (o + 1 >= bytes.length) break;
    var v = bytes[o] | (bytes[o + 1] << 8);
    if (v == _terminator) break;
    if (v == _inGameMale) v = _uniMale;
    if (v == _inGameFemale) v = _uniFemale;
    units.add(v);
  }
  return String.fromCharCodes(units);
}

/// Encode [text] into a UTF-16LE field of [maxChars] code-unit slots
/// (2 * maxChars bytes) at [start]: the code units, one 0x0000 terminator, then
/// 0x0000 padding — exactly the layout the games write. [text] is truncated to
/// `maxChars - 1` code units to leave room for the terminator.
void gen7EncodeText(Uint8List bytes, int start, int maxChars, String text) {
  final src = text.codeUnits; // UTF-16 code units
  final maxGlyphs = maxChars > 0 ? maxChars - 1 : 0;
  final n = src.length < maxGlyphs ? src.length : maxGlyphs;
  for (var i = 0; i < maxChars; i++) {
    final o = start + i * 2;
    int v;
    if (i < n) {
      v = src[i];
      if (v == _uniMale) v = _inGameMale;
      if (v == _uniFemale) v = _inGameFemale;
    } else {
      v = _terminator; // terminator at i == n, then padding stays 0x0000 too
    }
    bytes[o] = v & 0xFF;
    bytes[o + 1] = (v >> 8) & 0xFF;
  }
}

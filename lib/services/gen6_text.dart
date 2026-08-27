import 'dart:typed_data';

/// Gen 6 (X/Y, Omega Ruby/Alpha Sapphire) text codec.
///
/// This is the BIG codec change from Gen 4/5. Where Gen 4/5 stored strings as
/// 16-bit indices into a proprietary character table terminated by `0xFFFF`,
/// Gen 6 (the 3DS games) store strings as **native UTF-16 little-endian code
/// units**, terminated by `0x0000` and padded afterwards with `0x0000`.
/// (PKHeX `StringConverter6`: `const ushort TerminatorNull = 0;` and each u16 is
/// cast directly to a char — identity mapping for the whole BMP, ASCII included.)
///
/// The only remap PKHeX applies is the male/female gender symbols, which live in
/// a private-use area in-game. For Latin names (A–Z, a–z, 0–9, space, common
/// punctuation) the stored code units are just the Unicode code points, so this
/// codec is a straight UTF-16LE read/write. Gender-symbol remap is intentionally
/// omitted (documented limitation — irrelevant for our injected/read names).
const int _gen6Terminator = 0x0000;

// PKHeX NormalizeGenderSymbol mappings (in-game private-use <-> Unicode).
// Included so nicknames containing ♂/♀ round-trip; harmless for plain ASCII.
const int _pkGlyphMale = 0x246D; // in-game codepoint for ♂ (Gen 6/7)
const int _pkGlyphFemale = 0x246E; // in-game codepoint for ♀
const int _uniMale = 0x2642; // ♂
const int _uniFemale = 0x2640; // ♀

int _normalize(int cp) {
  if (cp == _pkGlyphMale) return _uniMale;
  if (cp == _pkGlyphFemale) return _uniFemale;
  return cp;
}

int _unnormalize(int cp) {
  if (cp == _uniMale) return _pkGlyphMale;
  if (cp == _uniFemale) return _pkGlyphFemale;
  return cp;
}

/// Decode up to [maxChars] Gen 6 characters (2 bytes each) starting at byte
/// [start]. Stops at the `0x0000` terminator.
String gen6DecodeText(Uint8List bytes, int start, int maxChars) {
  final units = <int>[];
  for (var i = 0; i < maxChars; i++) {
    final o = start + i * 2;
    if (o + 1 >= bytes.length) break;
    final v = bytes[o] | (bytes[o + 1] << 8);
    if (v == _gen6Terminator) break;
    units.add(_normalize(v));
  }
  return String.fromCharCodes(units);
}

/// Encode [text] into a Gen 6 string field of [maxChars] character slots
/// (2 × maxChars bytes) at [start]: UTF-16LE code units, one `0x0000`
/// terminator, then `0x0000` padding — exactly the games' layout.
///
/// [maxChars] counts total u16 slots including the terminator; e.g. a 26-byte
/// nickname field is `maxChars = 13` (12 glyphs + terminator).
void gen6EncodeText(Uint8List bytes, int start, int maxChars, String text) {
  final units = text.codeUnits; // UTF-16 code units
  final maxGlyphs = maxChars > 0 ? maxChars - 1 : 0;
  final n = units.length < maxGlyphs ? units.length : maxGlyphs;
  for (var i = 0; i < maxChars; i++) {
    final o = start + i * 2;
    int v;
    if (i < n) {
      v = _unnormalize(units[i]) & 0xFFFF;
    } else {
      v = _gen6Terminator; // terminator at i==n, then padding (also 0x0000)
    }
    bytes[o] = v & 0xFF;
    bytes[o + 1] = (v >> 8) & 0xFF;
  }
}

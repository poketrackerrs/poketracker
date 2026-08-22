import 'dart:typed_data';

/// Gen 4 (Diamond/Pearl/Platinum, HGSS) text codec.
///
/// Gen 4 stores strings as an array of 16-bit little-endian codepoints in a
/// proprietary character table, terminated by 0xFFFF and padded afterwards with
/// 0x0000. This maps the Western printable set (digits, A–Z, a–z, space and the
/// common punctuation) to/from that table.
///
/// The letter/digit ranges were confirmed **empirically** against a real
/// Platinum save: the general-block OT name decodes to "Rafael", the same string
/// appears again as a decrypted PK4 nickname, and the rival's default name
/// decodes to "Barry" — all with the mapping below. Punctuation values that
/// couldn't be observed in that save are taken from the documented Gen 4
/// character-index table and marked accordingly.
///
/// Verified Western ranges (raw codepoint → char):
///   0x0121–0x012A → '0'–'9'
///   0x012B–0x0144 → 'A'–'Z'
///   0x0145–0x015E → 'a'–'z'
///   0x0001        → ' ' (space)
///   0xFFFF        → terminator, 0x0000 → padding
const int _gen4Terminator = 0xFFFF;
const int _gen4Padding = 0x0000;
const int _gen4Space = 0x0001;

/// Extra (non-contiguous) glyphs from the documented Gen 4 Western table. These
/// were not present in the verification save, so treat them as reference values
/// rather than save-verified. Round-trips regardless (decode/encode share it).
const Map<int, String> _gen4Punct = {
  _gen4Space: ' ',
  0x01AB: '!',
  0x01AC: '?',
  0x01AD: ',',
  0x01AE: '.',
  0x01B5: '/',
  0x01B6: "'",
  0x01BC: '-',
  0x01F4: '(',
  0x01F5: ')',
  0x01B3: ':',
  0x01AF: '&',
};

/// Raw codepoint → character (built once). Letters/digits are the contiguous,
/// empirically-verified ranges; punctuation comes from [_gen4Punct].
final Map<int, String> _gen4ToChar = () {
  final m = <int, String>{};
  for (var i = 0; i < 10; i++) {
    m[0x0121 + i] = '$i'; // 0-9
  }
  for (var i = 0; i < 26; i++) {
    m[0x012B + i] = String.fromCharCode(65 + i); // A-Z
  }
  for (var i = 0; i < 26; i++) {
    m[0x0145 + i] = String.fromCharCode(97 + i); // a-z
  }
  m.addAll(_gen4Punct);
  return m;
}();

/// Character → raw codepoint (inverse of [_gen4ToChar]).
final Map<String, int> _charToGen4 = {
  for (final e in _gen4ToChar.entries) e.value: e.key
};

/// Decode up to [maxChars] Gen 4 characters starting at byte [start]. Stops at
/// the 0xFFFF terminator. Unmapped codepoints decode to '' (skipped) so a stray
/// glyph never corrupts the readable part of a name.
String gen4DecodeText(Uint8List bytes, int start, int maxChars) {
  final sb = StringBuffer();
  for (var i = 0; i < maxChars; i++) {
    final o = start + i * 2;
    if (o + 1 >= bytes.length) break;
    final v = bytes[o] | (bytes[o + 1] << 8);
    if (v == _gen4Terminator) break;
    sb.write(_gen4ToChar[v] ?? '');
  }
  return sb.toString().trimRight();
}

/// Encode [text] into a Gen 4 string field of [maxChars] character slots
/// (2 × maxChars bytes) starting at [start]. Writes the mapped codepoints, then
/// a single 0xFFFF terminator, then 0x0000 padding for the rest — exactly the
/// layout the games write. Characters beyond the field (leaving room for the
/// terminator) are dropped; unmappable characters become a space.
void gen4EncodeText(Uint8List bytes, int start, int maxChars, String text) {
  // Always reserve the final slot for the terminator, matching the games.
  final maxGlyphs = maxChars > 0 ? maxChars - 1 : 0;
  final n = text.length < maxGlyphs ? text.length : maxGlyphs;
  for (var i = 0; i < maxChars; i++) {
    final o = start + i * 2;
    int v;
    if (i < n) {
      v = _charToGen4[text[i]] ?? _gen4Space;
    } else if (i == n) {
      v = _gen4Terminator;
    } else {
      v = _gen4Padding;
    }
    bytes[o] = v & 0xFF;
    bytes[o + 1] = (v >> 8) & 0xFF;
  }
}

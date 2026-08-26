import 'dart:typed_data';

/// Gen 5 (Black/White, Black 2/White 2) text codec.
///
/// Gen 5 keeps Gen 4's scheme: strings are an array of 16-bit little-endian
/// codepoints in the proprietary character table, terminated by 0xFFFF and
/// padded afterwards with 0x0000. For the Western printable set (digits, A–Z,
/// a–z, space, common punctuation) the code points are the SAME as Gen 4, so
/// this table is copied verbatim from the verified `gen4_text.dart`. (Only a
/// handful of Japanese/Korean glyphs differ between the Gen 4 and Gen 5 tables;
/// English text round-trips identically.)
const int _gen5Terminator = 0xFFFF;
const int _gen5Padding = 0x0000;
const int _gen5Space = 0x0001;

const Map<int, String> _gen5Punct = {
  _gen5Space: ' ',
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

final Map<int, String> _gen5ToChar = () {
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
  m.addAll(_gen5Punct);
  return m;
}();

final Map<String, int> _charToGen5 = {
  for (final e in _gen5ToChar.entries) e.value: e.key
};

/// Decode up to [maxChars] Gen 5 characters starting at byte [start]. Stops at
/// the 0xFFFF terminator. Unmapped codepoints are skipped.
String gen5DecodeText(Uint8List bytes, int start, int maxChars) {
  final sb = StringBuffer();
  for (var i = 0; i < maxChars; i++) {
    final o = start + i * 2;
    if (o + 1 >= bytes.length) break;
    final v = bytes[o] | (bytes[o + 1] << 8);
    if (v == _gen5Terminator) break;
    sb.write(_gen5ToChar[v] ?? '');
  }
  return sb.toString().trimRight();
}

/// Encode [text] into a Gen 5 string field of [maxChars] character slots
/// (2 × maxChars bytes) at [start]: mapped codepoints, one 0xFFFF terminator,
/// then 0x0000 padding — exactly the layout the games write.
void gen5EncodeText(Uint8List bytes, int start, int maxChars, String text) {
  final maxGlyphs = maxChars > 0 ? maxChars - 1 : 0;
  final n = text.length < maxGlyphs ? text.length : maxGlyphs;
  for (var i = 0; i < maxChars; i++) {
    final o = start + i * 2;
    int v;
    if (i < n) {
      v = _charToGen5[text[i]] ?? _gen5Space;
    } else if (i == n) {
      v = _gen5Terminator;
    } else {
      v = _gen5Padding;
    }
    bytes[o] = v & 0xFF;
    bytes[o + 1] = (v >> 8) & 0xFF;
  }
}

import 'package:flutter/material.dart';

/// Signature accent color for each region, used for section headers and each
/// game's completion ring when "region tinting" is enabled.
const Map<String, Color> kRegionColors = {
  'Kanto': Color(0xFFEE1515),
  'Johto': Color(0xFFD9A406),
  'Hoenn': Color(0xFF12A17A),
  'Sinnoh': Color(0xFF5B6BD6),
  'Unova': Color(0xFF57636E),
  'Kalos': Color(0xFFC13B8E),
  'Alola': Color(0xFFFF8A3D),
  'Galar': Color(0xFF7B4BD6),
  'Paldea': Color(0xFFD03A45),
  'Hisui': Color(0xFF3E8E7E),
};

/// Region color, or [fallback] (typically the user's accent) if unknown.
Color regionColor(String region, Color fallback) =>
    kRegionColors[region] ?? fallback;

/// Accent swatches offered in Settings.
const List<Color> kAccentChoices = [
  Color(0xFFEE1515), // Poke Ball red
  Color(0xFF2F6FD0), // blue
  Color(0xFF12A17A), // teal
  Color(0xFFC13B8E), // magenta
  Color(0xFFD9A406), // gold
  Color(0xFF6B4BD6), // violet
];

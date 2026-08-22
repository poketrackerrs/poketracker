import 'package:flutter/material.dart';

/// Pokémon type → brand color, shared by the Pokédex entry page and the save
/// editor so they read as one visual system.
const Map<String, Color> kTypeColors = {
  'normal': Color(0xFFA8A77A), 'fire': Color(0xFFEE8130),
  'water': Color(0xFF6390F0), 'electric': Color(0xFFF7D02C),
  'grass': Color(0xFF7AC74C), 'ice': Color(0xFF96D9D6),
  'fighting': Color(0xFFC22E28), 'poison': Color(0xFFA33EA1),
  'ground': Color(0xFFE2BF65), 'flying': Color(0xFFA98FF3),
  'psychic': Color(0xFFF95587), 'bug': Color(0xFFA6B91A),
  'rock': Color(0xFFB6A136), 'ghost': Color(0xFF735797),
  'dragon': Color(0xFF6F35FC), 'dark': Color(0xFF705746),
  'steel': Color(0xFFB7B7CE), 'fairy': Color(0xFFD685AD),
};

Color typeColor(String type) => kTypeColors[type] ?? const Color(0xFF9AA0A6);

/// A small colored type chip (used in the move rows and headers).
class TypeChip extends StatelessWidget {
  final String type;
  final double fontSize;
  const TypeChip(this.type, {super.key, this.fontSize = 10});
  @override
  Widget build(BuildContext context) {
    if (type.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: typeColor(type),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        type.toUpperCase(),
        style: TextStyle(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5),
      ),
    );
  }
}

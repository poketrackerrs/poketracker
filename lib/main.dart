import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'state/app_state.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState()..init(),
      child: const PokeTrackerApp(),
    ),
  );
}

class PokeTrackerApp extends StatelessWidget {
  const PokeTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFFEE1515), // Poke Ball red
      brightness: Brightness.light,
    );
    final darkScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFFEE1515),
      brightness: Brightness.dark,
    );
    return MaterialApp(
      title: 'PokeTracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: scheme, useMaterial3: true),
      darkTheme: ThemeData(colorScheme: darkScheme, useMaterial3: true),
      themeMode: context.watch<AppState>().themeMode,
      home: const HomeScreen(),
    );
  }
}

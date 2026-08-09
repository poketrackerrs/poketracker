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
    final accent = context.watch<AppState>().accent;
    return MaterialApp(
      title: 'PokeTracker',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(accent, Brightness.light),
      darkTheme: _buildTheme(accent, Brightness.dark),
      themeMode: context.watch<AppState>().themeMode,
      home: const HomeScreen(),
    );
  }

  ThemeData _buildTheme(Color seed, Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    final dark = brightness == Brightness.dark;
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: dark
          ? const Color(0xFF0F1013)
          : const Color(0xFFF5F6F8),
      cardTheme: CardThemeData(
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        color: dark ? const Color(0xFF1B1D22) : Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: dark ? 0.5 : 0.7)),
        ),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        scrolledUnderElevation: 2,
        backgroundColor: dark ? const Color(0xFF15171B) : Colors.white,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: dark ? const Color(0xFF15171B) : Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        height: 66,
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ),
      chipTheme: ChipThemeData(
        side: BorderSide.none,
        backgroundColor: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        labelStyle: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: dark ? 0.5 : 0.7),
      ),
    );
  }
}

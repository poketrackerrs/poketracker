// Throwaway: loops the real showLaunch3D for a GBA game so the SP launch can be
// screenshotted in the actual Flutter engine. Run:
//   flutter run -d windows -t tool/launch_preview.dart
import 'package:flutter/material.dart';
import 'package:poketracker/screens/launch3d.dart';
import 'package:poketracker/data/games_data.dart';

void main() => runApp(const _App());

class _App extends StatelessWidget {
  const _App();
  @override
  Widget build(BuildContext context) => const MaterialApp(
      debugShowCheckedModeBanner: false, home: _Home());
}

class _Home extends StatefulWidget {
  const _Home();
  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loop());
  }

  Future<void> _loop() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    while (mounted) {
      final game = kGames.firstWhere((g) => g.id == 'emerald');
      await showLaunch3D(context,
          game: game,
          onLaunch: () async =>
              Future<void>.delayed(const Duration(milliseconds: 350)));
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text('launch preview',
              style: TextStyle(color: Colors.white24)),
        ),
      );
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/games_data.dart';
import '../models/game.dart';
import '../state/app_state.dart';

/// The Pokémon Vault: a game-independent store. Copy Pokémon here from any
/// Gen 3 game (PC Boxes → Save to Vault), then copy or clone them into other
/// Gen 3 games from here.
class VaultScreen extends StatelessWidget {
  const VaultScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pokémon Vault')),
      body: Consumer<AppState>(
        builder: (context, state, _) {
          if (state.vault.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Your Vault is empty.\n\nOpen a Gen 3 game → Edit save → '
                  'PC Boxes, tap a Pokémon and "Save to Vault". Then copy or '
                  'clone it into any other Gen 3 game from here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            );
          }
          return ListView.separated(
            itemCount: state.vault.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final v = state.vault[i];
              return ListTile(
                leading: Icon(v.shiny ? Icons.star : Icons.catching_pokemon,
                    color: v.shiny ? Colors.amber : null),
                title: Text('${v.name}${v.shiny ? '  ★' : ''}'),
                subtitle: Text('Lv ${v.level}  ·  #${v.dex}'),
                trailing: const Icon(Icons.more_vert),
                onTap: () => _actions(context, state, i),
              );
            },
          );
        },
      ),
    );
  }

  void _actions(BuildContext context, AppState state, int i) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.send_to_mobile),
              title: const Text('Copy to a game'),
              subtitle: const Text('Clone into another Gen 3 game'),
              onTap: () {
                Navigator.pop(context);
                _copyTo(context, state, i);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Duplicate in Vault'),
              onTap: () {
                state.duplicateInVault(i);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Remove from Vault',
                  style: TextStyle(color: Colors.red)),
              onTap: () {
                state.removeFromVault(i);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copyTo(BuildContext context, AppState state, int i) async {
    final gen3 = [
      for (final g in kGames)
        if (g.generation == 3 && state.isInstalled(g.id)) g
    ];
    if (gen3.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No installed Gen 3 games to copy into.')));
      return;
    }
    Game? game = gen3.length == 1 ? gen3.first : null;
    var party = false;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Copy to a game'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<Game>(
                initialValue: game,
                decoration: const InputDecoration(labelText: 'Game'),
                items: [
                  for (final g in gen3)
                    DropdownMenuItem(value: g, child: Text(g.title)),
                ],
                onChanged: (g) => setD(() => game = g),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Into party (else PC box)'),
                value: party,
                onChanged: (v) => setD(() => party = v),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed:
                    game == null ? null : () => Navigator.pop(ctx, true),
                child: const Text('Copy')),
          ],
        ),
      ),
    );
    if (go != true || game == null || !context.mounted) return;
    final msg = await state.copyVaultToGame(game!, i, party: party);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 5)));
  }
}

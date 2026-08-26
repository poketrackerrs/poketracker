import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/games_data.dart';
import '../models/game.dart';
import '../state/app_state.dart';
import 'dual_box_screen.dart';
import 'game_screen.dart';

String _sprite(int dex, bool shiny) =>
    'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/'
    '${shiny ? 'shiny/' : ''}$dex.png';

/// The Pokémon Vault hub (a top-level tab). A game-independent store you can
/// pull Pokémon into from any Gen 3 game (boxes *and* party), sort by Dex,
/// multi-select to clone into other games, duplicate, or delete.
class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});
  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  final Set<int> _sel = {};
  bool get _selecting => _sel.isNotEmpty;

  void _toggle(int i) => setState(() {
        if (!_sel.remove(i)) _sel.add(i);
      });

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        _sel.removeWhere((i) => i >= state.vault.length);
        return Column(
          children: [
            _toolbar(context, state),
            const Divider(height: 1),
            Expanded(
              child: state.vault.isEmpty
                  ? _empty(context, state)
                  : _grid(context, state),
            ),
          ],
        );
      },
    );
  }

  Widget _toolbar(BuildContext context, AppState state) {
    if (_selecting) {
      return Material(
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Clear selection',
                icon: const Icon(Icons.close),
                onPressed: () => setState(_sel.clear),
              ),
              Text('${_sel.length} selected',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.send_to_mobile),
                label: const Text('Copy to game'),
                onPressed: () => _copyTo(context, _sel.toList()),
              ),
              IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.delete_outline),
                onPressed: () {
                  state.removeFromVaultMulti(_sel.toList());
                  setState(_sel.clear);
                },
              ),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          TextButton.icon(
            icon: const Icon(Icons.download),
            label: const Text('Pull from game'),
            onPressed: () => _pullFromGame(context, state),
          ),
          const SizedBox(width: 4),
          TextButton.icon(
            icon: const Icon(Icons.sort_by_alpha),
            label: const Text('Sort by Dex'),
            onPressed:
                state.vault.isEmpty ? null : () => state.sortVaultByDex(),
          ),
          const Spacer(),
          Text('${state.vault.length}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context, AppState state) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.inventory_2_outlined,
                  size: 56, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                'Your Vault is empty.\n\nUse "Pull from game" to bring '
                'Pokémon in from any Gen 3 game — including party members — '
                'then sort, clone into other games, or delete them here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                icon: const Icon(Icons.download),
                label: const Text('Pull from game'),
                onPressed: () => _pullFromGame(context, state),
              ),
            ],
          ),
        ),
      );

  Widget _grid(BuildContext context, AppState state) {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 96,
        childAspectRatio: 0.72,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
      ),
      itemCount: state.vault.length,
      itemBuilder: (context, i) {
        final v = state.vault[i];
        final selected = _sel.contains(i);
        return GestureDetector(
          onTap: () =>
              _selecting ? _toggle(i) : _actions(context, state, i),
          onLongPress: () => _toggle(i),
          child: Container(
            decoration: BoxDecoration(
              color: selected
                  ? Colors.blue.withValues(alpha: 0.22)
                  : Colors.black.withValues(alpha: 0.04),
              border: Border.all(
                color: selected ? Colors.blue : Colors.black12,
                width: selected ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.all(2),
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CachedNetworkImage(
                          imageUrl: _sprite(v.dex, v.shiny),
                          fit: BoxFit.contain,
                          errorWidget: (_, _, _) =>
                              const Icon(Icons.catching_pokemon),
                        ),
                      ),
                      if (v.shiny)
                        const Positioned(
                          top: 0,
                          right: 0,
                          child: Icon(Icons.star, size: 14, color: Colors.amber),
                        ),
                      if (selected)
                        const Positioned(
                          top: 0,
                          left: 0,
                          child: Icon(Icons.check_circle,
                              size: 16, color: Colors.blue),
                        ),
                    ],
                  ),
                ),
                Text(
                  v.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
                Text('Lv ${v.level} · #${v.dex}',
                    style:
                        const TextStyle(fontSize: 9, color: Colors.grey)),
                if (v.origin.isNotEmpty)
                  Text(v.origin,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 8,
                          fontStyle: FontStyle.italic,
                          color: Colors.grey)),
              ],
            ),
          ),
        );
      },
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
              leading: const Icon(Icons.edit),
              title: const Text('Edit Pokémon'),
              subtitle:
                  const Text('Shiny, IVs/EVs, moves, nature, species…'),
              onTap: () {
                Navigator.pop(context);
                _editMon(context, state, i);
              },
            ),
            ListTile(
              leading: const Icon(Icons.send_to_mobile),
              title: const Text('Copy to a game'),
              subtitle: const Text('Clone into a Gen 3 game (box or party)'),
              onTap: () {
                Navigator.pop(context);
                _copyTo(context, [i]);
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
              leading: const Icon(Icons.checklist),
              title: const Text('Select'),
              onTap: () {
                Navigator.pop(context);
                _toggle(i);
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

  Future<void> _editMon(BuildContext context, AppState state, int i) async {
    final pm = await state.vaultMonForEditor(i);
    if (pm == null || !context.mounted) return;
    final ed = await pushGen3MonEditor(context, mon: pm);
    if (ed == null || !context.mounted) return;
    final msg = await state.editVaultMon(i, ed);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 4)));
  }

  /// Pick an installed Gen 3 game, then open the side-by-side box view so the
  /// user can marquee-select box or party Pokémon and copy them into the Vault.
  Future<void> _pullFromGame(BuildContext context, AppState state) async {
    final game = await _pickGame(context, state);
    if (game == null || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DualBoxScreen(game: game)),
    );
  }

  Future<Game?> _pickGame(BuildContext context, AppState state) async {
    final gen3 = [
      for (final g in kGames)
        if (g.generation == 3 && state.isInstalled(g.id)) g
    ];
    if (gen3.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No installed Gen 3 games found.')));
      return null;
    }
    if (gen3.length == 1) return gen3.first;
    return showDialog<Game>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Choose a game'),
        children: [
          for (final g in gen3)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, g),
              child: Text(g.title),
            ),
        ],
      ),
    );
  }

  Future<void> _copyTo(BuildContext context, List<int> indices) async {
    final state = context.read<AppState>();
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
          title: Text(indices.length == 1
              ? 'Copy to a game'
              : 'Copy ${indices.length} to a game'),
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
    final msg = await state.copyVaultMultiToGame(game!, indices, party: party);
    if (!context.mounted) return;
    setState(_sel.clear);
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 5)));
  }
}

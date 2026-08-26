import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../data/pokeapi_maps.dart';
import '../data/region_theme.dart';
import '../models/game.dart';
import '../models/pokedex_models.dart';
import '../models/progress.dart';
import '../models/save_models.dart';
import '../services/pokedex_service.dart';
import '../data/gen3_events.dart';
import '../data/gen3_items.dart';
import '../data/type_colors.dart';
import '../services/gen3_save_editor.dart';
import '../services/gen4_save_editor.dart';
import '../services/pk3.dart';
import '../state/app_state.dart';
import 'achievements_screen.dart';
import 'cartridge_viewer.dart';
import 'dual_box_screen.dart';
import '../widgets/completion_ring.dart';
import '../widgets/game_box_art.dart';
import 'game_launch.dart';
import 'pokemon_detail_screen.dart';

class GameScreen extends StatelessWidget {
  final Game game;
  const GameScreen({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final tint =
        state.regionTint ? regionColor(game.region, state.accent) : state.accent;
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        floatingActionButton: _playButton(context, state, tint),
        appBar: AppBar(
          backgroundColor: tint,
          foregroundColor: Colors.white,
          title: Text(game.title),
          actions: [
            if (game.generation == 3 || game.generation == 4)
              IconButton(
                tooltip: 'Edit save file',
                icon: const Icon(Icons.tune),
                onPressed: () => _showSaveEditor(context, game),
              ),
            IconButton(
              tooltip: 'Sync from save file',
              icon: const Icon(Icons.sync),
              onPressed: () => _startSaveSync(context, game),
            ),
          ],
        ),
        body: Column(
          children: [
            _GameHeader(game: game, tint: tint),
            Material(
              color: Theme.of(context).colorScheme.surface,
              child: TabBar(
                isScrollable: true,
                indicatorColor: tint,
                labelColor: tint,
                tabs: const [
                  Tab(icon: Icon(Icons.emoji_events), text: 'Badges'),
                  Tab(icon: Icon(Icons.menu_book), text: 'Pokedex'),
                  Tab(icon: Icon(Icons.groups), text: 'Team'),
                  Tab(icon: Icon(Icons.auto_awesome), text: 'Shiny'),
                  Tab(icon: Icon(Icons.military_tech), text: 'Trophies'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _MilestonesTab(game: game, tint: tint),
                  _DexTab(game: game, tint: tint),
                  _TeamTab(game: game, tint: tint),
                  _ShinyTab(game: game, tint: tint),
                  GameAchievementsView(game: game),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Play (or Download) affordance for this game — mirrors the console shelf so
  // games opened straight from the list are still playable.
  Widget? _playButton(BuildContext context, AppState state, Color tint) {
    if (state.downloadProgress(game.id) != null) {
      return FloatingActionButton.extended(
        backgroundColor: Colors.grey,
        onPressed: null,
        icon: const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Colors.white)),
        label: const Text('Downloading…'),
      );
    }
    if (state.isInstalled(game.id)) {
      return FloatingActionButton.extended(
        backgroundColor: tint,
        foregroundColor: Colors.white,
        onPressed: () => launchGame(context, game),
        icon: const Icon(Icons.play_arrow),
        label: const Text('Play'),
      );
    }
    if (state.canDownload(game.id)) {
      return FloatingActionButton.extended(
        backgroundColor: tint,
        foregroundColor: Colors.white,
        onPressed: () async {
          final m = ScaffoldMessenger.of(context);
          try {
            await context.read<AppState>().downloadGame(game.id);
            if (!context.mounted) return;
            m.showSnackBar(SnackBar(content: Text('Downloaded ${game.title}')));
          } catch (e) {
            m.showSnackBar(SnackBar(content: Text('Download failed: $e')));
          }
        },
        icon: const Icon(Icons.download),
        label: const Text('Download'),
      );
    }
    return null;
  }
}

class _GameHeader extends StatelessWidget {
  final Game game;
  final Color tint;
  const _GameHeader({required this.game, required this.tint});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final pct = state.completion(game);
    return Container(
      width: double.infinity,
      color: tint,
      child: Stack(
        children: [
          // Faded cover art as a banner texture so the header isn't a flat block.
          Positioned.fill(
            child: ClipRect(
              child: Opacity(
                opacity: 0.22,
                child: Image.asset(
                  game.boxArtAsset,
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          ),
          // Tint gradient so the artwork reads as texture and text stays legible.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [tint, tint.withValues(alpha: 0.55)],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
            child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () => _showBoxPopout(context, game),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GameBoxArt(game: game, height: 118),
                    const SizedBox(height: 3),
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.zoom_out_map,
                            size: 11, color: Colors.white70),
                        SizedBox(width: 3),
                        Text('Tap to rotate',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 11)),
                      ],
                    ),
                  ],
                ),
              ),
              if (_cartAsset(game) != null) ...[
                const SizedBox(height: 6),
                _CartButton(
                  onTap: () => showModelViewerDialog(context,
                      src: _cartAsset(game)!, title: '${game.title} cartridge'),
                ),
              ],
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _HeaderChip(text: game.region),
                    _HeaderChip(text: '${game.releaseYear}'),
                    _HeaderChip(text: game.category.label),
                    _HeaderChip(text: 'Gen ${game.generation}'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          CompletionRing(
            value: pct,
            color: Colors.white,
            size: 62,
            stroke: 6,
            trackColor: Colors.white.withValues(alpha: 0.3),
            textColor: Colors.white,
          ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderChip extends StatelessWidget {
  final String text;
  const _HeaderChip({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text,
          style: const TextStyle(color: Colors.white, fontSize: 12)),
    );
  }
}

/// Games with a baked 3D cartridge model (GB/GBC/GBA — where a labelled
/// cartridge exists). Add ids as more carts are baked.
const _cartGames = {
  'red', 'blue', 'yellow', 'gold', 'silver', 'crystal',
  'ruby', 'sapphire', 'emerald', 'firered', 'leafgreen',
};
String? _cartAsset(Game game) =>
    _cartGames.contains(game.id) ? 'assets/models/carts/${game.id}.glb' : null;

/// Small tappable that opens the game's 3D cartridge in the model viewer.
class _CartButton extends StatelessWidget {
  final VoidCallback onTap;
  const _CartButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videogame_asset, size: 13, color: Colors.white),
            SizedBox(width: 5),
            Text('Cartridge 3D',
                style: TextStyle(color: Colors.white, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

/// Pops the game's box into an enlarged, drag-to-rotate overlay above the page.
void _showBoxPopout(BuildContext context, Game game) {
  showDialog(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.88),
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GameBoxArt(game: game, height: 400, interactive: true),
          const SizedBox(height: 20),
          const Text(
            'Drag to rotate  •  tap outside to close',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    ),
  );
}

/// Gen 3 save editor (step 1): money + complete-Pokedex, written back to the
/// .sav with an automatic backup. Refuses to touch a save whose checksums
/// don't validate.
void _showSaveEditor(BuildContext context, Game game) {
  showDialog(
    context: context,
    builder: (_) => _SaveEditorDialog(game: game),
  );
}

class _SaveEditorDialog extends StatefulWidget {
  final Game game;
  const _SaveEditorDialog({required this.game});
  @override
  State<_SaveEditorDialog> createState() => _SaveEditorDialogState();
}

class _SaveEditorDialogState extends State<_SaveEditorDialog> {
  final _money = TextEditingController();
  bool _loading = true, _busy = false, _completeDex = false;
  bool _completeSeenDex = false;
  final Set<Gen3Ticket> _tickets = {};
  int? _caught, _seen;
  List<Gen3PartyMon>? _party;
  final Map<int, PartyEdit> _partyEdits = {};
  final Map<int, PartyEdit> _boxEdits = {}; // keyed by global PC slot 0..419
  // Trainer card
  final _otName = TextEditingController();
  final _tid = TextEditingController();
  final _sid = TextEditingController();
  final _hours = TextEditingController();
  int _gender = 0, _minutes = 0;
  bool _trainerLoaded = false;
  // Bag: pockets the user edited (empty = leave the bag untouched)
  final Map<Gen3Pocket, List<({int id, int qty})>> _bagEdits = {};
  // Event Pokémon queued for injection (built blocks + labels for display)
  final List<Uint8List> _partyInjects = [];
  final List<Uint8List> _boxInjects = [];
  final List<String> _injectLabels = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool get _gen4 => widget.game.generation == 4;

  Future<void> _load() async {
    final state = context.read<AppState>();
    if (_gen4) {
      final data = await state.readGen4Save(widget.game);
      final party = await state.readGen4Party(widget.game);
      if (!mounted) return;
      setState(() {
        _party = party;
        _loading = false;
        if (data == null) {
          _error = 'No editable Gen 4 save found. Play and save in-game once.';
        } else {
          _money.text = '${data.money}';
          _otName.text = data.trainer;
          _tid.text = '${data.tid}';
          _sid.text = '${data.sid}';
          _gender = data.gender;
          _trainerLoaded = true;
        }
      });
      return;
    }
    final data = await state.readGen3Save(widget.game);
    final party = await state.readGen3Party(widget.game);
    final trainer = await state.readGen3Trainer(widget.game);
    if (!mounted) return;
    setState(() {
      _party = party;
      _loading = false;
      if (trainer != null) {
        _otName.text = trainer.name;
        _tid.text = '${trainer.tid}';
        _sid.text = '${trainer.sid}';
        _hours.text = '${trainer.hours}';
        _gender = trainer.gender;
        _minutes = trainer.minutes;
        _trainerLoaded = true;
      }
      if (data == null) {
        _error = 'No editable save found. Play and save in-game once, then '
            'set the save path in the Sync dialog if needed.';
      } else {
        _money.text = '${data.money}';
        _caught = data.caught;
        _seen = data.seen;
      }
    });
  }

  Future<void> _apply() async {
    setState(() => _busy = true);
    final money = int.tryParse(_money.text.trim());
    if (_gen4) {
      final msg = await context.read<AppState>().writeGen4Save(
            widget.game,
            money: money,
            trainer: _trainerLoaded
                ? Gen4Trainer(
                    name: _otName.text.trim(),
                    tid: int.tryParse(_tid.text.trim()) ?? 0,
                    sid: int.tryParse(_sid.text.trim()) ?? 0,
                    money: money ?? 0,
                    gender: _gender,
                  )
                : null,
            partyEdits: _partyEdits,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), duration: const Duration(seconds: 6)));
      return;
    }
    final msg = await context.read<AppState>().writeGen3Save(
          widget.game,
          money: money,
          completeDex: _completeDex,
          completeSeenDex: _completeSeenDex,
          tickets: _tickets.toList(),
          partyEdits: _partyEdits,
          boxEdits: _boxEdits,
          trainer: _trainerLoaded
              ? Gen3Trainer(
                  name: _otName.text.trim(),
                  gender: _gender,
                  tid: int.tryParse(_tid.text.trim()) ?? 0,
                  sid: int.tryParse(_sid.text.trim()) ?? 0,
                  hours: int.tryParse(_hours.text.trim()) ?? 0,
                  minutes: _minutes,
                )
              : null,
          bag: _bagEdits.isEmpty ? null : _bagEdits,
          partyInjects: _partyInjects,
          boxInjects: _boxInjects,
        );
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 6)));
  }

  Future<void> _editMon(Gen3PartyMon m) async {
    final result = await Navigator.of(context).push<PartyEdit>(
      MaterialPageRoute(
          builder: (_) =>
              _MonEditor(
                  mon: m,
                  initial: _partyEdits[m.slot],
                  strictLegal: true,
                  generation: widget.game.generation)),
    );
    if (result != null && mounted) {
      setState(() => _partyEdits[m.slot] = result);
    }
  }

  // A rich party-list row: sprite, name, level, nature (with stat effect) and a
  // held-item icon. Reflects any pending edit (shiny/nature/held item).
  Widget _partyRow(Gen3PartyMon m) {
    final ed = _partyEdits[m.slot];
    final shiny = ed?.shiny ?? m.shiny;
    final nature = ed?.nature ?? m.nature;
    final held = ed?.heldItem ?? m.heldItem;
    final up = natureUp(nature);
    final sprite = 'https://raw.githubusercontent.com/PokeAPI/sprites/master'
        '/sprites/pokemon${shiny ? '/shiny' : ''}/${m.dex}.png';
    return InkWell(
      onTap: () => _editMon(m),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              height: 44,
              child: CachedNetworkImage(
                imageUrl: sprite,
                fit: BoxFit.contain,
                errorWidget: (_, _, _) =>
                    const Icon(Icons.catching_pokemon, color: Colors.grey),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(m.name ?? '#${m.dex}',
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (shiny)
                        const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Icon(Icons.auto_awesome,
                              size: 13, color: Colors.amber),
                        ),
                      if (ed != null)
                        const Padding(
                          padding: EdgeInsets.only(left: 6),
                          child: Text('edited',
                              style: TextStyle(
                                  fontSize: 10, color: Colors.blueAccent)),
                        ),
                    ],
                  ),
                  Row(
                    children: [
                      Text('Lv${m.level}  ·  ${kNatures[nature % 25]}',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey)),
                      if (up >= 0) ...[
                        const SizedBox(width: 5),
                        Text('+${kNatureStats[up]}',
                            style: const TextStyle(
                                fontSize: 10,
                                color: Colors.green,
                                fontWeight: FontWeight.w600)),
                        Text(' −${kNatureStats[natureDown(nature)]}',
                            style: const TextStyle(
                                fontSize: 10,
                                color: Colors.redAccent,
                                fontWeight: FontWeight.w600)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (held != 0) ...[
              if (!_gen4 && gen3ItemSprite(held) != null)
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CachedNetworkImage(
                    imageUrl: gen3ItemSprite(held)!,
                    fit: BoxFit.contain,
                    errorWidget: (_, _, _) => const SizedBox.shrink(),
                  ),
                )
              else
                const Icon(Icons.circle, size: 8, color: Colors.blueGrey),
            ],
            const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Future<void> _restoreBackup() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore last backup?'),
        content: const Text(
            'This replaces the current save with the most recent backup the '
            'editor made (before your last Apply). Your latest edits are undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Restore')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final msg = await context.read<AppState>().restoreGen3Backup(widget.game);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 6)));
    // Reload the editor from the restored save (clears the error state).
    if (msg.startsWith('Restored')) {
      setState(() {
        _busy = false;
        _loading = true;
        _error = null;
      });
      await _load();
    } else {
      setState(() => _busy = false);
    }
  }

  Future<void> _addEvent() async {
    final ev = await showModalBottomSheet<Gen3Event>(
      context: context,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(14),
              child: Text('Add an event Pokémon',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            for (final e in kGen3Events)
              ListTile(
                leading: const Icon(Icons.auto_awesome, color: Colors.amber),
                title: Text('${e.label}  ·  Lv${e.level}'),
                subtitle: Text('OT ${e.otName}  ·  ${e.note}',
                    style: const TextStyle(fontSize: 11)),
                onTap: () => Navigator.pop(context, e),
              ),
          ],
        ),
      ),
    );
    if (ev == null || !mounted) return;
    // Party if there's room (counting queued party injects), else a PC box.
    final partyRoom = 6 - (_party?.length ?? 0) - _partyInjects.length;
    final toParty = partyRoom > 0;
    setState(() => _busy = true);
    final block =
        await context.read<AppState>().buildEventMon(widget.game, ev, party: toParty);
    if (!mounted) return;
    setState(() {
      (toParty ? _partyInjects : _boxInjects).add(block);
      _injectLabels.add('${ev.label} → ${toParty ? 'party' : 'PC box'}');
      _busy = false;
    });
  }

  @override
  void dispose() {
    for (final c in [_money, _otName, _tid, _sid, _hours]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit save'),
      content: _loading
          ? const SizedBox(
              height: 60, child: Center(child: CircularProgressIndicator()))
          : _error != null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_error!),
                    if (!_gen4) ...[
                      const SizedBox(height: 16),
                      // Reachable even when the current save is corrupt/blank —
                      // this is exactly when you need to roll back to a backup.
                      FilledButton.icon(
                        onPressed: _busy ? null : _restoreBackup,
                        icon: const Icon(Icons.restore),
                        label: const Text('Restore last backup'),
                      ),
                    ],
                  ],
                )
              : SingleChildScrollView(
                  child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _money,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Money',
                        helperText: '0 – 999999',
                      ),
                    ),
                    if (_trainerLoaded) ...[
                      const SizedBox(height: 10),
                      const Text('Trainer',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _otName,
                              maxLength: 7,
                              decoration: const InputDecoration(
                                  isDense: true,
                                  labelText: 'Name',
                                  counterText: ''),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ToggleButtons(
                            isSelected: [_gender == 0, _gender == 1],
                            onPressed: (i) => setState(() => _gender = i),
                            constraints: const BoxConstraints(
                                minWidth: 34, minHeight: 30),
                            children: const [Text('♂'), Text('♀')],
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _tid,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                  isDense: true, labelText: 'ID'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _sid,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                  isDense: true, labelText: 'Secret ID'),
                            ),
                          ),
                          if (!_gen4) ...[
                            const SizedBox(width: 10),
                            SizedBox(
                              width: 64,
                              child: TextField(
                                controller: _hours,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                    isDense: true, labelText: 'Hours'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    if (!_gen4) ...[
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Complete Pokédex (caught)'),
                        subtitle:
                            Text('Currently caught: ${_caught ?? '—'} / 386'),
                        value: _completeDex,
                        onChanged: (v) => setState(() => _completeDex = v),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Complete Pokédex (seen)'),
                        subtitle: Text('Currently seen: ${_seen ?? '—'} / 386'),
                        value: _completeSeenDex || _completeDex,
                        onChanged: _completeDex
                            ? null // caught implies seen
                            : (v) => setState(() => _completeSeenDex = v),
                      ),
                      const Divider(),
                      const Text('Event tickets',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      ...Gen3SaveEditor.ticketsFor(widget.game.version).map(
                        (t) => CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(t.label),
                          subtitle: Text(t.unlocks,
                              style: const TextStyle(fontSize: 11)),
                          value: _tickets.contains(t),
                          onChanged: (v) => setState(() =>
                              v == true ? _tickets.add(t) : _tickets.remove(t)),
                        ),
                      ),
                    ],
                    if (_party != null && _party!.isNotEmpty) ...[
                      const Divider(),
                      const Text('Party  ·  tap a Pokémon to edit',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      ..._party!.map((m) => _partyRow(m)),
                    ],
                    if (!_gen4) ...[
                      const Divider(),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.inventory_2_outlined),
                        title: const Text('PC Boxes'),
                        subtitle: Text(_boxEdits.isEmpty
                            ? 'Browse & edit stored Pokémon'
                            : '${_boxEdits.length} edited'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          await Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => _BoxBrowser(
                                game: widget.game, edits: _boxEdits),
                          ));
                          if (mounted) setState(() {});
                        },
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.backpack_outlined),
                        title: const Text('Bag'),
                        subtitle: Text(_bagEdits.isEmpty
                            ? 'Items, balls, TMs, berries'
                            : '${_bagEdits.length} pocket(s) edited'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          await Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => _BagEditor(
                                game: widget.game, edits: _bagEdits),
                          ));
                          if (mounted) setState(() {});
                        },
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.auto_awesome,
                            color: Colors.amber),
                        title: const Text('Event Pokémon'),
                        subtitle: Text(_injectLabels.isEmpty
                            ? 'Add Mew, Celebi, Jirachi, Deoxys…'
                            : _injectLabels.join(', ')),
                        trailing: const Icon(Icons.add),
                        onTap: _busy ? null : _addEvent,
                      ),
                      const Divider(),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading:
                            const Icon(Icons.restore, color: Colors.orange),
                        title: const Text('Restore last backup'),
                        subtitle:
                            const Text('Undo the last edit if a save broke'),
                        onTap: _busy ? null : _restoreBackup,
                      ),
                    ],
                    const SizedBox(height: 4),
                    const Text(
                      'The original save is backed up first. Reload it in your '
                      'emulator to confirm the changes.',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                )),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        if (_error == null && !_loading)
          FilledButton(
            onPressed: _busy ? null : _apply,
            child: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Apply'),
          ),
      ],
    );
  }
}

/// Browses the PC boxes (14×30) and edits stored Pokémon through the same
/// per-mon editor as the party. Mutates the parent's [edits] map (keyed by
/// global PC slot 0..419) so the changes ride along on the save's Apply.
class _BoxBrowser extends StatefulWidget {
  final Game game;
  final Map<int, PartyEdit> edits;
  const _BoxBrowser({required this.game, required this.edits});
  @override
  State<_BoxBrowser> createState() => _BoxBrowserState();
}

class _BoxBrowserState extends State<_BoxBrowser> {
  List<Gen3PartyMon>? _mons; // occupied slots only, boxSlot = global index
  int _box = 0; // selected box 0..13
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final mons = await context.read<AppState>().readGen3Boxes(widget.game);
    if (!mounted) return;
    setState(() {
      _mons = mons ?? [];
      _loading = false;
      // Land on the first box that actually has Pokémon.
      if (_mons!.isNotEmpty) _box = _mons!.first.boxSlot! ~/ 30;
    });
  }

  Future<void> _sortByDex() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Organize by Dex?'),
        content: const Text(
            'This rearranges every boxed Pokémon by National Dex number, '
            'packed from Box 1. A backup is written next to your save first. '
            'Any unsaved box edits here will be discarded.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Organize')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final msg =
        await context.read<AppState>().sortGen3BoxesByDex(widget.game);
    if (!mounted) return;
    widget.edits.clear(); // slot keys are no longer valid after a reorder
    setState(() => _loading = true);
    await _load();
    messenger.showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _makeAllShiny() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Make all box Pokémon shiny?'),
        content: const Text(
            'Every Pokémon in your PC boxes becomes shiny (kept legal — nature, '
            'gender, ability and IVs are preserved). Event Pokémon (Mew, Deoxys, '
            'Jirachi, Celebi) are skipped, since a shiny event Pokémon would be '
            'illegal. A backup is written next to your save first.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Make shiny')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final msg = await context.read<AppState>().makeAllBoxShiny(widget.game);
    if (!mounted) return;
    widget.edits.clear(); // PIDs changed; queued slot edits are stale
    setState(() => _loading = true);
    await _load();
    messenger.showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 6)));
  }

  Future<void> _edit(Gen3PartyMon m) async {
    final state = context.read<AppState>();
    // Boxed mons store no level byte — derive it from EXP for the editor.
    final lvl = await state.gen3LevelForExp(m.dex, m.exp);
    if (!mounted) return;
    final result = await Navigator.of(context).push<PartyEdit>(
      MaterialPageRoute(
          builder: (_) => _MonEditor(
              mon: m.copyWith(level: lvl), initial: widget.edits[m.boxSlot])),
    );
    if (result != null && mounted) {
      setState(() => widget.edits[m.boxSlot!] = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mons = _mons ?? const <Gen3PartyMon>[];
    final counts = <int, int>{};
    for (final m in mons) {
      final b = m.boxSlot! ~/ 30;
      counts[b] = (counts[b] ?? 0) + 1;
    }
    final inBox = mons.where((m) => m.boxSlot! ~/ 30 == _box).toList()
      ..sort((a, b) => a.boxSlot!.compareTo(b.boxSlot!));
    return Scaffold(
      appBar: AppBar(
        title: const Text('PC Boxes'),
        bottom: mons.isEmpty
            ? null
            : const PreferredSize(
                preferredSize: Size.fromHeight(20),
                child: Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Text('Tap to edit  ·  long-press to save to Vault',
                      style: TextStyle(fontSize: 11, color: Colors.white70)),
                ),
              ),
        actions: [
          IconButton(
            tooltip: 'Boxes ⟷ Vault (side by side)',
            icon: const Icon(Icons.swap_horiz),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => DualBoxScreen(game: widget.game))),
          ),
          IconButton(
            tooltip: 'Make all shiny (skips events)',
            icon: const Icon(Icons.auto_awesome),
            onPressed: _loading || mons.isEmpty ? null : _makeAllShiny,
          ),
          IconButton(
            tooltip: 'Organize by Dex',
            icon: const Icon(Icons.sort),
            onPressed: _loading || mons.isEmpty ? null : _sortByDex,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : mons.isEmpty
              ? const Center(child: Text('No Pokémon in the PC.'))
              : Column(
                  children: [
                    // Box selector
                    SizedBox(
                      height: 46,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        children: [
                          for (var b = 0; b < Gen3SaveEditor.pcBoxCount; b++)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 3, vertical: 6),
                              child: ChoiceChip(
                                label: Text('Box ${b + 1}'
                                    '${counts[b] != null ? ' (${counts[b]})' : ''}'),
                                selected: _box == b,
                                onSelected: (_) => setState(() => _box = b),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: inBox.isEmpty
                          ? const Center(child: Text('This box is empty.'))
                          : ListView(
                              children: [
                                for (final m in inBox)
                                  _boxRow(m),
                              ],
                            ),
                    ),
                  ],
                ),
    );
  }

  Widget _boxRow(Gen3PartyMon m) {
    final ed = widget.edits[m.boxSlot];
    final shiny = ed?.shiny ?? m.shiny;
    return ListTile(
      dense: true,
      leading: Icon(shiny ? Icons.star : Icons.star_border,
          color: shiny ? Colors.amber : Colors.grey, size: 18),
      title: Text('${m.name ?? '#${m.dex}'}  ·  ${m.natureName}'),
      subtitle: Text('Slot ${(m.boxSlot! % 30) + 1}'
          '${ed != null ? '  ·  edited' : ''}',
          style: const TextStyle(fontSize: 11)),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: () => _edit(m),
      onLongPress: () => _toVault(m),
    );
  }

  Future<void> _toVault(Gen3PartyMon m) async {
    final messenger = ScaffoldMessenger.of(context);
    final msg = await context
        .read<AppState>()
        .copyGameBoxToVault(widget.game, m.boxSlot!);
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(msg)));
  }
}

/// Bag editor — the five Gen 3 pockets, with quantity edits and add/remove.
/// Mutates the parent's [edits] map (only pockets the user touches are written).
class _BagEditor extends StatefulWidget {
  final Game game;
  final Map<Gen3Pocket, List<({int id, int qty})>> edits;
  const _BagEditor({required this.game, required this.edits});
  @override
  State<_BagEditor> createState() => _BagEditorState();
}

class _BagEditorState extends State<_BagEditor> {
  static const _pocketNames = {
    Gen3Pocket.items: 'Items',
    Gen3Pocket.keyItems: 'Key',
    Gen3Pocket.balls: 'Balls',
    Gen3Pocket.tmHm: 'TMs/HMs',
    Gen3Pocket.berries: 'Berries',
  };
  final Map<Gen3Pocket, List<({int id, int qty})>> _local = {};
  Gen3Pocket _pocket = Gen3Pocket.items;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bag = await context.read<AppState>().readGen3Bag(widget.game);
    if (!mounted) return;
    setState(() {
      for (final p in Gen3Pocket.values) {
        // Prefer any in-progress edit for this pocket, else the file's contents.
        _local[p] = List.of(widget.edits[p] ?? bag?[p] ?? const []);
      }
      _loading = false;
    });
  }

  void _commit() =>
      setState(() => widget.edits[_pocket] = List.of(_local[_pocket]!));

  Future<void> _editQty(int index) async {
    final cur = _local[_pocket]![index];
    final ctrl = TextEditingController(text: '${cur.qty}');
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(gen3ItemName(cur.id)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Quantity (1–999)'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, -1),
              child: const Text('Remove',
                  style: TextStyle(color: Colors.red))),
          TextButton(
              onPressed: () => Navigator.pop(ctx,
                  (int.tryParse(ctrl.text.trim()) ?? cur.qty).clamp(1, 999)),
              child: const Text('OK')),
        ],
      ),
    );
    if (result == null) return;
    setState(() {
      if (result < 0) {
        _local[_pocket]!.removeAt(index);
      } else {
        _local[_pocket]![index] = (id: cur.id, qty: result);
      }
    });
    _commit();
  }

  Future<void> _addItem() async {
    final all = gen3ItemPicker();
    final picked = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        var query = '';
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            final q = query.trim().toLowerCase();
            final matches = q.isEmpty
                ? all
                : all.where((e) => e.name.toLowerCase().contains(q)).toList();
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.7,
              builder: (_, scroll) => Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Search items…',
                          isDense: true),
                      onChanged: (v) => setSheet(() => query = v),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      controller: scroll,
                      itemCount: matches.length,
                      itemBuilder: (_, i) => ListTile(
                        leading: _itemImage(matches[i].id),
                        title: Text(matches[i].name),
                        onTap: () => Navigator.pop(ctx, matches[i].id),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (picked == null || !mounted) return;
    // If already in the pocket, just add one; else add a new stack of 1.
    final idx = _local[_pocket]!.indexWhere((e) => e.id == picked);
    setState(() {
      if (idx >= 0) {
        final cur = _local[_pocket]![idx];
        _local[_pocket]![idx] =
            (id: cur.id, qty: (cur.qty + 1).clamp(1, 999));
      } else {
        _local[_pocket]!.add((id: picked, qty: 1));
      }
    });
    _commit();
  }

  @override
  Widget build(BuildContext context) {
    final list = _local[_pocket] ?? const <({int id, int qty})>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Bag')),
      floatingActionButton: _loading
          ? null
          : FloatingActionButton(
              onPressed: _addItem, child: const Icon(Icons.add)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                SizedBox(
                  height: 46,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    children: [
                      for (final p in Gen3Pocket.values)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 3, vertical: 6),
                          child: ChoiceChip(
                            label: Text(_pocketNames[p]!),
                            selected: _pocket == p,
                            onSelected: (_) => setState(() => _pocket = p),
                          ),
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: list.isEmpty
                      ? const Center(child: Text('Empty pocket. Tap + to add.'))
                      : ListView.builder(
                          itemCount: list.length,
                          itemBuilder: (_, i) => ListTile(
                            leading: _itemImage(list[i].id),
                            title: Text(gen3ItemName(list[i].id)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.remove_circle_outline),
                                  onPressed: () => _bump(i, -1),
                                ),
                                SizedBox(
                                  width: 34,
                                  child: Text('${list[i].qty}',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700)),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.add_circle_outline),
                                  onPressed: () => _bump(i, 1),
                                ),
                              ],
                            ),
                            onTap: () => _editQty(i), // precise set / remove
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  /// The item's sprite (from data/gen3_items), with a graceful fallback icon.
  Widget _itemImage(int id) {
    const fallback = Icon(Icons.category_outlined, size: 22, color: Colors.grey);
    final url = gen3ItemSprite(id);
    if (url == null) return const SizedBox(width: 34, child: Center(child: fallback));
    return SizedBox(
      width: 34,
      height: 34,
      child: CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.contain,
        errorWidget: (_, _, _) => fallback,
        placeholder: (_, _) => const SizedBox(width: 34, height: 34),
      ),
    );
  }

  // Tap +/- to change a quantity; removes the item at 0.
  void _bump(int index, int delta) {
    final cur = _local[_pocket]![index];
    final q = (cur.qty + delta).clamp(0, 999);
    setState(() {
      if (q == 0) {
        _local[_pocket]!.removeAt(index);
      } else {
        _local[_pocket]![index] = (id: cur.id, qty: q);
      }
    });
    _commit();
  }
}

/// Per-Pokémon editor: shiny + IVs + EVs, kept legal (IV 0–31, EV 0–255 / 510).
/// Opens the full Gen 3 Pokémon editor for [mon] and returns the resulting
/// [PartyEdit] (null if cancelled). Public so other screens — e.g. the Vault —
/// can reuse the exact same editor UI.
Future<PartyEdit?> pushGen3MonEditor(BuildContext context,
    {required Gen3PartyMon mon, PartyEdit? initial, int generation = 3}) {
  return Navigator.of(context).push<PartyEdit>(
    MaterialPageRoute(
      builder: (_) =>
          _MonEditor(mon: mon, initial: initial, generation: generation),
    ),
  );
}

class _MonEditor extends StatefulWidget {
  final Gen3PartyMon mon;
  final PartyEdit? initial;
  // Gen 3 uses strict-legal (correlated Method-1 PID+IV, read-only IVs). Gen 4
  // (strictLegal:false) edits IVs freely and regenerates the PID directly for
  // nature/shiny, and hides the Gen-3-only species picker.
  final bool strictLegal;
  // The game's generation — selects the legal move pool (Gen 3 vs Gen 4 learnset).
  final int generation;
  const _MonEditor(
      {required this.mon,
      this.initial,
      this.strictLegal = true,
      this.generation = 3});
  @override
  State<_MonEditor> createState() => _MonEditorState();
}

class _MonEditorState extends State<_MonEditor> {
  static const _labels = ['HP', 'Atk', 'Def', 'Spe', 'SpA', 'SpD'];
  late bool _shiny;
  late int _nature;
  late TextEditingController _level;
  late TextEditingController _nickname;
  late List<TextEditingController> _ev;
  // IVs are checker-legal (Method-1 correlated with the PID). Read-only; nature/
  // shiny changes and the re-roll button regenerate them. _legalPid non-null
  // means "apply this correlated PID + these IVs".
  late List<int> _ivs;
  late List<TextEditingController> _iv; // editable IVs (Gen 4 / non-strict)
  int? _legalPid;
  int _legalSeed = 0;
  int? _wantAbility; // target ability slot for the strict-legal PID regen
  bool _rolling = false;
  late List<int> _moves;
  late int _speciesDex; // National dex; may change in the editor
  late int _friendship;
  late TextEditingController _otName;
  late int _ball, _metLevel, _otGender, _language, _markings, _pokerus;
  late int _heldItem; // held item id (Gen 3 item ids; Gen 4 stored byte)
  late int _abilityId; // Gen 4 stored ability id (Gen 3 ability is PID-derived)
  // Species abilities (id + name + hidden), slot order, for the ability picker.
  List<({int id, String name, bool hidden})> _abilities = const [];
  late List<TextEditingController> _contest;
  static const _contestLabels = ['Cool', 'Beauty', 'Cute', 'Smart', 'Tough', 'Sheen'];
  static const _markGlyphs = ['●', '■', '▲', '♥'];
  List<({int id, String name})>? _legal; // learnset, null while loading
  final Map<int, String> _nameById = {};
  List<({int id, String name})> _allSpecies = const []; // for the picker
  List<String> _types = const []; // for the dex-style header banner
  // move id -> display info (power/pp/type/category), fetched lazily + cached
  final Map<int, ({int power, int pp, int accuracy, String type, String damageClass})>
      _mi = {};

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _shiny = i?.shiny ?? widget.mon.shiny;
    _nature = i?.nature ?? widget.mon.nature;
    _speciesDex = i?.species ?? widget.mon.dex;
    _friendship = i?.friendship ?? widget.mon.friendship;
    _level = TextEditingController(text: '${i?.level ?? widget.mon.level}');
    _nickname = TextEditingController(
        text: i?.nickname ?? widget.mon.nickname);
    _ivs = List<int>.from(i?.ivs ?? widget.mon.ivs);
    _iv = [for (final v in _ivs) TextEditingController(text: '$v')];
    _legalPid = i?.legalPid;
    final evs = i?.evs ?? widget.mon.evs;
    _moves = List<int>.from(i?.moves ?? widget.mon.moves);
    _ev = [for (final v in evs) TextEditingController(text: '$v')];
    final mon = widget.mon;
    _otName = TextEditingController(text: i?.otName ?? mon.otName);
    _ball = i?.ball ?? mon.ball;
    _metLevel = i?.metLevel ?? mon.metLevel;
    _otGender = i?.otGender ?? mon.otGender;
    _language = i?.language ?? mon.language;
    _markings = i?.markings ?? mon.markings;
    _pokerus = i?.pokerus ?? mon.pokerus;
    _heldItem = i?.heldItem ?? mon.heldItem;
    _abilityId = i?.ability ?? mon.ability;
    final contest = i?.contest ?? mon.contest;
    _contest = [for (final v in contest) TextEditingController(text: '$v')];
    _loadMoves();
    _loadSpecies();
    _loadTypes();
    _loadAbilities();
    for (final id in _moves) {
      _ensureMoveInfo(id);
    }
  }

  Future<void> _loadTypes() async {
    try {
      final d = await context.read<AppState>().pokedexTypes(_speciesDex);
      if (mounted) setState(() => _types = d);
    } catch (_) {/* keep header neutral */}
  }

  // The mon's ability slot (0/1), from its PID — Gen 3 & 4 both derive the
  // in-game ability slot from PID bit 0.
  int get _abilitySlot => (_legalPid ?? widget.mon.pid) & 1;

  Future<void> _loadAbilities() async {
    final list =
        await context.read<AppState>().pokedexAbilities(_speciesDex);
    if (!mounted) return;
    setState(() {
      _abilities = list;
      // Gen 4: if the stored ability id isn't one of this species' abilities
      // (e.g. after a species change), snap it to the PID-slot's ability.
      if (widget.generation == 4 && list.isNotEmpty &&
          !list.any((a) => a.id == _abilityId)) {
        final normal = [for (final a in list) if (!a.hidden) a];
        if (normal.isNotEmpty) {
          _abilityId = normal[_abilitySlot % normal.length].id;
        }
      }
    });
  }

  // The ability name to display for the current mon.
  String get _abilityName {
    if (_abilities.isEmpty) return '…';
    if (widget.generation == 4) {
      for (final a in _abilities) {
        if (a.id == _abilityId) return _pretty(a.name);
      }
    }
    // Gen 3 (and Gen-4 fallback): PID slot picks among the non-hidden abilities.
    final normal = [for (final a in _abilities) if (!a.hidden) a];
    if (normal.isEmpty) return _pretty(_abilities.first.name);
    return _pretty(normal[_abilitySlot % normal.length].name);
  }

  Future<void> _ensureMoveInfo(int id) async {
    if (id == 0 || _mi.containsKey(id)) return;
    final info = await context.read<AppState>().moveInfo(id);
    if (mounted) setState(() => _mi[id] = info);
  }

  Future<void> _loadSpecies() async {
    final list = await context.read<AppState>().allSpeciesForPicker();
    if (!mounted) return;
    setState(() => _allSpecies = list);
  }

  Future<void> _loadMoves() async {
    final legal = await context
        .read<AppState>()
        .gen3Learnset(_speciesDex, gen: widget.generation);
    if (!mounted) return;
    setState(() {
      _legal = legal;
      _nameById.clear();
      for (final m in legal) {
        _nameById[m.id] = m.name;
      }
    });
  }

  // Switching species invalidates the old moves (illegal on the new species):
  // reload the new learnset and seed the four slots with its first legal moves.
  Future<void> _changeSpecies(int dex, String name) async {
    setState(() {
      _speciesDex = dex;
      _nickname.text = name.toUpperCase();
      _legal = null;
      _moves = [0, 0, 0, 0];
      _abilities = const [];
    });
    _loadTypes();
    _loadAbilities();
    final legal = await context
        .read<AppState>()
        .gen3Learnset(dex, gen: widget.generation);
    if (!mounted) return;
    setState(() {
      _legal = legal;
      _nameById
        ..clear()
        ..addEntries(legal.map((m) => MapEntry(m.id, m.name)));
      for (var k = 0; k < 4 && k < legal.length; k++) {
        _moves[k] = legal[k].id;
      }
    });
    _loadTypes();
    for (final id in _moves) {
      _ensureMoveInfo(id);
    }
  }

  // Regenerate a checker-legal (Method-1 correlated) PID + IVs for the current
  // nature + shininess. [reroll] advances the seed for a different IV spread.
  Future<void> _regenLegal({bool reroll = false, int? abilitySlot}) async {
    if (abilitySlot != null) _wantAbility = abilitySlot;
    setState(() => _rolling = true);
    final res = await context.read<AppState>().findLegalPidIv(
          dex: _speciesDex,
          tid: widget.mon.otid & 0xFFFF,
          sid: widget.mon.otid >> 16,
          nature: _nature,
          shiny: _shiny,
          currentPid: widget.mon.pid,
          wantAbility: _wantAbility,
          startSeed: reroll ? _legalSeed + 1 : 0,
        );
    if (!mounted) return;
    setState(() {
      _rolling = false;
      if (res != null) {
        _legalPid = res.pid;
        _ivs = res.ivs;
        _legalSeed = res.seed;
      }
    });
  }

  int get _ivTotal => _ivs.fold(0, (a, b) => a + b);

  String _moveName(int id) => id == 0
      ? '—'
      : (_nameById[id] ?? '#$id').replaceAll('-', ' ');

  static const _catIcon = {
    'physical': Icons.sports_mma,
    'special': Icons.auto_awesome,
    'status': Icons.shield_outlined,
  };

  // Color-coded +stat / −stat for a nature (grey "neutral" for the 5 neutrals).
  Widget _natureEffectChip(int n) {
    final up = natureUp(n);
    if (up < 0) {
      return const Text('neutral',
          style: TextStyle(fontSize: 11, color: Colors.grey));
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('+${kNatureStats[up]}',
            style: const TextStyle(
                fontSize: 11,
                color: Colors.green,
                fontWeight: FontWeight.w600)),
        const SizedBox(width: 4),
        Text('−${kNatureStats[natureDown(n)]}',
            style: const TextStyle(
                fontSize: 11,
                color: Colors.redAccent,
                fontWeight: FontWeight.w600)),
      ],
    );
  }

  // Compact "type · category · Pow · PP · Acc" line for a move's info.
  Widget _moveMeta(({int power, int pp, int accuracy, String type, String damageClass}) info) =>
      Row(
        children: [
          TypeChip(info.type),
          const SizedBox(width: 8),
          Icon(_catIcon[info.damageClass] ?? Icons.help_outline,
              size: 14, color: Colors.grey),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              'Pow ${info.power == 0 ? '—' : info.power}   PP ${info.pp}'
              '${info.accuracy > 0 ? '   Acc ${info.accuracy}' : ''}',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );

  // One move slot: a tappable card that opens the rich picker, showing the
  // selected move's name and its type/category/power/PP.
  Widget _moveRow(int k) {
    final id = _moves[k];
    final info = _mi[id];
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _pickMove(k),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                SizedBox(
                    width: 16,
                    child: Text('${k + 1}',
                        style: TextStyle(
                            fontSize: 12, color: scheme.onSurfaceVariant))),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(id == 0 ? '—' : _moveName(id),
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                      if (id != 0 && info != null) ...[
                        const SizedBox(height: 4),
                        _moveMeta(info),
                      ],
                    ],
                  ),
                ),
                Icon(Icons.expand_more, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Rich move picker (matches the bag picker): searchable list where each move
  // shows its type / category / power / PP, loaded lazily and cached.
  Future<void> _pickMove(int slot) async {
    final legal = _legal ?? const <({int id, String name})>[];
    final picked = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        var query = '';
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            final q = query.trim().toLowerCase();
            final matches = q.isEmpty
                ? legal
                : legal.where((m) => m.name.toLowerCase().contains(q)).toList();
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.75,
              maxChildSize: 0.95,
              builder: (_, scroll) => Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Search moves…',
                          isDense: true),
                      onChanged: (v) => setSheet(() => query = v),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      controller: scroll,
                      itemCount: matches.length + 1,
                      itemBuilder: (_, i) {
                        if (i == 0) {
                          return ListTile(
                            leading: const Icon(Icons.block, color: Colors.grey),
                            title: const Text('— (empty slot)'),
                            onTap: () => Navigator.pop(ctx, 0),
                          );
                        }
                        final m = matches[i - 1];
                        return _movePickerRow(m.id, m.name,
                            () => Navigator.pop(ctx, m.id));
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (picked != null && mounted) {
      setState(() => _moves[slot] = picked);
      _ensureMoveInfo(picked);
    }
  }

  Widget _movePickerRow(int id, String name, VoidCallback onTap) {
    return ListTile(
      title: Text(name.replaceAll('-', ' ')),
      subtitle: FutureBuilder<
          ({int power, int pp, int accuracy, String type, String damageClass})>(
        future: context.read<AppState>().moveInfo(id),
        builder: (_, snap) => snap.hasData
            ? Padding(
                padding: const EdgeInsets.only(top: 2),
                child: _moveMeta(snap.data!),
              )
            : const SizedBox(height: 16),
      ),
      onTap: onTap,
    );
  }

  // Ability row. Gen 4 stores the ability, so it's an editable dropdown of the
  // species' abilities; Gen 3 derives it from the PID, so it's read-only.
  Widget _abilityRow() {
    final normal = [for (final a in _abilities) if (!a.hidden) a];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const SizedBox(
              width: 90,
              child: Text('Ability',
                  style: TextStyle(fontWeight: FontWeight.w600))),
          if (widget.generation == 4 && normal.isNotEmpty)
            Expanded(
              child: DropdownButton<int>(
                isExpanded: true,
                isDense: true,
                value: normal.any((a) => a.id == _abilityId)
                    ? _abilityId
                    : normal.first.id,
                style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).textTheme.bodyLarge?.color),
                items: [
                  for (final a in normal)
                    DropdownMenuItem(
                        value: a.id, child: Text(_pretty(a.name))),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  final slot = normal.indexWhere((a) => a.id == v);
                  setState(() => _abilityId = v);
                  // Keep it legal: regenerate the PID so bit 0 selects this
                  // ability's slot (the stored ability then matches the PID).
                  if (widget.strictLegal && slot >= 0) {
                    _regenLegal(abilitySlot: slot);
                  }
                },
              ),
            )
          else
            Expanded(
              child: Text(_abilityName,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }

  // Held-item row. Editable (with sprites) for Gen 3; Gen 4 item ids differ, so
  // it's shown read-only there until a Gen-4 item table exists.
  Widget _heldItemRow() {
    final gen3 = widget.generation == 3;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const SizedBox(
              width: 90,
              child: Text('Held item',
                  style: TextStyle(fontWeight: FontWeight.w600))),
          if (gen3) _heldItemImage(_heldItem),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _heldItem == 0
                  ? 'None'
                  : gen3
                      ? gen3ItemName(_heldItem)
                      : 'Item #$_heldItem',
              style: const TextStyle(fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (gen3)
            TextButton(
                onPressed: _pickHeldItem, child: const Text('Change')),
        ],
      ),
    );
  }

  Widget _heldItemImage(int id) {
    const fallback =
        Icon(Icons.remove_circle_outline, size: 20, color: Colors.grey);
    if (id == 0) return const SizedBox(width: 28, child: Center(child: fallback));
    final url = gen3ItemSprite(id);
    if (url == null) {
      return const SizedBox(
          width: 28, child: Icon(Icons.category_outlined, size: 20));
    }
    return SizedBox(
      width: 28,
      height: 28,
      child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.contain,
          errorWidget: (_, _, _) =>
              const Icon(Icons.category_outlined, size: 20)),
    );
  }

  Future<void> _pickHeldItem() async {
    final all = [(id: 0, name: 'None'), ...gen3ItemPicker()];
    final picked = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        var query = '';
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            final q = query.trim().toLowerCase();
            final matches = q.isEmpty
                ? all
                : all.where((e) => e.name.toLowerCase().contains(q)).toList();
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.7,
              builder: (_, scroll) => Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Search items…',
                          isDense: true),
                      onChanged: (v) => setSheet(() => query = v),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      controller: scroll,
                      itemCount: matches.length,
                      itemBuilder: (_, i) => ListTile(
                        leading: _heldItemImage(matches[i].id),
                        title: Text(matches[i].name),
                        onTap: () => Navigator.pop(ctx, matches[i].id),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (picked == null || !mounted) return;
    setState(() => _heldItem = picked);
  }

  @override
  void dispose() {
    for (final c in [_level, _nickname, _otName, ..._iv, ..._ev, ..._contest]) {
      c.dispose();
    }
    super.dispose();
  }

  List<int> _read(List<TextEditingController> cs, int max) =>
      [for (final c in cs) (int.tryParse(c.text.trim()) ?? 0).clamp(0, max)];

  int get _evTotal => _read(_ev, 255).fold(0, (a, b) => a + b);

  String get _speciesName {
    for (final s in _allSpecies) {
      if (s.id == _speciesDex) return _pretty(s.name);
    }
    return '#$_speciesDex';
  }

  static String _pretty(String n) => n.isEmpty
      ? n
      : n
          .replaceAll('-', ' ')
          .split(' ')
          .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
          .join(' ');

  Widget _statRow(String title, List<TextEditingController> cs, int max) => Row(
        children: [
          SizedBox(
              width: 30,
              child: Text(title, style: const TextStyle(fontSize: 11))),
          for (var k = 0; k < 6; k++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  children: [
                    Text(_labels[k], style: const TextStyle(fontSize: 9)),
                    TextField(
                      controller: cs[k],
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontSize: 12),
                      decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 6)),
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );

  // Advanced fields — OT, ball, met, language, Pokérus, markings, contest.
  Widget _moreSection() => ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        title: const Text('More', style: TextStyle(fontWeight: FontWeight.w600)),
        children: [
          Row(
            children: [
              const Text('OT  ', style: TextStyle(fontWeight: FontWeight.w600)),
              Expanded(
                child: TextField(
                  controller: _otName,
                  maxLength: 7,
                  style: const TextStyle(fontSize: 13),
                  decoration:
                      const InputDecoration(isDense: true, counterText: ''),
                ),
              ),
              const SizedBox(width: 8),
              ToggleButtons(
                isSelected: [_otGender == 0, _otGender == 1],
                onPressed: (i) => setState(() => _otGender = i),
                constraints:
                    const BoxConstraints(minWidth: 34, minHeight: 30),
                children: const [Text('♂'), Text('♀')],
              ),
            ],
          ),
          Row(
            children: [
              const Text('Ball  ',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              Expanded(
                child: DropdownButton<int>(
                  isExpanded: true,
                  isDense: true,
                  value: _ball.clamp(0, kGen3Balls.length - 1),
                  style: const TextStyle(fontSize: 13, color: Colors.black),
                  items: [
                    for (var b = 0; b < kGen3Balls.length; b++)
                      DropdownMenuItem(value: b, child: Text(kGen3Balls[b])),
                  ],
                  onChanged: (v) => setState(() => _ball = v ?? _ball),
                ),
              ),
              const SizedBox(width: 12),
              const Text('Lang  ',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              DropdownButton<int>(
                isDense: true,
                value: kGen3Languages.containsKey(_language) ? _language : 2,
                style: const TextStyle(fontSize: 13, color: Colors.black),
                items: [
                  for (final e in kGen3Languages.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() => _language = v ?? _language),
              ),
            ],
          ),
          Row(
            children: [
              const Text('Met level  ',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              SizedBox(
                width: 48,
                child: TextField(
                  controller:
                      TextEditingController(text: '$_metLevel'),
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(isDense: true),
                  onChanged: (v) =>
                      _metLevel = (int.tryParse(v) ?? _metLevel).clamp(0, 100),
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  for (var b = 0; b < 4; b++)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: FilterChip(
                        label: Text(_markGlyphs[b]),
                        visualDensity: VisualDensity.compact,
                        selected: (_markings & (1 << b)) != 0,
                        onSelected: (s) => setState(() => _markings =
                            s ? _markings | (1 << b) : _markings & ~(1 << b)),
                      ),
                    ),
                ],
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Pokérus (immune)'),
            value: _pokerus != 0,
            onChanged: (v) => setState(() => _pokerus = v ? 0x40 : 0),
          ),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Contest', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          Row(
            children: [
              for (var k = 0; k < 6; k++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Column(
                      children: [
                        Text(_contestLabels[k],
                            style: const TextStyle(fontSize: 8)),
                        TextField(
                          controller: _contest[k],
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(fontSize: 12),
                          decoration: const InputDecoration(
                              isDense: true,
                              contentPadding:
                                  EdgeInsets.symmetric(vertical: 6)),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final over = _evTotal > 510;
    final keyboardUp = MediaQuery.of(context).viewInsets.bottom > 0;
    return Scaffold(
      body: Column(
        children: [
          _header(context),
          Expanded(
            // Tap anywhere in the form to dismiss the (number-pad) keyboard,
            // which has no return key of its own on iOS.
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => FocusScope.of(context).unfocus(),
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
            // Species picker — changing it re-derives stats, legal moves,
            // growth-rate EXP and the default nickname (Gen 3 + Gen 4).
            Row(
              children: [
                const Text('Species  ',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                Expanded(
                  child: Text(_speciesName,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            Autocomplete<({int id, String name})>(
              optionsBuilder: (v) {
                final q = v.text.trim().toLowerCase();
                if (q.isEmpty) return const Iterable.empty();
                return _allSpecies
                    .where((s) => s.name.toLowerCase().contains(q))
                    .take(40);
              },
              displayStringForOption: (o) => _pretty(o.name),
              onSelected: (o) => _changeSpecies(o.id, o.name),
              fieldViewBuilder: (ctx, ctrl, focus, onSubmit) => TextField(
                controller: ctrl,
                focusNode: focus,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search, size: 18),
                    hintText: 'Change species…'),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Nickname  ',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                Expanded(
                  child: TextField(
                    controller: _nickname,
                    maxLength: 10,
                    style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(
                        isDense: true, counterText: ''),
                  ),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Shiny'),
              value: _shiny,
              onChanged: (v) {
                setState(() => _shiny = v);
                if (widget.strictLegal) _regenLegal();
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const SizedBox(
                    width: 90,
                    child: Text('Level',
                        style: TextStyle(fontWeight: FontWeight.w600))),
                SizedBox(
                  width: 64,
                  child: TextField(
                    controller: _level,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14),
                    decoration: const InputDecoration(
                        isDense: true, helperText: '1–100'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const SizedBox(
                    width: 90,
                    child: Text('Nature',
                        style: TextStyle(fontWeight: FontWeight.w600))),
                Expanded(
                  child: DropdownButton<int>(
                    isExpanded: true,
                    isDense: true,
                    value: _nature,
                    style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).textTheme.bodyLarge?.color),
                    selectedItemBuilder: (_) => [
                      for (var n = 0; n < kNatures.length; n++)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Row(
                            children: [
                              Text(kNatures[n]),
                              const SizedBox(width: 8),
                              _natureEffectChip(n),
                            ],
                          ),
                        ),
                    ],
                    items: [
                      for (var n = 0; n < kNatures.length; n++)
                        DropdownMenuItem(
                          value: n,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(width: 76, child: Text(kNatures[n])),
                              _natureEffectChip(n),
                            ],
                          ),
                        ),
                    ],
                    onChanged: (v) {
                      setState(() => _nature = v ?? _nature);
                      if (widget.strictLegal) _regenLegal();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _abilityRow(),
            _heldItemRow(),
            const SizedBox(height: 4),
            Row(
              children: [
                const SizedBox(
                    width: 90,
                    child: Text('Friendship',
                        style: TextStyle(fontWeight: FontWeight.w600))),
                SizedBox(
                    width: 34,
                    child: Text('$_friendship',
                        style: const TextStyle(fontSize: 12))),
                Expanded(
                  child: Slider(
                    value: _friendship.toDouble(),
                    min: 0,
                    max: 255,
                    onChanged: (v) => setState(() => _friendship = v.round()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (widget.strictLegal) ...[
              Row(
                children: [
                  const Text('IVs',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(width: 6),
                  Text('total $_ivTotal',
                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  const Spacer(),
                  if (_rolling)
                    const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                  else
                    TextButton.icon(
                      onPressed: () => _regenLegal(reroll: true),
                      icon: const Icon(Icons.casino, size: 16),
                      label: const Text('Re-roll'),
                    ),
                ],
              ),
              // Read-only: IVs are RNG-legal (correlated with the PID).
              Row(
                children: [
                  for (var k = 0; k < 6; k++)
                    Expanded(
                      child: Column(
                        children: [
                          Text(_labels[k], style: const TextStyle(fontSize: 9)),
                          Text('${_ivs[k]}',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _ivs[k] == 31
                                      ? Colors.green
                                      : Theme.of(context)
                                          .textTheme
                                          .bodyLarge
                                          ?.color)),
                        ],
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _legalPid == null
                      ? 'IVs are the Pokémon\'s current legal values.'
                      : 'Legal PID + IVs generated (checker-safe).',
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ),
            ] else ...[
              // Gen 4: free IV editing.
              Row(
                children: [
                  const Text('IVs',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(() {
                      for (final c in _iv) {
                        c.text = '31';
                      }
                    }),
                    child: const Text('Max'),
                  ),
                ],
              ),
              _statRow('', _iv, 31),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('EVs', style: TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                Text('total $_evTotal / 510',
                    style: TextStyle(
                        fontSize: 11,
                        color: over ? Colors.red : Colors.grey)),
              ],
            ),
            const SizedBox(height: 4),
            _statRow('', _ev, 255),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Moves',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                if (_legal == null) ...[
                  const SizedBox(width: 8),
                  const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                ],
              ],
            ),
            for (var k = 0; k < 4; k++) _moveRow(k),
                  _moreSection(),
                  ],
                ),
              ),
            ),
          ),
          // A Done bar sits directly above the number pad (which has no return
          // key) so the keyboard can always be dismissed.
          if (keyboardUp)
            Material(
              color: Theme.of(context).colorScheme.surface,
              elevation: 8,
              child: SafeArea(
                top: false,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => FocusScope.of(context).unfocus(),
                    icon: const Icon(Icons.keyboard_hide, size: 18),
                    label: const Text('Done'),
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: _saveBar(context, over),
    );
  }

  PartyEdit _buildEdit() => PartyEdit(
        shiny: _shiny,
        nature: _nature,
        level: (int.tryParse(_level.text.trim()) ?? widget.mon.level)
            .clamp(1, 100),
        // Gen 3 strict-legal ships a correlated PID+IVs (or nothing if untouched);
        // Gen 4 ships freely-edited IVs + nature/shiny directly.
        legalPid: widget.strictLegal ? _legalPid : null,
        ivs: widget.strictLegal
            ? (_legalPid != null ? _ivs : null)
            : _read(_iv, 31),
        evs: _read(_ev, 255),
        moves: _moves,
        species: _speciesDex != widget.mon.dex ? _speciesDex : null,
        nickname:
            _nickname.text.trim().isEmpty ? null : _nickname.text.trim(),
        friendship: _friendship,
        otName: _otName.text.trim().isEmpty ? null : _otName.text.trim(),
        ball: _ball,
        metLevel: _metLevel,
        otGender: _otGender,
        language: _language,
        markings: _markings,
        pokerus: _pokerus,
        contest: _read(_contest, 255),
        heldItem: _heldItem != widget.mon.heldItem ? _heldItem : null,
        // Gen 4 only: Gen 3 ability is PID-derived (not stored).
        ability: (widget.generation == 4 && _abilityId != widget.mon.ability)
            ? _abilityId
            : null,
      );

  // Dex-entry-style header: type-colored banner with artwork, name, level,
  // shiny star and type chips.
  Widget _header(BuildContext context) {
    final banner = _types.isEmpty ? const Color(0xFF6B7280) : typeColor(_types.first);
    // Shiny-aware official artwork; the URL changes with species + shiny so the
    // header re-fetches whenever either is edited.
    final art =
        'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/other/official-artwork/${_shiny ? 'shiny/' : ''}$_speciesDex.png';
    final name = _nickname.text.trim().isEmpty ? _speciesName : _nickname.text.trim();
    final lvl = int.tryParse(_level.text.trim()) ?? widget.mon.level;
    return Container(
      color: banner,
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 132,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800)),
                        ),
                        if (_shiny)
                          const Padding(
                            padding: EdgeInsets.only(left: 6),
                            child: Icon(Icons.auto_awesome,
                                color: Colors.amberAccent, size: 20),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text('$_speciesName  ·  Lv$lvl',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        for (final t in _types)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.white24,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(t.toUpperCase(),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.5)),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: CachedNetworkImage(
                  imageUrl: art,
                  width: 104,
                  height: 104,
                  fit: BoxFit.contain,
                  errorWidget: (_, _, _) =>
                      const Icon(Icons.catching_pokemon, color: Colors.white54, size: 60),
                  placeholder: (_, _) => const SizedBox(width: 104, height: 104),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _saveBar(BuildContext context, bool over) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed:
                      over ? null : () => Navigator.pop(context, _buildEdit()),
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      );
}

// --------------------------------------------------------------- Badges
class _MilestonesTab extends StatelessWidget {
  final Game game;
  final Color tint;
  const _MilestonesTab({required this.game, required this.tint});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final p = state.progressFor(game.id);
    bool done(String m) => p.milestones[m] ?? false;
    void toggle(String m) => state.setMilestone(game.id, m, !done(m));

    final badges = game.milestones.where((m) => m.contains('Badge')).toList();
    final others = game.milestones.where((m) => !m.contains('Badge')).toList();
    final badgesDone = badges.where(done).length;
    final allDone = game.milestones.where(done).length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (badges.isNotEmpty) ...[
          Text('$badgesDone / ${badges.length} badges',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          _progressBar(badgesDone / badges.length),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 16,
            children: [
              for (final m in badges)
                _BadgeDisc(
                    name: m,
                    earned: done(m),
                    tint: tint,
                    onTap: () => toggle(m)),
            ],
          ),
          if (others.isNotEmpty) const Divider(height: 34),
        ] else ...[
          Text('$allDone / ${game.milestones.length} completed',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          _progressBar(game.milestones.isEmpty
              ? 0
              : allDone / game.milestones.length),
          const SizedBox(height: 8),
        ],
        for (final m in others)
          _MilestoneRow(label: m, done: done(m), tint: tint, onTap: () => toggle(m)),
      ],
    );
  }

  Widget _progressBar(double v) => ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
          value: v.clamp(0.0, 1.0),
          minHeight: 8,
          color: tint,
          backgroundColor: tint.withValues(alpha: 0.15),
        ),
      );
}

class _BadgeDisc extends StatelessWidget {
  final String name;
  final bool earned;
  final Color tint;
  final VoidCallback onTap;
  const _BadgeDisc({
    required this.name,
    required this.earned,
    required this.tint,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final spec = _gymBadgeSpecs[name];
    return SizedBox(
      width: 66,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Column(
          children: [
            SizedBox(
              width: 54,
              height: 54,
              child: spec != null
                  ? CustomPaint(painter: _GymBadgePainter(spec, earned))
                  : Container(
                      decoration: BoxDecoration(
                        color:
                            earned ? tint : scheme.surfaceContainerHighest,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.workspace_premium,
                          size: 26,
                          color: earned
                              ? Colors.white
                              : scheme.onSurfaceVariant),
                    ),
            ),
            const SizedBox(height: 6),
            Text(
              name.replaceAll(' Badge', ''),
              textAlign: TextAlign.center,
              maxLines: 2,
              style: TextStyle(
                  fontSize: 11,
                  color: earned ? scheme.onSurface : scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Gym badge artwork (drawn, no assets) ---------------------------------

enum _BadgeShape { octagon, teardrop, star, flower, heart, disc, rhombus, leaf }

class _GymBadgeSpec {
  final _BadgeShape shape;
  final Color color;
  const _GymBadgeSpec(this.shape, this.color);
}

// The eight Kanto Gym Badges, by milestone name — shape + signature color.
const Map<String, _GymBadgeSpec> _gymBadgeSpecs = {
  'Boulder Badge': _GymBadgeSpec(_BadgeShape.octagon, Color(0xFFB0A08A)),
  'Cascade Badge': _GymBadgeSpec(_BadgeShape.teardrop, Color(0xFF35A7E0)),
  'Thunder Badge': _GymBadgeSpec(_BadgeShape.star, Color(0xFFF6B92B)),
  'Rainbow Badge': _GymBadgeSpec(_BadgeShape.flower, Color(0xFFE24B87)),
  'Soul Badge': _GymBadgeSpec(_BadgeShape.heart, Color(0xFFE8567F)),
  'Marsh Badge': _GymBadgeSpec(_BadgeShape.disc, Color(0xFFF4CE3A)),
  'Volcano Badge': _GymBadgeSpec(_BadgeShape.rhombus, Color(0xFFE24C3B)),
  'Earth Badge': _GymBadgeSpec(_BadgeShape.leaf, Color(0xFF64B45A)),
};

class _GymBadgePainter extends CustomPainter {
  final _GymBadgeSpec spec;
  final bool earned;
  _GymBadgePainter(this.spec, this.earned);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width * 0.42;
    // Locked badges are drawn as a flat grey silhouette.
    final base = earned ? spec.color : const Color(0xFFB8B8B8);
    final dark = Color.lerp(base, Colors.black, 0.35)!;
    final fill = Paint()..color = base;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = dark;

    if (spec.shape == _BadgeShape.flower) {
      _flower(canvas, c, r);
    } else {
      final path = _shapePath(spec.shape, c, r);
      canvas.drawPath(path, fill);
      canvas.drawPath(path, stroke);
      // A soft highlight for a metallic feel.
      canvas.drawCircle(c.translate(-r * 0.28, -r * 0.28), r * 0.16,
          Paint()..color = Colors.white.withValues(alpha: earned ? 0.5 : 0.2));
    }
  }

  void _flower(Canvas canvas, Offset c, double r) {
    const petals = [
      Color(0xFFE24B87), // pink
      Color(0xFFF6B92B), // yellow
      Color(0xFF64B45A), // green
      Color(0xFF35A7E0), // blue
      Color(0xFF9B59B6), // purple
      Color(0xFFE24C3B), // red
    ];
    for (var i = 0; i < 6; i++) {
      final a = (i / 6) * 2 * math.pi - math.pi / 2;
      final pc = c + Offset(math.cos(a), math.sin(a)) * (r * 0.55);
      canvas.drawCircle(
          pc, r * 0.42, Paint()..color = earned ? petals[i] : const Color(0xFFC4C4C4));
    }
    canvas.drawCircle(c, r * 0.42,
        Paint()..color = earned ? const Color(0xFFF6D64A) : const Color(0xFFDDDDDD));
  }

  Path _shapePath(_BadgeShape s, Offset c, double r) {
    final p = Path();
    switch (s) {
      case _BadgeShape.octagon:
        for (var i = 0; i < 8; i++) {
          final a = (i / 8) * 2 * math.pi + math.pi / 8;
          final pt = c + Offset(math.cos(a), math.sin(a)) * r;
          i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
        }
        p.close();
      case _BadgeShape.disc:
        p.addOval(Rect.fromCircle(center: c, radius: r));
      case _BadgeShape.rhombus:
        p.moveTo(c.dx, c.dy - r);
        p.lineTo(c.dx + r * 0.8, c.dy);
        p.lineTo(c.dx, c.dy + r);
        p.lineTo(c.dx - r * 0.8, c.dy);
        p.close();
      case _BadgeShape.star:
        for (var i = 0; i < 16; i++) {
          final rad = i.isEven ? r : r * 0.46;
          final a = (i / 16) * 2 * math.pi - math.pi / 2;
          final pt = c + Offset(math.cos(a), math.sin(a)) * rad;
          i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
        }
        p.close();
      case _BadgeShape.teardrop:
        p.moveTo(c.dx, c.dy - r);
        p.quadraticBezierTo(c.dx + r, c.dy - r * 0.1, c.dx + r * 0.75, c.dy + r * 0.5);
        p.arcToPoint(Offset(c.dx - r * 0.75, c.dy + r * 0.5),
            radius: Radius.circular(r * 0.8), clockwise: true);
        p.quadraticBezierTo(c.dx - r, c.dy - r * 0.1, c.dx, c.dy - r);
        p.close();
      case _BadgeShape.heart:
        p.moveTo(c.dx, c.dy + r * 0.85);
        p.cubicTo(c.dx - r * 1.3, c.dy - r * 0.1, c.dx - r * 0.5, c.dy - r,
            c.dx, c.dy - r * 0.35);
        p.cubicTo(c.dx + r * 0.5, c.dy - r, c.dx + r * 1.3, c.dy - r * 0.1,
            c.dx, c.dy + r * 0.85);
        p.close();
      case _BadgeShape.leaf:
        p.moveTo(c.dx, c.dy - r);
        p.quadraticBezierTo(c.dx + r, c.dy, c.dx, c.dy + r);
        p.quadraticBezierTo(c.dx - r, c.dy, c.dx, c.dy - r);
        p.close();
      case _BadgeShape.flower:
        break; // handled separately
    }
    return p;
  }

  @override
  bool shouldRepaint(_GymBadgePainter old) =>
      old.earned != earned || old.spec != spec;
}

class _MilestoneRow extends StatelessWidget {
  final String label;
  final bool done;
  final Color tint;
  final VoidCallback onTap;
  const _MilestoneRow({
    required this.label,
    required this.done,
    required this.tint,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: done ? tint : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: done ? null : Border.all(color: scheme.outline),
              ),
              child: done
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(label)),
          ],
        ),
      ),
    );
  }
}

// --------------------------------------------------------------- Pokedex
/// Per-game Pokedex: only this game's species, with obtainability tags and a
/// caught checkbox that feeds completion.
class _DexTab extends StatefulWidget {
  final Game game;
  final Color tint;
  const _DexTab({required this.game, required this.tint});

  @override
  State<_DexTab> createState() => _DexTabState();
}

enum _DexFilter { all, caught, missing }

/// A row in the per-game dex: a base species or one of its forms.
class _DexRow {
  final int id; // /pokemon id
  final int baseDex;
  final String name; // base species name
  final int entryNumber;
  final bool isForm;
  final String? formLabel;
  const _DexRow({
    required this.id,
    required this.baseDex,
    required this.name,
    required this.entryNumber,
    this.isForm = false,
    this.formLabel,
  });

  String get spriteUrl =>
      'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/$id.png';
}

int _genForDex(int dex) {
  const ends = [151, 251, 386, 493, 649, 721, 809, 905, 1025];
  for (var i = 0; i < ends.length; i++) {
    if (dex <= ends[i]) return i + 1;
  }
  return 9;
}

/// Best-effort introduction generation for a form, from its label.
int _formIntroGen(String label, int baseDex) {
  final l = label.toLowerCase();
  if (l.contains('alolan')) return 7;
  if (l.contains('galarian')) return 8;
  if (l.contains('hisuian')) return 8;
  if (l.contains('paldean')) return 9;
  if (l.contains('mega') || l.contains('primal')) return 6;
  if (l.contains('gigantamax')) return 8;
  return _genForDex(baseDex);
}

class _DexTabState extends State<_DexTab> {
  final _service = PokedexService();
  GameDex? _dex;
  final Map<int, List<_DexRow>> _formsByDex = {};
  bool _loading = true;
  String? _error;
  bool _showForms = false;
  _DexFilter _filter = _DexFilter.all;
  String _query = '';

  // Memoized obtainability futures so rebuilds (checkbox taps) don't refetch.
  final Map<int, Future<ObtainInfo>> _obtain = {};
  // Memoized type lookups for the per-entry type chips.
  final Map<int, Future<List<String>>> _typesFut = {};
  Future<List<String>> _typesFor(int id) =>
      _typesFut.putIfAbsent(id, () => _service.typesOf(id));

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dex = await _service.loadGameDex(widget.game.versionGroup);
      final baseNameToDex = {for (final s in dex.species) s.name: s.id};
      final dexToName = {for (final s in dex.species) s.id: s.name};
      final varieties = await _service.loadAllVarieties();
      final formsByDex = <int, List<_DexRow>>{};
      for (final v in varieties) {
        if (v.id < 10000) continue;
        final baseDex = _baseDexForForm(v.name, baseNameToDex);
        if (baseDex == null) continue;
        final baseName = dexToName[baseDex]!;
        final label = _service.labelForForm(v.name, baseName);
        if (_formIntroGen(label, baseDex) > widget.game.generation) continue;
        formsByDex.putIfAbsent(baseDex, () => []).add(_DexRow(
              id: v.id,
              baseDex: baseDex,
              name: baseName,
              entryNumber: 0,
              isForm: true,
              formLabel: label,
            ));
      }
      for (final l in formsByDex.values) {
        l.sort((a, b) => a.id.compareTo(b.id));
      }
      if (!mounted) return;
      setState(() {
        _dex = dex;
        _formsByDex
          ..clear()
          ..addAll(formsByDex);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load this game\'s Pokedex.\nCheck your connection and retry.';
        _loading = false;
      });
    }
  }

  Future<void> _addToBox(_DexRow r) async {
    // The lowest level this species can legally be (its evolution requirement).
    final minLevel =
        await context.read<AppState>().minAddLevel(widget.game, r.baseDex);
    if (!mounted) return;
    final levelCtrl = TextEditingController(text: '$minLevel');
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add ${prettifyName(r.name)} to PC box'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                'Creates a legal Pokémon (correlated PID/IVs, level-appropriate '
                'moves, you as the OT) in the first free box slot. A backup is '
                'written first.'),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Level  ',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                SizedBox(
                  width: 72,
                  child: TextField(
                    controller: levelCtrl,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                        isDense: true, helperText: 'min $minLevel'),
                  ),
                ),
              ],
            ),
            if (minLevel > 5)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                    '${prettifyName(r.name)} can\'t legally exist below Lv $minLevel '
                    '(its evolution level).',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Add')),
        ],
      ),
    );
    if (go != true || !mounted) return;
    final level =
        (int.tryParse(levelCtrl.text.trim()) ?? minLevel).clamp(minLevel, 100);
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Building a legal Pokémon…')));
    final state = context.read<AppState>();
    final msg = await state.addLegalMonToBox(widget.game, r.baseDex, level: level);
    if (!mounted) return;
    if (msg.startsWith('Added')) {
      state.setCaught(widget.game.id, r.baseDex, true); // reflect in the dex now
    }
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 5)));
  }

  int? _baseDexForForm(String formName, Map<String, int> baseNameToDex) {
    final parts = formName.split('-');
    for (var take = parts.length - 1; take >= 1; take--) {
      final dex = baseNameToDex[parts.take(take).join('-')];
      if (dex != null) return dex;
    }
    return null;
  }

  Future<ObtainInfo> _obtainFor(int id, List<String> versions) =>
      _obtain.putIfAbsent(id, () => _service.loadObtainability(id, versions));

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    final dex = _dex!;
    if (dex.species.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            "Pokedex data for this game isn't available yet.",
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final state = context.watch<AppState>();
    final gameId = widget.game.id;
    final total = dex.species.length;
    final caught =
        dex.species.where((s) => state.isCaught(gameId, s.id)).length;

    // Merge base species with their forms, then apply the caught filter.
    final rows = <_DexRow>[];
    for (final s in dex.species) {
      rows.add(_DexRow(
          id: s.id, baseDex: s.id, name: s.name, entryNumber: s.entryNumber));
      if (_showForms) rows.addAll(_formsByDex[s.id] ?? const []);
    }
    final q = _query.trim().toLowerCase();
    final visible = rows.where((r) {
      final isCaught = state.isCaught(gameId, r.id);
      final passFilter = switch (_filter) {
        _DexFilter.all => true,
        _DexFilter.caught => isCaught,
        _DexFilter.missing => !isCaught,
      };
      if (!passFilter) return false;
      if (q.isEmpty) return true;
      // Match on name, national dex number, or entry number.
      return r.name.toLowerCase().contains(q) ||
          '${r.baseDex}'.contains(q) ||
          r.entryNumber.toString().padLeft(3, '0').contains(q);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Caught $caught / $total',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: total == 0 ? 0 : caught / total,
                  minHeight: 8,
                  color: widget.tint,
                  backgroundColor: widget.tint.withValues(alpha: 0.15),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final f in _DexFilter.values)
                    ChoiceChip(
                      label: Text(f.name[0].toUpperCase() + f.name.substring(1)),
                      selected: _filter == f,
                      selectedColor: widget.tint,
                      showCheckmark: false,
                      labelStyle: TextStyle(
                        color: _filter == f
                            ? Colors.white
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                      onSelected: (_) => setState(() => _filter = f),
                    ),
                  FilterChip(
                    label: const Text('Forms'),
                    selected: _showForms,
                    showCheckmark: true,
                    checkmarkColor: Colors.white,
                    selectedColor: widget.tint,
                    labelStyle: TextStyle(
                      color: _showForms
                          ? Colors.white
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                    onSelected: (v) => setState(() => _showForms = v),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  hintText: 'Search name or number…',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () => setState(() => _query = ''),
                        ),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: visible.length,
            itemBuilder: (context, i) => _row(context, state, visible[i]),
          ),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, AppState state, _DexRow r) {
    final gameId = widget.game.id;
    final isCaught = state.isCaught(gameId, r.id);
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      tileColor: isCaught ? widget.tint.withValues(alpha: 0.07) : null,
      contentPadding: EdgeInsets.only(left: r.isForm ? 32 : 16, right: 8),
      leading: SizedBox(
        width: 44,
        height: 44,
        child: () {
          final img = CachedNetworkImage(
            imageUrl: r.spriteUrl,
            fit: BoxFit.contain,
            errorWidget: (_, _, _) =>
                const Icon(Icons.catching_pokemon, color: Colors.grey),
            placeholder: (_, _) => const SizedBox(),
          );
          // Uncaught entries show as a dark silhouette, like the real Pokédex.
          return isCaught
              ? img
              : ColorFiltered(
                  colorFilter: ColorFilter.mode(
                      scheme.onSurface.withValues(alpha: 0.82),
                      BlendMode.srcATop),
                  child: Opacity(opacity: 0.85, child: img),
                );
        }(),
      ),
      title: r.isForm
          ? Row(
              children: [
                Flexible(child: Text(prettifyName(r.name))),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: widget.tint,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(r.formLabel ?? 'Form',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            )
          : Text(prettifyName(r.name)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          FutureBuilder<List<String>>(
            future: _typesFor(r.id),
            builder: (context, snap) {
              final types = snap.data ?? const <String>[];
              return Row(
                children: [
                  if (!r.isForm) ...[
                    Text('#${r.entryNumber.toString().padLeft(3, '0')}',
                        style: TextStyle(color: scheme.onSurfaceVariant)),
                    const SizedBox(width: 8),
                  ],
                  for (final t in types) ...[
                    _TypeChip(type: t),
                    const SizedBox(width: 4),
                  ],
                ],
              );
            },
          ),
          if (!r.isForm)
            FutureBuilder<ObtainInfo>(
              future: _obtainFor(r.id, [widget.game.version]),
              builder: (context, snap) => Padding(
                padding: const EdgeInsets.only(top: 3),
                child: snap.hasData
                    ? _ObtainChip(info: snap.data!)
                    : const Text('…', style: TextStyle(color: Colors.grey)),
              ),
            )
          else
            Text('Alternate form',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
        ],
      ),
      isThreeLine: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Add a legal copy to the PC box (Gen 3 base species only).
          if (widget.game.generation == 3 && !r.isForm)
            IconButton(
              tooltip: 'Add a legal one to your PC box',
              icon: const Icon(Icons.add_box_outlined),
              color: widget.tint,
              onPressed: () => _addToBox(r),
            ),
          Checkbox(
            value: isCaught,
            activeColor: widget.tint,
            onChanged: (v) => state.setCaught(gameId, r.id, v ?? false),
          ),
        ],
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PokemonDetailScreen(
            id: r.baseDex,
            name: r.name,
            generation: widget.game.generation,
            initialFormId: r.isForm ? r.id : null,
            gameVersion: widget.game.version,
            gameTitle: widget.game.title.replaceFirst('Pokemon ', ''),
          ),
        ),
      ),
    );
  }
}

/// A small colored type chip (Grass, Fire, …).
class _TypeChip extends StatelessWidget {
  final String type;
  const _TypeChip({required this.type});

  @override
  Widget build(BuildContext context) {
    final c = typeColor(type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: c,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(type.toUpperCase(),
          style: const TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3)),
    );
  }
}

/// Colored chip summarizing obtainability.
class _ObtainChip extends StatelessWidget {
  final ObtainInfo info;
  const _ObtainChip({required this.info});

  @override
  Widget build(BuildContext context) {
    late Color color;
    late String label;
    switch (info.kind) {
      case ObtainKind.wild:
        color = Colors.green;
        label = 'Wild';
        break;
      case ObtainKind.partial:
        color = Colors.blue;
        label = 'Wild: ${info.versions.map(prettifyName).join(', ')}';
        break;
      case ObtainKind.none:
        color = Colors.orange;
        label = 'Not in wild';
        break;
      case ObtainKind.unknown:
        color = Colors.grey;
        label = 'Unknown';
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(label,
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

// ----------------------------------------------- Form resolution (Team/Shiny)
/// Resolves species text (base name or form variety like "raichu-alola") to a
/// sprite id, a nice display name, and the list of a species' forms.
class _FormIndex {
  final Map<String, int> nameToId;
  final Map<String, String> varietyToBase;
  final Map<String, List<({int id, String name, String label})>> formsByBase;
  _FormIndex(this.nameToId, this.varietyToBase, this.formsByBase);

  static String norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static Future<_FormIndex> load() async {
    final svc = PokedexService();
    final varieties = await svc.loadAllVarieties();
    final formsByBase = await svc.loadFormsByBase();
    final nameToId = {for (final v in varieties) norm(v.name): v.id};
    final varietyToBase = <String, String>{};
    for (final e in formsByBase.entries) {
      for (final f in e.value) {
        varietyToBase[norm(f.name)] = e.key;
      }
    }
    return _FormIndex(nameToId, varietyToBase, formsByBase);
  }

  int? idFor(String species) {
    final s = species.trim();
    if (s.isEmpty) return null;
    if (s.startsWith('#')) return int.tryParse(s.substring(1));
    return nameToId[norm(s)];
  }

  List<({int id, String name, String label})> formsFor(String species) {
    final base = varietyToBase[norm(species)];
    if (base == null) return const [];
    return formsByBase[base] ?? const [];
  }

  String display(String species) {
    final base = varietyToBase[norm(species)];
    if (base != null && norm(base) != norm(species)) {
      final f = (formsByBase[base] ?? const [])
          .where((x) => norm(x.name) == norm(species));
      if (f.isNotEmpty && f.first.label != 'Normal') {
        return '${prettifyName(base)} · ${f.first.label}';
      }
    }
    return prettifyName(species);
  }
}

/// A chip row to pick a species' form; empty until a species with >1 form is
/// entered. Shared by the Team and Shiny edit sheets.
Widget _formPickerRow(BuildContext ctx, TextEditingController species,
    StateSetter setSheet, _FormIndex? forms, Color tint) {
  final list = forms?.formsFor(species.text) ?? const [];
  if (list.length <= 1) return const SizedBox.shrink();
  final scheme = Theme.of(ctx).colorScheme;
  return Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final f in list)
          ChoiceChip(
            label: Text(f.label),
            selected: _FormIndex.norm(species.text) == _FormIndex.norm(f.name),
            showCheckmark: false,
            selectedColor: tint,
            labelStyle: TextStyle(
              color: _FormIndex.norm(species.text) == _FormIndex.norm(f.name)
                  ? Colors.white
                  : scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
            onSelected: (_) => setSheet(() => species.text = f.name),
          ),
      ],
    ),
  );
}

// --------------------------------------------------------------- Team
class _TeamTab extends StatefulWidget {
  final Game game;
  final Color tint;
  const _TeamTab({required this.game, required this.tint});

  @override
  State<_TeamTab> createState() => _TeamTabState();
}

class _TeamTabState extends State<_TeamTab> {
  _FormIndex? _forms;

  @override
  void initState() {
    super.initState();
    _FormIndex.load().then((f) {
      if (mounted) setState(() => _forms = f);
    });
  }

  int? _dexIdFor(String species) => _forms?.idFor(species) ?? _fallbackId(species);

  int? _fallbackId(String species) {
    final s = species.trim();
    if (s.startsWith('#')) return int.tryParse(s.substring(1));
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final team = state.progressFor(widget.game.id).team;

    return Scaffold(
      body: team.isEmpty
          ? const Center(child: Text('No team members yet. Tap + to add one.'))
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
              itemCount: team.length,
              itemBuilder: (context, i) =>
                  _memberCard(context, state, i, team[i]),
            ),
      floatingActionButton: team.length < 6
          ? FloatingActionButton.extended(
              backgroundColor: widget.tint,
              foregroundColor: Colors.white,
              onPressed: () async {
                final s = context.read<AppState>();
                s.addTeamMember(widget.game.id);
                final list = s.progressFor(widget.game.id).team;
                await _editMember(context, s, list.length - 1, list.last);
              },
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            )
          : null,
    );
  }

  Widget _memberCard(
      BuildContext context, AppState state, int i, TeamMember member) {
    final id = _dexIdFor(member.species);
    final scheme = Theme.of(context).colorScheme;
    final title = member.species.trim().isEmpty
        ? 'Tap to choose'
        : (_forms?.display(member.species) ?? prettifyName(member.species));
    final sub = member.nickname.trim().isEmpty ? null : '"${member.nickname}"';
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: InkWell(
        onTap: () => _editMember(context, state, i, member),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                clipBehavior: Clip.antiAlias,
                child: id == null
                    ? Icon(Icons.catching_pokemon,
                        color: scheme.onSurfaceVariant)
                    : CachedNetworkImage(
                        imageUrl:
                            'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/$id.png',
                        errorWidget: (_, _, _) => Icon(Icons.catching_pokemon,
                            color: scheme.onSurfaceVariant),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    if (sub != null)
                      Text(sub,
                          style: TextStyle(
                              fontSize: 12, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('Lv ${member.level}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editMember(
      BuildContext context, AppState state, int index, TeamMember member) async {
    final species = TextEditingController(text: member.species);
    final nickname = TextEditingController(text: member.nickname);
    final level = TextEditingController(text: member.level.toString());
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
              16, 4, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Edit Pokémon', style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 12),
              TextField(
                controller: species,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                    labelText: 'Species', border: OutlineInputBorder()),
                onChanged: (_) => setSheet(() {}),
              ),
              _formPickerRow(ctx, species, setSheet, _forms, widget.tint),
              const SizedBox(height: 12),
              TextField(
                controller: nickname,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                    labelText: 'Nickname (optional)',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: level,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Level', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () {
                      state.removeTeamMember(widget.game.id, index);
                      Navigator.pop(ctx);
                    },
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Remove'),
                  ),
                  const Spacer(),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: widget.tint),
                    onPressed: () {
                      member.species = species.text.trim();
                      member.nickname = nickname.text.trim();
                      member.level = int.tryParse(level.text) ?? member.level;
                      state.updateTeamMember(widget.game.id, index, member);
                      Navigator.pop(ctx);
                    },
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }
}

// --------------------------------------------------------------- Shiny
/// Common shiny-hunting methods and their approximate base odds denominator.
const List<({String name, int rate})> _shinyMethods = [
  (name: 'Random encounter', rate: 4096),
  (name: 'Full Odds', rate: 4096),
  (name: 'Masuda Method', rate: 683),
  (name: 'Masuda + Shiny Charm', rate: 512),
  (name: 'SOS chain', rate: 683),
  (name: 'Soft reset', rate: 4096),
  (name: 'Shiny Charm', rate: 1365),
  (name: 'Gen 2 (1/8192)', rate: 8192),
];

int _shinyRate(String method) {
  final m = method.toLowerCase();
  if (m.contains('masuda') && m.contains('charm')) return 512;
  if (m.contains('masuda')) return 683;
  if (m.contains('sos') || m.contains('chain') || m.contains('combo')) {
    return 683;
  }
  if (m.contains('charm')) return 1365;
  if (m.contains('8192') || m.contains('gen 2')) return 8192;
  return 4096;
}

class _ShinyTab extends StatefulWidget {
  final Game game;
  final Color tint;
  const _ShinyTab({required this.game, required this.tint});

  @override
  State<_ShinyTab> createState() => _ShinyTabState();
}

class _ShinyTabState extends State<_ShinyTab> {
  _FormIndex? _forms;

  @override
  void initState() {
    super.initState();
    _FormIndex.load().then((f) {
      if (mounted) setState(() => _forms = f);
    });
  }

  int? _dexIdFor(String species) {
    final s = species.trim();
    if (s.startsWith('#')) return int.tryParse(s.substring(1));
    return _forms?.idFor(species);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final hunts = state.progressFor(widget.game.id).shinyHunts;

    return Scaffold(
      body: hunts.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No shiny hunts yet. Tap + to start one.',
                    textAlign: TextAlign.center),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
              itemCount: hunts.length,
              itemBuilder: (context, i) => _huntCard(context, state, i, hunts[i]),
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: widget.tint,
        foregroundColor: Colors.white,
        onPressed: () async {
          final s = context.read<AppState>();
          s.addShinyHunt(widget.game.id);
          final list = s.progressFor(widget.game.id).shinyHunts;
          await _editHunt(context, s, list.length - 1, list.last);
        },
        icon: const Icon(Icons.auto_awesome),
        label: const Text('New hunt'),
      ),
    );
  }

  Widget _huntCard(
      BuildContext context, AppState state, int i, ShinyHunt hunt) {
    final scheme = Theme.of(context).colorScheme;
    final tint = widget.tint;
    final id = _dexIdFor(hunt.species);
    final rate = _shinyRate(hunt.method);
    final chance = 1 - math.pow(1 - 1 / rate, hunt.count).toDouble();
    final chanceText = hunt.count == 0
        ? '1/$rate base odds'
        : '≈ ${(chance * 100).toStringAsFixed(chance < 0.1 ? 1 : 0)}% by now · 1/$rate';
    final title = hunt.species.trim().isEmpty
        ? 'Tap to set species'
        : (_forms?.display(hunt.species) ?? prettifyName(hunt.species));

    void update() => state.updateShinyHunt(widget.game.id, i, hunt);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: hunt.caught
            ? BorderSide(color: tint, width: 2)
            : BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: () => _editHunt(context, state, i, hunt),
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      shape: BoxShape.circle,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: id == null
                        ? Icon(Icons.auto_awesome, color: tint)
                        : CachedNetworkImage(
                            imageUrl:
                                'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/shiny/$id.png',
                            errorWidget: (_, _, _) =>
                                Icon(Icons.auto_awesome, color: tint),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _editHunt(context, state, i, hunt),
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600)),
                            ),
                            if (hunt.caught) ...[
                              const SizedBox(width: 6),
                              Icon(Icons.check_circle, size: 18, color: tint),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(hunt.method,
                            style: TextStyle(
                                fontSize: 12, color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => state.removeShinyHunt(widget.game.id, i),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Encounters',
                        style: TextStyle(
                            fontSize: 11, color: scheme.onSurfaceVariant)),
                    Text('${hunt.count}',
                        style: const TextStyle(
                            fontSize: 28, fontWeight: FontWeight.w700)),
                  ],
                ),
                const Spacer(),
                _RoundBtn(
                  icon: Icons.remove,
                  color: tint,
                  filled: false,
                  onTap: hunt.count > 0
                      ? () {
                          hunt.count--;
                          update();
                        }
                      : null,
                ),
                const SizedBox(width: 10),
                _RoundBtn(
                  icon: Icons.add,
                  color: tint,
                  filled: true,
                  onTap: () {
                    hunt.count++;
                    update();
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.percent, size: 14, color: scheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(chanceText,
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant)),
                const Spacer(),
                FilterChip(
                  label: const Text('Caught!'),
                  avatar: Icon(Icons.auto_awesome,
                      size: 16,
                      color: hunt.caught ? Colors.white : tint),
                  selected: hunt.caught,
                  showCheckmark: false,
                  selectedColor: tint,
                  labelStyle: TextStyle(
                    color: hunt.caught ? Colors.white : scheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                  onSelected: (v) {
                    hunt.caught = v;
                    update();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editHunt(
      BuildContext context, AppState state, int index, ShinyHunt hunt) async {
    final species = TextEditingController(text: hunt.species);
    final method = TextEditingController(text: hunt.method);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
              16, 4, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Shiny hunt', style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 12),
              TextField(
                controller: species,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                    labelText: 'Species', border: OutlineInputBorder()),
                onChanged: (_) => setSheet(() {}),
              ),
              _formPickerRow(ctx, species, setSheet, _forms, widget.tint),
              const SizedBox(height: 12),
              TextField(
                controller: method,
                decoration: const InputDecoration(
                    labelText: 'Method', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final m in _shinyMethods)
                    ActionChip(
                      label: Text(m.name),
                      onPressed: () => setSheet(() => method.text = m.name),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () {
                      state.removeShinyHunt(widget.game.id, index);
                      Navigator.pop(ctx);
                    },
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Remove'),
                  ),
                  const Spacer(),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: widget.tint),
                    onPressed: () {
                      hunt.species = species.text.trim();
                      hunt.method = method.text.trim().isEmpty
                          ? 'Random encounter'
                          : method.text.trim();
                      state.updateShinyHunt(widget.game.id, index, hunt);
                      Navigator.pop(ctx);
                    },
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }
}

class _RoundBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool filled;
  final VoidCallback? onTap;
  const _RoundBtn({
    required this.icon,
    required this.color,
    required this.filled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    final bg = filled
        ? (enabled ? color : scheme.surfaceContainerHighest)
        : scheme.surfaceContainerHighest;
    final fg = filled
        ? Colors.white
        : (enabled ? color : scheme.onSurfaceVariant.withValues(alpha: 0.4));
    return Material(
      color: bg,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: fg),
        ),
      ),
    );
  }
}

// -------------------------------------------------- Save-file auto-tracker

Future<void> _startSaveSync(BuildContext context, Game game) async {
  final state = context.read<AppState>();
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(const SnackBar(content: Text('Reading save file…')));
  SaveData? data;
  try {
    data = await state.scanSave(game);
  } on SaveParseException catch (e) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return;
  } catch (e) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text('Could not read save: $e')));
    return;
  }
  messenger.hideCurrentSnackBar();
  if (!context.mounted) return;

  if (data == null) {
    final locate = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('No save file found'),
        content: Text(
            'I looked next to ${game.title}\'s ROM but found no save (.sav). '
            'Play the game once so the emulator writes a save, or point me to '
            'the save file.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Close')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Locate save…')),
        ],
      ),
    );
    if (locate == true && context.mounted) await _locateSave(context, game);
    return;
  }

  await showDialog(
    context: context,
    builder: (_) => _SaveSyncDialog(game: game, data: data!),
  );
}

Future<void> _locateSave(BuildContext context, Game game) async {
  final controller = TextEditingController();
  final path = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Locate save file'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: r'C:\...\game.sav',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Use file')),
      ],
    ),
  );
  if (path == null || path.isEmpty || !context.mounted) return;
  await context.read<AppState>().setSavePath(game.id, path);
  if (context.mounted) await _startSaveSync(context, game);
}

class _SaveSyncDialog extends StatefulWidget {
  final Game game;
  final SaveData data;
  const _SaveSyncDialog({required this.game, required this.data});

  @override
  State<_SaveSyncDialog> createState() => _SaveSyncDialogState();
}

class _SaveSyncDialogState extends State<_SaveSyncDialog> {
  late bool _dex = widget.data.caughtCount > 0;
  late bool _badges = widget.data.badgeCount != null;
  late bool _team = widget.data.team.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final muted = Theme.of(context).textTheme.bodySmall;
    return AlertDialog(
      title: const Text('Sync from save'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (d.trainerName != null && d.trainerName!.isNotEmpty)
              Text('Trainer: ${d.trainerName}',
                  style: Theme.of(context).textTheme.titleSmall),
            if (d.trainerId != null)
              Text(
                  'ID ${d.trainerId!.toString().padLeft(5, '0')}'
                  '${d.secretId != null ? '   ·   Secret ID ${d.secretId!.toString().padLeft(5, '0')}' : ''}',
                  style: muted),
            if (d.playTime != null)
              Text('Play time: ${d.playTimeText}', style: muted),
            if (d.money != null)
              Text('Money: ₽${d.money}', style: muted),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _dex,
              onChanged: d.caughtCount == 0
                  ? null
                  : (v) => setState(() => _dex = v ?? false),
              title: Text(
                  'Caught Pokedex — ${d.caughtCount} / ${widget.game.dexTotal} species'),
              subtitle: d.seenCount > 0
                  ? Text('${d.seenCount} seen', style: muted)
                  : null,
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _badges,
              onChanged: d.badgeCount == null
                  ? null
                  : (v) => setState(() => _badges = v ?? false),
              title: Text(d.badgeCount == null
                  ? 'Badges — not available for this save'
                  : 'Badges — ${d.badgeCount}'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _team,
              onChanged: d.team.isEmpty
                  ? null
                  : (v) => setState(() => _team = v ?? false),
              title: Text(d.team.isEmpty
                  ? 'Team — not available for this save'
                  : 'Team — ${d.team.length} Pokemon'),
              subtitle: d.team.isEmpty
                  ? null
                  : Text(
                      d.team
                          .map((m) =>
                              '${m.name ?? (m.dexId != null ? '#${m.dexId}' : '?')} Lv${m.level}')
                          .join(', '),
                      style: muted),
            ),
            for (final note in d.notes)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('• $note', style: muted),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: (_dex || _badges || _team)
              ? () async {
                  await context.read<AppState>().applySaveData(
                        widget.game,
                        d,
                        dex: _dex,
                        badges: _badges,
                        team: _team,
                      );
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Progress synced from save.')),
                  );
                }
              : null,
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../models/cheat.dart';
import '../models/game.dart';
import '../services/cheat_service.dart';

/// Bottom sheet to manage cheat codes for a game: toggle the bundled codes,
/// add/remove your own, all persisted per game. When shown from the running
/// emulator, [onApply] re-applies the enabled set live.
class CheatsSheet extends StatefulWidget {
  final Game game;
  final Future<void> Function()? onApply;
  const CheatsSheet({super.key, required this.game, this.onApply});

  @override
  State<CheatsSheet> createState() => _CheatsSheetState();
}

class _CheatsSheetState extends State<CheatsSheet> {
  List<Cheat> _cheats = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cheats = await CheatService.forGame(widget.game.id);
    if (!mounted) return;
    setState(() {
      _cheats = cheats;
      _loading = false;
    });
  }

  Future<void> _toggle(Cheat c, bool on) async {
    await CheatService.setEnabled(widget.game.id, c, on);
    await _load();
    await widget.onApply?.call();
  }

  Future<void> _remove(Cheat c) async {
    await CheatService.removeUserCheat(widget.game.id, c.name);
    await _load();
    await widget.onApply?.call();
  }

  Future<void> _add() async {
    final added = await showDialog<bool>(
      context: context,
      builder: (_) => _AddCheatDialog(gameId: widget.game.id),
    );
    if (added == true) {
      await _load();
      await widget.onApply?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Cheats', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.warning_amber,
                          size: 15, color: theme.colorScheme.error),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Cheats can corrupt a save. Duplicate your save first '
                          '(Saves → Duplicate). Codes take effect on the next '
                          'launch or when toggled in-game.',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.hintColor),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_cheats.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text('No cheats yet. Add one below.',
                    style: theme.textTheme.bodyMedium),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final c in _cheats)
                      SwitchListTile(
                        value: c.enabled,
                        onChanged: (v) => _toggle(c, v),
                        title: Text(c.name),
                        subtitle: Text(
                          '${c.builtIn ? 'Built-in' : 'Custom'} · '
                          '${c.code.split(RegExp(r"[\r\n]+")).first}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                        secondary: c.builtIn
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.delete_outline),
                                tooltip: 'Delete',
                                onPressed: () => _remove(c),
                              ),
                      ),
                  ],
                ),
              ),
            const Divider(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: OutlinedButton.icon(
                onPressed: _loading ? null : _add,
                icon: const Icon(Icons.add),
                label: const Text('Add cheat'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddCheatDialog extends StatefulWidget {
  final String gameId;
  const _AddCheatDialog({required this.gameId});

  @override
  State<_AddCheatDialog> createState() => _AddCheatDialogState();
}

class _AddCheatDialogState extends State<_AddCheatDialog> {
  final _name = TextEditingController();
  final _code = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final code = _code.text.trim();
    if (name.isEmpty || code.isEmpty) return;
    await CheatService.addUserCheat(widget.gameId, name, code);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add cheat'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
                labelText: 'Name', hintText: 'e.g. Infinite Money'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _code,
            minLines: 2,
            maxLines: 6,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: const InputDecoration(
              labelText: 'Code',
              hintText: 'GameShark / AR lines\none per line',
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Add')),
      ],
    );
  }
}

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/game.dart';
import '../state/app_state.dart';

String _sprite(int dex, bool shiny) =>
    'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/'
    '${shiny ? 'shiny/' : ''}$dex.png';

/// PKHeX-style side-by-side boxes: the game's PC boxes on the left, the Vault
/// on the right. Click-drag to marquee-select in either panel, then copy the
/// selection across.
class DualBoxScreen extends StatefulWidget {
  final Game game;
  const DualBoxScreen({super.key, required this.game});
  @override
  State<DualBoxScreen> createState() => _DualBoxScreenState();
}

class _DualBoxScreenState extends State<DualBoxScreen> {
  static const _cols = 6, _rows = 5, _perBox = 30;
  Map<int, ({int dex, bool shiny})> _game = {}; // boxSlot -> mon
  bool _loading = true;
  int _gameBox = 0, _vaultBox = 0;
  final Set<int> _gameSel = {}; // boxSlot values
  final Set<int> _vaultSel = {}; // vault indices

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    final mons = await state.readGen3Boxes(widget.game);
    final party = await state.readGen3Party(widget.game);
    if (!mounted) return;
    setState(() {
      _game = {
        for (final m in (mons ?? const []))
          m.boxSlot!: (dex: m.dex, shiny: m.shiny),
        // party at global slots 420..425 (shown as the "Party" box, index 14)
        for (final m in (party ?? const []))
          420 + (m.slot as int): (dex: m.dex, shiny: m.shiny),
      };
      _loading = false;
      final pcKeys = _game.keys.where((k) => k < 420);
      if (pcKeys.isNotEmpty) _gameBox = pcKeys.first ~/ _perBox;
    });
  }

  Future<void> _msg(Future<String> f) async {
    final messenger = ScaffoldMessenger.of(context);
    final m = await f;
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _gameToVault() async {
    if (_gameSel.isEmpty) return;
    await _msg(context
        .read<AppState>()
        .copyGameBoxesToVault(widget.game, _gameSel.toList()));
    if (mounted) setState(_gameSel.clear);
  }

  Future<void> _vaultToGame() async {
    if (_vaultSel.isEmpty) return;
    await _msg(context.read<AppState>().copyVaultMultiToGame(
        widget.game, _vaultSel.toList(),
        party: _gameBox == 14));
    if (mounted) {
      setState(_vaultSel.clear);
      await _load(); // refresh the game side after injecting
    }
  }

  @override
  Widget build(BuildContext context) {
    final vault = context.watch<AppState>().vault;
    _vaultSel.removeWhere((i) => i >= vault.length);
    final vaultBoxes = (vault.length / _perBox).ceil().clamp(1, 99);
    return Scaffold(
      appBar: AppBar(title: const Text('Boxes ⟷ Vault')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _panel(
                          title: widget.game.title,
                          box: _gameBox,
                          boxCount: 15, // 14 PC boxes + Party
                          partyBox: 14,
                          onBox: (b) => setState(() => _gameBox = b),
                          sel: _gameSel,
                          dataAt: (g) => _game[g],
                          onSel: (s) => setState(() {
                            _gameSel
                              ..clear()
                              ..addAll(s);
                          }),
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: _panel(
                          title: 'Vault',
                          box: _vaultBox,
                          boxCount: vaultBoxes,
                          onBox: (b) => setState(() => _vaultBox = b),
                          sel: _vaultSel,
                          dataAt: (g) => g < vault.length
                              ? (dex: vault[g].dex, shiny: vault[g].shiny)
                              : null,
                          onSel: (s) => setState(() {
                            _vaultSel
                              ..clear()
                              ..addAll(s);
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
                _actionBar(),
              ],
            ),
    );
  }

  Widget _actionBar() {
    return Material(
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _gameSel.isEmpty ? null : _gameToVault,
                icon: const Icon(Icons.arrow_forward),
                label: Text(_gameSel.isEmpty
                    ? 'Select in game → Vault'
                    : 'Copy ${_gameSel.length} → Vault'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: _vaultSel.isEmpty ? null : _vaultToGame,
                icon: const Icon(Icons.arrow_back),
                label: Text(_vaultSel.isEmpty
                    ? 'Select in Vault → game'
                    : 'Copy ${_vaultSel.length} → game'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _panel({
    required String title,
    required int box,
    required int boxCount,
    int? partyBox,
    required ValueChanged<int> onBox,
    required Set<int> sel,
    required ({int dex, bool shiny})? Function(int globalIndex) dataAt,
    required ValueChanged<Set<int>> onSel,
  }) {
    return Column(
      children: [
        Text(title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: box > 0 ? () => onBox(box - 1) : null,
            ),
            Text(box == partyBox ? 'Party' : 'Box ${box + 1}/$boxCount'),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: box < boxCount - 1 ? () => onBox(box + 1) : null,
            ),
          ],
        ),
        Expanded(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: _MarqueeGrid(
                columns: _cols,
                rows: _rows,
                boxOffset: box * _perBox,
                selection: sel,
                dataAt: dataAt,
                onSelection: onSel,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A fixed 6×5 grid of box cells with click-drag marquee selection. Selection
/// is by GLOBAL index (boxOffset + cell). Dragging replaces the selection with
/// the occupied cells the rubber-band touches; tapping toggles one.
class _MarqueeGrid extends StatefulWidget {
  final int columns, rows, boxOffset;
  final Set<int> selection;
  final ({int dex, bool shiny})? Function(int globalIndex) dataAt;
  final ValueChanged<Set<int>> onSelection;
  const _MarqueeGrid({
    required this.columns,
    required this.rows,
    required this.boxOffset,
    required this.selection,
    required this.dataAt,
    required this.onSelection,
  });
  @override
  State<_MarqueeGrid> createState() => _MarqueeGridState();
}

class _MarqueeGridState extends State<_MarqueeGrid> {
  Offset? _start, _cur;

  Rect? _marquee() => (_start == null || _cur == null)
      ? null
      : Rect.fromPoints(_start!, _cur!);

  void _apply(double cw, double ch) {
    final r = _marquee();
    if (r == null) return;
    final next = <int>{};
    final n = widget.columns * widget.rows;
    for (var i = 0; i < n; i++) {
      final cell = Rect.fromLTWH(
          (i % widget.columns) * cw, (i ~/ widget.columns) * ch, cw, ch);
      if (cell.overlaps(r) && widget.dataAt(widget.boxOffset + i) != null) {
        next.add(widget.boxOffset + i);
      }
    }
    widget.onSelection(next);
  }

  void _tap(Offset p, double cw, double ch) {
    final col = (p.dx / cw).floor(), row = (p.dy / ch).floor();
    if (col < 0 || col >= widget.columns || row < 0 || row >= widget.rows) {
      return;
    }
    final g = widget.boxOffset + row * widget.columns + col;
    if (widget.dataAt(g) == null) return;
    final s = {...widget.selection};
    s.contains(g) ? s.remove(g) : s.add(g);
    widget.onSelection(s);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, c) {
      final cw = c.maxWidth / widget.columns;
      final ch = cw;
      final gridH = ch * widget.rows;
      return GestureDetector(
        onPanStart: (d) {
          setState(() {
            _start = d.localPosition;
            _cur = d.localPosition;
          });
          widget.onSelection({});
        },
        onPanUpdate: (d) {
          setState(() => _cur = d.localPosition);
          _apply(cw, ch);
        },
        onPanEnd: (_) => setState(() {
          _start = null;
          _cur = null;
        }),
        onTapUp: (d) => _tap(d.localPosition, cw, ch),
        child: SizedBox(
          width: c.maxWidth,
          height: gridH,
          child: Stack(
            children: [
              for (var i = 0; i < widget.columns * widget.rows; i++)
                Positioned(
                  left: (i % widget.columns) * cw,
                  top: (i ~/ widget.columns) * ch,
                  width: cw,
                  height: ch,
                  child: _cell(widget.boxOffset + i),
                ),
              if (_marquee() != null)
                Positioned.fromRect(
                  rect: _marquee()!,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.15),
                        border: Border.all(color: Colors.blue, width: 1),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }

  Widget _cell(int g) {
    final d = widget.dataAt(g);
    final selected = widget.selection.contains(g);
    return Container(
      margin: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        color: selected
            ? Colors.blue.withValues(alpha: 0.30)
            : Colors.black.withValues(alpha: 0.05),
        border: Border.all(
            color: selected ? Colors.blue : Colors.black12,
            width: selected ? 2 : 1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: d == null
          ? const SizedBox.shrink()
          : CachedNetworkImage(
              imageUrl: _sprite(d.dex, d.shiny),
              fit: BoxFit.contain,
              errorWidget: (_, _, _) =>
                  const Icon(Icons.catching_pokemon, size: 16),
            ),
    );
  }
}

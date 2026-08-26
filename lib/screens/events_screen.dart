import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../data/events_catalog.dart';

/// Read-only reference of notable event / distribution Pokémon across the
/// generations. Data-only for now; the Gen 3 injector uses gen3_events.dart.
class EventsReferenceScreen extends StatelessWidget {
  const EventsReferenceScreen({super.key});

  static const _genLabel = {
    1: 'Gen 1 · Red/Blue/Yellow',
    2: 'Gen 2 · Gold/Silver/Crystal',
    3: 'Gen 3 · Ruby/Sapphire/Emerald/FR/LG',
    4: 'Gen 4 · Diamond/Pearl/Platinum/HG/SS',
    5: 'Gen 5 · Black/White · B2/W2',
    6: 'Gen 6 · X/Y · ORAS',
    7: 'Gen 7 · Sun/Moon · USUM · LGPE',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final gens = kEventCatalog.keys.toList()..sort();
    return Scaffold(
      appBar: AppBar(title: const Text('Event Pokémon')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 28),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Text(
              'Notable official distributions by generation. A reference for '
              'now — Gen 3 events can be injected from a game\'s Edit save.',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          ),
          for (final gen in gens)
            if ((kEventCatalog[gen] ?? const []).isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
                child: Text(_genLabel[gen] ?? 'Gen $gen',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                        color: scheme.primary)),
              ),
              for (final e in kEventCatalog[gen]!) _EventTile(e: e),
            ],
        ],
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  final EventMon e;
  const _EventTile({required this.e});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sprite =
        'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/${e.dex}.png';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 3, 12, 3),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.32),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 46,
              height: 46,
              child: CachedNetworkImage(
                imageUrl: sprite,
                fit: BoxFit.contain,
                errorWidget: (_, _, _) =>
                    const Icon(Icons.catching_pokemon, color: Colors.grey),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(e.name,
                            style: const TextStyle(
                                fontSize: 14.5, fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 6),
                      Text('Lv ${e.level > 0 ? e.level : '?'}',
                          style: TextStyle(
                              fontSize: 12, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                  const SizedBox(height: 1),
                  Wrap(
                    spacing: 6,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _pill(context, e.games),
                      if (e.ot.isNotEmpty)
                        Text('OT ${e.ot}',
                            style: TextStyle(
                                fontSize: 12, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                  if (e.note.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(e.note,
                          style: TextStyle(
                              fontSize: 12, color: scheme.onSurfaceVariant)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(BuildContext context, String text) {
    final c = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: c)),
    );
  }
}

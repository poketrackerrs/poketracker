import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/games_data.dart';
import '../models/achievement.dart';
import '../models/game.dart';
import '../state/app_state.dart';

/// The global (cross-game) achievements page, reached from the home app bar.
/// Shows meta achievements plus a per-game unlocked rollup.
class AchievementsScreen extends StatelessWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final global = state.globalAchievements();
    final unlocked = global.where((a) => a.unlocked).length;

    // Per-game rollup (only games with any progress shown first).
    final perGame = <(Game, int, int)>[];
    for (final g in kGames) {
      if (!state.hasProgress(g.id)) continue;
      final list = state.gameAchievements(g);
      final u = list.where((a) => a.unlocked).length;
      if (u > 0) perGame.add((g, u, list.length));
    }
    perGame.sort((a, b) => b.$2.compareTo(a.$2));

    return Scaffold(
      appBar: AppBar(title: const Text('Achievements')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _SummaryHeader(unlocked: unlocked, total: global.length),
          const _SectionLabel('Cross-game'),
          ...AchievementListView.grouped(global),
          if (perGame.isNotEmpty) ...[
            const _SectionLabel('By game'),
            for (final (g, u, t) in perGame)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: AchGroup.progression.color.withValues(alpha: 0.15),
                  child: Text('$u',
                      style: TextStyle(
                          color: AchGroup.progression.color,
                          fontWeight: FontWeight.w800)),
                ),
                title: Text(g.title),
                subtitle: Text('$u / $t unlocked'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => _GameAchievementsScreen(game: g))),
              ),
          ],
        ],
      ),
    );
  }
}

class _GameAchievementsScreen extends StatelessWidget {
  final Game game;
  const _GameAchievementsScreen({required this.game});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${game.title} · Achievements')),
      body: GameAchievementsView(game: game),
    );
  }
}

/// The per-game achievements list (also embedded as a tab in the game screen).
class GameAchievementsView extends StatelessWidget {
  final Game game;
  const GameAchievementsView({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final list = state.gameAchievements(game);
    final unlocked = list.where((a) => a.unlocked).length;
    final earnedPts = list
        .where((a) => a.unlocked)
        .fold(0, (a, s) => a + s.achievement.points);
    final totalPts =
        list.fold(0, (a, s) => a + s.achievement.points);
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _SummaryHeader(
            unlocked: unlocked,
            total: list.length,
            earnedPoints: earnedPts,
            totalPoints: totalPts),
        ...AchievementListView.grouped(
          list,
          onToggle: (s) => context.read<AppState>().toggleAchievement(
              game.id, s.achievement.id, !s.unlocked),
        ),
      ],
    );
  }
}

/// Builds a grouped list of achievement tiles (section headers per group).
class AchievementListView {
  static List<Widget> grouped(List<AchievementStatus> items,
      {void Function(AchievementStatus)? onToggle}) {
    final out = <Widget>[];
    for (final group in AchGroup.values) {
      final inGroup = items.where((s) => s.achievement.group == group).toList();
      if (inGroup.isEmpty) continue;
      // Unlocked first, then by descending progress.
      inGroup.sort((a, b) {
        if (a.unlocked != b.unlocked) return a.unlocked ? -1 : 1;
        return b.progress.compareTo(a.progress);
      });
      out.add(_SectionLabel(group.label));
      out.addAll(inGroup.map((s) => AchievementTile(
            status: s,
            onToggle:
                (s.manual && onToggle != null) ? () => onToggle(s) : null,
          )));
    }
    return out;
  }
}

class AchievementTile extends StatelessWidget {
  final AchievementStatus status;
  final VoidCallback? onToggle; // non-null for manual achievements
  const AchievementTile({super.key, required this.status, this.onToggle});

  @override
  Widget build(BuildContext context) {
    final a = status.achievement;
    final color = a.group.color;
    final unlocked = status.unlocked;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Opacity(
        opacity: unlocked ? 1 : 0.72,
        child: InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(14),
          child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: unlocked
                ? color.withValues(alpha: 0.10)
                : Theme.of(context).colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: unlocked ? color.withValues(alpha: 0.5) : Colors.transparent,
                width: 1.5),
          ),
          child: Row(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: unlocked
                        ? color
                        : Colors.grey.withValues(alpha: 0.35),
                    child: Icon(a.icon,
                        color: unlocked ? Colors.white : Colors.grey.shade400,
                        size: 22),
                  ),
                  if (!unlocked)
                    const Positioned(
                      right: 0,
                      bottom: 0,
                      child: CircleAvatar(
                        radius: 8,
                        backgroundColor: Colors.black54,
                        child: Icon(Icons.lock, size: 10, color: Colors.white),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(a.title,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 14)),
                        ),
                        if (a.points > 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text('${a.points}',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: color)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 1),
                    Text(a.description,
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).textTheme.bodySmall?.color)),
                    if (!unlocked && status.detail.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: status.progress,
                          minHeight: 5,
                          backgroundColor: Colors.grey.withValues(alpha: 0.25),
                          valueColor: AlwaysStoppedAnimation(color),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(status.detail,
                          style: const TextStyle(
                              fontSize: 10, color: Colors.grey)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (status.manual)
                Icon(
                    unlocked
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: unlocked ? color : Colors.grey,
                    size: 24)
              else if (unlocked)
                Icon(Icons.check_circle, color: color, size: 22)
              else
                const SizedBox(width: 22),
            ],
          ),
        ),
        ),
      ),
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  final int unlocked;
  final int total;
  final int earnedPoints;
  final int totalPoints;
  const _SummaryHeader(
      {required this.unlocked,
      required this.total,
      this.earnedPoints = 0,
      this.totalPoints = 0});

  @override
  Widget build(BuildContext context) {
    final frac = total == 0 ? 0.0 : unlocked / total;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          SizedBox(
            width: 54,
            height: 54,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: frac,
                  strokeWidth: 5,
                  backgroundColor: Colors.grey.withValues(alpha: 0.25),
                ),
                Icon(Icons.emoji_events,
                    color: AchGroup.progression.color, size: 22),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$unlocked / $total unlocked',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800)),
              Text(
                  totalPoints > 0
                      ? '${(frac * 100).round()}% · $earnedPoints / $totalPoints pts'
                      : '${(frac * 100).round()}% complete',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12,
                letterSpacing: 1.2,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
}

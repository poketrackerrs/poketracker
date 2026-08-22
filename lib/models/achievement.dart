import 'package:flutter/material.dart';

/// The category an achievement belongs to (drives grouping + section colors).
enum AchGroup { progression, collection, shiny, team, meta }

extension AchGroupInfo on AchGroup {
  String get label => switch (this) {
        AchGroup.progression => 'Progression',
        AchGroup.collection => 'Collection',
        AchGroup.shiny => 'Shiny',
        AchGroup.team => 'Team',
        AchGroup.meta => 'Cross-game',
      };

  IconData get icon => switch (this) {
        AchGroup.progression => Icons.emoji_events,
        AchGroup.collection => Icons.menu_book,
        AchGroup.shiny => Icons.auto_awesome,
        AchGroup.team => Icons.groups,
        AchGroup.meta => Icons.public,
      };

  Color get color => switch (this) {
        AchGroup.progression => const Color(0xFFEAB308),
        AchGroup.collection => const Color(0xFF3B82F6),
        AchGroup.shiny => const Color(0xFFEC4899),
        AchGroup.team => const Color(0xFF10B981),
        AchGroup.meta => const Color(0xFF8B5CF6),
      };
}

/// A single achievement's definition. Evaluation happens in AppState, which
/// produces an [AchievementStatus] pairing this with the user's progress.
class Achievement {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final AchGroup group;
  final int points; // RetroAchievements-style point value (0 = unweighted)
  const Achievement({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.group,
    this.points = 0,
  });
}

/// An achievement together with the user's current progress toward it.
class AchievementStatus {
  final Achievement achievement;
  final bool unlocked;

  /// 0..1 completion (1.0 when unlocked). For milestone (yes/no) achievements
  /// this is just 0 or 1.
  final double progress;

  /// Human-readable progress, e.g. "3 / 8" or "Lv 100". Empty for yes/no.
  final String detail;

  /// True if this achievement is unlocked by the user tapping it (the app can't
  /// detect it from a save), so the UI shows a check-off control.
  final bool manual;

  const AchievementStatus({
    required this.achievement,
    required this.unlocked,
    required this.progress,
    this.detail = '',
    this.manual = false,
  });
}

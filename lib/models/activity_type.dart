import 'package:flutter/material.dart';

enum ActivityType {
  hiit('HIIT', 'HIIT / Interval', Icons.local_fire_department, Color(0xFF0DF2A3)),
  strength('STRENGTH', 'Strength Training', Icons.fitness_center, Color(0xFFFF7A00)),
  functionalStrength('FUNCTIONAL_STRENGTH', 'Functional Strength', Icons.sports_gymnastics, Color(0xFFFF9500)),
  core('CORE', 'Core Training', Icons.accessibility_new, Color(0xFFFFD60A)),
  cardio('CARDIO', 'Mixed Cardio', Icons.directions_run, Color(0xFF38B6FF)),
  yoga('YOGA', 'Yoga', Icons.self_improvement, Color(0xFFBF5AF2)),
  pilates('PILATES', 'Pilates', Icons.sports_kabaddi, Color(0xFFFF2D55)),
  calisthenics('CALISTHENICS', 'Calisthenics', Icons.sports_handball, Color(0xFF5E5CE6)),
  other('OTHER', 'Other', Icons.more_horiz, Colors.grey);

  final String dbCode;
  final String label;
  final IconData icon;
  final Color color;

  const ActivityType(this.dbCode, this.label, this.icon, this.color);

  /// Whether this activity category tracks lifting weight & reps per round (tonnage)
  bool get isStrengthBased =>
      this == ActivityType.strength ||
      this == ActivityType.functionalStrength ||
      this == ActivityType.calisthenics;

  /// Helper to convert a stored DB string (e.g. 'HIIT', 'STRENGTH') into ActivityType
  static ActivityType fromString(String? code) {
    if (code == null || code.isEmpty) return ActivityType.hiit;
    return ActivityType.values.firstWhere(
      (e) => e.dbCode.toUpperCase() == code.toUpperCase() || e.name.toUpperCase() == code.toUpperCase(),
      orElse: () => ActivityType.other,
    );
  }

  /// List of all activity filter options (including 'All')
  static List<String> get filterOptions => [
        'All',
        ...ActivityType.values.map((e) => e.dbCode),
      ];
}

enum FocusMusicMode {
  auto('AUTO', 'Auto', 'Matches Activity', Icons.auto_awesome),
  focus('FOCUS', 'Focus', '120 BPM', Icons.graphic_eq),
  strength('STRENGTH', 'Strength', '100 BPM', Icons.fitness_center),
  running('RUNNING', 'Running', '160 BPM', Icons.directions_run),
  meditation('MEDITATION', 'Meditation', 'Unhurried', Icons.self_improvement),
  off('OFF', 'Off', 'Muted', Icons.music_off);

  final String dbCode;
  final String label;
  final String shortSubtitle;
  final IconData icon;

  const FocusMusicMode(this.dbCode, this.label, this.shortSubtitle, this.icon);

  String get code => dbCode;

  String get shortLabel => '$label ($shortSubtitle)';

  Color get color {
    switch (this) {
      case FocusMusicMode.auto:
        return const Color(0xFF00E5FF);
      case FocusMusicMode.focus:
        return const Color(0xFF00E676);
      case FocusMusicMode.strength:
        return const Color(0xFFFF6D00);
      case FocusMusicMode.running:
        return const Color(0xFFFF1744);
      case FocusMusicMode.meditation:
        return const Color(0xFFCE93D8);
      case FocusMusicMode.off:
        return Colors.grey;
    }
  }

  /// Relative asset path inside `assets/` for `AssetSource(...)`.
  String? get assetPath {
    switch (this) {
      case FocusMusicMode.focus:
        return 'music/focus.m4a';
      case FocusMusicMode.strength:
        return 'music/strength.m4a';
      case FocusMusicMode.running:
        return 'music/running.m4a';
      case FocusMusicMode.meditation:
        return 'music/meditation.m4a';
      case FocusMusicMode.auto:
      case FocusMusicMode.off:
        return null;
    }
  }

  /// Resolves `auto` into the concrete track for a given [activity] and [isTreadmill] flag.
  FocusMusicMode resolve({
    required ActivityType activity,
    bool isTreadmill = false,
  }) {
    if (this != FocusMusicMode.auto) return this;
    if (isTreadmill || activity == ActivityType.cardio) {
      return FocusMusicMode.running;
    }
    if (activity.isStrengthBased) {
      return FocusMusicMode.strength;
    }
    if (activity == ActivityType.yoga) {
      return FocusMusicMode.meditation;
    }
    return FocusMusicMode.focus;
  }

  /// Compact summary string for the TimerScreen music pill.
  String pillLabel({
    required ActivityType activity,
    bool isTreadmill = false,
  }) {
    if (this == FocusMusicMode.off) return 'Music: Off';
    final resolved = resolve(activity: activity, isTreadmill: isTreadmill);
    if (this == FocusMusicMode.auto) {
      return 'Auto · ${resolved.label} (${resolved.shortSubtitle})';
    }
    return '${resolved.label} · ${resolved.shortSubtitle}';
  }

  static FocusMusicMode fromString(String? code) {
    if (code == null || code.isEmpty) return FocusMusicMode.auto;
    return FocusMusicMode.values.firstWhere(
      (e) =>
          e.dbCode.toUpperCase() == code.toUpperCase() ||
          e.name.toUpperCase() == code.toUpperCase(),
      orElse: () => FocusMusicMode.auto,
    );
  }
}

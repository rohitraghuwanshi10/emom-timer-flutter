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

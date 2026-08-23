import 'package:flutter/material.dart';

class CalorieCalculator {
  CalorieCalculator._();

  /// Calculates calories burned using the Keytel formula (when HR is available) or MET formula fallback
  static double calculateCaloriesBurnt({
    required int avgHr,
    required double weightKg,
    required int totalTimeSec,
    String? birthDateStr,
    String? sex,
    double fallbackMet = 8.5,
  }) {
    if (totalTimeSec <= 0 || weightKg <= 0) return 0.0;
    final double totalMins = totalTimeSec / 60.0;
    double caloriesBurnt = 0.0;

    if (avgHr > 0) {
      final int age = _calculateAge(birthDateStr);
      final String resolvedSex = (sex != null && sex.toLowerCase().contains('female')) ? 'Female' : 'Male';

      double cpm;
      if (resolvedSex == 'Male') {
        cpm = (-55.0969 + (0.6309 * avgHr) + (0.1988 * weightKg) + (0.2017 * age)) / 4.184;
      } else {
        cpm = (-20.4022 + (0.4472 * avgHr) - (0.1263 * weightKg) + (0.074 * age)) / 4.184;
      }
      caloriesBurnt = cpm * totalMins;
    } else {
      // Fallback MET-based equation
      caloriesBurnt = fallbackMet * 3.5 * weightKg / 200 * totalMins;
    }

    if (caloriesBurnt < 0) caloriesBurnt = 0.0;
    return double.parse(caloriesBurnt.toStringAsFixed(2));
  }

  /// Calculates the heart rate zone name based on max HR percentage
  static String calculateZone(int bpm, int maxHr) {
    if (bpm <= 0 || maxHr <= 0) return '';
    final double pct = (bpm / maxHr) * 100;
    if (pct < 50) return 'WARM UP';
    if (pct < 60) return 'ZONE 1';
    if (pct < 70) return 'ZONE 2';
    if (pct < 80) return 'ZONE 3';
    if (pct < 90) return 'ZONE 4';
    return 'ZONE 5';
  }

  /// Returns the color associated with a heart rate zone
  static Color getZoneColor(String zone) {
    switch (zone) {
      case 'WARM UP':
        return Colors.grey;
      case 'ZONE 1':
        return const Color(0xFF38B6FF); // Blue
      case 'ZONE 2':
        return const Color(0xFF0DF2A3); // Green / Mint
      case 'ZONE 3':
        return const Color(0xFFFFD60A); // Yellow
      case 'ZONE 4':
        return const Color(0xFFFF7A00); // Orange
      case 'ZONE 5':
        return const Color(0xFFFF3B30); // Red
      default:
        return Colors.grey;
    }
  }

  static int _calculateAge(String? birthDateStr) {
    if (birthDateStr == null || birthDateStr.isEmpty) return 35;
    try {
      final birth = DateTime.parse(birthDateStr);
      final today = DateTime.now();
      int age = today.year - birth.year;
      if (today.month < birth.month || (today.month == birth.month && today.day < birth.day)) {
        age--;
      }
      return age.clamp(10, 120);
    } catch (_) {
      return 35;
    }
  }
}

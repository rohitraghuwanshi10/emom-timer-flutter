import 'package:flutter_test/flutter_test.dart';
import 'package:emom_timer_flutter/utils/calorie_calculator.dart';

void main() {
  group('CalorieCalculator Tests', () {
    test('calculateCaloriesBurnt with HR uses Keytel formula', () {
      final maleCalories = CalorieCalculator.calculateCaloriesBurnt(
        avgHr: 150,
        weightKg: 75.0,
        totalTimeSec: 1800, // 30 mins
        birthDateStr: '1990-01-01',
        sex: 'Male',
      );
      expect(maleCalories, greaterThan(200.0));
      expect(maleCalories, lessThan(600.0));

      final femaleCalories = CalorieCalculator.calculateCaloriesBurnt(
        avgHr: 150,
        weightKg: 60.0,
        totalTimeSec: 1800,
        birthDateStr: '1995-01-01',
        sex: 'Female',
      );
      expect(femaleCalories, greaterThan(150.0));
      expect(femaleCalories, lessThan(500.0));
    });

    test('calculateCaloriesBurnt without HR falls back to MET', () {
      final metCalories = CalorieCalculator.calculateCaloriesBurnt(
        avgHr: 0,
        weightKg: 70.0,
        totalTimeSec: 1200, // 20 mins
      );
      expect(metCalories, greaterThan(50.0));
    });

    test('calculateZone maps heart rate zones properly', () {
      const int maxHr = 180;
      expect(CalorieCalculator.calculateZone(80, maxHr), equals('WARM UP'));  // 44.4%
      expect(CalorieCalculator.calculateZone(100, maxHr), equals('ZONE 1')); // 55.5%
      expect(CalorieCalculator.calculateZone(115, maxHr), equals('ZONE 2')); // 63.8%
      expect(CalorieCalculator.calculateZone(135, maxHr), equals('ZONE 3')); // 75.0%
      expect(CalorieCalculator.calculateZone(155, maxHr), equals('ZONE 4')); // 86.1%
      expect(CalorieCalculator.calculateZone(170, maxHr), equals('ZONE 5')); // 94.4%
      expect(CalorieCalculator.calculateZone(0, maxHr), equals(''));
    });
  });
}

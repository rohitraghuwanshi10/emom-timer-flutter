import 'package:flutter_test/flutter_test.dart';
import 'package:emom_timer_flutter/models/activity_type.dart';

void main() {
  group('ActivityType Tests', () {
    test('fromString parses correctly', () {
      expect(ActivityType.fromString('HIIT'), equals(ActivityType.hiit));
      expect(ActivityType.fromString('STRENGTH'), equals(ActivityType.strength));
      expect(ActivityType.fromString('FUNCTIONAL_STRENGTH'), equals(ActivityType.functionalStrength));
      expect(ActivityType.fromString('yoga'), equals(ActivityType.yoga));
      expect(ActivityType.fromString(null), equals(ActivityType.hiit));
      expect(ActivityType.fromString('UNKNOWN_XYZ'), equals(ActivityType.other));
    });

    test('isStrengthBased identifies strength training categories', () {
      expect(ActivityType.strength.isStrengthBased, isTrue);
      expect(ActivityType.functionalStrength.isStrengthBased, isTrue);
      expect(ActivityType.calisthenics.isStrengthBased, isTrue);
      expect(ActivityType.hiit.isStrengthBased, isFalse);
      expect(ActivityType.cardio.isStrengthBased, isFalse);
      expect(ActivityType.yoga.isStrengthBased, isFalse);
    });

    test('filterOptions contains All and all db codes', () {
      final options = ActivityType.filterOptions;
      expect(options.first, equals('All'));
      expect(options, contains('HIIT'));
      expect(options, contains('STRENGTH'));
      expect(options, contains('CALISTHENICS'));
    });
  });
}

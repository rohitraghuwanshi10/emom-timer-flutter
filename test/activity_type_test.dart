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

  group('FocusMusicMode Tests', () {
    test('fromString parses codes and defaults to auto', () {
      expect(FocusMusicMode.fromString('AUTO'), equals(FocusMusicMode.auto));
      expect(FocusMusicMode.fromString('FOCUS'), equals(FocusMusicMode.focus));
      expect(FocusMusicMode.fromString('STRENGTH'), equals(FocusMusicMode.strength));
      expect(FocusMusicMode.fromString('RUNNING'), equals(FocusMusicMode.running));
      expect(FocusMusicMode.fromString('MEDITATION'), equals(FocusMusicMode.meditation));
      expect(FocusMusicMode.fromString('OFF'), equals(FocusMusicMode.off));
      expect(FocusMusicMode.fromString(null), equals(FocusMusicMode.auto));
      expect(FocusMusicMode.fromString('invalid'), equals(FocusMusicMode.auto));
    });

    test('resolve maps AUTO to appropriate concrete track based on ActivityType and treadmill flag', () {
      // Treadmill overrides activity type to Running
      expect(
        FocusMusicMode.auto.resolve(activity: ActivityType.hiit, isTreadmill: true),
        equals(FocusMusicMode.running),
      );

      // Cardio -> Running
      expect(
        FocusMusicMode.auto.resolve(activity: ActivityType.cardio),
        equals(FocusMusicMode.running),
      );

      // Strength, Functional Strength, Calisthenics -> Strength
      expect(
        FocusMusicMode.auto.resolve(activity: ActivityType.strength),
        equals(FocusMusicMode.strength),
      );
      expect(
        FocusMusicMode.auto.resolve(activity: ActivityType.functionalStrength),
        equals(FocusMusicMode.strength),
      );
      expect(
        FocusMusicMode.auto.resolve(activity: ActivityType.calisthenics),
        equals(FocusMusicMode.strength),
      );

      // Yoga -> Meditation
      expect(
        FocusMusicMode.auto.resolve(activity: ActivityType.yoga),
        equals(FocusMusicMode.meditation),
      );

      // HIIT, Core, Pilates, Other -> Focus
      expect(
        FocusMusicMode.auto.resolve(activity: ActivityType.hiit),
        equals(FocusMusicMode.focus),
      );
      expect(
        FocusMusicMode.auto.resolve(activity: ActivityType.core),
        equals(FocusMusicMode.focus),
      );
      expect(
        FocusMusicMode.auto.resolve(activity: ActivityType.pilates),
        equals(FocusMusicMode.focus),
      );
      expect(
        FocusMusicMode.auto.resolve(activity: ActivityType.other),
        equals(FocusMusicMode.focus),
      );
    });

    test('explicit modes resolve to themselves and provide valid assetPath', () {
      expect(
        FocusMusicMode.strength.resolve(activity: ActivityType.hiit, isTreadmill: true),
        equals(FocusMusicMode.strength),
      );
      expect(
        FocusMusicMode.off.resolve(activity: ActivityType.strength),
        equals(FocusMusicMode.off),
      );

      expect(FocusMusicMode.focus.assetPath, equals('music/focus.m4a'));
      expect(FocusMusicMode.strength.assetPath, equals('music/strength.m4a'));
      expect(FocusMusicMode.running.assetPath, equals('music/running.m4a'));
      expect(FocusMusicMode.meditation.assetPath, equals('music/meditation.m4a'));
      expect(FocusMusicMode.auto.assetPath, isNull);
      expect(FocusMusicMode.off.assetPath, isNull);
    });
  });
}

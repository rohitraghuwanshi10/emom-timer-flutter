import 'package:flutter_test/flutter_test.dart';
import 'package:emom_timer_flutter/utils/format_utils.dart';

void main() {
  group('FormatUtils Tests', () {
    test('formatDuration formats seconds to MM:SS correctly', () {
      expect(FormatUtils.formatDuration(0), equals('00:00'));
      expect(FormatUtils.formatDuration(5), equals('00:05'));
      expect(FormatUtils.formatDuration(65), equals('01:05'));
      expect(FormatUtils.formatDuration(600), equals('10:00'));
      expect(FormatUtils.formatDuration(3665), equals('61:05'));
    });

    test('formatDurationConcise formats readable strings', () {
      expect(FormatUtils.formatDurationConcise(0), equals('None'));
      expect(FormatUtils.formatDurationConcise(0, zeroText: '0s'), equals('0s'));
      expect(FormatUtils.formatDurationConcise(45), equals('45s'));
      expect(FormatUtils.formatDurationConcise(60), equals('1m'));
      expect(FormatUtils.formatDurationConcise(150), equals('2m 30s'));
    });

    test('formatSpeed handles metric and imperial preferences', () {
      expect(FormatUtils.formatSpeed(10.0, isMetric: true), equals('10.0 km/h'));
      expect(FormatUtils.formatSpeed(10.0, isMetric: false), equals('6.2 mph'));
    });

    test('formatDistance handles metric and imperial preferences', () {
      expect(FormatUtils.formatDistance(5.0, isMetric: true), equals('5.00 km'));
      expect(FormatUtils.formatDistance(5.0, isMetric: false), equals('3.11 mi'));
    });

    test('formatWeight handles units', () {
      expect(FormatUtils.formatWeight(20.0, 'kg'), equals('20.0 kg'));
      expect(FormatUtils.formatWeight(0, 'lbs'), equals('0 lbs'));
    });

    test('calculateAge calculates age correctly from birthdate string', () {
      expect(FormatUtils.calculateAge(null), equals(35));
      expect(FormatUtils.calculateAge(''), equals(35));
      expect(FormatUtils.calculateAge('2000-01-01') > 20, isTrue);
    });
  });
}

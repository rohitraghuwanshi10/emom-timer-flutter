import 'package:flutter_test/flutter_test.dart';
import 'package:emom_timer_flutter/services/hrr_service.dart';

void main() {
  group('HrrService.computeDrop', () {
    test('baseline minus reading', () {
      expect(HrrService.computeDrop(170, 140), 30);
    });
    test('never negative', () {
      expect(HrrService.computeDrop(120, 125), 0);
    });
    test('null when there is no valid reading', () {
      expect(HrrService.computeDrop(170, null), isNull);
      expect(HrrService.computeDrop(170, 0), isNull);
      expect(HrrService.computeDrop(0, 140), isNull);
    });
  });

  group('HrrService HR freshness and baseline', () {
    late DateTime now;
    final hrr = HrrService.instance;

    setUp(() {
      now = DateTime(2026, 11, 18, 19, 0, 0);
      hrr.clockOverride = () => now;
    });

    tearDown(() {
      hrr.stopRecovery(finalize: false);
    });

    test('a sample is fresh for 5 s, then stale', () {
      hrr.addSampleForTest(150);
      expect(hrr.hasFreshHr, isTrue);
      now = now.add(const Duration(seconds: 5));
      expect(hrr.hasFreshHr, isTrue);
      now = now.add(const Duration(seconds: 1));
      expect(hrr.hasFreshHr, isFalse);
    });

    test('baseline is HR at exercise stop, not the workout max', () {
      hrr.addSampleForTest(162);
      hrr.startRecovery(workoutId: 1, peakHr: 181);
      expect(hrr.state.peakHr, 162);
    });

    test('falls back to the workout max when there is no live reading', () {
      hrr.addSampleForTest(162);
      now = now.add(const Duration(seconds: 30));
      hrr.startRecovery(workoutId: 1, peakHr: 181);
      expect(hrr.state.peakHr, 181);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:emom_timer_flutter/models/workout_engine.dart';

void main() {
  group('WorkoutEngine Basic Flow Tests', () {
    test('Standard workout without auto-regulation runs and finishes', () async {
      final engine = WorkoutEngine(
        totalRounds: 2,
        workDuration: 1,
        baseRestDuration: 1,
        prepDuration: 1,
        autoRegulationEnabled: false,
      );

      final events = <WorkoutEvent>[];
      final subscription = engine.workoutStream.listen((event) {
        events.add(event);
      });

      engine.start();

      // Let the engine tick. With prep=1, work=1, rest=1, 2 rounds:
      // Tick 1: PREP (remaining 1) -> transitions to WORK (remaining 1)
      // Tick 2: WORK (remaining 1) -> transitions to REST (remaining 1)
      // Tick 3: REST (remaining 1) -> transitions to WORK round 2 (remaining 1)
      // Tick 4: WORK round 2 (remaining 1) -> transitions to REST round 2 (remaining 1)
      // Tick 5: REST round 2 (remaining 1) -> transitions to FINISHED
      await Future.delayed(const Duration(milliseconds: 5500));
      engine.dispose();
      await subscription.cancel();

      // Verify that states were transitioned through properly
      final states = events.map((e) => e.state).toList();
      expect(states, contains(WorkoutState.PREP));
      expect(states, contains(WorkoutState.WORK));
      expect(states, contains(WorkoutState.REST));
      expect(states.last, equals(WorkoutState.FINISHED));
    });
  });

  group('WorkoutEngine Auto-Regulation Tests', () {
    test('Holds rest phase if heart rate is above threshold', () async {
      final engine = WorkoutEngine(
        totalRounds: 1,
        workDuration: 1,
        baseRestDuration: 2,
        prepDuration: 1,
        autoRegulationEnabled: true,
        maxPreworkHr: 120,
      );

      final events = <WorkoutEvent>[];
      final subscription = engine.workoutStream.listen((event) {
        events.add(event);
      });

      engine.start();

      // Feed high heart rate immediately
      engine.updateHeartRate(140);

      // Wait 4 seconds (enough time for prep, work, and rest to get to the end)
      // The rest is 2 seconds, so it will count down: 2 -> 1.
      // At 1, it should check if HR > 120 (it is, 140), and trigger hold (isWaitingForHr = true).
      await Future.delayed(const Duration(milliseconds: 4500));

      // Verify it is holding in REST state and waiting for HR
      final restEvents = events.where((e) => e.state == WorkoutState.REST).toList();
      expect(restEvents, isNotEmpty);
      expect(restEvents.last.isWaitingForHr, isTrue);
      expect(events.last.state, equals(WorkoutState.REST)); // Still in rest!

      // Now drop the heart rate
      engine.updateHeartRate(110);

      // Wait 1.5 seconds to let the next tick trigger transition to finished
      await Future.delayed(const Duration(milliseconds: 1500));
      engine.dispose();
      await subscription.cancel();

      // Now it should have transitioned to FINISHED
      expect(events.last.state, equals(WorkoutState.FINISHED));
    });

    test('Does not hold rest phase if heart rate is below threshold', () async {
      final engine = WorkoutEngine(
        totalRounds: 1,
        workDuration: 1,
        baseRestDuration: 2,
        prepDuration: 1,
        autoRegulationEnabled: true,
        maxPreworkHr: 120,
      );

      final events = <WorkoutEvent>[];
      final subscription = engine.workoutStream.listen((event) {
        events.add(event);
      });

      engine.start();
      engine.updateHeartRate(110); // below threshold

      // Wait 4.5 seconds to let it finish naturally
      await Future.delayed(const Duration(milliseconds: 4500));
      engine.dispose();
      await subscription.cancel();

      // It should have finished without holding
      expect(events.last.state, equals(WorkoutState.FINISHED));
      final waitingEvents = events.where((e) => e.isWaitingForHr);
      expect(waitingEvents, isEmpty);
    });
  });

  group('WorkoutEngine Continuous Mode Tests', () {
    test('Continuous workout mode keeps running past the total rounds limit', () async {
      final engine = WorkoutEngine(
        totalRounds: 2,
        workDuration: 1,
        baseRestDuration: 1,
        prepDuration: 1,
        continuousMode: true,
      );

      final events = <WorkoutEvent>[];
      final subscription = engine.workoutStream.listen((event) {
        events.add(event);
      });

      engine.start();

      // Tick 1: PREP (remaining 1) -> transitions to WORK (remaining 1)
      // Tick 2: WORK (remaining 1) -> transitions to REST (remaining 1)
      // Tick 3: REST (remaining 1) -> transitions to WORK round 2 (remaining 1)
      // Tick 4: WORK round 2 (remaining 1) -> transitions to REST round 2 (remaining 1)
      // Tick 5: REST round 2 (remaining 1) -> transitions to WORK round 3 (remaining 1) instead of FINISHED!
      await Future.delayed(const Duration(milliseconds: 5500));
      
      // Stop it manually
      engine.stop();
      
      await Future.delayed(const Duration(milliseconds: 500));
      engine.dispose();
      await subscription.cancel();

      // Verify that states were transitioned through properly and exceeded round limit
      final states = events.map((e) => e.state).toList();
      final rounds = events.map((e) => e.currentRound).toList();
      
      expect(states, contains(WorkoutState.PREP));
      expect(states, contains(WorkoutState.WORK));
      expect(states, contains(WorkoutState.REST));
      
      expect(rounds, contains(3));
      expect(states.last, equals(WorkoutState.FINISHED));
    });
  });
}

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'database_helper.dart';
import 'sync_service.dart';
import 'bluetooth_service.dart';
import 'watch_connectivity_service.dart';

class HrrState {
  final bool isTracking;
  final int secondsRemaining;
  final int? workoutId;
  final int peakHr;
  final int? hr1min;
  final int currentHr;

  const HrrState({
    this.isTracking = false,
    this.secondsRemaining = 120,
    this.workoutId,
    this.peakHr = 0,
    this.hr1min,
    this.currentHr = 0,
  });

  HrrState copyWith({
    bool? isTracking,
    int? secondsRemaining,
    int? workoutId,
    int? peakHr,
    int? hr1min,
    int? currentHr,
  }) {
    return HrrState(
      isTracking: isTracking ?? this.isTracking,
      secondsRemaining: secondsRemaining ?? this.secondsRemaining,
      workoutId: workoutId ?? this.workoutId,
      peakHr: peakHr ?? this.peakHr,
      hr1min: hr1min ?? this.hr1min,
      currentHr: currentHr ?? this.currentHr,
    );
  }
}

class HrrService {
  static final HrrService instance = HrrService._init();
  HrrService._init();

  final ValueNotifier<HrrState> stateNotifier = ValueNotifier<HrrState>(const HrrState());
  HrrState get state => stateNotifier.value;

  Timer? _timer;
  StreamSubscription<int>? _bleHrSub;
  StreamSubscription<int>? _watchHrSub;
  int _lastHrSample = 0;

  void init() {
    _bleHrSub?.cancel();
    _watchHrSub?.cancel();

    _bleHrSub = AppBluetoothService.instance.heartRateStream.listen(_onHeartRateSample);
    _watchHrSub = WatchConnectivityService.instance.heartRateStream.listen(_onHeartRateSample);
  }

  void _onHeartRateSample(int hr) {
    if (hr <= 0) return;
    _lastHrSample = hr;
    
    if (state.isTracking && state.workoutId != null) {
      stateNotifier.value = state.copyWith(currentHr: hr);
    }
  }

  String _calculateZone(int hr) {
    if (hr >= 170) return 'ZONE 5';
    if (hr >= 150) return 'ZONE 4';
    if (hr >= 130) return 'ZONE 3';
    if (hr >= 110) return 'ZONE 2';
    return 'ZONE 1';
  }

  void startRecovery({required int workoutId, required int peakHr}) {
    stopRecovery(finalize: true);

    final initialPeak = peakHr > 0 ? peakHr : _lastHrSample;
    stateNotifier.value = HrrState(
      isTracking: true,
      secondsRemaining: 120,
      workoutId: workoutId,
      peakHr: initialPeak,
      hr1min: null,
      currentHr: _lastHrSample,
    );

    debugPrint('HrrService: Started post-workout HR recovery tracking for workout $workoutId (Peak HR: $initialPeak)');

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!state.isTracking || state.workoutId == null) {
        timer.cancel();
        return;
      }

      final newRemaining = state.secondsRemaining > 0 ? state.secondsRemaining - 1 : 0;
      final elapsed = 120 - newRemaining;

      // Record a 1-second HR log tick for smooth recovery curve matching active workout density
      if (_lastHrSample > 0) {
        final zoneStr = _calculateZone(_lastHrSample);
        DatabaseHelper.instance.insertHeartRateLog(
          workoutId: state.workoutId!,
          captureTime: DateTime.now().toIso8601String().substring(0, 19),
          bpm: _lastHrSample,
          zone: zoneStr,
          isRecovery: 1,
        );
      }

      int? updatedHr1m = state.hr1min;
      if (elapsed == 60 && _lastHrSample > 0 && updatedHr1m == null) {
        updatedHr1m = _lastHrSample;
        final drop1 = state.peakHr - updatedHr1m;
        DatabaseHelper.instance.updateWorkoutHRR(
          workoutId: state.workoutId!,
          hrr1min: drop1 > 0 ? drop1 : 0,
          recoveryDurationSec: 60,
        );
      }

      stateNotifier.value = state.copyWith(
        secondsRemaining: newRemaining,
        hr1min: updatedHr1m,
      );

      if (newRemaining <= 0) {
        finalizeRecovery();
      }
    });
  }

  Future<void> finalizeRecovery() async {
    if (!state.isTracking || state.workoutId == null) return;

    final elapsed = 120 - state.secondsRemaining;
    int? drop1;
    int? drop2;

    if (elapsed >= 60) {
      final hr1m = state.hr1min ?? (_lastHrSample > 0 ? _lastHrSample : null);
      if (hr1m != null) {
        drop1 = state.peakHr - hr1m;
        if (drop1 < 0) drop1 = 0;
      }
    }

    if (elapsed >= 120 && _lastHrSample > 0) {
      drop2 = state.peakHr - _lastHrSample;
      if (drop2 < 0) drop2 = 0;
    }

    await DatabaseHelper.instance.updateWorkoutHRR(
      workoutId: state.workoutId!,
      hrr1min: drop1,
      hrr2min: drop2,
      recoveryDurationSec: elapsed,
    );

    try {
      SyncService.instance.signInAndSync();
    } catch (e) {
      debugPrint('HrrService: SyncService skipped in unit test mode: $e');
    }
    stopRecovery(finalize: false);
  }

  void stopRecovery({bool finalize = true}) {
    if (finalize && state.isTracking) {
      finalizeRecovery();
      return;
    }
    _timer?.cancel();
    _timer = null;
    stateNotifier.value = const HrrState(
      isTracking: false,
      secondsRemaining: 120,
      workoutId: null,
      peakHr: 0,
      hr1min: null,
      currentHr: 0,
    );
  }

  void dispose() {
    stopRecovery(finalize: false);
    _bleHrSub?.cancel();
    _watchHrSub?.cancel();
  }
}

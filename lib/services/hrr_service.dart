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
  DateTime? _lastHrAt;
  DateTime Function() _now = DateTime.now;

  /// A sample older than this is treated as "no signal" (e.g. the strap or
  /// Watch stopped streaming) instead of being repeated as if it were live.
  static const Duration staleAfter = Duration(seconds: 5);

  @visibleForTesting
  set clockOverride(DateTime Function() now) => _now = now;

  @visibleForTesting
  void addSampleForTest(int hr) => _onHeartRateSample(hr);

  @visibleForTesting
  bool get hasFreshHr => _hrFresh;

  bool get _hrFresh =>
      _lastHrSample > 0 &&
      _lastHrAt != null &&
      _now().difference(_lastHrAt!) <= staleAfter;

  /// HRR drop in bpm; null when there is no valid reading.
  @visibleForTesting
  static int? computeDrop(int baseline, int? hr) {
    if (hr == null || hr <= 0 || baseline <= 0) return null;
    final drop = baseline - hr;
    return drop > 0 ? drop : 0;
  }

  void init() {
    _bleHrSub?.cancel();
    _watchHrSub?.cancel();

    _bleHrSub = AppBluetoothService.instance.heartRateStream.listen(_onHeartRateSample);
    _watchHrSub = WatchConnectivityService.instance.heartRateStream.listen(_onHeartRateSample);
  }

  void _onHeartRateSample(int hr) {
    if (hr <= 0) return;
    _lastHrSample = hr;
    _lastHrAt = _now();
    
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

    // HRR baseline = HR when exercise stops (clinical definition). Fall back to
    // the workout max only if there is no live reading at that moment.
    final initialPeak = _hrFresh ? _lastHrSample : peakHr;
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
      if (_hrFresh) {
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
      // Take the 1-minute reading at 60 s, or within 5 s after if the signal
      // briefly dropped exactly then.
      if (elapsed >= 60 && elapsed <= 65 && _hrFresh && updatedHr1m == null) {
        updatedHr1m = _lastHrSample;
        DatabaseHelper.instance.updateWorkoutHRR(
          workoutId: state.workoutId!,
          hrr1min: computeDrop(state.peakHr, updatedHr1m),
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
      drop1 = computeDrop(state.peakHr, state.hr1min);
    }

    if (elapsed >= 120 && _hrFresh) {
      drop2 = computeDrop(state.peakHr, _lastHrSample);
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

// ignore_for_file: constant_identifier_names
import 'dart:async';

enum WorkoutState { IDLE, PREP, WORK, REST, PAUSED, FINISHED }

class WorkoutEvent {
  final WorkoutState state;
  final WorkoutState? prevState;
  final int timeRemaining;
  final int currentRound;
  final int totalRounds;
  final bool isWaitingForHr;

  WorkoutEvent({
    required this.state,
    this.prevState,
    required this.timeRemaining,
    required this.currentRound,
    required this.totalRounds,
    required this.isWaitingForHr,
  });
}

class WorkoutEngine {
  final int totalRounds;
  final int workDuration;
  final int baseRestDuration;
  final int prepDuration;
  
  // Auto-regulation settings
  final bool autoRegulationEnabled;
  final int? maxPreworkHr;

  // State
  WorkoutState _state = WorkoutState.IDLE;
  WorkoutState? _prevState;
  int _currentRound = 1;
  int _timeRemaining = 0;
  bool _isWaitingForHr = false;
  int _currentHr = 0;
  
  // Elapsed metrics
  int totalTimeSec = 0;
  int workTimeSec = 0;
  int restTimeSec = 0;

  Timer? _timer;
  final _stateController = StreamController<WorkoutEvent>.broadcast();
  Stream<WorkoutEvent> get workoutStream => _stateController.stream;

  WorkoutEngine({
    required this.totalRounds,
    required this.workDuration,
    required this.baseRestDuration,
    this.autoRegulationEnabled = false,
    this.maxPreworkHr,
    this.prepDuration = 10,
  });

  void start() {
    if (_state != WorkoutState.IDLE) return;
    
    _state = WorkoutState.PREP;
    _timeRemaining = prepDuration;
    _broadcast();

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _tick();
    });
  }

  void pause() {
    if (_state == WorkoutState.FINISHED || _state == WorkoutState.IDLE) return;
    
    if (_state == WorkoutState.PAUSED) {
      // Resume
      if (_prevState != null) {
        _state = _prevState!;
        _prevState = null;
        _broadcast();
      }
    } else {
      _prevState = _state;
      _state = WorkoutState.PAUSED;
      _broadcast();
    }
  }
  
  void stop() {
    _timer?.cancel();
    _state = WorkoutState.FINISHED;
    _broadcast();
  }

  void _tick() {
    if (_state == WorkoutState.FINISHED || _state == WorkoutState.PAUSED) return;

    totalTimeSec++;
    if (_state == WorkoutState.WORK) workTimeSec++;
    if (_state == WorkoutState.REST) restTimeSec++;

    if (_timeRemaining > 1) {
      _timeRemaining--;
      
      // Auto-regulation: check near end of rest
      if (_state == WorkoutState.REST && _timeRemaining == 1) {
        if (autoRegulationEnabled && maxPreworkHr != null && _currentHr > 0) {
          if (_currentHr > maxPreworkHr!) {
            _isWaitingForHr = true;
            // Hold the timer at 1 second until HR drops
            _timeRemaining = 2; // will decrement back to 1 next tick
          } else {
            _isWaitingForHr = false;
          }
        }
      }
      
      _broadcast();
    } else {
      _handleTransition();
    }
  }

  void _handleTransition() {
    _isWaitingForHr = false;
    
    switch (_state) {
      case WorkoutState.PREP:
        _state = WorkoutState.WORK;
        _timeRemaining = workDuration;
        break;
      case WorkoutState.WORK:
        if (baseRestDuration <= 0) {
          if (_currentRound >= totalRounds) {
            _state = WorkoutState.FINISHED;
            _timeRemaining = 0;
            _timer?.cancel();
          } else {
            _currentRound++;
            _state = WorkoutState.WORK;
            _timeRemaining = workDuration;
          }
        } else {
          _state = WorkoutState.REST;
          _timeRemaining = baseRestDuration;
        }
        break;
      case WorkoutState.REST:
        if (_currentRound >= totalRounds) {
          _state = WorkoutState.FINISHED;
          _timeRemaining = 0;
          _timer?.cancel();
        } else {
          _currentRound++;
          _state = WorkoutState.WORK;
          _timeRemaining = workDuration;
        }
        break;
      default:
        break;
    }
    _broadcast();
  }

  void _broadcast() {
    _stateController.add(WorkoutEvent(
      state: _state,
      prevState: _prevState,
      timeRemaining: _timeRemaining,
      currentRound: _currentRound,
      totalRounds: totalRounds,
      isWaitingForHr: _isWaitingForHr,
    ));
  }
  
  // Used by the Bluetooth service to feed HR directly into the engine's tick loop
  void updateHeartRate(int hr) {
    _currentHr = hr;
    if (_isWaitingForHr && hr <= (maxPreworkHr ?? 999)) {
      _isWaitingForHr = false;
      _timeRemaining = 1; // allows it to transition immediately next tick
    }
  }

  void dispose() {
    _timer?.cancel();
    _stateController.close();
  }
}

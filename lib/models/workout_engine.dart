import 'dart:async';

enum WorkoutState { IDLE, PREP, WORK, REST, PAUSED, FINISHED }

class WorkoutEvent {
  final WorkoutState state;
  final int timeRemaining;
  final int currentRound;
  final int totalRounds;
  final bool isWaitingForHr;

  WorkoutEvent({
    required this.state,
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
  
  // Auto-regulation settings
  final bool autoRegulationEnabled;
  final int? maxPreworkHr;

  // State
  WorkoutState _state = WorkoutState.IDLE;
  int _currentRound = 1;
  int _timeRemaining = 0;
  bool _isWaitingForHr = false;
  
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
  });

  void start() {
    if (_state != WorkoutState.IDLE) return;
    
    _state = WorkoutState.PREP;
    _timeRemaining = 10; // 10 seconds prep
    _broadcast();

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _tick();
    });
  }

  void pause() {
    if (_state == WorkoutState.FINISHED || _state == WorkoutState.IDLE) return;
    
    if (_state == WorkoutState.PAUSED) {
      // Resume
      // We would need to know the previous state, but for simplicity let's assume 
      // the UI handles pause/resume logic or we store _prevState.
      // A more robust implementation will track the previous state.
    } else {
      _state = WorkoutState.PAUSED;
      _broadcast();
    }
  }
  
  void stop() {
    _timer?.cancel();
    _state = WorkoutState.FINISHED;
    _broadcast();
  }

  void _tick({int? currentHr}) {
    if (_state == WorkoutState.FINISHED || _state == WorkoutState.PAUSED) return;

    totalTimeSec++;
    if (_state == WorkoutState.WORK) workTimeSec++;
    if (_state == WorkoutState.REST) restTimeSec++;

    if (_timeRemaining > 1) {
      _timeRemaining--;
      
      // Auto-regulation: check near end of rest
      if (_state == WorkoutState.REST && _timeRemaining == 1) {
        if (autoRegulationEnabled && maxPreworkHr != null && currentHr != null) {
          if (currentHr > maxPreworkHr!) {
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
        if (_currentRound >= totalRounds) {
          _state = WorkoutState.FINISHED;
          _timeRemaining = 0;
          _timer?.cancel();
        } else {
          _state = WorkoutState.REST;
          _timeRemaining = baseRestDuration;
        }
        break;
      case WorkoutState.REST:
        _currentRound++;
        _state = WorkoutState.WORK;
        _timeRemaining = workDuration;
        break;
      default:
        break;
    }
    _broadcast();
  }

  void _broadcast() {
    _stateController.add(WorkoutEvent(
      state: _state,
      timeRemaining: _timeRemaining,
      currentRound: _currentRound,
      totalRounds: totalRounds,
      isWaitingForHr: _isWaitingForHr,
    ));
  }
  
  // Used by the Bluetooth service to feed HR directly into the engine's tick loop
  void updateHeartRate(int hr) {
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

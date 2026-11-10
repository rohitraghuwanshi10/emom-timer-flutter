import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import '../models/activity_type.dart';
import '../models/workout_engine.dart';
import 'hrr_service.dart';

class AudioService {
  static final AudioService instance = AudioService._init();
  late final AudioPlayer _workPlayer;
  late final AudioPlayer _restPlayer;
  late final AudioPlayer _tickPlayer;
  late final AudioPlayer _musicPlayer;

  double _musicVolume = 0.70;
  bool _musicMuted = false;
  double _phaseMultiplier = 0.0;
  double _currentAppliedVolume = 0.0;
  bool _isChimeDucking = false;
  bool _isMusicPlaying = false;
  bool _isHrrMusicActive = false;
  FocusMusicMode _lastSelectedMode = FocusMusicMode.auto;
  FocusMusicMode? _loadedTrack;
  WorkoutState _lastWorkoutState = WorkoutState.IDLE;

  Timer? _fadeTimer;
  Timer? _chimeDuckTimer;
  int _musicOperationSerial = 0;

  double get musicVolume => _musicVolume;
  bool get isMusicMuted => _musicMuted;
  bool get isMusicPlaying => _isMusicPlaying;
  bool get isHrrMusicActive => _isHrrMusicActive;
  FocusMusicMode? get activeTrack => _loadedTrack;

  AudioService._init() {
    _workPlayer = AudioPlayer()..setPlayerMode(PlayerMode.lowLatency);
    _restPlayer = AudioPlayer()..setPlayerMode(PlayerMode.lowLatency);
    _tickPlayer = AudioPlayer()..setPlayerMode(PlayerMode.lowLatency);
    _musicPlayer = AudioPlayer()..setPlayerMode(PlayerMode.mediaPlayer);
    _configureAudioSession();

    // Preload chime assets natively to buffer
    _workPlayer.setReleaseMode(ReleaseMode.stop);
    _workPlayer.setSource(AssetSource('sounds/Glass.wav'));

    _restPlayer.setReleaseMode(ReleaseMode.stop);
    _restPlayer.setSource(AssetSource('sounds/Hero.wav'));

    _tickPlayer.setReleaseMode(ReleaseMode.stop);
    _tickPlayer.setSource(AssetSource('sounds/Tick.wav'));
    _tickPlayer.setVolume(0.8);

    _musicPlayer.setReleaseMode(ReleaseMode.loop);

    // Listen to HRR recovery state to automatically play/fade Meditation cooldown music
    HrrService.instance.stateNotifier.addListener(_onHrrStateChanged);
  }

  void _configureAudioSession() async {
    final ctx = AudioContext(
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.playback,
        options: {
          AVAudioSessionOptions.duckOthers,
          AVAudioSessionOptions.mixWithOthers,
        },
      ),
      android: AudioContextAndroid(
        isSpeakerphoneOn: true,
        stayAwake: true,
        contentType: AndroidContentType.sonification,
        usageType: AndroidUsageType.assistanceSonification,
        audioFocus: AndroidAudioFocus.gainTransientMayDuck,
      ),
    );
    await _workPlayer.setAudioContext(ctx);
    await _restPlayer.setAudioContext(ctx);
    await _tickPlayer.setAudioContext(ctx);
    await _musicPlayer.setAudioContext(ctx);
  }

  double get _effectiveTargetVolume {
    if (_musicMuted) return 0.0;
    final mult = _isChimeDucking
        ? (_phaseMultiplier * 0.35).clamp(0.0, 0.30)
        : _phaseMultiplier;
    return (_musicVolume * mult).clamp(0.0, 1.0);
  }

  Future<void> setMusicVolume(double volume) async {
    _musicVolume = volume.clamp(0.0, 1.0);
    if (_isMusicPlaying) {
      _currentAppliedVolume = _effectiveTargetVolume;
      try {
        await _musicPlayer.setVolume(_currentAppliedVolume);
      } catch (e) {
        debugPrint('AudioService: setMusicVolume warning: $e');
      }
    }
  }

  Future<void> setMusicMuted(bool muted) async {
    _musicMuted = muted;
    if (_isMusicPlaying) {
      _fadeTo(_effectiveTargetVolume, const Duration(milliseconds: 200));
    }
  }

  Future<bool> toggleMusicMute() async {
    await setMusicMuted(!_musicMuted);
    return _musicMuted;
  }

  void _fadeTo(
    double targetVol,
    Duration duration, {
    VoidCallback? onComplete,
  }) {
    _fadeTimer?.cancel();
    final startVol = _currentAppliedVolume;
    final diff = targetVol - startVol;
    if (duration.inMilliseconds <= 25 || diff.abs() < 0.005) {
      _currentAppliedVolume = targetVol;
      _musicPlayer.setVolume(targetVol).catchError((_) {});
      onComplete?.call();
      return;
    }

    const int stepMs = 40;
    final int totalSteps = (duration.inMilliseconds / stepMs).ceil().clamp(1, 100);
    int currentStep = 0;

    _fadeTimer = Timer.periodic(const Duration(milliseconds: stepMs), (timer) {
      currentStep++;
      final double t = (currentStep / totalSteps).clamp(0.0, 1.0);
      _currentAppliedVolume = (startVol + diff * t).clamp(0.0, 1.0);
      _musicPlayer.setVolume(_currentAppliedVolume).catchError((_) {});
      if (currentStep >= totalSteps) {
        timer.cancel();
        onComplete?.call();
      }
    });
  }

  void _triggerChimeMicroDuck() {
    if (!_isMusicPlaying || _musicMuted || _phaseMultiplier <= 0.0) return;
    _chimeDuckTimer?.cancel();
    _isChimeDucking = true;
    _fadeTo(_effectiveTargetVolume, const Duration(milliseconds: 80));
    _chimeDuckTimer = Timer(const Duration(milliseconds: 650), () {
      _isChimeDucking = false;
      if (_isMusicPlaying) {
        _fadeTo(_effectiveTargetVolume, const Duration(milliseconds: 380));
      }
    });
  }

  Future<void> _startOrSwitchTrack(
    FocusMusicMode concreteTrack, {
    required double phaseMultiplier,
    required Duration fadeDuration,
  }) async {
    final assetPath = concreteTrack.assetPath;
    if (assetPath == null) return;

    final int op = ++_musicOperationSerial;
    _phaseMultiplier = phaseMultiplier;

    try {
      final bool trackChanged = _loadedTrack != concreteTrack;
      if (trackChanged) {
        _loadedTrack = concreteTrack;
        _currentAppliedVolume = 0.0;
        await _musicPlayer.stop();
        if (op != _musicOperationSerial) return;
        await _musicPlayer.setReleaseMode(ReleaseMode.loop);
        await _musicPlayer.setVolume(0.0);
        await _musicPlayer.play(AssetSource(assetPath));
        _isMusicPlaying = true;
      } else if (!_isMusicPlaying) {
        await _musicPlayer.setVolume(_currentAppliedVolume);
        await _musicPlayer.resume();
        _isMusicPlaying = true;
      }
      if (op != _musicOperationSerial) return;
      _fadeTo(_effectiveTargetVolume, fadeDuration);
    } catch (e) {
      debugPrint('AudioService: could not start track $assetPath: $e');
    }
  }

  /// Synchronizes Focus Music playback & volume envelope with the current workout state.
  Future<void> syncWorkoutMusic({
    required WorkoutState state,
    required FocusMusicMode mode,
    required ActivityType activity,
    bool isTreadmill = false,
  }) async {
    _lastSelectedMode = mode;
    _lastWorkoutState = state;

    final resolved = mode.resolve(activity: activity, isTreadmill: isTreadmill);
    if (resolved == FocusMusicMode.off) {
      await stopMusic(fadeDuration: const Duration(milliseconds: 300));
      return;
    }

    switch (state) {
      case WorkoutState.PREP:
        _isHrrMusicActive = false;
        await _startOrSwitchTrack(
          resolved,
          phaseMultiplier: 0.65,
          fadeDuration: const Duration(milliseconds: 800),
        );
        break;
      case WorkoutState.WORK:
        _isHrrMusicActive = false;
        await _startOrSwitchTrack(
          resolved,
          phaseMultiplier: 1.00,
          fadeDuration: const Duration(milliseconds: 400),
        );
        break;
      case WorkoutState.REST:
        _isHrrMusicActive = false;
        await _startOrSwitchTrack(
          resolved,
          phaseMultiplier: 0.45,
          fadeDuration: const Duration(milliseconds: 500),
        );
        break;
      case WorkoutState.PAUSED:
        if (_isMusicPlaying) {
          final int op = ++_musicOperationSerial;
          _fadeTo(
            0.0,
            const Duration(milliseconds: 250),
            onComplete: () {
              if (op == _musicOperationSerial) {
                _musicPlayer.pause().catchError((_) {});
                _isMusicPlaying = false;
              }
            },
          );
        }
        break;
      case WorkoutState.FINISHED:
      case WorkoutState.IDLE:
        // If HRR post-workout recovery is active, let HRR Meditation play instead of stopping
        if (HrrService.instance.state.isTracking && _lastSelectedMode != FocusMusicMode.off) {
          await _startHrrMeditation();
        } else {
          await stopMusic(fadeDuration: const Duration(milliseconds: 800));
        }
        break;
    }
  }

  Future<void> _startHrrMeditation() async {
    if (_lastSelectedMode == FocusMusicMode.off) return;
    _isHrrMusicActive = true;
    await _startOrSwitchTrack(
      FocusMusicMode.meditation,
      phaseMultiplier: 0.75,
      fadeDuration: const Duration(milliseconds: 1200),
    );
  }

  void _onHrrStateChanged() {
    final isTracking = HrrService.instance.state.isTracking;
    final bool workoutActive = _lastWorkoutState == WorkoutState.PREP ||
        _lastWorkoutState == WorkoutState.WORK ||
        _lastWorkoutState == WorkoutState.REST ||
        _lastWorkoutState == WorkoutState.PAUSED;

    if (isTracking && !workoutActive && !_isHrrMusicActive && _lastSelectedMode != FocusMusicMode.off) {
      _startHrrMeditation();
    } else if (!isTracking && _isHrrMusicActive && !workoutActive) {
      _isHrrMusicActive = false;
      stopMusic(fadeDuration: const Duration(milliseconds: 1500));
    }
  }

  Future<void> stopMusic({
    Duration fadeDuration = const Duration(milliseconds: 500),
  }) async {
    final int op = ++_musicOperationSerial;
    _isHrrMusicActive = false;
    _phaseMultiplier = 0.0;
    _isChimeDucking = false;
    _chimeDuckTimer?.cancel();

    if (!_isMusicPlaying && _loadedTrack == null) return;

    _fadeTo(
      0.0,
      fadeDuration,
      onComplete: () {
        if (op == _musicOperationSerial) {
          _musicPlayer.stop().catchError((_) {});
          _isMusicPlaying = false;
          _loadedTrack = null;
        }
      },
    );
  }

  Future<void> playWorkChime() async {
    _triggerChimeMicroDuck();
    await _workPlayer.stop();
    await _workPlayer.resume();
  }

  Future<void> playRestChime() async {
    _triggerChimeMicroDuck();
    await _restPlayer.stop();
    await _restPlayer.resume();
  }

  Future<void> playTick() async {
    await _tickPlayer.stop();
    await _tickPlayer.resume();
  }

  Future<void> dispose() async {
    HrrService.instance.stateNotifier.removeListener(_onHrrStateChanged);
    _fadeTimer?.cancel();
    _chimeDuckTimer?.cancel();
    await _workPlayer.dispose();
    await _restPlayer.dispose();
    await _tickPlayer.dispose();
    await _musicPlayer.dispose();
  }
}

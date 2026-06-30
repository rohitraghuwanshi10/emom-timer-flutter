import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/workout_engine.dart';
import '../services/bluetooth_service.dart';
import '../services/audio_service.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../services/health_service.dart';
import '../services/watch_connectivity_service.dart';
import '../services/treadmill_service.dart';
import 'package:sqflite/sqflite.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class TimerScreen extends StatefulWidget {
  const TimerScreen({super.key});

  @override
  State<TimerScreen> createState() => TimerScreenState();
}

class TimerScreenState extends State<TimerScreen> with SingleTickerProviderStateMixin {
  WorkoutEngine? _engine;
  StreamSubscription? _workoutSubscription;
  StreamSubscription? _hrSubscription;
  StreamSubscription? _watchSubscription;
  StreamSubscription? _btStateSubscription;
  StreamSubscription? _treadmillConnectionSubscription;
  StreamSubscription? _treadmillStatusSubscription;
  late AnimationController _progressController;

  int _workDuration = 60;
  int _restDuration = 10;
  int _totalRounds = 10;
  
  bool _autoRegulationEnabled = false;
  int _maxPreworkHr = 130;
  String _profileName = 'Default';
  List<String> _availableProfiles = [];
  
  int _currentHr = 0;
  bool _isBluetoothConnected = false;
  
  BluetoothConnectionState _treadmillConnectionState = BluetoothConnectionState.disconnected;
  TreadmillStatus? _treadmillStatus;
  WorkoutState? _lastProcessedTreadmillState;

  WorkoutEvent _currentEvent = WorkoutEvent(
    state: WorkoutState.IDLE,
    timeRemaining: 0,
    currentRound: 0,
    totalRounds: 0,
    isWaitingForHr: false,
  );

  bool _saveHistoryEnabled = true;
  bool _continuousMode = false;
  final TextEditingController _notesController = TextEditingController();
  String? _loadedTemplateName;
  Map<String, dynamic>? _loadedTemplate;
  String _activityType = 'HIIT';
  bool _treadmillWorkout = false;

  double _weightMoved = 0.0;
  String _weightUnit = 'kg';
  double _ruckWeight = 0.0;
  String _ruckWeightUnit = 'lbs';

  bool get _isTemplateModified {
    if (_loadedTemplate == null) return false;
    final templateAutoRegulate = (_loadedTemplate!['auto_regulate'] as int? ?? 1) == 1;
    final autoRegulateModified = _isBluetoothConnected
        ? _autoRegulationEnabled != templateAutoRegulate
        : false;
    final templateTreadmillWorkout = (_loadedTemplate!['treadmill_workout'] as int? ?? 0) == 1;
    final templateWorkSpeed = (_loadedTemplate!['work_speed'] as num?)?.toDouble() ?? 4.0;
    final templateRestSpeed = (_loadedTemplate!['rest_speed'] as num?)?.toDouble() ?? 0.0;
    final treadmillModified = _treadmillWorkout != templateTreadmillWorkout ||
        TreadmillBluetoothService.instance.workSpeed != templateWorkSpeed ||
        TreadmillBluetoothService.instance.restSpeed != templateRestSpeed;

    final templateWeightMoved = (_loadedTemplate!['weight_moved'] as num?)?.toDouble() ?? 0.0;
    final templateWeightUnit = _loadedTemplate!['weight_unit'] as String? ?? 'kg';
    final templateRuckWeight = (_loadedTemplate!['ruck_weight'] as num?)?.toDouble() ?? 0.0;
    final templateRuckWeightUnit = _loadedTemplate!['ruck_weight_unit'] as String? ?? 'lbs';

    final weightModified = _weightMoved != templateWeightMoved ||
        _weightUnit != templateWeightUnit ||
        _ruckWeight != templateRuckWeight ||
        _ruckWeightUnit != templateRuckWeightUnit;

    return _totalRounds != _loadedTemplate!['rounds'] ||
        _workDuration != _loadedTemplate!['work_time'] ||
        _restDuration != _loadedTemplate!['rest_time'] ||
        _notesController.text != (_loadedTemplate!['notes'] ?? '') ||
        _continuousMode != ((_loadedTemplate!['continuous_mode'] as int? ?? 0) == 1) ||
        _activityType != (_loadedTemplate!['activity_type'] ?? 'HIIT') ||
        autoRegulateModified ||
        treadmillModified ||
        weightModified;
  }
  
  // Cache variables for calorie/zone calculations
  int _maxHr = 180;
  String? _birthDate;
  String? _sex;
  double _weightKg = 70.0;
  bool _healthEnabled = false;
  String _distanceUnitPref = 'km';

  // Session data
  List<Map<String, dynamic>> _hrDetails = [];
  DateTime? _workoutStartTime;
  double _treadmillAccumulatedDistance = 0.0;
  double _lastTreadmillDistanceSample = -1.0;
  double _treadmillPeakSpeed = 0.0;
  List<double> _treadmillSpeeds = [];

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(vsync: this);
    AudioService.instance; // Force lazy-init to eagerly preload audio assets
    loadProfileSettings();
    _setupBluetooth();
    _setupTreadmill();
  }

  Future<void> loadProfileSettings() async {
    try {
      final activeProfile = await DatabaseHelper.instance.getActiveProfileName();
      final db = await DatabaseHelper.instance.database;
      
      // Load all available profiles for dropdown
      final allProfiles = await db.query('profiles', columns: ['name']);
      
      final results = await db.query('profiles', where: 'name = ?', whereArgs: [activeProfile], limit: 1);
      if (results.isNotEmpty) {
        final profile = results.first;
        if (mounted) {
          setState(() {
            _availableProfiles = allProfiles.map((p) => p['name'] as String).toList();
            _maxPreworkHr = profile['max_prework_hr'] as int? ?? 130;
            _profileName = activeProfile;
            _maxHr = profile['max_hr'] as int? ?? 180;
            _birthDate = profile['birth_date'] as String?;
            _sex = profile['sex'] as String?;
            _weightKg = profile['weight_kg'] as double? ?? 70.0;
            _healthEnabled = (profile['health_enabled'] as int? ?? 0) == 1;
            _saveHistoryEnabled = (profile['save_history'] as int? ?? 1) == 1;
            _distanceUnitPref = profile['distance_unit_pref'] as String? ?? 'km';
            
            TreadmillBluetoothService.instance.treadmillEnabled = (profile['treadmill_enabled'] as int? ?? 0) == 1;
            final p1 = (profile['treadmill_preset_1'] as num?)?.toDouble() ?? 2.0;
            final p2 = (profile['treadmill_preset_2'] as num?)?.toDouble() ?? 4.0;
            final p3 = (profile['treadmill_preset_3'] as num?)?.toDouble() ?? 6.0;
            TreadmillBluetoothService.instance.speedPresets = [p1, p2, p3];

            // Auto-check if Bluetooth is connected and maxPreworkHr is configured
            if (_isBluetoothConnected) {
              final templateAutoRegulate = _loadedTemplate == null || (_loadedTemplate!['auto_regulate'] as int? ?? 1) == 1;
              _autoRegulationEnabled = templateAutoRegulate && _maxPreworkHr > 0;
            } else {
              _autoRegulationEnabled = false;
            }
          });
          
          final autoConnect = profile['auto_connect_hr'] as int? ?? 1;
          if (autoConnect == 1) {
            debugPrint("TimerScreen: Profile auto_connect_hr is enabled. Starting auto-connect...");
            AppBluetoothService.instance.startScanAndConnect();
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading profile in timer: $e');
    }
  }

  Future<void> _onProfileChanged(String val) async {
    await DatabaseHelper.instance.setActiveProfileName(val);
    await loadProfileSettings();
  }

  void loadTemplate(Map<String, dynamic> template) {
    if (mounted) {
      setState(() {
        _totalRounds = template['rounds'] as int;
        _workDuration = template['work_time'] as int;
        _restDuration = template['rest_time'] as int;
        _notesController.text = template['notes'] as String? ?? '';
        _continuousMode = (template['continuous_mode'] as int? ?? 0) == 1;
        _activityType = template['activity_type'] as String? ?? 'HIIT';
        _loadedTemplateName = template['template_name'] as String?;
        _loadedTemplate = template;
        _autoRegulationEnabled = (template['auto_regulate'] as int? ?? 1) == 1 && _isBluetoothConnected && _maxPreworkHr > 0;
        _treadmillWorkout = (template['treadmill_workout'] as int? ?? 0) == 1;
        if (_treadmillWorkout) {
          TreadmillBluetoothService.instance.workSpeed = (template['work_speed'] as num?)?.toDouble() ?? 4.0;
          TreadmillBluetoothService.instance.restSpeed = (template['rest_speed'] as num?)?.toDouble() ?? 0.0;
          TreadmillBluetoothService.instance.autoSpeedSync = true;
        }
        _weightMoved = (template['weight_moved'] as num?)?.toDouble() ?? 0.0;
        _weightUnit = template['weight_unit'] as String? ?? 'kg';
        _ruckWeight = (template['ruck_weight'] as num?)?.toDouble() ?? 0.0;
        _ruckWeightUnit = template['ruck_weight_unit'] as String? ?? 'lbs';
      });
      if (_currentEvent.state == WorkoutState.FINISHED) _resetToIdle();
    }
  }

  void _setupBluetooth() {
    _isBluetoothConnected = AppBluetoothService.instance.isConnected;
    _btStateSubscription = AppBluetoothService.instance.deviceStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isBluetoothConnected = state == BluetoothConnectionState.connected;
          if (_isBluetoothConnected) {
            final templateAutoRegulate = _loadedTemplate == null || (_loadedTemplate!['auto_regulate'] as int? ?? 1) == 1;
            _autoRegulationEnabled = templateAutoRegulate && _maxPreworkHr > 0;
          } else {
            _autoRegulationEnabled = false;
          }
        });
      }
    });

    _hrSubscription = AppBluetoothService.instance.heartRateStream.listen((hr) {
      if (mounted) {
        setState(() => _currentHr = hr);
      }
      _engine?.updateHeartRate(hr);
    });

    WatchConnectivityService.instance.startListening();
    _watchSubscription = WatchConnectivityService.instance.heartRateStream.listen((hr) {
      if (mounted) {
        setState(() => _currentHr = hr);
      }
      _engine?.updateHeartRate(hr);
    });
  }

  void _setupTreadmill() {
    _treadmillConnectionState = TreadmillBluetoothService.instance.connectionState;
    _treadmillStatus = TreadmillBluetoothService.instance.lastStatus;

    _treadmillConnectionSubscription = TreadmillBluetoothService.instance.connectionStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _treadmillConnectionState = state;
        });
      }
    });

    _treadmillStatusSubscription = TreadmillBluetoothService.instance.statusStream.listen((status) {
      if (mounted) {
        setState(() {
          _treadmillStatus = status;
        });
      }
      final state = _currentEvent.state;
      if (_engine != null && state != WorkoutState.IDLE && state != WorkoutState.FINISHED) {
        if (_lastTreadmillDistanceSample < 0) {
          _lastTreadmillDistanceSample = status.distance;
        } else {
          final diff = status.distance - _lastTreadmillDistanceSample;
          if (diff > 0) {
            _treadmillAccumulatedDistance += diff;
          }
          _lastTreadmillDistanceSample = status.distance;
        }

        if (status.speed > _treadmillPeakSpeed) {
          _treadmillPeakSpeed = status.speed;
        }

        if (status.speed > 0.0) {
          _treadmillSpeeds.add(status.speed);
        }
      }
    });
  }

  void _startWorkout() {
    if (_engine != null && _currentEvent.state != WorkoutState.IDLE && _currentEvent.state != WorkoutState.FINISHED) return;

    WakelockPlus.enable(); // Keep screen awake during active workout
    _engine?.dispose(); // clean up any old engine
    _workoutSubscription?.cancel();

    _hrDetails = [];
    _workoutStartTime = DateTime.now();
    _treadmillAccumulatedDistance = 0.0;
    _lastTreadmillDistanceSample = -1.0;
    _treadmillPeakSpeed = 0.0;
    _treadmillSpeeds = [];
    if (TreadmillBluetoothService.instance.treadmillEnabled &&
        TreadmillBluetoothService.instance.isConnected &&
        _treadmillStatus != null) {
      _lastTreadmillDistanceSample = _treadmillStatus!.distance;
    }

    _engine = WorkoutEngine(
      totalRounds: _totalRounds,
      workDuration: _workDuration,
      baseRestDuration: _restDuration,
      autoRegulationEnabled: _autoRegulationEnabled,
      maxPreworkHr: _maxPreworkHr,
      continuousMode: _continuousMode,
    );

    _workoutSubscription = _engine!.workoutStream.listen((event) {
      setState(() {
        _currentEvent = event;
      });
      
      _recordHrTick(event.state);

      if (event.state == WorkoutState.FINISHED) {
        _saveWorkoutToDb();
        _resetToIdle();
        if (TreadmillBluetoothService.instance.treadmillEnabled &&
            _treadmillWorkout &&
            TreadmillBluetoothService.instance.autoSpeedSync &&
            TreadmillBluetoothService.instance.isConnected) {
          TreadmillBluetoothService.instance.stop();
        }
      }

      // Auto Speed Sync control logic
      if (TreadmillBluetoothService.instance.treadmillEnabled &&
          _treadmillWorkout &&
          TreadmillBluetoothService.instance.autoSpeedSync &&
          TreadmillBluetoothService.instance.isConnected) {
        if (event.state != _lastProcessedTreadmillState) {
          _lastProcessedTreadmillState = event.state;

          if (event.state == WorkoutState.WORK) {
            TreadmillBluetoothService.instance.startAndSetSpeed(TreadmillBluetoothService.instance.workSpeed);
          } else if (event.state == WorkoutState.REST) {
            TreadmillBluetoothService.instance.setSpeed(TreadmillBluetoothService.instance.restSpeed);
          } else if (event.state == WorkoutState.PAUSED) {
            TreadmillBluetoothService.instance.stop();
          } else if (event.state == WorkoutState.PREP && event.timeRemaining == 3) {
            // Pre-start treadmill 3s before WORK starts so it is fully spun up on WORK phase chime
            TreadmillBluetoothService.instance.setMode(1);
            TreadmillBluetoothService.instance.start();
          }
        }
      }
      
      // Play sounds on transitions
      if (event.timeRemaining == _workDuration && event.state == WorkoutState.WORK) {
        AudioService.instance.playWorkChime();
      } else if (event.timeRemaining == _restDuration && event.state == WorkoutState.REST) {
        AudioService.instance.playRestChime();
      } else if (event.timeRemaining == 10 && event.state == WorkoutState.PREP) {
        AudioService.instance.playWorkChime(); // Play 'Work' sound for PREP
      } else if ((event.state == WorkoutState.PREP || event.state == WorkoutState.REST) &&
          (event.timeRemaining == 3 || event.timeRemaining == 2 || event.timeRemaining == 1)) {
        AudioService.instance.playTick();
      }

      // Animation orchestration
      if (event.state == WorkoutState.PAUSED) {
        _progressController.stop(); // Instantly freeze animation!
      } else if (event.state == WorkoutState.IDLE || event.state == WorkoutState.FINISHED) {
        _progressController.stop();
        _progressController.value = 1.0;
      } else if (event.isWaitingForHr) {
        _progressController.stop(); // Let CircularProgressIndicator handle the infinite spin
      } else {
        int totalPhaseDuration = 1;
        switch (event.state) {
          case WorkoutState.PREP: totalPhaseDuration = 10; break;
          case WorkoutState.WORK: totalPhaseDuration = _workDuration; break;
          case WorkoutState.REST: totalPhaseDuration = _restDuration; break;
          default: totalPhaseDuration = 1;
        }
        if (totalPhaseDuration <= 0) totalPhaseDuration = 1;

        double targetProgress = (totalPhaseDuration - event.timeRemaining + 1) / totalPhaseDuration;
        if (targetProgress > 1.0) targetProgress = 1.0;

        if (event.timeRemaining == totalPhaseDuration || targetProgress < _progressController.value) {
          _progressController.value = 0.0;
        }

        int durationMs = ((targetProgress - _progressController.value) * totalPhaseDuration * 1000).toInt();
        if (durationMs <= 0) durationMs = 1000;

        _progressController.animateTo(targetProgress, duration: Duration(milliseconds: durationMs), curve: Curves.linear);
      }
    });

    _engine!.start();
  }

  void _stopWorkout() {
    if (_engine != null) {
      final completedRounds = _getCompletedRounds();
      if (completedRounds > 0) {
        _saveWorkoutToDb(completedRoundsOverride: completedRounds);
      }
      _engine?.stop();
    }
    _workoutSubscription?.cancel();
    _resetToIdle();
  }

  void _resetToIdle() {
    WakelockPlus.disable(); // Allow screen to sleep after workout is done
    _engine?.dispose();
    _engine = null;
    _lastProcessedTreadmillState = null;
    if (TreadmillBluetoothService.instance.treadmillEnabled &&
        TreadmillBluetoothService.instance.isConnected) {
      TreadmillBluetoothService.instance.stop();
    }
    setState(() {
      _currentEvent = WorkoutEvent(
        state: WorkoutState.IDLE,
        timeRemaining: 0,
        currentRound: 0,
        totalRounds: 0,
        isWaitingForHr: false,
      );
    });
  }

  @override
  void dispose() {
    WakelockPlus.disable(); // Ensure screen wake lock is released on page dispose
    _notesController.dispose();
    _progressController.dispose();
    _workoutSubscription?.cancel();
    _hrSubscription?.cancel();
    _watchSubscription?.cancel();
    WatchConnectivityService.instance.stopListening();
    _btStateSubscription?.cancel();
    _treadmillConnectionSubscription?.cancel();
    _treadmillStatusSubscription?.cancel();
    _engine?.dispose();
    super.dispose();
  }

  void _recordHrTick(WorkoutState state) {
    if (state == WorkoutState.WORK || state == WorkoutState.REST || state == WorkoutState.PREP) {
      if (_currentHr > 0) {
        final zoneStr = _calculateZone(_currentHr);
        _hrDetails.add({
          'capture_time': DateTime.now().toIso8601String().substring(0, 19),
          'bpm': _currentHr,
          'zone': zoneStr,
        });
      }
    }
  }

  int _getCompletedRounds() {
    if (_engine == null) return 0;
    final currentRound = _currentEvent.currentRound;
    if (currentRound == 0) return 0;

    final activeState = _currentEvent.state == WorkoutState.PAUSED 
        ? (_currentEvent.prevState ?? WorkoutState.WORK) 
        : _currentEvent.state;

    if (activeState == WorkoutState.WORK) {
      final completedWork = _workDuration - _currentEvent.timeRemaining;
      if (completedWork > (_workDuration / 2)) {
        return currentRound;
      } else {
        return currentRound - 1;
      }
    } else {
      return currentRound;
    }
  }

  int _calculateAge(String birthDateStr) {
    try {
      final birth = DateTime.parse(birthDateStr);
      final today = DateTime.now();
      int age = today.year - birth.year;
      if (today.month < birth.month || (today.month == birth.month && today.day < birth.day)) {
        age--;
      }
      return age;
    } catch (_) {
      return 0;
    }
  }

  String _calculateZone(int bpm) {
    if (_maxHr <= 0) return '';
    final pct = (bpm / _maxHr) * 100;
    if (pct < 50) return 'WARM UP';
    if (pct < 60) return 'ZONE 1';
    if (pct < 70) return 'ZONE 2';
    if (pct < 80) return 'ZONE 3';
    if (pct < 90) return 'ZONE 4';
    return 'ZONE 5';
  }

  Color _getZoneColor(String zone) {
    switch (zone) {
      case 'WARM UP': return Colors.grey;
      case 'ZONE 1': return Colors.blue;
      case 'ZONE 2': return Colors.green;
      case 'ZONE 3': return Colors.yellow;
      case 'ZONE 4': return Colors.orange;
      case 'ZONE 5': return Colors.red;
      default: return Colors.grey;
    }
  }

  Widget _buildLiveHeartRateDisplay() {
    final bool isConnected = _currentHr > 0;
    final zone = isConnected ? _calculateZone(_currentHr) : '';
    final zoneColor = isConnected ? _getZoneColor(zone) : Colors.grey;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            PulsingHeart(isActive: isConnected),
            const SizedBox(width: 8),
            Text(
              isConnected ? '$_currentHr' : '--',
              style: TextStyle(
                fontSize: 64,
                fontWeight: FontWeight.w900,
                color: isConnected ? Colors.white : Colors.grey.withValues(alpha: 0.3),
                letterSpacing: -2,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              'BPM',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isConnected ? Colors.grey : Colors.grey.withValues(alpha: 0.3),
              ),
            ),
          ],
        ),
        if (isConnected && zone.isNotEmpty) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: zoneColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: zoneColor.withValues(alpha: 0.5),
                width: 1,
              ),
            ),
            child: Text(
              zone,
              style: TextStyle(
                color: zoneColor,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ] else ...[
          const SizedBox(height: 4),
          Text(
            'NO HR MONITOR CONNECTED',
            style: TextStyle(
              color: Colors.grey.withValues(alpha: 0.4),
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _saveWorkoutToDb({int? completedRoundsOverride}) async {
    if (!_saveHistoryEnabled) return;
    if (_engine == null || _workoutStartTime == null) return;

    final completedRounds = completedRoundsOverride ?? _getCompletedRounds();
    if (completedRounds <= 0) return;

    try {
      final endTime = DateTime.now();
      final duration = _engine!.workTimeSec;
      final rest = _engine!.restTimeSec;
      final totalTime = duration + rest;

      int maxHr = 0;
      int avgHr = 0;
      if (_hrDetails.isNotEmpty) {
        final bpms = _hrDetails.map((x) => x['bpm'] as int).toList();
        maxHr = bpms.reduce((a, b) => a > b ? a : b);
        avgHr = (bpms.reduce((a, b) => a + b) / bpms.length).round();
      }

      double caloriesBurnt = 0.0;
      final totalMins = totalTime / 60.0;
      double weight = _weightKg;

      if (avgHr > 0) {
        final age = _birthDate != null ? _calculateAge(_birthDate!) : 35;
        final sex = _sex ?? 'Male';
        
        double cpm;
        if (sex == 'Male') {
          cpm = (-55.0969 + (0.6309 * avgHr) + (0.1988 * weight) + (0.2017 * age)) / 4.184;
        } else {
          cpm = (-20.4022 + (0.4472 * avgHr) - (0.1263 * weight) + (0.074 * age)) / 4.184;
        }
        caloriesBurnt = cpm * totalMins;
      } else {
        // Fallback MET-based formula (MET value of 8.5 for HIIT/EMOM)
        const double met = 8.5;
        caloriesBurnt = met * 3.5 * weight / 200 * totalMins;
      }

      if (caloriesBurnt < 0) caloriesBurnt = 0.0;
      caloriesBurnt = double.parse(caloriesBurnt.toStringAsFixed(2));

      final notes = _notesController.text;
      
      final workoutName = _loadedTemplateName != null
          ? (_isTemplateModified ? '$_loadedTemplateName (Modified)' : _loadedTemplateName)
          : null;

      double avgSpeed = _treadmillSpeeds.isNotEmpty
          ? (_treadmillSpeeds.reduce((a, b) => a + b) / _treadmillSpeeds.length)
          : 0.0;

      final bool isStrength = const {'STRENGTH', 'FUNCTIONAL_STRENGTH', 'CALISTHENICS'}.contains(_activityType);
      final double weightMovedToSave = isStrength ? _weightMoved : 0.0;
      final double ruckWeightToSave = !isStrength ? _ruckWeight : 0.0;

      final workoutId = await DatabaseHelper.instance.saveWorkout(
        profileName: _profileName,
        workoutName: workoutName,
        startTime: _workoutStartTime!.toIso8601String().substring(0, 19),
        endTime: endTime.toIso8601String().substring(0, 19),
        totalRoundsCompleted: completedRounds,
        workDuration: _workDuration,
        restDuration: _restDuration,
        totalTimeSec: totalTime,
        workTimeSec: duration,
        restTimeSec: rest,
        maxHr: maxHr,
        avgHr: avgHr,
        caloriesBurntKcal: caloriesBurnt,
        notes: notes,
        hrLogs: _hrDetails,
        activityType: _activityType,
        runDistance: _treadmillWorkout ? double.parse(_treadmillAccumulatedDistance.toStringAsFixed(2)) : 0.0,
        runPeakSpeed: _treadmillWorkout ? _treadmillPeakSpeed : 0.0,
        runAvgSpeed: _treadmillWorkout ? double.parse(avgSpeed.toStringAsFixed(2)) : 0.0,
        weightMoved: weightMovedToSave,
        weightUnit: _weightUnit,
        ruckWeight: ruckWeightToSave,
        ruckWeightUnit: _ruckWeightUnit,
      );
      
      debugPrint("TimerScreen: _healthEnabled is $_healthEnabled");
      if (_healthEnabled) {
        HealthService.instance.saveWorkout(
          start: _workoutStartTime!,
          end: endTime,
          totalCalories: caloriesBurnt.round(),
          title: workoutName ?? 'EMOM Workout',
          heartRateData: _hrDetails,
          activityTypeStr: _activityType,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Workout saved successfully! ID: $workoutId, Calories: $caloriesBurnt kcal')),
        );
        _notesController.clear();
      }
      
      // Trigger background sync to upload the newly saved workout
      SyncService.instance.signInAndSync();
    } catch (e) {
      debugPrint('TimerScreen: Error saving workout: $e');
    }
  }

  void _showHelpDialog(String title, String description) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(description),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _showSaveTemplateDialog() async {
    final TextEditingController controller = TextEditingController(text: _loadedTemplateName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save Template'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Template Name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                try {
                  final db = await DatabaseHelper.instance.database;
                  final wasTemplateAutoRegulated = _loadedTemplate != null && (_loadedTemplate!['auto_regulate'] as int? ?? 1) == 1;
                  final autoRegulateToSave = _isBluetoothConnected
                      ? (_autoRegulationEnabled ? 1 : 0)
                      : (wasTemplateAutoRegulated || _loadedTemplate == null ? 1 : 0);

                  await db.insert('workout_templates', {
                    'profile_name': _profileName,
                    'template_name': controller.text,
                    'rounds': _totalRounds,
                    'work_time': _workDuration,
                    'rest_time': _restDuration,
                    'notes': _notesController.text,
                    'continuous_mode': _continuousMode ? 1 : 0,
                    'activity_type': _activityType,
                    'auto_regulate': autoRegulateToSave,
                    'treadmill_workout': _treadmillWorkout ? 1 : 0,
                    'work_speed': TreadmillBluetoothService.instance.workSpeed,
                    'rest_speed': TreadmillBluetoothService.instance.restSpeed,
                  }, conflictAlgorithm: ConflictAlgorithm.replace);
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Template saved')));
                  }
                } catch (e) {
                  debugPrint('Error saving template: \$e');
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  String _getActivityName(String code) {
    switch (code) {
      case 'HIIT':
        return 'HIIT / Interval';
      case 'STRENGTH':
        return 'Strength Training';
      case 'FUNCTIONAL_STRENGTH':
        return 'Functional Strength';
      case 'CORE':
        return 'Core Training';
      case 'CARDIO':
        return 'Mixed Cardio';
      case 'YOGA':
        return 'Yoga';
      case 'PILATES':
        return 'Pilates';
      case 'CALISTHENICS':
        return 'Calisthenics';
      default:
        return 'Other';
    }
  }

  Color _getActivityColor(String code) {
    switch (code) {
      case 'HIIT':
        return const Color(0xFFBD93F9);
      case 'STRENGTH':
        return const Color(0xFF81A1C1);
      case 'FUNCTIONAL_STRENGTH':
        return const Color(0xFF88C0D0);
      case 'CORE':
        return const Color(0xFFD08770);
      case 'CARDIO':
        return const Color(0xFF0DF2A3);
      case 'YOGA':
        return const Color(0xFFB48EAD);
      case 'PILATES':
        return const Color(0xFFFF79C6);
      case 'CALISTHENICS':
        return const Color(0xFFEBCB8B);
      default:
        return const Color(0xFF4C566A);
    }
  }

  String _formatDuration(int seconds) {
    if (seconds >= 3600) {
      final hours = seconds ~/ 3600;
      final minutes = (seconds % 3600) ~/ 60;
      return '${hours}h ${minutes}m';
    }
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    if (secs == 0) return '${mins}m';
    return '${mins}m ${secs}s';
  }

  double _secondsToSliderValue(int seconds) {
    if (seconds <= 300) {
      final pct = (seconds - 10) / (300 - 10);
      return pct * 0.5;
    } else {
      final pct = (seconds - 300) / (3600 - 300);
      return 0.5 + pct * 0.5;
    }
  }

  int _sliderValueToSeconds(double value) {
    if (value <= 0.5) {
      final pct = value / 0.5;
      final seconds = 10 + (300 - 10) * pct;
      return ((seconds / 5).round() * 5).clamp(10, 300);
    } else {
      final pct = (value - 0.5) / 0.5;
      final seconds = 300 + (3600 - 300) * pct;
      return ((seconds / 60).round() * 60).clamp(300, 3600);
    }
  }

  int _decrementWorkDuration(int current) {
    if (current <= 10) return 10;
    if (current <= 300) {
      return (current - 5).clamp(10, 3600);
    } else {
      final newDuration = ((current - 60) / 60).floor() * 60;
      return newDuration.clamp(300, 3600);
    }
  }

  int _incrementWorkDuration(int current) {
    if (current >= 3600) return 3600;
    if (current < 300) {
      return (current + 5).clamp(10, 3600);
    } else {
      final newDuration = ((current + 60) / 60).floor() * 60;
      return newDuration.clamp(300, 3600);
    }
  }

  double _secondsToRestSliderValue(int seconds) {
    if (seconds <= 120) {
      final pct = seconds / 120.0;
      return pct * 0.5;
    } else {
      final pct = (seconds - 120) / (900.0 - 120.0);
      return 0.5 + pct * 0.5;
    }
  }

  int _sliderValueToRestSeconds(double value) {
    if (value <= 0.5) {
      final pct = value / 0.5;
      final seconds = 120.0 * pct;
      return ((seconds / 5).round() * 5).clamp(0, 120);
    } else {
      final pct = (value - 0.5) / 0.5;
      final seconds = 120.0 + (900.0 - 120.0) * pct;
      return ((seconds / 30).round() * 30).clamp(120, 900);
    }
  }

  int _decrementRestDuration(int current) {
    if (current <= 0) return 0;
    if (current <= 120) {
      return (current - 5).clamp(0, 900);
    } else {
      final newDuration = ((current - 30) / 30).floor() * 30;
      return newDuration.clamp(120, 900);
    }
  }

  int _incrementRestDuration(int current) {
    if (current >= 900) return 900;
    if (current < 120) {
      return (current + 5).clamp(0, 900);
    } else {
      final newDuration = ((current + 30) / 30).floor() * 30;
      return newDuration.clamp(120, 900);
    }
  }



  Widget _buildStatColumn(String label, String value, IconData icon, {Color? valueColor}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 13, color: Colors.grey),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
      ],
    );
  }



  Widget _buildTemplateHeader() {
    if (_loadedTemplateName == null) return const SizedBox.shrink();
    
    final isModified = _isTemplateModified;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.star, color: Theme.of(context).colorScheme.primary, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _loadedTemplateName!,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (isModified)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit, size: 10, color: Colors.orange),
                      SizedBox(width: 4),
                      Text(
                        'Modified',
                        style: TextStyle(
                          color: Colors.orange,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
               OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _loadedTemplateName = null;
                    _loadedTemplate = null;
                    _treadmillWorkout = false;
                    TreadmillBluetoothService.instance.autoSpeedSync = false;
                    _autoRegulationEnabled = _isBluetoothConnected && _maxPreworkHr > 0;
                    _weightMoved = 0.0;
                    _weightUnit = 'kg';
                    _ruckWeight = 0.0;
                    _ruckWeightUnit = 'lbs';
                  });
                },
                icon: const Icon(Icons.close, size: 14),
                label: const Text('Unload', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  side: BorderSide(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.2)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              if (isModified) ...[
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () {
                    if (_loadedTemplate != null) {
                      loadTemplate(_loadedTemplate!);
                    }
                  },
                  icon: const Icon(Icons.undo, size: 14),
                  label: const Text('Reset', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.withValues(alpha: 0.2),
                    foregroundColor: Colors.orange,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWorkoutSummaryCard() {
    final isTreadmill = TreadmillBluetoothService.instance.treadmillEnabled && _treadmillWorkout;
    return Card(
      color: Theme.of(context).colorScheme.surface,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_loadedTemplateName != null && MediaQuery.of(context).orientation != Orientation.landscape) ...[
              _buildTemplateHeader(),
              const SizedBox(height: 12),
            ],
            // A clean 2x2 grid of key stats
            Row(
              children: [
                Expanded(
                  child: _buildStatColumn(
                    'Work Duration',
                    _formatDuration(_workDuration),
                    Icons.timer,
                    valueColor: Theme.of(context).colorScheme.primary,
                  ),
                ),
                Expanded(
                  child: _buildStatColumn(
                    'Rest Duration',
                    _restDuration == 0 ? 'None' : _formatDuration(_restDuration),
                    Icons.coffee,
                    valueColor: Theme.of(context).colorScheme.secondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildStatColumn(
                    'Rounds',
                    _continuousMode ? 'Open Ended' : '$_totalRounds',
                    Icons.repeat,
                  ),
                ),
                Expanded(
                  child: _buildStatColumn(
                    'Activity Type',
                    _getActivityName(_activityType),
                    Icons.fitness_center,
                    valueColor: _getActivityColor(_activityType),
                  ),
                ),
              ],
            ),
            if (_autoRegulationEnabled) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.favorite_border, size: 14, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    'Auto-regulated Rest (< $_maxPreworkHr BPM)',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
            if (isTreadmill) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.directions_run, size: 14, color: Theme.of(context).colorScheme.secondary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final bool isMetric = _distanceUnitPref == 'km';
                        final double displayWorkSpeed = isMetric 
                            ? TreadmillBluetoothService.instance.workSpeed 
                            : TreadmillBluetoothService.instance.workSpeed * 0.621371;
                        final double displayRestSpeed = isMetric 
                            ? TreadmillBluetoothService.instance.restSpeed 
                            : TreadmillBluetoothService.instance.restSpeed * 0.621371;
                        final String speedUnit = isMetric ? 'km/h' : 'mph';

                        return Text(
                          TreadmillBluetoothService.instance.autoSpeedSync
                              ? 'Treadmill speed sync: Work ${displayWorkSpeed.toStringAsFixed(1)} $speedUnit | Rest ${displayRestSpeed.toStringAsFixed(1)} $speedUnit'
                              : 'Treadmill integration active (Auto Speed Sync: OFF)',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.secondary,
                            fontWeight: FontWeight.w500,
                          ),
                        );
                      }
                    ),
                  ),
                ],
              ),
            ],
            if (_notesController.text.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.note_alt_outlined, size: 14, color: Colors.grey),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _notesController.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _showCustomizeWorkoutSheet,
              icon: const Icon(Icons.tune, size: 18),
              label: const Text('Customize Workout'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                foregroundColor: Theme.of(context).colorScheme.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCustomizeWorkoutSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _CustomizeWorkoutSheet(timerState: this);
      },
    );
  }

  Widget _buildTimerDisplay({double? customSize}) {
    Color stateColor;
    String stateText;
    
    WorkoutState displayState = _currentEvent.state == WorkoutState.PAUSED 
        ? (_currentEvent.prevState ?? WorkoutState.WORK) 
        : _currentEvent.state;

    switch (displayState) {
      case WorkoutState.IDLE:
        stateColor = Theme.of(context).colorScheme.surface;
        stateText = 'READY';
        break;
      case WorkoutState.PREP:
        stateColor = Colors.amber;
        stateText = 'PREPARE';
        break;
      case WorkoutState.WORK:
        stateColor = Theme.of(context).colorScheme.secondary; // Green
        stateText = 'WORK';
        break;
      case WorkoutState.REST:
        stateColor = Theme.of(context).colorScheme.primary; // Blue
        stateText = _currentEvent.isWaitingForHr ? 'HOLDING...' : 'REST';
        if (_currentEvent.isWaitingForHr) {
          stateColor = Colors.orangeAccent;
        }
        break;
      case WorkoutState.FINISHED:
        stateColor = Colors.grey;
        stateText = 'DONE';
        break;
      default:
        stateColor = Colors.grey;
        stateText = '';
    }

    if (_currentEvent.state == WorkoutState.PAUSED) {
      stateText = 'PAUSED';
      stateColor = Colors.grey;
    }

    int totalPhaseDuration = 1;
    switch (displayState) {
      case WorkoutState.PREP:
        totalPhaseDuration = 10;
        break;
      case WorkoutState.WORK:
        totalPhaseDuration = _workDuration;
        break;
      case WorkoutState.REST:
        totalPhaseDuration = _restDuration;
        break;
      default:
        totalPhaseDuration = 1;
    }

    if (totalPhaseDuration <= 0) totalPhaseDuration = 1;

    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape && MediaQuery.of(context).size.height < 500;
    final size = MediaQuery.of(context).size;
    final double timerSize = customSize ?? (isLandscape 
        ? 160.0 
        : (size.width < size.height ? size.width * 0.8 : size.height * 0.6).clamp(200.0, 600.0));
    
    final double timeFontSize = timerSize * 0.29;
    final double stateFontSize = timerSize * 0.085;
    final double roundFontSize = timerSize * 0.065;
    final double strokeWidth = timerSize * 0.03;

    return SizedBox(
      width: timerSize,
      height: timerSize,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedBuilder(
            animation: _progressController,
            builder: (context, child) => CircularProgressIndicator(
              value: _currentEvent.isWaitingForHr 
                  ? null 
                  : _progressController.value,
              strokeWidth: strokeWidth,
              backgroundColor: stateColor.withValues(alpha: 0.2),
              valueColor: AlwaysStoppedAnimation<Color>(stateColor),
            ),
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  stateText,
                  style: TextStyle(color: stateColor, fontSize: stateFontSize, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: timerSize * 0.03),
                Text(
                  _currentEvent.state == WorkoutState.IDLE 
                    ? '${(_workDuration ~/ 60).toString().padLeft(2, '0')}:${(_workDuration % 60).toString().padLeft(2, '0')}' 
                    : '${(_currentEvent.timeRemaining ~/ 60).toString().padLeft(2, '0')}:${(_currentEvent.timeRemaining % 60).toString().padLeft(2, '0')}',
                  style: TextStyle(fontSize: timeFontSize, fontWeight: FontWeight.w200),
                ),
                if (_currentEvent.state != WorkoutState.IDLE && _currentEvent.state != WorkoutState.FINISHED)
                  Text(
                    'Round ${_currentEvent.currentRound} / ${_currentEvent.totalRounds}',
                    style: TextStyle(fontSize: roundFontSize, color: Colors.grey),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileSelectorAction(bool isEnabled) {
    if (_availableProfiles.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(right: 8.0),
        child: Chip(
          avatar: Icon(Icons.person, size: 14, color: Theme.of(context).colorScheme.primary),
          label: Text(_profileName, style: const TextStyle(fontSize: 12)),
          padding: EdgeInsets.zero,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
      child: PopupMenuButton<String>(
        enabled: isEnabled,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isEnabled
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)
                  : Colors.grey.withValues(alpha: 0.3),
            ),
            color: Theme.of(context).colorScheme.surface,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.person,
                size: 14,
                color: isEnabled ? Theme.of(context).colorScheme.primary : Colors.grey,
              ),
              const SizedBox(width: 6),
              Text(
                _profileName,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isEnabled ? Colors.white : Colors.grey,
                ),
              ),
              Icon(
                Icons.arrow_drop_down,
                size: 14,
                color: isEnabled ? Colors.white : Colors.grey,
              ),
            ],
          ),
        ),
        onSelected: (val) async {
          await _onProfileChanged(val);
        },
        itemBuilder: (context) {
          return _availableProfiles.map((p) {
            return PopupMenuItem<String>(
              value: p,
              child: Text(p),
            );
          }).toList();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isIdle = _currentEvent.state == WorkoutState.IDLE || _currentEvent.state == WorkoutState.FINISHED;
    final bool isNarrow = MediaQuery.of(context).size.width < 600;
    final bool isLandscape = MediaQuery.of(context).orientation == Orientation.landscape && MediaQuery.of(context).size.height < 500;
    final bool showTreadmillStop = !isIdle &&
        TreadmillBluetoothService.instance.treadmillEnabled &&
        _treadmillWorkout &&
        _treadmillConnectionState == BluetoothConnectionState.connected;

    return Scaffold(
      appBar: isLandscape
          ? null
          : AppBar(
              title: const Text('ChronoPulse Active'),
              actions: [
                _buildProfileSelectorAction(isIdle),
                IconButton(
                  icon: Icon(
                    (_isBluetoothConnected || _treadmillConnectionState == BluetoothConnectionState.connected)
                        ? Icons.bluetooth_connected
                        : Icons.bluetooth_disabled,
                    color: (_isBluetoothConnected || _treadmillConnectionState == BluetoothConnectionState.connected)
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey,
                  ),
                  onPressed: _showBluetoothDeviceManager,
                ),
              ],
            ),
      body: isLandscape
          ? SafeArea(
              top: true,
              bottom: false,
              left: true,
              right: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Left Column: Scrollable Stats & Telemetry (50% Width)
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Top control bar inline: Loaded Template badge with Close/Unload action
                          if (_loadedTemplateName != null) ...[
                            Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.star_outline,
                                      size: 14,
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      _loadedTemplateName! + (_isTemplateModified ? ' (Modified)' : ''),
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(context).colorScheme.primary,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          _loadedTemplateName = null;
                                          _loadedTemplate = null;
                                          _treadmillWorkout = false;
                                        });
                                      },
                                      child: Icon(
                                        Icons.close,
                                        size: 14,
                                        color: Theme.of(context).colorScheme.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          _buildLiveHeartRateDisplay(),
                          const SizedBox(height: 16),
                          _buildLiveTreadmillTelemetry(),
                          if (isIdle) ...[
                            const SizedBox(height: 8),
                            _buildWorkoutSummaryCard(),
                          ],
                        ],
                      ),
                    ),
                  ),
                  // Divider
                  VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.15),
                  ),
                  // Right Column: Dynamically-sized Timer Circle and controls (50% Width)
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final availableHeight = constraints.maxHeight;
                        // Dynamically size timer circle to fit height nicely (leave ~80px for spacing/controls)
                        final timerSize = (availableHeight - 80).clamp(130.0, 220.0);

                        return Center(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                _buildTimerDisplay(customSize: timerSize),
                                const SizedBox(height: 12),
                                _buildInlineControls(isIdle, showTreadmillStop),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              child: SizedBox(
                width: MediaQuery.of(context).size.width,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 16),
                    if (_loadedTemplateName != null && !isIdle) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.star_outline,
                              size: 16,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _loadedTemplateName! + (_isTemplateModified ? ' (Modified)' : ''),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    _buildTimerDisplay(),
                    const SizedBox(height: 24),
                    _buildLiveHeartRateDisplay(),
                    const SizedBox(height: 24),
                    _buildLiveTreadmillTelemetry(),
                    const SizedBox(height: 24),
                    if (isIdle) _buildWorkoutSummaryCard(),
                  ],
                ),
              ),
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: isLandscape
          ? null
          : (isIdle
              ? (isNarrow
                  ? FloatingActionButton(
                      heroTag: 'start_btn',
                      onPressed: _startWorkout,
                      backgroundColor: Theme.of(context).colorScheme.secondary,
                      child: const Icon(Icons.play_arrow),
                    )
                  : FloatingActionButton.extended(
                      heroTag: 'start_btn',
                      onPressed: _startWorkout,
                      backgroundColor: Theme.of(context).colorScheme.secondary,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Start'),
                    ))
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    isNarrow
                        ? FloatingActionButton(
                            heroTag: 'pause_btn',
                            onPressed: () => _engine?.pause(),
                            backgroundColor: _currentEvent.state == WorkoutState.PAUSED 
                                ? Theme.of(context).colorScheme.secondary 
                                : Colors.orange,
                            child: Icon(_currentEvent.state == WorkoutState.PAUSED ? Icons.play_arrow : Icons.pause),
                          )
                        : FloatingActionButton.extended(
                            heroTag: 'pause_btn',
                            onPressed: () => _engine?.pause(),
                            backgroundColor: _currentEvent.state == WorkoutState.PAUSED 
                                ? Theme.of(context).colorScheme.secondary 
                                : Colors.orange,
                            icon: Icon(_currentEvent.state == WorkoutState.PAUSED ? Icons.play_arrow : Icons.pause),
                            label: Text(_currentEvent.state == WorkoutState.PAUSED ? 'Resume' : 'Pause'),
                          ),
                    if (showTreadmillStop) ...[
                      const SizedBox(width: 16),
                      isNarrow
                          ? FloatingActionButton(
                              heroTag: 'tm_stop_btn',
                              onPressed: () {
                                TreadmillBluetoothService.instance.stop();
                                _engine?.pause();
                              },
                              backgroundColor: Colors.red,
                              child: const Icon(Icons.pan_tool, color: Colors.white),
                            )
                          : FloatingActionButton.extended(
                              heroTag: 'tm_stop_btn',
                              onPressed: () {
                                TreadmillBluetoothService.instance.stop();
                                _engine?.pause();
                              },
                              backgroundColor: Colors.red,
                              icon: const Icon(Icons.pan_tool, color: Colors.white),
                              label: const Text('STOP TREADMILL', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            ),
                    ],
                    const SizedBox(width: 16),
                    isNarrow
                        ? FloatingActionButton(
                            heroTag: 'stop_btn',
                            onPressed: _stopWorkout,
                            backgroundColor: Theme.of(context).colorScheme.error,
                            child: const Icon(Icons.stop),
                          )
                        : FloatingActionButton.extended(
                            heroTag: 'stop_btn',
                            onPressed: _stopWorkout,
                            backgroundColor: Theme.of(context).colorScheme.error,
                            icon: const Icon(Icons.stop),
                            label: const Text('End'),
                          ),
                  ],
                )),
    );
  }

  Widget _buildInlineControls(bool isIdle, bool showTreadmillStop) {
    if (isIdle) {
      return ElevatedButton.icon(
        onPressed: _startWorkout,
        style: ElevatedButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.secondary,
          foregroundColor: Theme.of(context).colorScheme.onSecondary,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: const Icon(Icons.play_arrow),
        label: const Text('Start', style: TextStyle(fontWeight: FontWeight.bold)),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        ElevatedButton.icon(
          onPressed: () => _engine?.pause(),
          style: ElevatedButton.styleFrom(
            backgroundColor: _currentEvent.state == WorkoutState.PAUSED 
                ? Theme.of(context).colorScheme.secondary 
                : Colors.orange,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          icon: Icon(_currentEvent.state == WorkoutState.PAUSED ? Icons.play_arrow : Icons.pause, size: 14),
          label: Text(_currentEvent.state == WorkoutState.PAUSED ? 'Resume' : 'Pause', style: const TextStyle(fontSize: 11)),
        ),
        if (showTreadmillStop)
          ElevatedButton.icon(
            onPressed: () {
              TreadmillBluetoothService.instance.stop();
              _engine?.pause();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: const Icon(Icons.pan_tool, size: 12, color: Colors.white),
            label: const Text('STOP TM', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ElevatedButton.icon(
          onPressed: _stopWorkout,
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          icon: const Icon(Icons.stop, size: 14),
          label: const Text('End', style: TextStyle(fontSize: 11)),
        ),
      ],
    );
  }

  void _showBluetoothDeviceManager() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return const BluetoothDeviceManagerSheet();
      },
    );
  }

  Widget _buildLiveTreadmillTelemetry() {
    final bool isEnabled = TreadmillBluetoothService.instance.treadmillEnabled;
    final bool isConnected = _treadmillConnectionState == BluetoothConnectionState.connected;
    if (!isEnabled || !isConnected || !_treadmillWorkout) return const SizedBox.shrink();

    final status = _treadmillStatus;
    final double rawSpeed = status?.speed ?? 0.0;
    final double rawDist = status?.distance ?? 0.0;
    final time = status?.time ?? 0;
    final steps = status?.steps ?? 0;

    final bool isMetric = _distanceUnitPref == 'km';
    final double displaySpeed = isMetric ? rawSpeed : rawSpeed * 0.621371;
    final double displayDist = isMetric ? rawDist : rawDist * 0.621371;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Card(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.directions_run, color: Theme.of(context).colorScheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'WalkingPad Telemetry',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
              const Divider(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildTelemetryItem(
                    label: 'Speed',
                    value: '${displaySpeed.toStringAsFixed(1)} ${isMetric ? "km/h" : "mph"}',
                    icon: Icons.speed,
                  ),
                  _buildTelemetryItem(
                    label: 'Distance',
                    value: '${displayDist.toStringAsFixed(2)} ${isMetric ? "km" : "mi"}',
                    icon: Icons.map,
                  ),
                  _buildTelemetryItem(
                    label: 'Time',
                    value: _formatDuration(time),
                    icon: Icons.timer,
                  ),
                  _buildTelemetryItem(
                    label: 'Steps',
                    value: '$steps',
                    icon: Icons.nordic_walking,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTelemetryItem({required String label, required String value, required IconData icon}) {
    return Column(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.6)),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}

class BluetoothDeviceManagerSheet extends StatefulWidget {
  const BluetoothDeviceManagerSheet({super.key});

  @override
  State<BluetoothDeviceManagerSheet> createState() => _BluetoothDeviceManagerSheetState();
}

class _BluetoothDeviceManagerSheetState extends State<BluetoothDeviceManagerSheet> {
  StreamSubscription? _hrStateSub;
  StreamSubscription? _hrValueSub;
  StreamSubscription? _treadmillStateSub;
  StreamSubscription? _treadmillStatusSub;
  StreamSubscription? _treadmillScanSub;
  StreamSubscription? _hrScanSub;

  BluetoothConnectionState _hrState = BluetoothConnectionState.disconnected;
  int _hrValue = 0;
  BluetoothConnectionState _treadmillState = BluetoothConnectionState.disconnected;
  TreadmillStatus? _treadmillStatus;
  bool _isTreadmillScanning = false;
  bool _isHrScanning = false;
  String _distanceUnitPref = 'km';

  Future<void> _loadDistanceUnitPref() async {
    try {
      final activeProfile = await DatabaseHelper.instance.getActiveProfileName();
      final db = await DatabaseHelper.instance.database;
      final profRes = await db.query('profiles', where: 'name = ?', whereArgs: [activeProfile], limit: 1);
      if (profRes.isNotEmpty && mounted) {
        setState(() {
          _distanceUnitPref = profRes.first['distance_unit_pref'] as String? ?? 'km';
        });
      }
    } catch (e) {
      debugPrint('Error loading distance unit in Bluetooth sheet: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _loadDistanceUnitPref();
    _hrState = AppBluetoothService.instance.isConnected ? BluetoothConnectionState.connected : BluetoothConnectionState.disconnected;
    _treadmillState = TreadmillBluetoothService.instance.connectionState;
    _treadmillStatus = TreadmillBluetoothService.instance.lastStatus;
    _isTreadmillScanning = TreadmillBluetoothService.instance.isScanning;

    _hrStateSub = AppBluetoothService.instance.deviceStateStream.listen((state) {
      if (mounted) setState(() => _hrState = state);
    });
    _hrValueSub = AppBluetoothService.instance.heartRateStream.listen((hr) {
      if (mounted) setState(() => _hrValue = hr);
    });

    _treadmillStateSub = TreadmillBluetoothService.instance.connectionStateStream.listen((state) {
      if (mounted) setState(() => _treadmillState = state);
    });
    _treadmillStatusSub = TreadmillBluetoothService.instance.statusStream.listen((status) {
      if (mounted) setState(() => _treadmillStatus = status);
    });
    _treadmillScanSub = TreadmillBluetoothService.instance.scanningStream.listen((scanning) {
      if (mounted) setState(() => _isTreadmillScanning = scanning);
    });

    _hrScanSub = FlutterBluePlus.isScanning.listen((scanning) {
      if (mounted) setState(() => _isHrScanning = scanning);
    });
  }

  @override
  void dispose() {
    _hrStateSub?.cancel();
    _hrValueSub?.cancel();
    _treadmillStateSub?.cancel();
    _treadmillStatusSub?.cancel();
    _treadmillScanSub?.cancel();
    _hrScanSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hrConnected = _hrState == BluetoothConnectionState.connected;
    final tmConnected = _treadmillState == BluetoothConnectionState.connected;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Device Connection Manager',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 24),
          
          // Card 1: Heart Rate Monitor
          Card(
            color: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: hrConnected 
                    ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)
                    : Colors.grey.withValues(alpha: 0.1),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.favorite,
                        color: hrConnected ? Colors.redAccent : Colors.grey,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Heart Rate Monitor',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              hrConnected 
                                  ? 'Connected (${_hrValue > 0 ? '$_hrValue BPM' : '-- BPM'})'
                                  : (_isHrScanning ? 'Scanning...' : 'Disconnected'),
                              style: TextStyle(
                                fontSize: 12,
                                color: hrConnected 
                                    ? Theme.of(context).colorScheme.primary 
                                    : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: hrConnected 
                              ? Theme.of(context).colorScheme.error.withValues(alpha: 0.15)
                              : Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                          foregroundColor: hrConnected 
                              ? Theme.of(context).colorScheme.error 
                              : Theme.of(context).colorScheme.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 0,
                        ),
                        onPressed: () {
                          if (hrConnected) {
                            AppBluetoothService.instance.disconnect();
                          } else {
                            AppBluetoothService.instance.startScanAndConnect();
                          }
                        },
                        child: Text(hrConnected ? 'Disconnect' : 'Connect'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          if (TreadmillBluetoothService.instance.treadmillEnabled) ...[
            const SizedBox(height: 16),

            // Card 2: Kingsmith Treadmill
            Card(
              color: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: tmConnected 
                      ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)
                      : Colors.grey.withValues(alpha: 0.1),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.directions_run,
                          color: tmConnected ? Theme.of(context).colorScheme.primary : Colors.grey,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'WalkingPad Treadmill',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                tmConnected 
                                    ? 'Connected'
                                    : (_isTreadmillScanning ? 'Scanning...' : 'Disconnected'),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: tmConnected 
                                      ? Theme.of(context).colorScheme.primary 
                                      : Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: tmConnected 
                                ? Theme.of(context).colorScheme.error.withValues(alpha: 0.15)
                                : Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                            foregroundColor: tmConnected 
                                ? Theme.of(context).colorScheme.error 
                                : Theme.of(context).colorScheme.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 0,
                          ),
                          onPressed: () {
                            if (tmConnected) {
                              TreadmillBluetoothService.instance.disconnect();
                            } else {
                              TreadmillBluetoothService.instance.startScan();
                            }
                          },
                          child: Text(tmConnected ? 'Disconnect' : 'Connect'),
                        ),
                      ],
                    ),
                    
                    if (tmConnected) ...[
                      const Divider(height: 24),
                      // Telemetry Grid
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Builder(
                            builder: (context) {
                              final bool isMetric = _distanceUnitPref == 'km';
                              final double rawSpeed = _treadmillStatus?.speed ?? 0.0;
                              final double displaySpeed = isMetric ? rawSpeed : rawSpeed * 0.621371;
                              final String speedUnit = isMetric ? 'km/h' : 'mph';
                              return _buildStatItem('Speed', '${displaySpeed.toStringAsFixed(1)} $speedUnit');
                            }
                          ),
                          Builder(
                            builder: (context) {
                              final bool isMetric = _distanceUnitPref == 'km';
                              final double rawDist = _treadmillStatus?.distance ?? 0.0;
                              final double displayDist = isMetric ? rawDist : rawDist * 0.621371;
                              final String distUnit = isMetric ? 'km' : 'mi';
                              return _buildStatItem('Distance', '${displayDist.toStringAsFixed(2)} $distUnit');
                            }
                          ),
                          _buildStatItem('Time', _formatDuration(_treadmillStatus?.time ?? 0)),
                          _buildStatItem('Steps', '${_treadmillStatus?.steps ?? 0}'),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      // Modes Selection Row (standby = 2, manual = 1, auto = 0)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildModeChip('Standby', 2),
                          const SizedBox(width: 8),
                          _buildModeChip('Manual', 1),
                          const SizedBox(width: 8),
                          _buildModeChip('Automatic', 0),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      // Controls Row (Speed up, Speed down, Start, Stop)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // Decrease Speed Button
                          IconButton.filledTonal(
                            icon: const Icon(Icons.remove),
                            onPressed: () {
                              if (_treadmillStatus != null) {
                                TreadmillBluetoothService.instance.setSpeed(_treadmillStatus!.speed - 0.5);
                              }
                            },
                          ),
                          
                          // Play/Pause Button
                          ElevatedButton.icon(
                            onPressed: () {
                              final state = _treadmillStatus?.beltState;
                              if (state == 1 || state == 2) {
                                TreadmillBluetoothService.instance.stop();
                              } else {
                                TreadmillBluetoothService.instance.start();
                              }
                            },
                            icon: Icon(
                              (_treadmillStatus?.beltState == 1 || _treadmillStatus?.beltState == 2)
                                  ? Icons.stop
                                  : Icons.play_arrow,
                            ),
                            label: Text(
                              (_treadmillStatus?.beltState == 1 || _treadmillStatus?.beltState == 2)
                                  ? 'Stop Belt'
                                  : 'Start Belt',
                            ),
                          ),
                          
                          // Increase Speed Button
                          IconButton.filledTonal(
                            icon: const Icon(Icons.add),
                            onPressed: () {
                              if (_treadmillStatus != null) {
                                TreadmillBluetoothService.instance.setSpeed(_treadmillStatus!.speed + 0.5);
                              }
                            },
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 12),
                      // Helper text for custom presets
                      Text(
                        'Tap to set speed • Long-press to edit preset',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 10,
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Presets Row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildPresetChip(0),
                          const SizedBox(width: 8),
                          _buildPresetChip(1),
                          const SizedBox(width: 8),
                          _buildPresetChip(2),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _editPresetSpeed(int index) async {
    final bool isMetric = _distanceUnitPref == 'km';
    final String speedUnit = isMetric ? 'km/h' : 'mph';

    final double minSpeed = isMetric ? 0.5 : 0.3;
    final double maxSpeed = isMetric ? 10.0 : 6.2;
    final int divSpeed = ((maxSpeed - minSpeed) / 0.1).round();

    final currentSpeed = TreadmillBluetoothService.instance.speedPresets[index];
    final double initialSpeed = isMetric ? currentSpeed : currentSpeed * 0.621371;
    double selectedSpeed = initialSpeed.clamp(minSpeed, maxSpeed);

    final newSpeed = await showDialog<double>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Customize Speed Preset'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Preset #${index + 1}: ${selectedSpeed.toStringAsFixed(1)} $speedUnit',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  Slider(
                    value: selectedSpeed,
                    min: minSpeed,
                    max: maxSpeed,
                    divisions: divSpeed,
                    label: '${selectedSpeed.toStringAsFixed(1)} $speedUnit',
                    onChanged: (val) {
                      setDialogState(() {
                        selectedSpeed = val;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, selectedSpeed),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (newSpeed != null && mounted) {
      final double newKmh = isMetric ? newSpeed : newSpeed * 1.60934;
      setState(() {
        TreadmillBluetoothService.instance.speedPresets[index] = double.parse(newKmh.toStringAsFixed(1));
      });
      // Persist to database active profile
      try {
        final activeProfile = await DatabaseHelper.instance.getActiveProfileName();
        final db = await DatabaseHelper.instance.database;
        await db.update(
          'profiles',
          {
            'treadmill_preset_1': TreadmillBluetoothService.instance.speedPresets[0],
            'treadmill_preset_2': TreadmillBluetoothService.instance.speedPresets[1],
            'treadmill_preset_3': TreadmillBluetoothService.instance.speedPresets[2],
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'name = ?',
          whereArgs: [activeProfile],
        );
        debugPrint("TreadmillService: Custom speed presets persisted to DB");
        SyncService.instance.signInAndSync();
      } catch (e) {
        debugPrint("TreadmillService: Error persisting custom speed presets to DB: $e");
      }
    }
  }

  Widget _buildPresetChip(int index) {
    final speed = TreadmillBluetoothService.instance.speedPresets[index];
    final bool isMetric = _distanceUnitPref == 'km';
    final double displaySpeed = isMetric ? speed : speed * 0.621371;
    final String speedUnit = isMetric ? 'km/h' : 'mph';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => TreadmillBluetoothService.instance.setSpeed(speed),
        onLongPress: () => _editPresetSpeed(index),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
            ),
          ),
          child: Text(
            '${displaySpeed.toStringAsFixed(1)} $speedUnit',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModeChip(String label, int mode) {
    final active = _treadmillStatus?.mode == mode;

    return ChoiceChip(
      label: Text(label),
      selected: active,
      onSelected: (selected) {
        if (selected) {
          TreadmillBluetoothService.instance.setMode(mode);
        }
      },
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  String _formatDuration(int seconds) {
    final int minutes = seconds ~/ 60;
    final int remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }
}

class PulsingHeart extends StatefulWidget {
  final bool isActive;
  const PulsingHeart({super.key, required this.isActive});

  @override
  State<PulsingHeart> createState() => _PulsingHeartState();
}

class _PulsingHeartState extends State<PulsingHeart> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _animation = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    if (widget.isActive) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant PulsingHeart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      if (widget.isActive) {
        _controller.repeat(reverse: true);
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: widget.isActive ? _animation : const AlwaysStoppedAnimation(1.0),
      child: Icon(
        Icons.favorite,
        color: widget.isActive ? Colors.redAccent : Colors.grey.withValues(alpha: 0.3),
        size: 36,
      ),
    );
  }
}

class _CustomizeWorkoutSheet extends StatefulWidget {
  final TimerScreenState timerState;

  const _CustomizeWorkoutSheet({required this.timerState});

  @override
  State<_CustomizeWorkoutSheet> createState() => _CustomizeWorkoutSheetState();
}

class _CustomizeWorkoutSheetState extends State<_CustomizeWorkoutSheet> {
  late final TextEditingController _weightController;
  late final TextEditingController _ruckWeightController;

  @override
  void initState() {
    super.initState();
    _weightController = TextEditingController(
      text: widget.timerState._weightMoved > 0 ? widget.timerState._weightMoved.toString() : '',
    );
    _ruckWeightController = TextEditingController(
      text: widget.timerState._ruckWeight > 0 ? widget.timerState._ruckWeight.toString() : '',
    );
  }

  @override
  void dispose() {
    _weightController.dispose();
    _ruckWeightController.dispose();
    super.dispose();
  }

  void _updateState(VoidCallback fn) {
    setState(fn);
    widget.timerState.setState(fn);
    if (widget.timerState._currentEvent.state == WorkoutState.FINISHED) {
      widget.timerState._resetToIdle();
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasTreadmill = TreadmillBluetoothService.instance.treadmillEnabled &&
        widget.timerState._treadmillWorkout;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        24,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Customize Workout',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.save),
                        label: const Text('Save Template'),
                        onPressed: widget.timerState._showSaveTemplateDialog,
                      ),
                    ],
                  ),
                  const Divider(),
                  // Work Duration Slider & Steppers
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Work Duration',
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                            Text(
                              widget.timerState._formatDuration(widget.timerState._workDuration),
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: () {
                              _updateState(() {
                                widget.timerState._workDuration = widget.timerState._decrementWorkDuration(widget.timerState._workDuration);
                              });
                            },
                          ),
                          Expanded(
                            child: Slider(
                              value: widget.timerState._secondsToSliderValue(widget.timerState._workDuration),
                              min: 0.0,
                              max: 1.0,
                              label: widget.timerState._formatDuration(widget.timerState._workDuration),
                              onChanged: (val) {
                                _updateState(() {
                                  widget.timerState._workDuration = widget.timerState._sliderValueToSeconds(val);
                                });
                              },
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: () {
                              _updateState(() {
                                widget.timerState._workDuration = widget.timerState._incrementWorkDuration(widget.timerState._workDuration);
                              });
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Rest Duration Slider & Steppers
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Rest Duration',
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                            Text(
                              widget.timerState._restDuration == 0 ? 'None' : widget.timerState._formatDuration(widget.timerState._restDuration),
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: () {
                              _updateState(() {
                                widget.timerState._restDuration = widget.timerState._decrementRestDuration(widget.timerState._restDuration);
                              });
                            },
                          ),
                          Expanded(
                            child: Slider(
                              value: widget.timerState._secondsToRestSliderValue(widget.timerState._restDuration),
                              min: 0.0,
                              max: 1.0,
                              label: widget.timerState._restDuration == 0 ? 'None' : widget.timerState._formatDuration(widget.timerState._restDuration),
                              onChanged: (val) {
                                _updateState(() {
                                  widget.timerState._restDuration = widget.timerState._sliderValueToRestSeconds(val);
                                });
                              },
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: () {
                              _updateState(() {
                                widget.timerState._restDuration = widget.timerState._incrementRestDuration(widget.timerState._restDuration);
                              });
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Rounds Slider & Steppers
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Rounds',
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                            Text(
                              '${widget.timerState._totalRounds}',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: () {
                              _updateState(() {
                                widget.timerState._totalRounds = (widget.timerState._totalRounds - 1).clamp(1, 50);
                              });
                            },
                          ),
                          Expanded(
                            child: Slider(
                              value: widget.timerState._totalRounds.toDouble(),
                              min: 1,
                              max: 50,
                              divisions: 49,
                              label: '${widget.timerState._totalRounds}',
                              onChanged: (val) {
                                _updateState(() {
                                  widget.timerState._totalRounds = val.toInt();
                                });
                              },
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: () {
                              _updateState(() {
                                widget.timerState._totalRounds = (widget.timerState._totalRounds + 1).clamp(1, 50);
                              });
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                  SwitchListTile(
                    title: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Auto Regulate Rest'),
                        const SizedBox(width: 4),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => widget.timerState._showHelpDialog(
                            'Auto Regulate Rest',
                            'Hold the rest phase countdown until your heart rate drops below your profile\'s configured threshold (currently ${widget.timerState._maxPreworkHr} BPM). Requires a connected heart rate monitor.',
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: Icon(
                              Icons.help_outline,
                              size: 16,
                              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                      ],
                    ),
                    value: widget.timerState._autoRegulationEnabled,
                    onChanged: widget.timerState._isBluetoothConnected
                        ? (val) => _updateState(() => widget.timerState._autoRegulationEnabled = val)
                        : null,
                  ),
                  SwitchListTile(
                    title: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Open Ended Workout'),
                        const SizedBox(width: 4),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => widget.timerState._showHelpDialog(
                            'Open Ended Workout',
                            'The workout will run indefinitely, incrementing rounds continuously until you manually tap the Stop/End button.',
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: Icon(
                              Icons.help_outline,
                              size: 16,
                              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                      ],
                    ),
                    value: widget.timerState._continuousMode,
                    onChanged: (val) => _updateState(() => widget.timerState._continuousMode = val),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Activity Type'),
                          const SizedBox(width: 4),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => widget.timerState._showHelpDialog(
                              'Activity Type',
                              'Select the exercise category. This value is used to categorize the workout when saving it to Apple Health.',
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(4.0),
                              child: Icon(
                               Icons.help_outline,
                               size: 16,
                               color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                        ],
                      ),
                      DropdownButton<String>(
                        value: widget.timerState._activityType,
                        items: const [
                          DropdownMenuItem(value: 'HIIT', child: Text('HIIT / Interval')),
                          DropdownMenuItem(value: 'STRENGTH', child: Text('Strength Training')),
                          DropdownMenuItem(value: 'FUNCTIONAL_STRENGTH', child: Text('Functional Strength')),
                          DropdownMenuItem(value: 'CORE', child: Text('Core Training')),
                          DropdownMenuItem(value: 'CARDIO', child: Text('Mixed Cardio')),
                          DropdownMenuItem(value: 'YOGA', child: Text('Yoga')),
                          DropdownMenuItem(value: 'PILATES', child: Text('Pilates')),
                          DropdownMenuItem(value: 'CALISTHENICS', child: Text('Calisthenics')),
                          DropdownMenuItem(value: 'OTHER', child: Text('Other')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            _updateState(() {
                              widget.timerState._activityType = val;
                            });
                          }
                        },
                      ),
                    ],
                  ),
                  const Divider(),
                  Builder(
                    builder: (context) {
                      final bool isStrength = const {'STRENGTH', 'FUNCTIONAL_STRENGTH', 'CALISTHENICS'}.contains(widget.timerState._activityType);
                      if (isStrength) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: TextField(
                                  controller: _weightController,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  decoration: const InputDecoration(
                                    labelText: 'Lifting Weight per Round',
                                    hintText: '0.0',
                                    border: OutlineInputBorder(),
                                  ),
                                  onChanged: (val) {
                                    _updateState(() {
                                      widget.timerState._weightMoved = double.tryParse(val) ?? 0.0;
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 2,
                                child: DropdownButtonFormField<String>(
                                  initialValue: widget.timerState._weightUnit,
                                  decoration: const InputDecoration(
                                    labelText: 'Unit',
                                    border: OutlineInputBorder(),
                                  ),
                                  items: const [
                                    DropdownMenuItem(value: 'kg', child: Text('kg')),
                                    DropdownMenuItem(value: 'lbs', child: Text('lbs')),
                                  ],
                                  onChanged: (val) {
                                    if (val != null) {
                                      _updateState(() {
                                        widget.timerState._weightUnit = val;
                                      });
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                        );
                      } else {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: TextField(
                                  controller: _ruckWeightController,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  decoration: const InputDecoration(
                                    labelText: 'Ruck / Vest Weight',
                                    hintText: '0.0',
                                    border: OutlineInputBorder(),
                                  ),
                                  onChanged: (val) {
                                    _updateState(() {
                                      widget.timerState._ruckWeight = double.tryParse(val) ?? 0.0;
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 2,
                                child: DropdownButtonFormField<String>(
                                  initialValue: widget.timerState._ruckWeightUnit,
                                  decoration: const InputDecoration(
                                    labelText: 'Unit',
                                    border: OutlineInputBorder(),
                                  ),
                                  items: const [
                                    DropdownMenuItem(value: 'kg', child: Text('kg')),
                                    DropdownMenuItem(value: 'lbs', child: Text('lbs')),
                                  ],
                                  onChanged: (val) {
                                    if (val != null) {
                                      _updateState(() {
                                        widget.timerState._ruckWeightUnit = val;
                                      });
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                    },
                  ),
                  if (hasTreadmill) ...[
                    const Divider(),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                        child: Text(
                          'WalkingPad Treadmill',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey),
                        ),
                      ),
                    ),
                    SwitchListTile(
                      title: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Auto Speed Sync'),
                          const SizedBox(width: 4),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => widget.timerState._showHelpDialog(
                              'Auto Speed Sync',
                              'Automatically controls the treadmill speed based on your workout interval. On WORK, it starts the belt and ramps up to Work Speed. On REST, it slows down to Rest Speed (or stops the belt). On PAUSE/END, it stops the belt.',
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(4.0),
                              child: Icon(
                                Icons.help_outline,
                                size: 16,
                                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                        ],
                      ),
                      subtitle: Text(
                        widget.timerState._treadmillConnectionState == BluetoothConnectionState.connected
                            ? 'Connected and ready'
                            : 'Treadmill not connected (auto-sync will activate upon connection)',
                        style: const TextStyle(fontSize: 12),
                      ),
                      value: TreadmillBluetoothService.instance.autoSpeedSync,
                      onChanged: (val) => _updateState(() {
                        TreadmillBluetoothService.instance.autoSpeedSync = val;
                      }),
                    ),
                    if (TreadmillBluetoothService.instance.autoSpeedSync) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                        child: Builder(
                          builder: (context) {
                            final bool isMetric = widget.timerState._distanceUnitPref == 'km';
                            final String speedUnit = isMetric ? 'km/h' : 'mph';

                            // Work Speed
                            final double rawWorkSpeed = TreadmillBluetoothService.instance.workSpeed;
                            final double displayWorkSpeed = isMetric ? rawWorkSpeed : rawWorkSpeed * 0.621371;
                            final double minWork = isMetric ? 0.5 : 0.3;
                            final double maxWork = isMetric ? 10.0 : 6.2;
                            final int divWork = ((maxWork - minWork) / 0.1).round();

                            // Rest Speed
                            final double rawRestSpeed = TreadmillBluetoothService.instance.restSpeed;
                            final double displayRestSpeed = isMetric ? rawRestSpeed : rawRestSpeed * 0.621371;
                            final double minRest = 0.0;
                            final double maxRest = isMetric ? 10.0 : 6.2;
                            final int divRest = ((maxRest - minRest) / 0.1).round();

                            // Clamp values to prevent Slider assertion failures due to precision differences
                            final double clampedWork = displayWorkSpeed.clamp(minWork, maxWork);
                            final double clampedRest = displayRestSpeed.clamp(minRest, maxRest);

                            return Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Work Phase Speed'),
                                    Text(
                                      '${clampedWork.toStringAsFixed(1)} $speedUnit',
                                      style: TextStyle(
                                        color: Theme.of(context).colorScheme.primary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                Slider(
                                  value: clampedWork,
                                  min: minWork,
                                  max: maxWork,
                                  divisions: divWork,
                                  label: '${clampedWork.toStringAsFixed(1)} $speedUnit',
                                  onChanged: (val) => _updateState(() {
                                    final double newKmh = isMetric ? val : val * 1.60934;
                                    TreadmillBluetoothService.instance.workSpeed = double.parse(newKmh.toStringAsFixed(1));
                                  }),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Rest Phase Speed'),
                                    Text(
                                      clampedRest == 0.0
                                          ? 'Stop (0.0 $speedUnit)'
                                          : '${clampedRest.toStringAsFixed(1)} $speedUnit',
                                      style: TextStyle(
                                        color: Theme.of(context).colorScheme.secondary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                Slider(
                                  value: clampedRest,
                                  min: minRest,
                                  max: maxRest,
                                  divisions: divRest,
                                  label: clampedRest == 0.0
                                      ? 'Stop'
                                      : '${clampedRest.toStringAsFixed(1)} $speedUnit',
                                  onChanged: (val) => _updateState(() {
                                    final double newKmh = isMetric ? val : val * 1.60934;
                                    TreadmillBluetoothService.instance.restSpeed = double.parse(newKmh.toStringAsFixed(1));
                                  }),
                                ),
                              ],
                            );
                          }
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 8),
                  TextField(
                    controller: widget.timerState._notesController,
                    decoration: const InputDecoration(
                      labelText: 'Workout Notes',
                      hintText: 'Enter notes for this workout...',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.note),
                    ),
                    maxLines: 2,
                    onChanged: (val) {
                      _updateState(() {});
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

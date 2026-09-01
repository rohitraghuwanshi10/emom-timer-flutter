import 'dart:async';
import 'dart:ui';
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
import '../services/hrr_service.dart';
import 'package:sqflite/sqflite.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/activity_type.dart';
import '../utils/format_utils.dart';
import '../utils/calorie_calculator.dart';
import '../widgets/profile_selector_capsule.dart';
import '../widgets/recovery_tracking_banner.dart';
import '../widgets/live_heart_rate_display.dart';
import '../widgets/bluetooth_device_modal.dart';
import '../widgets/customize_workout_sheet.dart';
import '../utils/responsive_utils.dart';

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
  int _repsPerRound = 1;
  int _repsCompleted = 0;

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
    final templateRepsPerRound = _loadedTemplate!['reps_per_round'] as int? ?? 1;

    final weightModified = _weightMoved != templateWeightMoved ||
        _weightUnit != templateWeightUnit ||
        _ruckWeight != templateRuckWeight ||
        _ruckWeightUnit != templateRuckWeightUnit ||
        _repsPerRound != templateRepsPerRound;

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

  Widget _buildRecoveryTrackingBanner() => const RecoveryTrackingBanner();

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
        _repsPerRound = template['reps_per_round'] as int? ?? 1;
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
    if (HrrService.instance.state.isTracking) {
      HrrService.instance.stopRecovery(finalize: true);
    }
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
          (event.timeRemaining >= 1 && event.timeRemaining <= 5)) {
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
    _repsCompleted = 0;
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

  String _calculateZone(int bpm) => CalorieCalculator.calculateZone(bpm, _maxHr);

  Widget _buildLiveHeartRateDisplay() => LiveHeartRateDisplay(currentHr: _currentHr, maxHr: _maxHr);

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

      final double caloriesBurnt = CalorieCalculator.calculateCaloriesBurnt(
        avgHr: avgHr,
        weightKg: _weightKg,
        totalTimeSec: totalTime,
        birthDateStr: _birthDate,
        sex: _sex,
      );

      final notes = _notesController.text;
      
      final workoutName = _loadedTemplateName != null
          ? (_isTemplateModified ? '$_loadedTemplateName (Modified)' : _loadedTemplateName)
          : null;

      double avgSpeed = _treadmillSpeeds.isNotEmpty
          ? (_treadmillSpeeds.reduce((a, b) => a + b) / _treadmillSpeeds.length)
          : 0.0;

      final bool isStrength = ActivityType.fromString(_activityType).isStrengthBased;
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
        repsPerRound: _repsPerRound,
        repsCompleted: _repsCompleted > 0 ? _repsCompleted : (completedRounds * _repsPerRound),
      );

      if (workoutId != null && (maxHr > 0 || _currentHr > 0)) {
        HrrService.instance.startRecovery(workoutId: workoutId, peakHr: maxHr);
      }
      
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

  String _getActivityName(String code) => ActivityType.fromString(code).label;

  Color _getActivityColor(String code) => ActivityType.fromString(code).color;

  String _formatDuration(int seconds) => FormatUtils.formatDurationConcise(seconds, zeroText: '0s');

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
    final hasTreadmill = TreadmillBluetoothService.instance.treadmillEnabled && _treadmillWorkout;
    ResponsiveUtils.showAdaptiveModal(
      context: context,
      child: CustomizeWorkoutSheet(
        workDuration: _workDuration,
        onWorkDurationChanged: (val) => setState(() {
          _workDuration = val;
          if (_currentEvent.state == WorkoutState.IDLE || _currentEvent.state == WorkoutState.FINISHED) {
            _currentEvent = WorkoutEvent(
              state: WorkoutState.IDLE,
              timeRemaining: val,
              currentRound: 0,
              totalRounds: _totalRounds,
              isWaitingForHr: false,
            );
          }
        }),
        restDuration: _restDuration,
        onRestDurationChanged: (val) => setState(() => _restDuration = val),
        totalRounds: _totalRounds,
        onTotalRoundsChanged: (val) => setState(() => _totalRounds = val),
        autoRegulationEnabled: _autoRegulationEnabled,
        onAutoRegulationChanged: _isBluetoothConnected ? (val) => setState(() => _autoRegulationEnabled = val) : null,
        maxPreworkHr: _maxPreworkHr,
        continuousMode: _continuousMode,
        onContinuousModeChanged: (val) => setState(() => _continuousMode = val),
        activityType: _activityType,
        onActivityTypeChanged: (val) => setState(() => _activityType = val),
        weightMoved: _weightMoved,
        onWeightMovedChanged: (val) => setState(() => _weightMoved = val),
        weightUnit: _weightUnit,
        onWeightUnitChanged: (val) => setState(() => _weightUnit = val),
        ruckWeight: _ruckWeight,
        onRuckWeightChanged: (val) => setState(() => _ruckWeight = val),
        ruckWeightUnit: _ruckWeightUnit,
        onRuckWeightUnitChanged: (val) => setState(() => _ruckWeightUnit = val),
        repsPerRound: _repsPerRound,
        onRepsPerRoundChanged: (val) => setState(() => _repsPerRound = val),
        repsCompleted: _repsCompleted,
        onRepsCompletedChanged: (val) => setState(() => _repsCompleted = val),
        notesController: _notesController,
        hasTreadmill: hasTreadmill,
        treadmillConnected: _treadmillConnectionState == BluetoothConnectionState.connected,
        distanceUnitPref: _distanceUnitPref,
        autoSpeedSync: TreadmillBluetoothService.instance.autoSpeedSync,
        onAutoSpeedSyncChanged: (val) => setState(() => TreadmillBluetoothService.instance.autoSpeedSync = val),
        workSpeed: TreadmillBluetoothService.instance.workSpeed,
        onWorkSpeedChanged: (val) => setState(() => TreadmillBluetoothService.instance.workSpeed = val),
        restSpeed: TreadmillBluetoothService.instance.restSpeed,
        onRestSpeedChanged: (val) => setState(() => TreadmillBluetoothService.instance.restSpeed = val),
        onSaveTemplate: _showSaveTemplateDialog,
        onHelpRequested: _showHelpDialog,
      ),
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

    final bool useWide = context.useWideLayout;
    final size = MediaQuery.of(context).size;
    final double timerSize = customSize ?? (useWide
        ? (size.height * 0.58).clamp(240.0, 520.0)
        : (size.width * 0.82).clamp(220.0, 520.0));
    
    final double timeFontSize = timerSize * 0.28;
    final double stateFontSize = (timerSize * 0.085).clamp(16.0, 42.0);
    final double roundFontSize = (timerSize * 0.065).clamp(13.0, 32.0);
    final double strokeWidth = (timerSize * 0.045).clamp(12.0, 22.0);

    final String timeStr = _currentEvent.state == WorkoutState.IDLE 
        ? '${(_workDuration ~/ 60).toString().padLeft(2, '0')}:${(_workDuration % 60).toString().padLeft(2, '0')}' 
        : '${(_currentEvent.timeRemaining ~/ 60).toString().padLeft(2, '0')}:${(_currentEvent.timeRemaining % 60).toString().padLeft(2, '0')}';

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
              strokeCap: StrokeCap.round,
              backgroundColor: stateColor.withValues(alpha: 0.18),
              valueColor: AlwaysStoppedAnimation<Color>(stateColor),
            ),
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  stateText,
                  style: TextStyle(
                    color: stateColor,
                    fontSize: stateFontSize,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3.5,
                  ),
                ),
                SizedBox(height: timerSize * 0.02),
                Text(
                  timeStr,
                  style: TextStyle(
                    fontSize: timeFontSize,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.0,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: Colors.white,
                  ),
                ),
                if (_currentEvent.state != WorkoutState.IDLE && _currentEvent.state != WorkoutState.FINISHED) ...[
                  SizedBox(height: timerSize * 0.015),
                  Text(
                    'ROUND ${_currentEvent.currentRound} / ${_continuousMode ? '∞' : _currentEvent.totalRounds}',
                    style: TextStyle(
                      fontSize: roundFontSize,
                      fontWeight: FontWeight.w700,
                      color: Colors.white70,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileSelectorAction(bool isEnabled) {
    return ProfileSelectorCapsule(
      currentProfile: _profileName,
      availableProfiles: _availableProfiles,
      onProfileSelected: _onProfileChanged,
      isEnabled: isEnabled,
    );
  }

  Widget? _buildLoadedTemplateBadge(bool isIdle) {
    if (_loadedTemplateName == null) return null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
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
          Flexible(
            child: Text(
              _loadedTemplateName! + (_isTemplateModified ? ' (Modified)' : ''),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          if (isIdle) ...[
            if (_isTemplateModified) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  if (_loadedTemplate != null) {
                    loadTemplate(_loadedTemplate!);
                  }
                },
                child: Icon(
                  Icons.undo,
                  size: 14,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
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
        ],
      ),
    );
  }

  Widget _buildLiveWorkoutDashboard() {
    final bool isTreadmill = TreadmillBluetoothService.instance.treadmillEnabled && _treadmillWorkout;
    final bool isStrength = ActivityType.fromString(_activityType).isStrengthBased;
    
    // Live metrics calculations
    int peakHr = 0;
    int avgHr = 0;
    if (_hrDetails.isNotEmpty) {
      final bpms = _hrDetails.map((x) => x['bpm'] as int).toList();
      peakHr = bpms.reduce((a, b) => a > b ? a : b);
      avgHr = (bpms.reduce((a, b) => a + b) / bpms.length).round();
    } else if (_currentHr > 0) {
      peakHr = _currentHr;
      avgHr = _currentHr;
    }

    final int elapsedSec = _workoutStartTime != null
        ? DateTime.now().difference(_workoutStartTime!).inSeconds
        : ((_engine?.workTimeSec ?? 0) + (_engine?.restTimeSec ?? 0));

    final double caloriesBurnt = CalorieCalculator.calculateCaloriesBurnt(
      avgHr: avgHr > 0 ? avgHr : (_currentHr > 0 ? _currentHr : 120),
      weightKg: _weightKg,
      totalTimeSec: elapsedSec,
      birthDateStr: _birthDate,
      sex: _sex,
    );

    final double kcalPerMin = elapsedSec > 30 ? (caloriesBurnt / (elapsedSec / 60.0)) : 0.0;
    final currentRnd = _currentEvent.currentRound.clamp(1, _totalRounds > 0 ? _totalRounds : 999);
    final double accumVolume = isStrength ? (currentRnd * _repsPerRound * _weightMoved) : 0.0;

    // Up next determination
    String upNextLabel;
    IconData upNextIcon;
    Color upNextColor;
    if (_currentEvent.state == WorkoutState.PREP) {
      upNextLabel = 'Round 1 Work (${_formatDuration(_workDuration)})';
      upNextIcon = Icons.fitness_center;
      upNextColor = Theme.of(context).colorScheme.secondary;
    } else if (_currentEvent.state == WorkoutState.WORK) {
      if (_currentEvent.currentRound >= _totalRounds && !_continuousMode) {
        upNextLabel = 'Workout Complete 🎉';
        upNextIcon = Icons.emoji_events;
        upNextColor = Colors.amber;
      } else {
        upNextLabel = 'Round ${_currentEvent.currentRound} Rest (${_restDuration == 0 ? 'None' : _formatDuration(_restDuration)})';
        upNextIcon = Icons.coffee;
        upNextColor = Theme.of(context).colorScheme.primary;
      }
    } else if (_currentEvent.state == WorkoutState.REST) {
      upNextLabel = 'Round ${_currentEvent.currentRound + 1} Work (${_formatDuration(_workDuration)})';
      upNextIcon = Icons.fitness_center;
      upNextColor = Theme.of(context).colorScheme.secondary;
    } else {
      upNextLabel = 'Workout in Progress';
      upNextIcon = Icons.timer;
      upNextColor = Colors.grey;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Header: Activity Type, Template Name & "Up Next" Card
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getActivityColor(_activityType).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _getActivityColor(_activityType).withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.fitness_center, size: 13, color: _getActivityColor(_activityType)),
                        const SizedBox(width: 5),
                        Text(
                          _getActivityName(_activityType),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _getActivityColor(_activityType),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_loadedTemplateName != null)
                    Expanded(
                      child: Text(
                        _loadedTemplateName!,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  const Spacer(),
                  // Elapsed time pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.timer_outlined, size: 13, color: Colors.grey),
                        const SizedBox(width: 5),
                        Text(
                          'Elapsed: ${_formatDuration(elapsedSec)}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1, color: Colors.white12),
              const SizedBox(height: 12),
              // Up Next Row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: upNextColor.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(upNextIcon, size: 16, color: upNextColor),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'UP NEXT',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                          color: upNextColor,
                        ),
                      ),
                      Text(
                        upNextLabel,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 2. Segmented Round Tracker
        _buildLiveRoundTracker(),
        const SizedBox(height: 14),

        // 3. Live Telemetry 2x2 Grid
        _buildLiveTelemetryGrid(
          peakHr: peakHr,
          avgHr: avgHr,
          caloriesBurnt: caloriesBurnt,
          kcalPerMin: kcalPerMin,
          elapsedSec: elapsedSec,
          isStrength: isStrength,
          accumVolume: accumVolume,
        ),

        // 4. Live Treadmill Telemetry (if connected)
        if (isTreadmill) ...[
          const SizedBox(height: 14),
          _buildLiveTreadmillTelemetry(),
        ],

        // 5. Notes / Cues (if available)
        if (_notesController.text.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.tips_and_updates_outlined, size: 16, color: Colors.amber),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'WORKOUT CUES & NOTES',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2, color: Colors.amber),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _notesController.text,
                        style: const TextStyle(fontSize: 13, color: Colors.white70, height: 1.3),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildLiveRoundTracker() {
    final current = _currentEvent.currentRound;
    final total = _totalRounds;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'ROUND PROGRESSION',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: Colors.grey.shade400,
                ),
              ),
              Text(
                _continuousMode ? 'Round $current (Open-Ended)' : 'Round $current of $total',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!_continuousMode && total <= 24)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(total, (index) {
                final roundNum = index + 1;
                final bool isCompleted = roundNum < current;
                final bool isCurrent = roundNum == current;

                Color bgColor;
                Color borderColor;
                Color textColor;

                if (isCompleted) {
                  bgColor = Theme.of(context).colorScheme.primary.withValues(alpha: 0.2);
                  borderColor = Theme.of(context).colorScheme.primary;
                  textColor = Theme.of(context).colorScheme.primary;
                } else if (isCurrent) {
                  bgColor = Theme.of(context).colorScheme.secondary.withValues(alpha: 0.25);
                  borderColor = Theme.of(context).colorScheme.secondary;
                  textColor = Theme.of(context).colorScheme.secondary;
                } else {
                  bgColor = Colors.white.withValues(alpha: 0.04);
                  borderColor = Colors.white12;
                  textColor = Colors.white38;
                }

                return Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: borderColor, width: isCurrent ? 2 : 1),
                  ),
                  alignment: Alignment.center,
                  child: isCompleted
                      ? Icon(Icons.check, size: 16, color: textColor)
                      : Text(
                          '$roundNum',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isCurrent ? FontWeight.w900 : FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                );
              }),
            )
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: _continuousMode
                    ? null
                    : (total > 0 ? (current / total).clamp(0.0, 1.0) : 0.0),
                minHeight: 12,
                backgroundColor: Colors.white10,
                valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLiveTelemetryGrid({
    required int peakHr,
    required int avgHr,
    required double caloriesBurnt,
    required double kcalPerMin,
    required int elapsedSec,
    required bool isStrength,
    required double accumVolume,
  }) {
    final bool hasHr = _currentHr > 0 || avgHr > 0;
    final String currentZone = _currentHr > 0 ? _calculateZone(_currentHr) : '';
    final Color zoneColor = _currentHr > 0 ? CalorieCalculator.getZoneColor(currentZone) : Colors.grey;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Column 1: Heart Rate & Calories
        Expanded(
          child: Column(
            children: [
              _buildLiveMetricTile(
                title: 'HEART RATE',
                icon: Icons.favorite,
                iconColor: hasHr ? Colors.redAccent : Colors.grey,
                mainValue: hasHr ? '$_currentHr BPM' : '-- BPM',
                subValue: currentZone.isNotEmpty ? currentZone : 'No Monitor',
                subValueColor: zoneColor,
                detailText: hasHr ? 'Peak: $peakHr • Avg: $avgHr BPM' : 'Connect HR Monitor',
              ),
              const SizedBox(height: 12),
              _buildLiveMetricTile(
                title: 'ENERGY BURNED',
                icon: Icons.local_fire_department,
                iconColor: Colors.orangeAccent,
                mainValue: '${caloriesBurnt.toStringAsFixed(0)} kcal',
                subValue: kcalPerMin > 0 ? '${kcalPerMin.toStringAsFixed(1)} kcal/min' : 'Active Calorie Burn',
                subValueColor: Colors.orangeAccent,
                detailText: 'Based on biometric profile',
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // Column 2: Work/Rest Breakdown & Volume/Reps
        Expanded(
          child: Column(
            children: [
              _buildLiveMetricTile(
                title: 'WORK / REST SPLIT',
                icon: Icons.pie_chart_outline,
                iconColor: Theme.of(context).colorScheme.primary,
                mainValue: 'Work: ${_formatDuration(_workDuration)}',
                subValue: 'Rest: ${_restDuration == 0 ? 'None' : _formatDuration(_restDuration)}',
                subValueColor: Theme.of(context).colorScheme.secondary,
                detailText: _autoRegulationEnabled ? 'Auto-Regulated (< $_maxPreworkHr BPM)' : 'Fixed Interval EMOM',
              ),
              const SizedBox(height: 12),
              _buildLiveMetricTile(
                title: isStrength ? 'VOLUME & LOAD' : (_ruckWeight > 0 ? 'RUCK WEIGHT' : 'TARGET REPS'),
                icon: Icons.fitness_center,
                iconColor: const Color(0xFF00E5FF),
                mainValue: isStrength
                    ? '${_weightMoved.toStringAsFixed(1)} $_weightUnit'
                    : (_ruckWeight > 0 ? '${_ruckWeight.toStringAsFixed(1)} $_ruckWeightUnit' : '$_repsPerRound reps/rnd'),
                subValue: isStrength
                    ? 'Total Vol: ${accumVolume.toStringAsFixed(0)} $_weightUnit'
                    : (_ruckWeight > 0 ? '$_repsPerRound reps per round' : 'Target: ${_totalRounds * _repsPerRound} reps'),
                subValueColor: const Color(0xFF00E5FF),
                detailText: 'Activity: $_activityType',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLiveMetricTile({
    required String title,
    required IconData icon,
    required Color iconColor,
    required String mainValue,
    required String subValue,
    required Color subValueColor,
    required String detailText,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: iconColor),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                  color: Colors.grey.shade400,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            mainValue,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subValue,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: subValueColor,
            ),
          ),
          const SizedBox(height: 6),
          const Divider(height: 1, color: Colors.white10),
          const SizedBox(height: 6),
          Text(
            detailText,
            style: const TextStyle(
              fontSize: 10,
              color: Colors.grey,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isIdle = _currentEvent.state == WorkoutState.IDLE || _currentEvent.state == WorkoutState.FINISHED;
    final bool useWide = context.useWideLayout;
    final bool hideAppBar = context.isPhoneLandscape;
    final bool showTreadmillStop = !isIdle &&
        TreadmillBluetoothService.instance.treadmillEnabled &&
        _treadmillWorkout &&
        _treadmillConnectionState == BluetoothConnectionState.connected;

    return Scaffold(
      appBar: hideAppBar
          ? null
          : AppBar(
              centerTitle: true,
              title: _buildLoadedTemplateBadge(isIdle),
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
      body: useWide
          ? SafeArea(
              top: true,
              bottom: false,
              left: true,
              right: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Left Pane: High-Visibility Timer Circle, Action Buttons, and Live HR Display
                  Expanded(
                    flex: 6,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final availableHeight = constraints.maxHeight;
                        final availableWidth = constraints.maxWidth;
                        // Dynamically scale timer size up to 520px while fitting the available pane bounds
                        final timerSize = (availableHeight * 0.58)
                            .clamp(240.0, 520.0)
                            .clamp(0.0, availableWidth * 0.85);

                        return Center(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                _buildTimerDisplay(customSize: timerSize),
                                const SizedBox(height: 20),
                                _buildInlineControls(isIdle, showTreadmillStop),
                                const SizedBox(height: 16),
                                _buildLiveHeartRateDisplay(),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  // Divider
                  VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.15),
                  ),
                  // Right Pane: Telemetry Dashboard during workout, or Template/Summary during Idle
                  Expanded(
                    flex: 6,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 750),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          child: isIdle
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    if (_loadedTemplateName != null) ...[
                                      Center(child: _buildLoadedTemplateBadge(isIdle)!),
                                      const SizedBox(height: 12),
                                    ],
                                    _buildRecoveryTrackingBanner(),
                                    const SizedBox(height: 8),
                                    _buildLiveTreadmillTelemetry(),
                                    const SizedBox(height: 8),
                                    _buildWorkoutSummaryCard(),
                                  ],
                                )
                              : _buildLiveWorkoutDashboard(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(height: 16),
                      _buildTimerDisplay(),
                      const SizedBox(height: 24),
                      _buildLiveHeartRateDisplay(),
                      _buildRecoveryTrackingBanner(),
                      const SizedBox(height: 24),
                      _buildLiveTreadmillTelemetry(),
                      const SizedBox(height: 24),
                      if (isIdle) _buildWorkoutSummaryCard(),
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
              ),
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: useWide
          ? null
          : (isIdle
              ? FloatingActionButton.extended(
                  heroTag: 'start_btn',
                  onPressed: _startWorkout,
                  backgroundColor: Theme.of(context).colorScheme.secondary,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start'),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FloatingActionButton.extended(
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
                      FloatingActionButton.extended(
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
                    FloatingActionButton.extended(
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
    final bool isLandscape = context.useWideLayout;
    if (isIdle) {
      return ElevatedButton.icon(
        onPressed: _startWorkout,
        style: ElevatedButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.secondary,
          foregroundColor: Theme.of(context).colorScheme.onSecondary,
          padding: EdgeInsets.symmetric(
            horizontal: isLandscape ? 32 : 20,
            vertical: isLandscape ? 16 : 12,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: Icon(Icons.play_arrow, size: isLandscape ? 22 : 18),
        label: Text(
          'Start',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: isLandscape ? 15 : 14,
          ),
        ),
      );
    }

    return Wrap(
      spacing: isLandscape ? 12 : 8,
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
            padding: EdgeInsets.symmetric(
              horizontal: isLandscape ? 20 : 12,
              vertical: isLandscape ? 14 : 8,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          icon: Icon(
            _currentEvent.state == WorkoutState.PAUSED ? Icons.play_arrow : Icons.pause,
            size: isLandscape ? 18 : 14,
          ),
          label: Text(
            _currentEvent.state == WorkoutState.PAUSED ? 'Resume' : 'Pause',
            style: TextStyle(
              fontSize: isLandscape ? 13 : 11,
              fontWeight: FontWeight.bold,
            ),
          ),
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
              padding: EdgeInsets.symmetric(
                horizontal: isLandscape ? 16 : 10,
                vertical: isLandscape ? 14 : 8,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: Icon(
              Icons.pan_tool,
              size: isLandscape ? 16 : 12,
              color: Colors.white,
            ),
            label: Text(
              'STOP TM',
              style: TextStyle(
                color: Colors.white,
                fontSize: isLandscape ? 13 : 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ElevatedButton.icon(
          onPressed: _stopWorkout,
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Colors.white,
            padding: EdgeInsets.symmetric(
              horizontal: isLandscape ? 20 : 12,
              vertical: isLandscape ? 14 : 8,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          icon: Icon(Icons.stop, size: isLandscape ? 18 : 14),
          label: Text(
            'End',
            style: TextStyle(
              fontSize: isLandscape ? 13 : 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  void _showBluetoothDeviceManager() {
    ResponsiveUtils.showAdaptiveModal(
      context: context,
      child: const BluetoothDeviceManagerSheet(),
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

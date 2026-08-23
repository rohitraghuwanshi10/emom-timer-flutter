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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return CustomizeWorkoutSheet(
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
        );
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
                            Center(child: _buildLoadedTemplateBadge(isIdle)!),
                            const SizedBox(height: 12),
                          ],
                          _buildLiveHeartRateDisplay(),
                          _buildRecoveryTrackingBanner(),
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
                        // Dynamically size timer circle to fit height nicely (leave ~90px for spacing/controls)
                        final timerSize = (availableHeight - 90).clamp(140.0, 260.0);

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
                    _buildTimerDisplay(),
                    const SizedBox(height: 24),
                    _buildLiveHeartRateDisplay(),
                    _buildRecoveryTrackingBanner(),
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
    final bool isLandscape = MediaQuery.of(context).orientation == Orientation.landscape && MediaQuery.of(context).size.height < 500;
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

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/workout_engine.dart';
import '../services/bluetooth_service.dart';
import '../services/audio_service.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../services/health_service.dart';
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
  StreamSubscription? _btStateSubscription;
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
  String _activityType = 'HIIT';
  
  // Cache variables for calorie/zone calculations
  int _maxHr = 180;
  String? _birthDate;
  String? _sex;
  double _weightKg = 70.0;
  bool _healthEnabled = false;

  // Session data
  List<Map<String, dynamic>> _hrDetails = [];
  DateTime? _workoutStartTime;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(vsync: this);
    AudioService.instance; // Force lazy-init to eagerly preload audio assets
    loadProfileSettings();
    _setupBluetooth();
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
            
            // Auto-check if Bluetooth is connected and maxPreworkHr is configured
            if (_isBluetoothConnected) {
              _autoRegulationEnabled = _maxPreworkHr > 0;
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

  void _setupBluetooth() {
    _isBluetoothConnected = AppBluetoothService.instance.isConnected;
    _btStateSubscription = AppBluetoothService.instance.deviceStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isBluetoothConnected = state == BluetoothConnectionState.connected;
          if (_isBluetoothConnected) {
            _autoRegulationEnabled = _maxPreworkHr > 0;
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
  }

  void _startWorkout() {
    if (_engine != null && _currentEvent.state != WorkoutState.IDLE && _currentEvent.state != WorkoutState.FINISHED) return;

    WakelockPlus.enable(); // Keep screen awake during active workout
    _engine?.dispose(); // clean up any old engine
    _workoutSubscription?.cancel();

    _hrDetails = [];
    _workoutStartTime = DateTime.now();

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
      }
      
      // Play sounds on transitions
      if (event.timeRemaining == _workDuration && event.state == WorkoutState.WORK) {
        AudioService.instance.playWorkChime();
      } else if (event.timeRemaining == _restDuration && event.state == WorkoutState.REST) {
        AudioService.instance.playRestChime();
      } else if (event.timeRemaining == 10 && event.state == WorkoutState.PREP) {
        AudioService.instance.playWorkChime(); // Play 'Work' sound for PREP
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
    _btStateSubscription?.cancel();
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
      
      final workoutId = await DatabaseHelper.instance.saveWorkout(
        profileName: _profileName,
        workoutName: _loadedTemplateName,
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
      );
      
      debugPrint("TimerScreen: _healthEnabled is $_healthEnabled");
      if (_healthEnabled) {
        HealthService.instance.saveWorkout(
          start: _workoutStartTime!,
          end: endTime,
          totalCalories: caloriesBurnt.round(),
          title: _loadedTemplateName ?? 'EMOM Workout',
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
                  await db.insert('workout_templates', {
                    'profile_name': _profileName,
                    'template_name': controller.text,
                    'rounds': _totalRounds,
                    'work_time': _workDuration,
                    'rest_time': _restDuration,
                    'notes': _notesController.text,
                    'continuous_mode': _continuousMode ? 1 : 0,
                    'activity_type': _activityType,
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

  Future<void> _showLoadTemplateDialog() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final templates = await db.query('workout_templates', where: 'profile_name = ?', whereArgs: [_profileName]);
      
      if (mounted) {
        showModalBottomSheet(
          context: context,
          builder: (context) => templates.isEmpty 
            ? const Padding(padding: EdgeInsets.all(32), child: Text('No workouts saved for this profile.'))
            : ListView.builder(
            itemCount: templates.length,
            itemBuilder: (context, index) {
              final t = templates[index];
              return ListTile(
                leading: const Icon(Icons.timer),
                title: Text(t['template_name'] as String),
                subtitle: Text("${t['rounds']} rounds • ${t['work_time']}s / ${t['rest_time']}s"),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () async {
                    await db.delete('workout_templates', where: 'id = ?', whereArgs: [t['id']]);
                    if (context.mounted) {
                      Navigator.pop(context); // Close the sheet to refresh
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Template deleted')));
                    }
                  },
                ),
                onTap: () {
                  setState(() {
                    _totalRounds = t['rounds'] as int;
                    _workDuration = t['work_time'] as int;
                    _restDuration = t['rest_time'] as int;
                    _notesController.text = t['notes'] as String? ?? '';
                    _continuousMode = (t['continuous_mode'] as int? ?? 0) == 1;
                    _activityType = t['activity_type'] as String? ?? 'HIIT';
                    _loadedTemplateName = t['template_name'] as String?;
                  });
                  if (_currentEvent.state == WorkoutState.FINISHED) _resetToIdle();
                  Navigator.pop(context);
                },
              );
            },
          ),
        );
      }
    } catch (e) {
      debugPrint('Error loading templates: \$e');
    }
  }

  Widget _buildConfigPanel() {
    return Card(
      color: Theme.of(context).colorScheme.surface,
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Select Workout'),
                  onPressed: _showLoadTemplateDialog,
                ),
                TextButton.icon(
                  icon: const Icon(Icons.save),
                  label: const Text('Save'),
                  onPressed: _showSaveTemplateDialog,
                ),
              ],
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Work (s)'),
                Expanded(
                  child: Slider(
                    value: _workDuration.toDouble(),
                    min: 10,
                    max: 3600,
                    divisions: 359,
                    label: '$_workDuration s',
                    onChanged: (val) {
                      setState(() {
                        _workDuration = val.toInt();
                      });
                      if (_currentEvent.state == WorkoutState.FINISHED) _resetToIdle();
                    },
                  ),
                ),
                Text('$_workDuration'),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Rest (s)'),
                Expanded(
                  child: Slider(
                    value: _restDuration.toDouble(),
                    min: 0,
                    max: 120,
                    divisions: 24,
                    label: '$_restDuration s',
                    onChanged: (val) {
                      setState(() {
                        _restDuration = val.toInt();
                      });
                      if (_currentEvent.state == WorkoutState.FINISHED) _resetToIdle();
                    },
                  ),
                ),
                Text('$_restDuration'),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Rounds'),
                Expanded(
                  child: Slider(
                    value: _totalRounds.toDouble(),
                    min: 1,
                    max: 50,
                    divisions: 49,
                    label: '$_totalRounds',
                    onChanged: (val) {
                      setState(() {
                        _totalRounds = val.toInt();
                      });
                      if (_currentEvent.state == WorkoutState.FINISHED) _resetToIdle();
                    },
                  ),
                ),
                Text('$_totalRounds'),
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
                    onTap: () => _showHelpDialog(
                      'Auto Regulate Rest',
                      'Hold the rest phase countdown until your heart rate drops below your profile\'s configured threshold (currently $_maxPreworkHr BPM). Requires a connected heart rate monitor.',
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
              value: _autoRegulationEnabled,
              onChanged: _isBluetoothConnected
                  ? (val) => setState(() => _autoRegulationEnabled = val)
                  : null,
            ),
            SwitchListTile(
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Continuous Workout'),
                  const SizedBox(width: 4),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _showHelpDialog(
                      'Continuous Workout',
                      'Workout runs indefinitely, incrementing rounds continuously until you manually tap the Stop/End button.',
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
              value: _continuousMode,
              onChanged: (val) => setState(() => _continuousMode = val),
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
                      onTap: () => _showHelpDialog(
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
                  value: _activityType,
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
                      setState(() {
                        _activityType = val;
                      });
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Workout Notes',
                hintText: 'Enter notes for this workout...',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.note),
              ),
              maxLines: 2,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimerDisplay() {
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

    final size = MediaQuery.of(context).size;
    // Base size off the smaller dimension, capped between 200px and 600px
    final double rawSize = size.width < size.height ? size.width * 0.8 : size.height * 0.6;
    final double timerSize = rawSize.clamp(200.0, 600.0);
    
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

  Widget _buildProfileSelector(bool isIdle) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.person,
            size: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _availableProfiles.isEmpty
                ? Text(
                    _profileName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  )
                : DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _profileName,
                      isExpanded: true,
                      isDense: true,
                      dropdownColor: Theme.of(context).colorScheme.surface,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        fontSize: 14,
                      ),
                      items: _availableProfiles.map((p) {
                        return DropdownMenuItem(value: p, child: Text(p));
                      }).toList(),
                      onChanged: isIdle
                          ? (val) async {
                              if (val != null) {
                                await _onProfileChanged(val);
                              }
                            }
                          : null,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isIdle = _currentEvent.state == WorkoutState.IDLE || _currentEvent.state == WorkoutState.FINISHED;
    final bool isNarrow = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ChronoPulse Active'),
        actions: [
          IconButton(
            icon: Icon(
              _isBluetoothConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
              color: _isBluetoothConnected ? Theme.of(context).colorScheme.primary : Colors.grey,
            ),
            onPressed: () {
              if (!_isBluetoothConnected) {
                AppBluetoothService.instance.startScanAndConnect();
              } else {
                AppBluetoothService.instance.disconnect();
              }
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Center(
              child: Text(
                '$_currentHr BPM',
                style: TextStyle(
                  color: _currentHr > 0 ? Theme.of(context).colorScheme.error : Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          )
        ],
      ),
      body: SingleChildScrollView(
        child: SizedBox(
          width: MediaQuery.of(context).size.width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 8),
              _buildProfileSelector(isIdle),
              const SizedBox(height: 16),
              if (_loadedTemplateName != null) ...[
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
                        _loadedTemplateName!,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      if (isIdle) ...[
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _loadedTemplateName = null;
                            });
                          },
                          child: const Icon(
                            Icons.cancel_outlined,
                            size: 16,
                            color: Colors.redAccent,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              _buildTimerDisplay(),
              const SizedBox(height: 24),
              _buildLiveHeartRateDisplay(),
              const SizedBox(height: 24),
              if (isIdle) _buildConfigPanel(),
            ],
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: isIdle
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
            ),
    );
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

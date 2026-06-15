import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/workout_engine.dart';
import '../services/bluetooth_service.dart';
import '../services/audio_service.dart';
import '../services/database_helper.dart';
import 'package:sqflite/sqflite.dart';

class TimerScreen extends StatefulWidget {
  const TimerScreen({Key? key}) : super(key: key);

  @override
  State<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends State<TimerScreen> with SingleTickerProviderStateMixin {
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
  
  int _currentHr = 0;
  bool _isBluetoothConnected = false;

  WorkoutEvent _currentEvent = WorkoutEvent(
    state: WorkoutState.IDLE,
    timeRemaining: 0,
    currentRound: 0,
    totalRounds: 0,
    isWaitingForHr: false,
  );

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(vsync: this);
    AudioService.instance; // Force lazy-init to eagerly preload audio assets
    _loadProfileSettings();
    _setupBluetooth();
  }

  Future<void> _loadProfileSettings() async {
    try {
      final activeProfile = await DatabaseHelper.instance.getActiveProfileName();
      final db = await DatabaseHelper.instance.database;
      final results = await db.query('profiles', where: 'name = ?', whereArgs: [activeProfile], limit: 1);
      if (results.isNotEmpty) {
        final profile = results.first;
        if (mounted) {
          setState(() {
            _maxPreworkHr = profile['max_prework_hr'] as int? ?? 130;
            _profileName = activeProfile;
          });
        }
      }
    } catch (e) {
      print('Error loading profile in timer: \$e');
    }
  }

  void _setupBluetooth() {
    _btStateSubscription = AppBluetoothService.instance.deviceStateStream.listen((state) {
      setState(() {
        _isBluetoothConnected = state == BluetoothConnectionState.connected;
      });
    });

    _hrSubscription = AppBluetoothService.instance.heartRateStream.listen((hr) {
      setState(() => _currentHr = hr);
      _engine?.updateHeartRate(hr);
    });
  }

  void _startWorkout() {
    if (_engine != null && _currentEvent.state != WorkoutState.IDLE && _currentEvent.state != WorkoutState.FINISHED) return;

    _engine?.dispose(); // clean up any old engine
    _workoutSubscription?.cancel();

    _engine = WorkoutEngine(
      totalRounds: _totalRounds,
      workDuration: _workDuration,
      baseRestDuration: _restDuration,
      autoRegulationEnabled: _autoRegulationEnabled,
      maxPreworkHr: _maxPreworkHr,
    );

    _workoutSubscription = _engine!.workoutStream.listen((event) {
      setState(() {
        _currentEvent = event;
      });
      
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
    _engine?.stop();
    _workoutSubscription?.cancel();
    _resetToIdle();
  }

  void _resetToIdle() {
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
    _progressController.dispose();
    _workoutSubscription?.cancel();
    _hrSubscription?.cancel();
    _btStateSubscription?.cancel();
    _engine?.dispose();
    super.dispose();
  }

  Future<void> _showSaveTemplateDialog() async {
    final controller = TextEditingController();
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
                  }, conflictAlgorithm: ConflictAlgorithm.replace);
                  if (mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Template saved')));
                  }
                } catch (e) {
                  print('Error saving template: \$e');
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
            ? const Padding(padding: EdgeInsets.all(32), child: Text('No templates saved for this profile.'))
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
                    if (mounted) {
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
      print('Error loading templates: \$e');
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
                  label: const Text('Load Template'),
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
                    max: 300,
                    divisions: 29,
                    label: '$_workDuration s',
                    onChanged: (val) {
                      setState(() => _workDuration = val.toInt());
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
                      setState(() => _restDuration = val.toInt());
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
                      setState(() => _totalRounds = val.toInt());
                      if (_currentEvent.state == WorkoutState.FINISHED) _resetToIdle();
                    },
                  ),
                ),
                Text('$_totalRounds'),
              ],
            ),
            SwitchListTile(
              title: const Text('Auto Regulate Rest'),
              subtitle: Text('Hold rest until HR < $_maxPreworkHr'),
              value: _autoRegulationEnabled,
              onChanged: (val) => setState(() => _autoRegulationEnabled = val),
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
              backgroundColor: stateColor.withOpacity(0.2),
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

  @override
  Widget build(BuildContext context) {
    bool isIdle = _currentEvent.state == WorkoutState.IDLE || _currentEvent.state == WorkoutState.FINISHED;

    return Scaffold(
      appBar: AppBar(
        title: const Text('EMOM Timer'),
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
              const SizedBox(height: 32),
              _buildTimerDisplay(),
              const SizedBox(height: 32),
              if (isIdle) _buildConfigPanel(),
            ],
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: isIdle
          ? FloatingActionButton.extended(
              onPressed: _startWorkout,
              backgroundColor: Theme.of(context).colorScheme.secondary,
              icon: const Icon(Icons.play_arrow),
              label: const Text('START WORKOUT'),
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
                  label: Text(_currentEvent.state == WorkoutState.PAUSED ? 'RESUME' : 'PAUSE'),
                ),
                const SizedBox(width: 16),
                FloatingActionButton.extended(
                  heroTag: 'stop_btn',
                  onPressed: _stopWorkout,
                  backgroundColor: Theme.of(context).colorScheme.error,
                  icon: const Icon(Icons.stop),
                  label: const Text('END WORKOUT'),
                ),
              ],
            ),
    );
  }
}

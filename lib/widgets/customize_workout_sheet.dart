import 'package:flutter/material.dart';
import '../models/activity_type.dart';
import '../utils/format_utils.dart';

class CustomizeWorkoutSheet extends StatefulWidget {
  final int workDuration;
  final ValueChanged<int> onWorkDurationChanged;
  final int restDuration;
  final ValueChanged<int> onRestDurationChanged;
  final int totalRounds;
  final ValueChanged<int> onTotalRoundsChanged;

  final bool autoRegulationEnabled;
  final ValueChanged<bool>? onAutoRegulationChanged;
  final int maxPreworkHr;

  final bool continuousMode;
  final ValueChanged<bool> onContinuousModeChanged;

  final String activityType;
  final ValueChanged<String> onActivityTypeChanged;

  final String musicMode;
  final ValueChanged<String>? onMusicModeChanged;
  final double musicVolume;
  final ValueChanged<double>? onMusicVolumeChanged;
  final bool musicMuted;
  final ValueChanged<bool>? onMusicMutedChanged;

  final double weightMoved;
  final ValueChanged<double> onWeightMovedChanged;
  final String weightUnit;
  final ValueChanged<String> onWeightUnitChanged;

  final double ruckWeight;
  final ValueChanged<double> onRuckWeightChanged;
  final String ruckWeightUnit;
  final ValueChanged<String> onRuckWeightUnitChanged;

  final int repsPerRound;
  final ValueChanged<int> onRepsPerRoundChanged;
  final int repsCompleted;
  final ValueChanged<int> onRepsCompletedChanged;

  final TextEditingController notesController;

  final bool hasTreadmill;
  final bool treadmillConnected;
  final String distanceUnitPref;
  final bool autoSpeedSync;
  final ValueChanged<bool> onAutoSpeedSyncChanged;
  final double workSpeed;
  final ValueChanged<double> onWorkSpeedChanged;
  final double restSpeed;
  final ValueChanged<double> onRestSpeedChanged;

  final VoidCallback onSaveTemplate;
  final void Function(String title, String message) onHelpRequested;

  const CustomizeWorkoutSheet({
    super.key,
    required this.workDuration,
    required this.onWorkDurationChanged,
    required this.restDuration,
    required this.onRestDurationChanged,
    required this.totalRounds,
    required this.onTotalRoundsChanged,
    required this.autoRegulationEnabled,
    this.onAutoRegulationChanged,
    required this.maxPreworkHr,
    required this.continuousMode,
    required this.onContinuousModeChanged,
    required this.activityType,
    required this.onActivityTypeChanged,
    this.musicMode = 'AUTO',
    this.onMusicModeChanged,
    this.musicVolume = 0.70,
    this.onMusicVolumeChanged,
    this.musicMuted = false,
    this.onMusicMutedChanged,
    required this.weightMoved,
    required this.onWeightMovedChanged,
    required this.weightUnit,
    required this.onWeightUnitChanged,
    required this.ruckWeight,
    required this.onRuckWeightChanged,
    required this.ruckWeightUnit,
    required this.onRuckWeightUnitChanged,
    required this.repsPerRound,
    required this.onRepsPerRoundChanged,
    required this.repsCompleted,
    required this.onRepsCompletedChanged,
    required this.notesController,
    required this.hasTreadmill,
    required this.treadmillConnected,
    required this.distanceUnitPref,
    required this.autoSpeedSync,
    required this.onAutoSpeedSyncChanged,
    required this.workSpeed,
    required this.onWorkSpeedChanged,
    required this.restSpeed,
    required this.onRestSpeedChanged,
    required this.onSaveTemplate,
    required this.onHelpRequested,
  });

  @override
  State<CustomizeWorkoutSheet> createState() => _CustomizeWorkoutSheetState();
}

class _CustomizeWorkoutSheetState extends State<CustomizeWorkoutSheet> {
  late final TextEditingController _weightController;
  late final TextEditingController _ruckWeightController;
  late final TextEditingController _repsController;
  late final TextEditingController _repsCompletedController;

  late String _activityType;
  late String _musicMode;
  late double _musicVolume;
  late bool _musicMuted;

  @override
  void initState() {
    super.initState();
    _activityType = widget.activityType;
    _musicMode = widget.musicMode;
    _musicVolume = widget.musicVolume;
    _musicMuted = widget.musicMuted;
    _weightController = TextEditingController(
      text: widget.weightMoved > 0 ? widget.weightMoved.toString() : '',
    );
    _ruckWeightController = TextEditingController(
      text: widget.ruckWeight > 0 ? widget.ruckWeight.toString() : '',
    );
    _repsController = TextEditingController(
      text: widget.repsPerRound.toString(),
    );
    _repsCompletedController = TextEditingController(
      text: widget.repsCompleted > 0 ? widget.repsCompleted.toString() : '',
    );
  }

  @override
  void didUpdateWidget(covariant CustomizeWorkoutSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activityType != widget.activityType) {
      _activityType = widget.activityType;
    }
    if (oldWidget.musicMode != widget.musicMode) {
      _musicMode = widget.musicMode;
    }
    if (oldWidget.musicVolume != widget.musicVolume) {
      _musicVolume = widget.musicVolume;
    }
    if (oldWidget.musicMuted != widget.musicMuted) {
      _musicMuted = widget.musicMuted;
    }
  }

  @override
  void dispose() {
    _weightController.dispose();
    _ruckWeightController.dispose();
    _repsController.dispose();
    _repsCompletedController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ActivityType selectedActivity = ActivityType.fromString(_activityType);
    final bool isStrength = selectedActivity.isStrengthBased;
    final FocusMusicMode selectedMusicMode = FocusMusicMode.fromString(_musicMode);
    final FocusMusicMode resolvedMusicMode = selectedMusicMode.resolve(
      activity: selectedActivity,
      isTreadmill: widget.hasTreadmill,
    );

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
                        onPressed: widget.onSaveTemplate,
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
                              FormatUtils.formatDurationConcise(widget.workDuration, zeroText: '0s'),
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
                              widget.onWorkDurationChanged(
                                FormatUtils.decrementWorkDuration(widget.workDuration),
                              );
                            },
                          ),
                          Expanded(
                            child: Slider(
                              value: FormatUtils.secondsToWorkSliderValue(widget.workDuration),
                              min: 0.0,
                              max: 1.0,
                              label: FormatUtils.formatDurationConcise(widget.workDuration, zeroText: '0s'),
                              onChanged: (val) {
                                widget.onWorkDurationChanged(
                                  FormatUtils.workSliderValueToSeconds(val),
                                );
                              },
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: () {
                              widget.onWorkDurationChanged(
                                FormatUtils.incrementWorkDuration(widget.workDuration),
                              );
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
                              FormatUtils.formatDurationConcise(widget.restDuration, zeroText: 'None'),
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
                              widget.onRestDurationChanged(
                                FormatUtils.decrementRestDuration(widget.restDuration),
                              );
                            },
                          ),
                          Expanded(
                            child: Slider(
                              value: FormatUtils.secondsToRestSliderValue(widget.restDuration),
                              min: 0.0,
                              max: 1.0,
                              label: FormatUtils.formatDurationConcise(widget.restDuration, zeroText: 'None'),
                              onChanged: (val) {
                                widget.onRestDurationChanged(
                                  FormatUtils.restSliderValueToSeconds(val),
                                );
                              },
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: () {
                              widget.onRestDurationChanged(
                                FormatUtils.incrementRestDuration(widget.restDuration),
                              );
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
                              '${widget.totalRounds}',
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
                              widget.onTotalRoundsChanged((widget.totalRounds - 1).clamp(1, 50));
                            },
                          ),
                          Expanded(
                            child: Slider(
                              value: widget.totalRounds.toDouble(),
                              min: 1,
                              max: 50,
                              divisions: 49,
                              label: '${widget.totalRounds}',
                              onChanged: (val) {
                                widget.onTotalRoundsChanged(val.toInt());
                              },
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: () {
                              widget.onTotalRoundsChanged((widget.totalRounds + 1).clamp(1, 50));
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
                          onTap: () => widget.onHelpRequested(
                            'Auto Regulate Rest',
                            'Hold the rest phase countdown until your heart rate drops below your profile\'s configured threshold (currently ${widget.maxPreworkHr} BPM). Requires a connected heart rate monitor.',
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
                    value: widget.autoRegulationEnabled,
                    onChanged: widget.onAutoRegulationChanged,
                  ),
                  SwitchListTile(
                    title: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Open Ended Workout'),
                        const SizedBox(width: 4),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => widget.onHelpRequested(
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
                    value: widget.continuousMode,
                    onChanged: widget.onContinuousModeChanged,
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
                            onTap: () => widget.onHelpRequested(
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
                        items: ActivityType.values.map((at) {
                          return DropdownMenuItem(
                            value: at.dbCode,
                            child: Text(at.label),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _activityType = val);
                            widget.onActivityTypeChanged(val);
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            selectedMusicMode.icon,
                            size: 18,
                            color: selectedMusicMode.color,
                          ),
                          const SizedBox(width: 6),
                          const Text('Workout Music'),
                          const SizedBox(width: 4),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => widget.onHelpRequested(
                              'Workout Music',
                              'Plays a procedural Focus Music track during your workout:\n'
                              '• Auto: Selects Strength (100 BPM), Running (160 BPM), Focus (120 BPM), or Meditation based on Activity Type.\n'
                              '• Dynamic Mix: Fades in during PREP, full energy during WORK, ducks during REST & chimes, and crossfades to Meditation during 2-minute HRR cooldown.',
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
                        value: selectedMusicMode.code,
                        items: FocusMusicMode.values.map((mode) {
                          final String text = mode == FocusMusicMode.auto
                              ? 'Auto (${resolvedMusicMode.shortLabel})'
                              : mode.label;
                          return DropdownMenuItem(
                            value: mode.code,
                            child: Text(text),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _musicMode = val);
                            widget.onMusicModeChanged?.call(val);
                          }
                        },
                      ),
                    ],
                  ),
                  if (selectedMusicMode != FocusMusicMode.off)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4.0),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: _musicMuted ? 'Unmute Music' : 'Mute Music',
                            icon: Icon(
                              _musicMuted || _musicVolume == 0
                                  ? Icons.volume_off
                                  : (_musicVolume < 0.5 ? Icons.volume_down : Icons.volume_up),
                              color: _musicMuted
                                  ? Colors.grey
                                  : selectedMusicMode.color,
                            ),
                            onPressed: () {
                              final nextMuted = !_musicMuted;
                              setState(() => _musicMuted = nextMuted);
                              widget.onMusicMutedChanged?.call(nextMuted);
                            },
                          ),
                          Expanded(
                            child: Slider(
                              value: _musicMuted ? 0.0 : _musicVolume.clamp(0.0, 1.0),
                              min: 0.0,
                              max: 1.0,
                              divisions: 20,
                              label: _musicMuted ? 'Muted' : '${(_musicVolume * 100).round()}%',
                              onChanged: (val) {
                                setState(() {
                                  _musicVolume = val;
                                  if (val > 0 && _musicMuted) {
                                    _musicMuted = false;
                                    widget.onMusicMutedChanged?.call(false);
                                  }
                                });
                                widget.onMusicVolumeChanged?.call(val);
                              },
                            ),
                          ),
                          SizedBox(
                            width: 44,
                            child: Text(
                              _musicMuted ? 'Mute' : '${(_musicVolume * 100).round()}%',
                              textAlign: TextAlign.end,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: _musicMuted
                                    ? Colors.grey
                                    : Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const Divider(),
                  if (isStrength)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
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
                                    widget.onWeightMovedChanged(double.tryParse(val) ?? 0.0);
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 2,
                                child: DropdownButtonFormField<String>(
                                  initialValue: widget.weightUnit,
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
                                      widget.onWeightUnitChanged(val);
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _repsController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Reps per Round (Tonnage Multiplier)',
                              hintText: '1',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (val) {
                              widget.onRepsPerRoundChanged(int.tryParse(val) ?? 1);
                            },
                          ),
                        ],
                      ),
                    )
                  else
                    Padding(
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
                              ),
                              onChanged: (val) {
                                widget.onRuckWeightChanged(double.tryParse(val) ?? 0.0);
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: DropdownButtonFormField<String>(
                              initialValue: widget.ruckWeightUnit,
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
                                  widget.onRuckWeightUnitChanged(val);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (widget.hasTreadmill) ...[
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
                            onTap: () => widget.onHelpRequested(
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
                        widget.treadmillConnected
                            ? 'Connected and ready'
                            : 'Treadmill not connected (auto-sync will activate upon connection)',
                        style: const TextStyle(fontSize: 12),
                      ),
                      value: widget.autoSpeedSync,
                      onChanged: widget.onAutoSpeedSyncChanged,
                    ),
                    if (widget.autoSpeedSync) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                        child: Builder(
                          builder: (context) {
                            final bool isMetric = widget.distanceUnitPref == 'km';
                            final String speedUnit = isMetric ? 'km/h' : 'mph';

                            // Work Speed
                            final double rawWorkSpeed = widget.workSpeed;
                            final double displayWorkSpeed = isMetric ? rawWorkSpeed : rawWorkSpeed * 0.621371;
                            final double minWork = isMetric ? 0.5 : 0.3;
                            final double maxWork = isMetric ? 10.0 : 6.2;
                            final int divWork = ((maxWork - minWork) / 0.1).round();

                            // Rest Speed
                            final double rawRestSpeed = widget.restSpeed;
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
                                  onChanged: (val) {
                                    final double newKmh = isMetric ? val : val * 1.60934;
                                    widget.onWorkSpeedChanged(double.parse(newKmh.toStringAsFixed(1)));
                                  },
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
                                  onChanged: (val) {
                                    final double newKmh = isMetric ? val : val * 1.60934;
                                    widget.onRestSpeedChanged(double.parse(newKmh.toStringAsFixed(1)));
                                  },
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
                    controller: _repsCompletedController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Total Reps Completed',
                      hintText: 'Enter total reps completed (e.g. pullups, pushups)...',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.fitness_center),
                    ),
                    onChanged: (val) {
                      widget.onRepsCompletedChanged(int.tryParse(val) ?? 0);
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: widget.notesController,
                    decoration: const InputDecoration(
                      labelText: 'Workout Notes',
                      hintText: 'Enter notes for this workout...',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.note),
                    ),
                    maxLines: 2,
                    onChanged: (_) {},
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

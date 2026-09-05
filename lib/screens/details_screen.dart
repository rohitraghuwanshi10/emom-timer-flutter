import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:file_picker/file_picker.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../theme/app_colors.dart';

class DetailsScreen extends StatefulWidget {
  final String dateStr;
  final String profileName;

  const DetailsScreen({
    super.key, 
    required this.dateStr, 
    required this.profileName,
  });

  @override
  State<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends State<DetailsScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _workouts = [];
  final Map<int, List<Map<String, dynamic>>> _hrLogs = {};
  int _maxHr = 180;
  String _distanceUnitPref = 'km';
  bool? _showCardsView;

  List<Color> get _nordColors => AppColors.chartColors;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final db = await DatabaseHelper.instance.database;
      
      // Get profile max_hr and distance unit preference
      final profRes = await db.query('profiles', where: 'name = ?', whereArgs: [widget.profileName], limit: 1);
      if (profRes.isNotEmpty) {
        _maxHr = profRes.first['max_hr'] as int? ?? 180;
        _distanceUnitPref = profRes.first['distance_unit_pref'] as String? ?? 'km';
      }

      // Get workouts
      _workouts = await DatabaseHelper.instance.getWorkoutsForDay(widget.profileName, widget.dateStr);

      // Get HR logs
      for (var w in _workouts) {
        final int wid = w['id'] as int;
        final logs = await DatabaseHelper.instance.getHeartRateLogs(wid);
        debugPrint('DetailsScreen: Workout ID $wid has ${logs.length} HR logs');
        _hrLogs[wid] = logs;
      }

      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('Error loading details: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _exportToCsv() async {
    debugPrint('DetailsScreen: _exportToCsv button clicked!');
    if (_workouts.isEmpty) {
      debugPrint('DetailsScreen: _workouts is empty, returning.');
      return;
    }

    final String cleanDateStr = widget.dateStr.replaceAll(' ', '_').replaceAll(',', '');
    final String defaultFileName = "${widget.profileName}_${cleanDateStr}_workouts.csv";
    debugPrint('DetailsScreen: defaultFileName is $defaultFileName');

    try {
      debugPrint('DetailsScreen: Calling FilePicker.platform.saveFile()...');
      final String? path = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Day\'s Workouts to CSV',
        fileName: defaultFileName,
        allowedExtensions: ['csv'],
        type: FileType.custom,
      );
      debugPrint('DetailsScreen: saveFile returned path: $path');

      if (path == null) {
        debugPrint('DetailsScreen: User cancelled save file dialog.');
        return;
      }

      // Generate CSV string
      final StringBuffer csvBuffer = StringBuffer();
      
      // Header row
      final bool isMetric = _distanceUnitPref == 'km';
      final String distUnit = isMetric ? 'km' : 'mi';
      final String speedUnit = isMetric ? 'km/h' : 'mph';
            csvBuffer.writeln('Workout,Start Time,Rounds,Reps Completed,Total Time,Work Time,Rest Time,Peak HR (BPM),Avg HR (BPM),1min HR Recovery (BPM),2min HR Recovery (BPM),Recovery Duration (s),Calories (kcal),Run Dist ($distUnit),Run Peak Speed ($speedUnit),Run Avg Speed ($speedUnit),Weight Moved,Weight Unit,Total Weight Moved,Ruck Weight,Ruck Weight Unit,Notes');

      for (int i = 0; i < _workouts.length; i++) {
        final w = _workouts[i];
        
        String startStr = '--';
        try {
          final dt = DateTime.parse(w['start_time'] as String).toLocal();
          final String period = dt.hour >= 12 ? 'PM' : 'AM';
          final int hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
          startStr = "$hour12:${dt.minute.toString().padLeft(2, '0')} $period";
        } catch (_) {}

        final String rounds = "${w['total_rounds_completed'] ?? 0}";
        final String totalTime = _fmtSec(w['total_time_sec']);
        final String workTime = _fmtSec(w['work_time_sec']);
        final String restTime = _fmtSec(w['rest_time_sec']);
        final String peakHr = _fmtHr(w['max_hr']);
        final String avgHr = _fmtHr(w['avg_hr']);
        final String hrr1min = w['hrr_1min'] != null ? '${w['hrr_1min']}' : '--';
        final String hrr2min = w['hrr_2min'] != null ? '${w['hrr_2min']}' : '--';
        final String hrrDuration = w['recovery_duration_sec'] != null ? '${w['recovery_duration_sec']}' : '--';
        final String calories = (w['calories_burnt_kcal'] as num?)?.toStringAsFixed(1) ?? '--';

        final double rawDist = (w['run_distance'] as num?)?.toDouble() ?? 0.0;
        final double rawPeak = (w['run_peak_speed'] as num?)?.toDouble() ?? 0.0;
        final double rawAvg = (w['run_avg_speed'] as num?)?.toDouble() ?? 0.0;

        final double displayDist = isMetric ? rawDist : rawDist * 0.621371;
        final double displayPeak = isMetric ? rawPeak : rawPeak * 0.621371;
        final double displayAvg = isMetric ? rawAvg : rawAvg * 0.621371;

        final String runDist = displayDist.toStringAsFixed(2);
        final String runPeak = displayPeak.toStringAsFixed(1);
        final String runAvg = displayAvg.toStringAsFixed(1);

        final int repsCompleted = w['reps_completed'] as int? ?? 0;
        final double weightMoved = (w['weight_moved'] as num?)?.toDouble() ?? 0.0;
        final String weightUnit = w['weight_unit'] as String? ?? 'kg';
        final double totalWeightMoved = (w['total_weight_moved'] as num?)?.toDouble() ?? 0.0;
        final double ruckWeight = (w['ruck_weight'] as num?)?.toDouble() ?? 0.0;
        final String ruckWeightUnit = w['ruck_weight_unit'] as String? ?? 'lbs';
        
        // Escape notes for CSV
        String notes = w['notes'] as String? ?? '';
        if (notes.contains(',') || notes.contains('"') || notes.contains('\n') || notes.contains('\r')) {
          notes = '"${notes.replaceAll('"', '""')}"';
        }

        final String name = (w['workout_name'] as String? ?? '').isNotEmpty
            ? w['workout_name'] as String
            : 'WO ${i + 1}';
        String escapedName = name;
        if (escapedName.contains(',') || escapedName.contains('"') || escapedName.contains('\n') || escapedName.contains('\r')) {
          escapedName = '"${escapedName.replaceAll('"', '""')}"';
        }
        csvBuffer.writeln('$escapedName,$startStr,$rounds,$repsCompleted,$totalTime,$workTime,$restTime,$peakHr,$avgHr,$hrr1min,$hrr2min,$hrrDuration,$calories,$runDist,$runPeak,$runAvg,$weightMoved,$weightUnit,$totalWeightMoved,$ruckWeight,$ruckWeightUnit,$notes');
      }

      // Write to file
      final file = File(path);
      await file.writeAsString(csvBuffer.toString());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Successfully exported to $path')),
        );
      }
    } catch (e) {
      debugPrint('Error exporting to CSV: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to export CSV: $e')),
        );
      }
    }
  }

  String _fmtSec(dynamic secObj) {
    if (secObj == null) return '--';
    int sec = (secObj as num).toInt();
    int h = sec ~/ 3600;
    int m = (sec % 3600) ~/ 60;
    int s = sec % 60;
    if (h > 0) return "${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
    return "${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
  }

  String _fmtHr(dynamic hrObj) {
    if (hrObj == null) return '--';
    int hr = (hrObj as num).toInt();
    return hr > 0 ? '$hr' : '--';
  }

  Future<void> _editWorkoutNotes(Map<String, dynamic> w) async {
    final notesController = TextEditingController(text: w['notes'] as String? ?? '');
    final repsController = TextEditingController(text: (w['reps_completed'] as int? ?? 0).toString());
    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Workout Details'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: repsController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Reps Completed',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Workout Notes',
                  hintText: 'Enter notes about your workout...',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              try {
                final int newReps = int.tryParse(repsController.text) ?? 0;
                final double weightMoved = (w['weight_moved'] as num?)?.toDouble() ?? 0.0;
                final double newTonnage = newReps * weightMoved;

                final db = await DatabaseHelper.instance.database;
                await db.update(
                  'workouts',
                  {
                    'notes': notesController.text,
                    'reps_completed': newReps,
                    'total_weight_moved': newTonnage,
                  },
                  where: 'id = ?',
                  whereArgs: [w['id']],
                );
                if (context.mounted) Navigator.pop(context, true);
              } catch (e) {
                debugPrint('Error updating workout details: $e');
                if (context.mounted) Navigator.pop(context, false);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (saved == true) {
      await _loadData();
      // Trigger background sync to upload the update
      SyncService.instance.signInAndSync();
    }
  }

  Widget _buildWorkoutCards() {
    if (_workouts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24.0),
        child: Center(child: Text('No workouts recorded for this day.')),
      );
    }

    final bool isMetric = _distanceUnitPref == 'km';
    final String distUnit = isMetric ? 'km' : 'mi';
    final String speedUnit = isMetric ? 'km/h' : 'mph';

    return Column(
      children: _workouts.asMap().entries.map((e) {
        final int idx = e.key;
        final w = e.value;
        final Color wColor = _nordColors[idx % _nordColors.length];

        String startStr = '--';
        try {
          final dt = DateTime.parse(w['start_time'] as String).toLocal();
          final period = dt.hour >= 12 ? 'PM' : 'AM';
          final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
          startStr = '$hour12:${dt.minute.toString().padLeft(2, '0')} $period';
        } catch (_) {}

        final String name = (w['workout_name'] as String? ?? '').isNotEmpty
            ? w['workout_name'] as String
            : 'Workout ${idx + 1}';
        final String activityType = w['activity_type'] as String? ?? 'HIIT';

        final int rounds = (w['total_rounds_completed'] as num?)?.toInt() ?? 0;
        final int repsCompleted = (w['reps_completed'] as num?)?.toInt() ?? 0;
        final double weightMoved = (w['weight_moved'] as num?)?.toDouble() ?? 0.0;
        final String weightUnit = w['weight_unit'] as String? ?? 'kg';
        final double totalWeightMoved = (w['total_weight_moved'] as num?)?.toDouble() ?? 0.0;
        final double ruckWeight = (w['ruck_weight'] as num?)?.toDouble() ?? 0.0;
        final String ruckWeightUnit = w['ruck_weight_unit'] as String? ?? 'lbs';

        final double rawDist = (w['run_distance'] as num?)?.toDouble() ?? 0.0;
        final double rawPeak = (w['run_peak_speed'] as num?)?.toDouble() ?? 0.0;
        final double rawAvg = (w['run_avg_speed'] as num?)?.toDouble() ?? 0.0;
        final double displayDist = isMetric ? rawDist : rawDist * 0.621371;
        final double displayPeak = isMetric ? rawPeak : rawPeak * 0.621371;
        final double displayAvg = isMetric ? rawAvg : rawAvg * 0.621371;

        final hrr1m = w['hrr_1min'] as int?;
        final hrr2m = w['hrr_2min'] as int?;
        final recDur = w['recovery_duration_sec'] as int?;
        final double calories = (w['calories_burnt_kcal'] as num?)?.toDouble() ?? 0.0;
        final String notes = w['notes'] as String? ?? '';

        return Card(
          margin: const EdgeInsets.only(bottom: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: wColor.withValues(alpha: 0.3), width: 1.5),
          ),
          color: Theme.of(context).colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Card Header
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: wColor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: wColor,
                            ),
                          ),
                          Text(
                            startStr,
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark ? Colors.white.withValues(alpha: 0.06) : AppColors.lightSurfaceSubtle,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        activityType.toUpperCase(),
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      icon: const Icon(Icons.edit_note, size: 20, color: Colors.grey),
                      tooltip: 'Edit Reps & Notes',
                      onPressed: () => _editWorkoutNotes(w),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Divider(height: 1, color: Theme.of(context).brightness == Brightness.dark ? Colors.white10 : AppColors.lightBorder),
                const SizedBox(height: 12),

                // 2x2 Key Metric Tiles
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _buildDetailCardStat(
                        icon: Icons.timer,
                        iconColor: const Color(0xFF0DF2A3),
                        label: 'DURATION',
                        mainValue: _fmtSec(w['total_time_sec']),
                        subValue: '${_fmtSec(w['work_time_sec'])} work • ${_fmtSec(w['rest_time_sec'])} rest',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildDetailCardStat(
                        icon: Icons.repeat,
                        iconColor: Theme.of(context).colorScheme.primary,
                        label: 'ROUNDS & REPS',
                        mainValue: '$rounds rounds',
                        subValue: repsCompleted > 0 ? '$repsCompleted reps recorded' : 'Rounds finished',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _buildDetailCardStat(
                        icon: Icons.favorite,
                        iconColor: const Color(0xFFFF3B30),
                        label: 'HEART RATE',
                        mainValue: '${_fmtHr(w['avg_hr'])} avg • ${_fmtHr(w['max_hr'])} max',
                        subValue: hrr1m != null
                            ? 'Recovery: -$hrr1m bpm (1m)${hrr2m != null ? ' • -$hrr2m (2m)' : ''}'
                            : (recDur != null ? 'Rec. tracking: ${recDur}s' : 'No HR recovery data'),
                        subValueColor: hrr1m != null ? const Color(0xFF00E5FF) : Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildDetailCardStat(
                        icon: Icons.local_fire_department,
                        iconColor: const Color(0xFFFF7A00),
                        label: 'ENERGY & VOLUME',
                        mainValue: calories > 0 ? '${calories.toStringAsFixed(0)} kcal' : '-- kcal',
                        subValue: weightMoved > 0
                            ? '${weightMoved.toStringAsFixed(1)} $weightUnit (${totalWeightMoved.toStringAsFixed(0)} $weightUnit total)'
                            : (ruckWeight > 0
                                ? '${ruckWeight.toStringAsFixed(1)} $ruckWeightUnit ruck'
                                : (rawDist > 0 ? '${displayDist.toStringAsFixed(2)} $distUnit @ ${displayAvg.toStringAsFixed(1)} $speedUnit (peak: ${displayPeak.toStringAsFixed(1)})' : 'General conditioning')),
                      ),
                    ),
                  ],
                ),

                // Notes display if not empty
                if (notes.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: () => _editWorkoutNotes(w),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark ? Colors.white.withValues(alpha: 0.03) : AppColors.lightSurfaceSubtle,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Theme.of(context).brightness == Brightness.dark ? Colors.white10 : AppColors.lightBorder),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.sticky_note_2_outlined, size: 14, color: Colors.amber),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              notes,
                              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Icon(Icons.edit, size: 12, color: Colors.grey),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDetailCardStat({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String mainValue,
    required String subValue,
    Color? subValueColor,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.03) : AppColors.lightSurfaceSubtle,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.white10 : AppColors.lightBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: iconColor),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                    color: Colors.grey,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            mainValue,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            subValue,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: subValueColor ?? Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildDataTable() {
    if (_workouts.isEmpty) return const Text('No workouts recorded.');

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingTextStyle: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
        dataRowMinHeight: 40,
        dataRowMaxHeight: 50,
        columns: const [
          DataColumn(label: Text('Workout')),
          DataColumn(label: Text('Start Time')),
          DataColumn(label: Text('Rounds')),
          DataColumn(label: Text('Reps')),
          DataColumn(label: Text('Total Time')),
          DataColumn(label: Text('Work Time')),
          DataColumn(label: Text('Rest Time')),
          DataColumn(label: Text('Peak HR')),
          DataColumn(label: Text('Avg HR')),
          DataColumn(label: Text('HRR 1m')),
          DataColumn(label: Text('HRR 2m')),
          DataColumn(label: Text('Cals (kcal)')),
          DataColumn(label: Text('Weight / Load')),
          DataColumn(label: Text('Run Dist')),
          DataColumn(label: Text('Peak Speed')),
          DataColumn(label: Text('Avg Speed')),
          DataColumn(label: Text('Notes')),
        ],
        rows: _workouts.asMap().entries.map((e) {
          int idx = e.key;
          var w = e.value;
          Color wColor = _nordColors[idx % _nordColors.length];

          String startStr = '--';
          try {
            final dt = DateTime.parse(w['start_time'] as String).toLocal();
            startStr = "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
          } catch (_) {}

            final String name = (w['workout_name'] as String? ?? '').isNotEmpty
                ? w['workout_name'] as String
                : 'WO ${idx + 1}';
            final bool isMetric = _distanceUnitPref == 'km';
            final double runDistance = (w['run_distance'] as num?)?.toDouble() ?? 0.0;
            final double runPeakSpeed = (w['run_peak_speed'] as num?)?.toDouble() ?? 0.0;
            final double runAvgSpeed = (w['run_avg_speed'] as num?)?.toDouble() ?? 0.0;

            final double displayDist = isMetric ? runDistance : runDistance * 0.621371;
            final double displayPeak = isMetric ? runPeakSpeed : runPeakSpeed * 0.621371;
            final double displayAvg = isMetric ? runAvgSpeed : runAvgSpeed * 0.621371;
            final String distUnit = isMetric ? 'km' : 'mi';
            final String speedUnit = isMetric ? 'km/h' : 'mph';

            final weightMoved = (w['weight_moved'] as num?)?.toDouble() ?? 0.0;
            final weightUnit = w['weight_unit'] as String? ?? 'kg';
            final totalWeightMoved = (w['total_weight_moved'] as num?)?.toDouble() ?? 0.0;
            final ruckWeight = (w['ruck_weight'] as num?)?.toDouble() ?? 0.0;
            final ruckWeightUnit = w['ruck_weight_unit'] as String? ?? 'lbs';
            final repsPerRound = w['reps_per_round'] as int? ?? 1;

            String weightLoadDisplay = '--';
            if (weightMoved > 0.0) {
              weightLoadDisplay = '${weightMoved.toStringAsFixed(1)} $weightUnit${repsPerRound > 1 ? ' (x$repsPerRound reps)' : ''} (${totalWeightMoved.toStringAsFixed(1)} total)';
            } else if (ruckWeight > 0.0) {
              weightLoadDisplay = '${ruckWeight.toStringAsFixed(1)} $ruckWeightUnit ruck';
            }

            final repsCompleted = w['reps_completed'] as int? ?? 0;
            final hrr1m = w['hrr_1min'] as int?;
            final hrr2m = w['hrr_2min'] as int?;
            final recDur = w['recovery_duration_sec'] as int?;

            String hrr1Display = '--';
            if (hrr1m != null) {
              hrr1Display = '-$hrr1m bpm';
            } else if (recDur != null && recDur < 60) {
              hrr1Display = 'N/A (${recDur}s)';
            }

            String hrr2Display = '--';
            if (hrr2m != null) {
              hrr2Display = '-$hrr2m bpm';
            } else if (recDur != null) {
              hrr2Display = 'N/A (${recDur}s)';
            }

            return DataRow(cells: [
              DataCell(Text(name, style: TextStyle(color: wColor, fontWeight: FontWeight.bold))),
            DataCell(Text(startStr)),
            DataCell(Text("${w['total_rounds_completed'] ?? 0}")),
            DataCell(
              InkWell(
                onTap: () => _editWorkoutNotes(w),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      repsCompleted > 0 ? "$repsCompleted" : '--',
                      style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.edit, size: 12, color: Colors.amber),
                  ],
                ),
              ),
            ),
            DataCell(Text(_fmtSec(w['total_time_sec']))),
            DataCell(Text(_fmtSec(w['work_time_sec']), style: const TextStyle(color: Color(0xFF0DF2A3)))), // Mint Neon
            DataCell(Text(_fmtSec(w['rest_time_sec']), style: const TextStyle(color: Color(0xFFFF7A00)))), // Vibrant Orange
            DataCell(Text(_fmtHr(w['max_hr']), style: const TextStyle(color: Color(0xFFFF3B30)))), // Neon Red
            DataCell(Text(_fmtHr(w['avg_hr']), style: const TextStyle(color: Color(0xFF38B6FF)))), // Cyan/Blue
            DataCell(Text(hrr1Display, style: TextStyle(color: hrr1m != null ? const Color(0xFF00E5FF) : Colors.grey, fontWeight: FontWeight.bold))),
            DataCell(Text(hrr2Display, style: TextStyle(color: hrr2m != null ? const Color(0xFF00E5FF) : Colors.grey, fontWeight: FontWeight.bold))),
            DataCell(Text((w['calories_burnt_kcal'] as num?)?.toStringAsFixed(1) ?? '--', style: const TextStyle(color: Color(0xFFBF5AF2)))), // Neon Purple
            DataCell(Text(weightLoadDisplay, style: const TextStyle(color: Colors.amber))),
            DataCell(Text(runDistance > 0 ? "${displayDist.toStringAsFixed(2)} $distUnit" : '--', style: const TextStyle(color: Color(0xFF00E5FF)))),
            DataCell(Text(runPeakSpeed > 0 ? "${displayPeak.toStringAsFixed(1)} $speedUnit" : '--')),
            DataCell(Text(runAvgSpeed > 0 ? "${displayAvg.toStringAsFixed(1)} $speedUnit" : '--')),
            DataCell(
              InkWell(
                onTap: () => _editWorkoutNotes(w),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      constraints: const BoxConstraints(maxWidth: 120),
                      child: Text(
                        w['notes'] as String? ?? '',
                        style: const TextStyle(color: Colors.grey),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.edit, size: 14, color: Colors.grey),
                  ],
                ),
              ),
            ),
          ]);
        }).toList(),
      ),
    );
  }

  Widget _buildGraph() {
    bool hasData = false;
    for (var w in _workouts) {
      if (_hrLogs[w['id']]?.isNotEmpty ?? false) hasData = true;
    }
    
    if (!hasData) {
      return const Center(child: Text('No Heart Rate Data Available', style: TextStyle(fontSize: 16)));
    }

    List<LineChartBarData> lineBarsData = [];
    double maxY = 40.0;
    double maxX = 0.0;

    // Find earliest log timestamp of the day as the session t=0 anchor
    DateTime? firstLogTs;
    for (var w in _workouts) {
      var logs = _hrLogs[w['id']] ?? [];
      for (var log in logs) {
        try {
          final dt = DateTime.parse(log['capture_time'] as String);
          if (firstLogTs == null || dt.isBefore(firstLogTs)) {
            firstLogTs = dt;
          }
        } catch (_) {}
      }
    }

    for (int i = 0; i < _workouts.length; i++) {
      var w = _workouts[i];
      var logs = _hrLogs[w['id']] ?? [];
      if (logs.isEmpty) continue;

      Color wColor = _nordColors[i % _nordColors.length];
      List<FlSpot> workoutSpots = [];
      List<FlSpot> recoverySpots = [];

      for (var log in logs) {
        try {
          final dt = DateTime.parse(log['capture_time'] as String);
          final double deltaMin = firstLogTs != null
              ? (dt.difference(firstLogTs).inSeconds / 60.0)
              : 0.0;
          final double bpm = (log['bpm'] as num).toDouble();
          
          if (bpm > maxY) maxY = bpm;
          if (deltaMin > maxX) maxX = deltaMin;

          final spot = FlSpot(deltaMin, bpm);
          final bool isRec = (log['is_recovery'] as int? ?? 0) == 1;

          if (isRec) {
            if (recoverySpots.isEmpty && workoutSpots.isNotEmpty) {
              recoverySpots.add(workoutSpots.last);
            }
            recoverySpots.add(spot);
          } else {
            workoutSpots.add(spot);
          }
        } catch (_) {}
      }

      if (workoutSpots.isNotEmpty) {
        lineBarsData.add(
          LineChartBarData(
            spots: workoutSpots,
            isCurved: false,
            color: wColor,
            barWidth: 2.0,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: wColor.withValues(alpha: 0.1),
            ),
          ),
        );
      }

      if (recoverySpots.isNotEmpty) {
        lineBarsData.add(
          LineChartBarData(
            spots: recoverySpots,
            isCurved: false,
            color: const Color(0xFF00E5FF),
            barWidth: 2.0,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: const Color(0xFF00E5FF).withValues(alpha: 0.15),
            ),
          ),
        );
      }
    }

    maxY = (maxY + 15).clamp(140.0, 220.0);

    // Zones
    final mh = _maxHr.toDouble();
    List<HorizontalLine> zLines = [
      HorizontalLine(y: 0.6 * mh, color: const Color(0xFF38B6FF).withValues(alpha: 0.3), strokeWidth: 1), // Z1
      HorizontalLine(y: 0.7 * mh, color: const Color(0xFF0DF2A3).withValues(alpha: 0.3), strokeWidth: 1), // Z2
      HorizontalLine(y: 0.8 * mh, color: const Color(0xFFFFD60A).withValues(alpha: 0.3), strokeWidth: 1), // Z3
      HorizontalLine(y: 0.9 * mh, color: const Color(0xFFFF7A00).withValues(alpha: 0.3), strokeWidth: 1), // Z4
      HorizontalLine(y: 1.0 * mh, color: const Color(0xFFFF3B30).withValues(alpha: 0.3), strokeWidth: 1), // Z5
    ];

    return Container(
      height: 300,
      padding: const EdgeInsets.only(right: 20, top: 20),
      child: LineChart(
        LineChartData(
          minY: 40,
          maxY: maxY,
          minX: 0,
          maxX: maxX,
          extraLinesData: ExtraLinesData(horizontalLines: zLines),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 20,
            getDrawingHorizontalLine: (value) => FlLine(
              color: Theme.of(context).brightness == Brightness.dark ? Colors.white10 : AppColors.lightBorder,
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                interval: (maxX / 5).clamp(1, double.infinity),
                getTitlesWidget: (val, meta) => Text('${val.toInt()}m', style: const TextStyle(color: Colors.grey, fontSize: 10)),
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 20,
                reservedSize: 40,
                getTitlesWidget: (val, meta) => Text('${val.toInt()}', style: const TextStyle(color: Colors.grey, fontSize: 10)),
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: lineBarsData,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isNarrow = screenWidth < 720;
    final bool useCards = _showCardsView ?? isNarrow;

    return Scaffold(
      appBar: AppBar(
        title: Text('Details: ${widget.dateStr}'),
        actions: [
          if (!_isLoading && _workouts.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.download),
              tooltip: 'Export Day to CSV',
              onPressed: _exportToCsv,
            ),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // View mode switcher header
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12.0, left: 4, right: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'WORKOUTS RECORDED (${_workouts.length})',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                            color: Colors.grey,
                          ),
                        ),
                        SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(
                              value: true,
                              icon: Icon(Icons.view_agenda_outlined, size: 15),
                              label: Text('Cards', style: TextStyle(fontSize: 12)),
                            ),
                            ButtonSegment(
                              value: false,
                              icon: Icon(Icons.table_chart_outlined, size: 15),
                              label: Text('Table', style: TextStyle(fontSize: 12)),
                            ),
                          ],
                          selected: {useCards},
                          onSelectionChanged: (set) => setState(() => _showCardsView = set.first),
                          style: const ButtonStyle(
                            visualDensity: VisualDensity.compact,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (useCards)
                    _buildWorkoutCards()
                  else
                    Card(
                      color: Theme.of(context).colorScheme.surface,
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: _buildDataTable(),
                      ),
                    ),
                  const SizedBox(height: 24),
                  const Text('Cumulative Daily Heart Rate Intensity', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Card(
                    color: Theme.of(context).colorScheme.surface,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: _buildGraph(),
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }
}

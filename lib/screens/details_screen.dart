import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:file_picker/file_picker.dart';
import '../services/database_helper.dart';

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

  final List<Color> _nordColors = const [
    Color(0xFF5E81AC), // Blue
    Color(0xFF88C0D0), // Cyan
    Color(0xFFA3BE8C), // Green
    Color(0xFFEBCB8B), // Yellow
    Color(0xFFD08770), // Orange
    Color(0xFFB48EAD), // Purple
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final db = await DatabaseHelper.instance.database;
      
      // Get profile max_hr
      final profRes = await db.query('profiles', where: 'name = ?', whereArgs: [widget.profileName], limit: 1);
      if (profRes.isNotEmpty) {
        _maxHr = profRes.first['max_hr'] as int? ?? 180;
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
      csvBuffer.writeln('Workout,Start Time,Rounds,Total Time,Work Time,Rest Time,Peak HR (BPM),Avg HR (BPM),Calories (kcal),Notes');

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
        final String calories = (w['calories_burnt_kcal'] as num?)?.toStringAsFixed(1) ?? '--';
        
        // Escape notes for CSV
        String notes = w['notes'] as String? ?? '';
        if (notes.contains(',') || notes.contains('"') || notes.contains('\n') || notes.contains('\r')) {
          notes = '"${notes.replaceAll('"', '""')}"';
        }

        csvBuffer.writeln('WO ${i + 1},$startStr,$rounds,$totalTime,$workTime,$restTime,$peakHr,$avgHr,$calories,$notes');
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
          DataColumn(label: Text('Total Time')),
          DataColumn(label: Text('Work Time')),
          DataColumn(label: Text('Rest Time')),
          DataColumn(label: Text('Peak HR')),
          DataColumn(label: Text('Avg HR')),
          DataColumn(label: Text('Cals (kcal)')),
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

          return DataRow(cells: [
            DataCell(Text('WO ${idx + 1}', style: TextStyle(color: wColor, fontWeight: FontWeight.bold))),
            DataCell(Text(startStr)),
            DataCell(Text("${w['total_rounds_completed'] ?? 0}")),
            DataCell(Text(_fmtSec(w['total_time_sec']))),
            DataCell(Text(_fmtSec(w['work_time_sec']), style: const TextStyle(color: Color(0xFFA3BE8C)))), // Green
            DataCell(Text(_fmtSec(w['rest_time_sec']), style: const TextStyle(color: Color(0xFFD08770)))), // Orange
            DataCell(Text(_fmtHr(w['max_hr']), style: const TextStyle(color: Color(0xFFBF616A)))), // Red
            DataCell(Text(_fmtHr(w['avg_hr']), style: const TextStyle(color: Color(0xFF5E81AC)))), // Blue
            DataCell(Text((w['calories_burnt_kcal'] as num?)?.toStringAsFixed(1) ?? '--', style: const TextStyle(color: Color(0xFFB48EAD)))), // Purple
            DataCell(Text(w['notes'] as String? ?? '', style: const TextStyle(color: Colors.grey))),
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
    double offsetMin = 0.0;
    double gapMin = 1.0;
    double maxY = 40.0;
    double maxX = 0.0;

    for (int i = 0; i < _workouts.length; i++) {
      var w = _workouts[i];
      var logs = _hrLogs[w['id']] ?? [];
      if (logs.isEmpty) continue;

      Color wColor = _nordColors[i % _nordColors.length];
      List<FlSpot> spots = [];
      DateTime? startTs;

      for (var log in logs) {
        try {
          final dt = DateTime.parse(log['capture_time'] as String);
          startTs ??= dt;
          final double deltaMin = dt.difference(startTs).inSeconds / 60.0;
          final double bpm = (log['bpm'] as num).toDouble();
          
          if (bpm > maxY) maxY = bpm;
          spots.add(FlSpot(offsetMin + deltaMin, bpm));
        } catch (_) {}
      }

      if (spots.isNotEmpty) {
        debugPrint('DetailsScreen: Created ${spots.length} FlSpots for workout ID ${w['id']}. First spot: ${spots.first.x}, ${spots.first.y}. Last spot: ${spots.last.x}, ${spots.last.y}');
        lineBarsData.add(
          LineChartBarData(
            spots: spots,
            isCurved: false,
            color: wColor,
            barWidth: 1.5,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: wColor.withValues(alpha: 0.1),
            ),
          )
        );
        offsetMin = spots.last.x + gapMin;
        if (offsetMin > maxX) maxX = offsetMin;
      } else {
        debugPrint('DetailsScreen: No spots created for workout ID ${w['id']}');
      }
    }

    maxY = (maxY + 15).clamp(140.0, 220.0);

    // Zones
    final mh = _maxHr.toDouble();
    List<HorizontalLine> zLines = [
      HorizontalLine(y: 0.6 * mh, color: const Color(0xFF5E81AC).withValues(alpha: 0.3), strokeWidth: 1), // Z1
      HorizontalLine(y: 0.7 * mh, color: const Color(0xFFA3BE8C).withValues(alpha: 0.3), strokeWidth: 1), // Z2
      HorizontalLine(y: 0.8 * mh, color: const Color(0xFFEBCB8B).withValues(alpha: 0.3), strokeWidth: 1), // Z3
      HorizontalLine(y: 0.9 * mh, color: const Color(0xFFD08770).withValues(alpha: 0.3), strokeWidth: 1), // Z4
      HorizontalLine(y: 1.0 * mh, color: const Color(0xFFBF616A).withValues(alpha: 0.3), strokeWidth: 1), // Z5
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
            getDrawingHorizontalLine: (value) => FlLine(color: Colors.white10, strokeWidth: 1),
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
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
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
    );
  }
}

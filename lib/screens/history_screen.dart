import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import 'details_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({Key? key}) : super(key: key);

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _days = [];
  bool _isLoading = true;
  String _profileName = '';

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    
    try {
      _profileName = await DatabaseHelper.instance.getActiveProfileName();
      final db = await DatabaseHelper.instance.database;
      final results = await db.rawQuery('''
        SELECT DATE(start_time) as date_str, COUNT(id) as workout_count, SUM(total_time_sec) as total_time
        FROM workouts
        WHERE profile_name = ?
        GROUP BY DATE(start_time)
        ORDER BY date_str DESC
        LIMIT 50
      ''', [_profileName]);
      
      setState(() {
        _days = results;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading history: $e');
      setState(() => _isLoading = false);
    }
  }

  String _formatDate(String dateStr) {
    try {
      // dateStr is 'YYYY-MM-DD'
      final parts = dateStr.split('-');
      final dt = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
    } catch (e) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Workout History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadHistory,
          )
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : _days.isEmpty 
          ? const Center(child: Text('No workouts found. Go crush one!'))
          : ListView.builder(
              itemCount: _days.length,
              itemBuilder: (context, index) {
                final day = _days[index];
                
                final int totalSec = (day['total_time'] as num?)?.toInt() ?? 0;
                final String timeStr = '${totalSec ~/ 60}m ${totalSec % 60}s';
                final dateStr = day['date_str'] as String;
                
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                      child: const Icon(Icons.calendar_today),
                    ),
                    title: Text(_formatDate(dateStr), style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('${day['workout_count']} workout(s) • Total time: $timeStr'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => DetailsScreen(
                            dateStr: dateStr,
                            profileName: _profileName,
                          ),
                        ),
                      ).then((_) => _loadHistory());
                    },
                  ),
                );
              },
            ),
    );
  }
}

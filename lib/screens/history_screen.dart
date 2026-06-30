import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import 'details_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => HistoryScreenState();
}

class HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _days = [];
  bool _isLoading = true;
  String _profileName = '';
  List<String> _availableProfiles = [];

  void refreshHistory() {
    _loadHistory();
  }

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
      
      // Load all available profiles for dropdown
      final allProfiles = await db.query('profiles', columns: ['name']);
      
      final results = await db.rawQuery('''
        SELECT DATE(start_time) as date_str, COUNT(id) as workout_count, SUM(total_time_sec) as total_time
        FROM workouts
        WHERE profile_name = ?
        GROUP BY DATE(start_time)
        ORDER BY date_str DESC
        LIMIT 50
      ''', [_profileName]);
      
      setState(() {
        _availableProfiles = allProfiles.map((p) => p['name'] as String).toList();
        _days = results;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading history: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _onProfileChanged(String val) async {
    await DatabaseHelper.instance.setActiveProfileName(val);
    await _loadHistory();
  }

  Widget _buildProfileSelectorAction() {
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
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
            ),
            color: Theme.of(context).colorScheme.surface,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.person,
                size: 14,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                _profileName,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const Icon(
                Icons.arrow_drop_down,
                size: 14,
                color: Colors.white,
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

  String _formatDate(String dateStr) {
    try {
      // dateStr is 'YYYY-MM-DD'
      final parts = dateStr.split('-');
      final dt = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
    } catch (_) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isLandscape = MediaQuery.of(context).orientation == Orientation.landscape && MediaQuery.of(context).size.height < 500;
    return Scaffold(
      appBar: isLandscape
          ? null
          : AppBar(
              title: const Text('Workout History'),
              actions: [
                _buildProfileSelectorAction(),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadHistory,
                )
              ],
            ),
      body: RefreshIndicator(
        onRefresh: _loadHistory,
        child: Column(
          children: [
            Expanded(
              child: _isLoading 
                ? const Center(child: CircularProgressIndicator())
                : _days.isEmpty 
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 100),
                        Center(child: Text('No workouts found. Go crush one!')),
                      ],
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: _days.length,
                      itemBuilder: (context, index) {
                        final day = _days[index];
                        
                        final int totalSec = (day['total_time'] as num?)?.toInt() ?? 0;
                        final String timeStr = totalSec >= 3600
                            ? '${totalSec ~/ 3600}h ${((totalSec % 3600) ~/ 60).toString().padLeft(2, '0')}m'
                            : '${totalSec ~/ 60}m ${totalSec % 60}s';
                        final dateStr = day['date_str'] as String;
                        
                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
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
            ),
          ],
        ),
      ),
    );
  }
}

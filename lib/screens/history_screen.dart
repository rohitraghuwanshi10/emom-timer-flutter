import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/database_helper.dart';
import '../widgets/profile_selector_capsule.dart';
import '../utils/responsive_utils.dart';
import '../theme/app_colors.dart';
import 'details_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => HistoryScreenState();
}

class HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _days = [];
  List<Map<String, dynamic>> _past7Days = [];
  int _weeklyWorkouts = 0;
  int _weeklySeconds = 0;
  double _weeklyCalories = 0.0;
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
        SELECT DATE(start_time) as date_str, COUNT(id) as workout_count, SUM(total_time_sec) as total_time, SUM(calories_burnt_kcal) as total_cals
        FROM workouts
        WHERE profile_name = ?
        GROUP BY DATE(start_time)
        ORDER BY date_str DESC
        LIMIT 60
      ''', [_profileName]);
      
      // Calculate trailing 7 days
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      
      final Map<String, Map<String, dynamic>> dateMap = {};
      for (var r in results) {
        final dStr = r['date_str'] as String;
        dateMap[dStr] = r;
      }
      
      final List<Map<String, dynamic>> past7 = [];
      int wCount = 0;
      int wSec = 0;
      double wCals = 0.0;

      for (int i = 6; i >= 0; i--) {
        final d = today.subtract(Duration(days: i));
        final dStr = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        final matched = dateMap[dStr];
        
        final count = (matched?['workout_count'] as num?)?.toInt() ?? 0;
        final sec = (matched?['total_time'] as num?)?.toInt() ?? 0;
        final cals = (matched?['total_cals'] as num?)?.toDouble() ?? 0.0;
        
        wCount += count;
        wSec += sec;
        wCals += cals;

        past7.add({
          'dateStr': dStr,
          'dayName': dayNames[d.weekday - 1],
          'minutes': sec / 60.0,
          'workouts': count,
          'calories': cals,
          'isToday': i == 0,
        });
      }

      setState(() {
        _availableProfiles = allProfiles.map((p) => p['name'] as String).toList();
        _days = results;
        _past7Days = past7;
        _weeklyWorkouts = wCount;
        _weeklySeconds = wSec;
        _weeklyCalories = wCals;
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

  String _formatDate(String dateStr) {
    try {
      final parts = dateStr.split('-');
      final dt = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
    } catch (_) {
      return dateStr;
    }
  }

  Widget _buildWeeklySummaryCard() {
    double maxMinutes = 0.0;
    for (var d in _past7Days) {
      final m = d['minutes'] as double;
      if (m > maxMinutes) maxMinutes = m;
    }
    final double yMax = (maxMinutes * 1.25).clamp(30.0, 180.0);

    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color badgeCyan = isDark ? AppColors.cyan : AppColors.cyanLight;
    final Color badgeMint = isDark ? AppColors.mintNeon : AppColors.mintLightPrimary;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: badgeCyan.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.insights_rounded, size: 16, color: badgeCyan),
              ),
              const SizedBox(width: 8),
              Text(
                'WEEKLY ACTIVITY (LAST 7 DAYS)',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              if (_weeklyWorkouts > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: badgeMint.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Active Week',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: badgeMint,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildKpiPill(
                  label: 'WORKOUTS',
                  value: '$_weeklyWorkouts',
                  icon: Icons.fitness_center,
                  iconColor: isDark ? AppColors.mintNeon : AppColors.mintLightPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildKpiPill(
                  label: 'TOTAL TIME',
                  value: _weeklySeconds >= 3600
                      ? '${_weeklySeconds ~/ 3600}h ${((_weeklySeconds % 3600) ~/ 60)}m'
                      : '${_weeklySeconds ~/ 60}m',
                  icon: Icons.timer,
                  iconColor: isDark ? AppColors.cyan : AppColors.cyanLight,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildKpiPill(
                  label: 'CALORIES',
                  value: '${_weeklyCalories.toInt()} kcal',
                  icon: Icons.local_fire_department,
                  iconColor: isDark ? AppColors.orangeNeon : AppColors.orangeLightSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 130,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: yMax,
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: (yMax / 2).clamp(15.0, 60.0),
                      getTitlesWidget: (val, meta) {
                        if (val == 0) return const SizedBox.shrink();
                        return Text(
                          '${val.toInt()}m',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 9),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 26,
                      getTitlesWidget: (val, meta) {
                        final idx = val.toInt();
                        if (idx < 0 || idx >= _past7Days.length) return const SizedBox.shrink();
                        final day = _past7Days[idx];
                        final isToday = day['isToday'] as bool;
                        final hasWorkout = (day['workouts'] as int) > 0;
                        return Padding(
                          padding: const EdgeInsets.only(top: 6.0),
                          child: Text(
                            isToday ? 'Today' : day['dayName'] as String,
                            style: TextStyle(
                              color: isToday
                                  ? (isDark ? AppColors.mintNeon : AppColors.mintLightPrimary)
                                  : (hasWorkout ? Theme.of(context).colorScheme.onSurface : Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                              fontWeight: (isToday || hasWorkout) ? FontWeight.bold : FontWeight.normal,
                              fontSize: 10,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: (yMax / 3).clamp(10.0, 60.0),
                  getDrawingHorizontalLine: (_) => FlLine(color: isDark ? Colors.white10 : AppColors.lightBorder, strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                barGroups: List.generate(_past7Days.length, (index) {
                  final day = _past7Days[index];
                  final double minutes = day['minutes'] as double;
                  final bool isToday = day['isToday'] as bool;

                  return BarChartGroupData(
                    x: index,
                    barRods: [
                      BarChartRodData(
                        toY: minutes > 0 ? minutes : 0.5,
                        width: 14,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                        gradient: LinearGradient(
                          colors: minutes > 0
                              ? (isToday
                                  ? [isDark ? AppColors.mintNeon : AppColors.mintLightPrimary, isDark ? AppColors.cyan : AppColors.cyanLight]
                                  : [Theme.of(context).colorScheme.primary, isDark ? AppColors.blue : AppColors.cyanLight])
                              : [isDark ? Colors.white12 : AppColors.lightBorder, isDark ? Colors.white12 : AppColors.lightBorder],
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                        ),
                        backDrawRodData: BackgroundBarChartRodData(
                          show: true,
                          toY: yMax,
                          color: isDark ? Colors.white.withValues(alpha: 0.03) : AppColors.lightSurfaceSubtle.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiPill({
    required String label,
    required String value,
    required IconData icon,
    required Color iconColor,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.04) : AppColors.lightSurfaceSubtle,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.white10 : AppColors.lightBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: iconColor),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 8.5,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isPhoneLandscape = context.isPhoneLandscape;
    return Scaffold(
      appBar: isPhoneLandscape
          ? null
          : AppBar(
              title: const Text('Workout History'),
              actions: [
                ProfileSelectorCapsule(
                  currentProfile: _profileName,
                  availableProfiles: _availableProfiles,
                  onProfileSelected: _onProfileChanged,
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadHistory,
                )
              ],
            ),
      body: RefreshIndicator(
        onRefresh: _loadHistory,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      _buildWeeklySummaryCard(),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'ALL SESSIONS',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                                color: Colors.grey,
                              ),
                            ),
                            Text(
                              '${_days.length} days logged',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_days.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(40.0),
                          child: Center(child: Text('No workouts found. Go crush one!')),
                        )
                      else
                        ..._days.map((day) {
                          final int totalSec = (day['total_time'] as num?)?.toInt() ?? 0;
                          final String timeStr = totalSec >= 3600
                              ? '${totalSec ~/ 3600}h ${((totalSec % 3600) ~/ 60).toString().padLeft(2, '0')}m'
                              : '${totalSec ~/ 60}m ${totalSec % 60}s';
                          final dateStr = day['date_str'] as String;
                          final double cals = (day['total_cals'] as num?)?.toDouble() ?? 0.0;

                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(
                                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                              ),
                            ),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                                child: Icon(Icons.calendar_today, size: 18, color: Theme.of(context).colorScheme.primary),
                              ),
                              title: Text(
                                _formatDate(dateStr),
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                              subtitle: Text(
                                '${day['workout_count']} workout(s) • $timeStr${cals > 0 ? ' • ${cals.toInt()} kcal' : ''}',
                                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                              ),
                              trailing: const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
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
                        }),
                      const SizedBox(height: 32),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

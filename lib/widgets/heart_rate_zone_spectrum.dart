import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../utils/calorie_calculator.dart';

/// A rich, real-time Heart Rate Zone Spectrum and Distribution widget for desktop/tablet dashboards.
/// Visualizes the 5-zone spectrum (Z1 to Z5), active zone highlighting, time spent per zone,
/// and a real-time heart rate trend sparkline.
class HeartRateZoneSpectrum extends StatelessWidget {
  final int currentHr;
  final int maxHr;
  final List<Map<String, dynamic>> hrDetails;
  final bool isCompact;

  const HeartRateZoneSpectrum({
    super.key,
    required this.currentHr,
    required this.maxHr,
    required this.hrDetails,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bool hasHr = currentHr > 0;
    final int resolvedMaxHr = maxHr > 0 ? maxHr : 180;
    final String currentZone = hasHr ? CalorieCalculator.calculateZone(currentHr, resolvedMaxHr) : '';
    final Color currentZoneColor = hasHr ? CalorieCalculator.getZoneColor(currentZone) : Colors.grey;

    // Calculate time spent per zone in seconds
    final Map<String, int> zoneSeconds = {
      'ZONE 1': 0,
      'ZONE 2': 0,
      'ZONE 3': 0,
      'ZONE 4': 0,
      'ZONE 5': 0,
    };

    for (final sample in hrDetails) {
      final z = sample['zone'] as String? ?? '';
      if (zoneSeconds.containsKey(z)) {
        zoneSeconds[z] = (zoneSeconds[z] ?? 0) + 1;
      }
    }

    final int totalLoggedSeconds = zoneSeconds.values.fold(0, (a, b) => a + b);

    // Zone BPM boundaries
    final int z1Min = (resolvedMaxHr * 0.50).round();
    final int z2Min = (resolvedMaxHr * 0.60).round();
    final int z3Min = (resolvedMaxHr * 0.70).round();
    final int z4Min = (resolvedMaxHr * 0.80).round();
    final int z5Min = (resolvedMaxHr * 0.90).round();

    final List<_ZoneInfo> zones = [
      _ZoneInfo(
        key: 'ZONE 1',
        label: 'Z1',
        name: 'Recovery',
        color: const Color(0xFF38B6FF),
        bpmRange: '$z1Min-$z2Min',
        seconds: zoneSeconds['ZONE 1'] ?? 0,
        isActive: currentZone == 'ZONE 1',
      ),
      _ZoneInfo(
        key: 'ZONE 2',
        label: 'Z2',
        name: 'Aerobic',
        color: const Color(0xFF0DF2A3),
        bpmRange: '$z2Min-$z3Min',
        seconds: zoneSeconds['ZONE 2'] ?? 0,
        isActive: currentZone == 'ZONE 2',
      ),
      _ZoneInfo(
        key: 'ZONE 3',
        label: 'Z3',
        name: 'Tempo',
        color: const Color(0xFFFFD60A),
        bpmRange: '$z3Min-$z4Min',
        seconds: zoneSeconds['ZONE 3'] ?? 0,
        isActive: currentZone == 'ZONE 3',
      ),
      _ZoneInfo(
        key: 'ZONE 4',
        label: 'Z4',
        name: 'Threshold',
        color: const Color(0xFFFF7A00),
        bpmRange: '$z4Min-$z5Min',
        seconds: zoneSeconds['ZONE 4'] ?? 0,
        isActive: currentZone == 'ZONE 4',
      ),
      _ZoneInfo(
        key: 'ZONE 5',
        label: 'Z5',
        name: 'Anaerobic',
        color: const Color(0xFFFF3B30),
        bpmRange: '>$z5Min',
        seconds: zoneSeconds['ZONE 5'] ?? 0,
        isActive: currentZone == 'ZONE 5',
      ),
    ];

    // Extract recent HR data points for sparkline
    final List<int> hrTrend = hrDetails.map((e) => (e['bpm'] as num).toInt()).toList();

    return Container(
      padding: EdgeInsets.all(isCompact ? 12 : 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasHr
              ? currentZoneColor.withValues(alpha: 0.3)
              : (isDark ? Colors.white10 : AppColors.lightBorder),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: hasHr ? currentZoneColor.withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.graphic_eq,
                      size: 14,
                      color: hasHr ? currentZoneColor : Colors.grey,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'HR ZONE SPECTRUM',
                    style: TextStyle(
                      fontSize: isCompact ? 10 : 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              if (hasHr && currentZone.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: currentZoneColor.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: currentZoneColor.withValues(alpha: 0.6), width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: currentZoneColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$currentZone • $currentHr BPM',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: currentZoneColor,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Text(
                  'No HR Monitor',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade500,
                  ),
                ),
            ],
          ),
          SizedBox(height: isCompact ? 10 : 14),

          // 5-Zone Continuous Segmented Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: isCompact ? 8 : 10,
              child: Row(
                children: zones.map((z) {
                  return Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        color: z.isActive
                            ? z.color
                            : z.color.withValues(alpha: hasHr ? 0.35 : 0.15),
                        borderRadius: BorderRadius.circular(3),
                        boxShadow: z.isActive
                            ? [
                                BoxShadow(
                                  color: z.color.withValues(alpha: 0.6),
                                  blurRadius: 6,
                                  spreadRadius: 1,
                                ),
                              ]
                            : null,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          SizedBox(height: isCompact ? 8 : 12),

          // Zone Breakdown Chips
          Row(
            children: zones.map((z) {
              final double pct = totalLoggedSeconds > 0
                  ? (z.seconds / totalLoggedSeconds) * 100
                  : 0.0;
              final String timeStr = _formatSeconds(z.seconds);

              return Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  padding: EdgeInsets.symmetric(
                    vertical: isCompact ? 6 : 8,
                    horizontal: 4,
                  ),
                  decoration: BoxDecoration(
                    color: z.isActive
                        ? z.color.withValues(alpha: 0.18)
                        : (isDark ? Colors.white.withValues(alpha: 0.03) : AppColors.lightSurfaceSubtle),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: z.isActive
                          ? z.color
                          : (isDark ? Colors.white10 : AppColors.lightBorder),
                      width: z.isActive ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        z.label,
                        style: TextStyle(
                          fontSize: isCompact ? 10 : 11,
                          fontWeight: FontWeight.bold,
                          color: z.isActive ? z.color : z.color.withValues(alpha: 0.8),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        z.bpmRange,
                        style: TextStyle(
                          fontSize: isCompact ? 8 : 9,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        totalLoggedSeconds > 0 ? '${pct.round()}%' : timeStr,
                        style: TextStyle(
                          fontSize: isCompact ? 9 : 10,
                          fontWeight: z.isActive ? FontWeight.bold : FontWeight.w600,
                          color: z.isActive ? Theme.of(context).colorScheme.onSurface : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),

          // Live HR Sparkline Trend (renders when sufficient data is available)
          if (hrTrend.length >= 6) ...[
            SizedBox(height: isCompact ? 10 : 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'LIVE HR TREND',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  '${hrTrend.length}s elapsed',
                  style: TextStyle(
                    fontSize: 9,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: isCompact ? 40 : 54,
              child: CustomPaint(
                painter: _HrSparklinePainter(
                  data: hrTrend,
                  lineColor: currentZoneColor,
                  isDark: isDark,
                  minHr: z1Min,
                  maxHr: resolvedMaxHr,
                ),
                size: Size.infinite,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatSeconds(int sec) {
    if (sec <= 0) return '0:00';
    final m = sec ~/ 60;
    final s = sec % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

class _ZoneInfo {
  final String key;
  final String label;
  final String name;
  final Color color;
  final String bpmRange;
  final int seconds;
  final bool isActive;

  _ZoneInfo({
    required this.key,
    required this.label,
    required this.name,
    required this.color,
    required this.bpmRange,
    required this.seconds,
    required this.isActive,
  });
}

class _HrSparklinePainter extends CustomPainter {
  final List<int> data;
  final Color lineColor;
  final bool isDark;
  final int minHr;
  final int maxHr;

  _HrSparklinePainter({
    required this.data,
    required this.lineColor,
    required this.isDark,
    required this.minHr,
    required this.maxHr,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;

    final double effectiveMin = (data.reduce((a, b) => a < b ? a : b) - 5).clamp(40, 220).toDouble();
    final double effectiveMax = (data.reduce((a, b) => a > b ? a : b) + 5).clamp(effectiveMin + 15, 230).toDouble();
    final double range = effectiveMax - effectiveMin;

    final path = Path();
    final fillPath = Path();

    final double dx = size.width / (data.length - 1);

    for (int i = 0; i < data.length; i++) {
      final double normalized = (data[i] - effectiveMin) / range;
      final double y = size.height - (normalized * size.height).clamp(0.0, size.height);
      final double x = i * dx;

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }

      if (i == data.length - 1) {
        fillPath.lineTo(x, size.height);
        fillPath.close();
      }
    }

    // Draw gradient under the curve
    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        lineColor.withValues(alpha: 0.25),
        lineColor.withValues(alpha: 0.0),
      ],
    );

    final fillPaint = Paint()
      ..shader = gradient.createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;
    canvas.drawPath(fillPath, fillPaint);

    // Draw the sparkline stroke
    final strokePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, strokePaint);

    // Draw a pulsating circle at the latest point
    final double lastX = (data.length - 1) * dx;
    final double lastNormalized = (data.last - effectiveMin) / range;
    final double lastY = size.height - (lastNormalized * size.height).clamp(0.0, size.height);

    final dotPaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(lastX, lastY), 3.5, dotPaint);

    final haloPaint = Paint()
      ..color = lineColor.withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(lastX, lastY), 6.5, haloPaint);
  }

  @override
  bool shouldRepaint(covariant _HrSparklinePainter oldDelegate) {
    return oldDelegate.data.length != data.length ||
        oldDelegate.lineColor != lineColor ||
        (data.isNotEmpty && oldDelegate.data.isNotEmpty && oldDelegate.data.last != data.last);
  }
}

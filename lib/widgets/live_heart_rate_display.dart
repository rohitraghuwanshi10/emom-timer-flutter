import 'package:flutter/material.dart';
import '../utils/calorie_calculator.dart';
import 'pulsing_heart.dart';

class LiveHeartRateDisplay extends StatelessWidget {
  final int currentHr;
  final int maxHr;
  final bool isCompact;

  const LiveHeartRateDisplay({
    super.key,
    required this.currentHr,
    required this.maxHr,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    final bool isConnected = currentHr > 0;
    final String zone = isConnected ? CalorieCalculator.calculateZone(currentHr, maxHr) : '';
    final Color zoneColor = isConnected ? CalorieCalculator.getZoneColor(zone) : Colors.grey;

    if (isCompact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          PulsingHeart(isActive: isConnected),
          const SizedBox(width: 6),
          Text(
            isConnected ? '$currentHr' : '--',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: isConnected ? Theme.of(context).colorScheme.onSurface : Colors.grey.withValues(alpha: 0.3),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'BPM',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: isConnected ? Colors.grey : Colors.grey.withValues(alpha: 0.3),
            ),
          ),
          if (isConnected && zone.isNotEmpty) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: zoneColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
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
                  fontSize: 11,
                ),
              ),
            ),
          ] else if (!isConnected) ...[
            const SizedBox(width: 6),
            Text(
              'DISCONNECTED',
              style: TextStyle(
                color: Colors.grey.withValues(alpha: 0.4),
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ],
      );
    }

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
              isConnected ? '$currentHr' : '--',
              style: TextStyle(
                fontSize: 64,
                fontWeight: FontWeight.w900,
                color: isConnected ? Theme.of(context).colorScheme.onSurface : Colors.grey.withValues(alpha: 0.3),
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
}

import 'package:flutter/material.dart';
import '../services/hrr_service.dart';
import '../theme/app_colors.dart';

class RecoveryTrackingBanner extends StatelessWidget {
  const RecoveryTrackingBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<HrrState>(
      valueListenable: HrrService.instance.stateNotifier,
      builder: (context, hrrState, _) {
        if (!hrrState.isTracking) return const SizedBox.shrink();

        final mins = hrrState.secondsRemaining ~/ 60;
        final secs = hrrState.secondsRemaining % 60;
        final timeStr = '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';

        final isDark = Theme.of(context).brightness == Brightness.dark;
        final accentColor = isDark ? AppColors.cyan : AppColors.cyanLight;

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accentColor.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.favorite, color: accentColor, size: 18),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'HR RECOVERY TRACKING',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: accentColor,
                          letterSpacing: 0.8,
                        ),
                      ),
                      Text(
                        'Measuring post-workout recovery ($timeStr left)',
                        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)),
                      ),
                    ],
                  ),
                ],
              ),
              TextButton(
                onPressed: () => HrrService.instance.finalizeRecovery(),
                style: TextButton.styleFrom(
                  foregroundColor: accentColor,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                ),
                child: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      },
    );
  }
}

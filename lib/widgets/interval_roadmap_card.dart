import 'package:flutter/material.dart';
import '../models/workout_engine.dart';
import '../theme/app_colors.dart';
import '../utils/format_utils.dart';

/// A rich, active interval roadmap and round progression card for desktop & tablet workouts.
/// Provides visual segment tracking, phase status, work/rest interval pacing, and round badges.
class IntervalRoadmapCard extends StatelessWidget {
  final WorkoutEvent currentEvent;
  final int totalRounds;
  final int workDuration;
  final int restDuration;
  final bool continuousMode;
  final int workTimeSec;
  final int restTimeSec;
  final bool isCompact;

  const IntervalRoadmapCard({
    super.key,
    required this.currentEvent,
    required this.totalRounds,
    required this.workDuration,
    required this.restDuration,
    required this.continuousMode,
    required this.workTimeSec,
    required this.restTimeSec,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final current = currentEvent.currentRound;
    final bool isWork = currentEvent.state == WorkoutState.WORK;
    final bool isRest = currentEvent.state == WorkoutState.REST;
    final bool isPrep = currentEvent.state == WorkoutState.PREP;
    final bool isPaused = currentEvent.state == WorkoutState.PAUSED;

    final Color phaseColor = isPrep
        ? Colors.amber
        : (isWork
            ? (isDark ? AppColors.mintNeon : AppColors.mintLightPrimary)
            : (isRest
                ? (isDark ? AppColors.orangeNeon : AppColors.orangeLightSecondary)
                : Colors.grey));

    final String phaseLabel = isPrep
        ? 'PREPARE'
        : (isWork
            ? 'WORK PHASE'
            : (isRest
                ? (currentEvent.isWaitingForHr ? 'HOLDING FOR HR' : 'REST PHASE')
                : (isPaused ? 'PAUSED' : 'READY')));

    final int currentPhaseTotal = isPrep ? 10 : (isWork ? workDuration : restDuration);
    final double phaseProgress = currentPhaseTotal > 0
        ? ((currentPhaseTotal - currentEvent.timeRemaining) / currentPhaseTotal).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      padding: EdgeInsets.all(isCompact ? 12 : 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: phaseColor.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: Section Title & Round Summary
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: phaseColor.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isWork ? Icons.fitness_center : (isRest ? Icons.coffee : Icons.timer_outlined),
                      size: 14,
                      color: phaseColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'ROUND PROGRESSION',
                    style: TextStyle(
                      fontSize: isCompact ? 10 : 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: phaseColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: phaseColor.withValues(alpha: 0.4), width: 1),
                ),
                child: Text(
                  continuousMode
                      ? 'Round $current (Open-Ended)'
                      : 'Round $current of $totalRounds',
                  style: TextStyle(
                    fontSize: isCompact ? 11 : 12,
                    fontWeight: FontWeight.bold,
                    color: phaseColor,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: isCompact ? 10 : 14),

          // Active Phase Progress Bar & Countdown Sub-bar
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: phaseColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: phaseColor.withValues(alpha: 0.7),
                              blurRadius: 6,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        phaseLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: phaseColor,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${_formatDuration(currentEvent.timeRemaining)} remaining',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: currentEvent.isWaitingForHr ? null : phaseProgress,
                  minHeight: isCompact ? 8 : 10,
                  backgroundColor: isDark ? Colors.white12 : AppColors.lightBorder,
                  valueColor: AlwaysStoppedAnimation<Color>(phaseColor),
                ),
              ),
            ],
          ),
          SizedBox(height: isCompact ? 12 : 16),

          // Round Chips (Fixed rounds <= 24) or Continuous Interval Split Summary
          if (!continuousMode && totalRounds <= 24)
            Wrap(
              spacing: isCompact ? 6 : 8,
              runSpacing: isCompact ? 6 : 8,
              children: List.generate(totalRounds, (index) {
                final roundNum = index + 1;
                final bool isCompleted = roundNum < current;
                final bool isCurrent = roundNum == current;

                Color bgColor;
                Color borderColor;
                Color textColor;

                if (isCompleted) {
                  bgColor = Theme.of(context).colorScheme.primary.withValues(alpha: 0.2);
                  borderColor = Theme.of(context).colorScheme.primary;
                  textColor = Theme.of(context).colorScheme.primary;
                } else if (isCurrent) {
                  bgColor = phaseColor.withValues(alpha: 0.25);
                  borderColor = phaseColor;
                  textColor = phaseColor;
                } else {
                  bgColor = isDark ? Colors.white.withValues(alpha: 0.04) : AppColors.lightSurfaceSubtle;
                  borderColor = isDark ? Colors.white12 : AppColors.lightBorder;
                  textColor = isDark ? Colors.white38 : AppColors.lightTextTertiary;
                }

                final double chipSize = isCompact ? 30 : 34;

                return Container(
                  width: chipSize,
                  height: chipSize,
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(isCompact ? 8 : 10),
                    border: Border.all(color: borderColor, width: isCurrent ? 2 : 1),
                  ),
                  alignment: Alignment.center,
                  child: isCompleted
                      ? Icon(Icons.check, size: isCompact ? 14 : 16, color: textColor)
                      : Text(
                          '$roundNum',
                          style: TextStyle(
                            fontSize: isCompact ? 11 : 12,
                            fontWeight: isCurrent ? FontWeight.w900 : FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                );
              }),
            )
          else ...[
            // Open-ended / Continuous mode split breakdown
            Row(
              children: [
                Expanded(
                  child: _buildSplitPill(
                    context,
                    label: 'TOTAL WORK TIME',
                    value: _formatDuration(workTimeSec),
                    color: isDark ? AppColors.mintNeon : AppColors.mintLightPrimary,
                    icon: Icons.timer,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildSplitPill(
                    context,
                    label: 'TOTAL REST TIME',
                    value: _formatDuration(restTimeSec),
                    color: isDark ? AppColors.orangeNeon : AppColors.orangeLightSecondary,
                    icon: Icons.coffee,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildSplitPill(
                    context,
                    label: 'COMPLETED ROUNDS',
                    value: '${current > 0 ? current - 1 : 0}',
                    color: Theme.of(context).colorScheme.primary,
                    icon: Icons.check_circle_outline,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSplitPill(
    BuildContext context, {
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 8 : 10,
        vertical: isCompact ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.03) : AppColors.lightSurfaceSubtle,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? Colors.white10 : AppColors.lightBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 11, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: isCompact ? 12 : 13,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(int seconds) => FormatUtils.formatDuration(seconds);
}

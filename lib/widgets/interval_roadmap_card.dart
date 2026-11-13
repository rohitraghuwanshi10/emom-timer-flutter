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
      padding: EdgeInsets.all(isCompact ? 10 : 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: phaseColor.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: Section Title, Compact Phase Status & Round Summary
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: phaseColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isWork ? Icons.fitness_center : (isRest ? Icons.coffee : Icons.timer_outlined),
                  size: 13,
                  color: phaseColor,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'ROUND PROGRESSION',
                style: TextStyle(
                  fontSize: isCompact ? 10 : 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: phaseColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: phaseColor.withValues(alpha: 0.7),
                      blurRadius: 5,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$phaseLabel · ${_formatDuration(currentEvent.timeRemaining)}',
                style: TextStyle(
                  fontSize: isCompact ? 10.5 : 11.5,
                  fontWeight: FontWeight.bold,
                  color: phaseColor,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: phaseColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: phaseColor.withValues(alpha: 0.4), width: 1),
                ),
                child: Text(
                  continuousMode
                      ? 'Rd $current (Open)'
                      : 'Rd $current / $totalRounds',
                  style: TextStyle(
                    fontSize: isCompact ? 10.5 : 11.5,
                    fontWeight: FontWeight.bold,
                    color: phaseColor,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: isCompact ? 8 : 10),

          // Full-width Segmented Round Bar (<= 12 rounds)
          if (!continuousMode && totalRounds > 0 && totalRounds <= 12)
            Row(
              children: List.generate(totalRounds, (index) {
                final roundNum = index + 1;
                final bool isCompleted = roundNum < current;
                final bool isCurrent = roundNum == current;

                final Color completedColor = Theme.of(context).colorScheme.primary;
                final Color bgColor = isCompleted
                    ? completedColor.withValues(alpha: 0.2)
                    : (isCurrent
                        ? phaseColor.withValues(alpha: 0.12)
                        : (isDark ? Colors.white.withValues(alpha: 0.04) : AppColors.lightSurfaceSubtle));
                final Color borderColor = isCompleted
                    ? completedColor.withValues(alpha: 0.7)
                    : (isCurrent
                        ? phaseColor
                        : (isDark ? Colors.white12 : AppColors.lightBorder));
                final Color textColor = isCompleted
                    ? completedColor
                    : (isCurrent
                        ? Theme.of(context).colorScheme.onSurface
                        : (isDark ? Colors.white54 : AppColors.lightTextTertiary));

                return Expanded(
                  child: Container(
                    height: isCompact ? 28 : 32,
                    margin: EdgeInsets.only(right: index == totalRounds - 1 ? 0 : 6),
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: borderColor, width: isCurrent ? 1.5 : 1),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      children: [
                        if (isCurrent)
                          FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: currentEvent.isWaitingForHr ? 1.0 : phaseProgress,
                            heightFactor: 1.0,
                            child: Container(
                              decoration: BoxDecoration(
                                color: phaseColor.withValues(alpha: currentEvent.isWaitingForHr ? 0.22 : 0.34),
                              ),
                            ),
                          ),
                        Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isCompleted) ...[
                                Icon(Icons.check, size: isCompact ? 12 : 14, color: textColor),
                                if (totalRounds <= 8) const SizedBox(width: 3),
                              ],
                              if (!isCompleted || totalRounds <= 8)
                                Text(
                                  totalRounds <= 6 ? 'Rd $roundNum' : '$roundNum',
                                  style: TextStyle(
                                    fontSize: isCompact ? 10.5 : 11.5,
                                    fontWeight: isCurrent ? FontWeight.w900 : FontWeight.bold,
                                    color: textColor,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            )
          else if (!continuousMode && totalRounds <= 24) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: currentEvent.isWaitingForHr ? null : phaseProgress,
                minHeight: 5,
                backgroundColor: isDark ? Colors.white12 : AppColors.lightBorder,
                valueColor: AlwaysStoppedAnimation<Color>(phaseColor),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
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

                final double chipSize = isCompact ? 26 : 28;

                return Container(
                  width: chipSize,
                  height: chipSize,
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: borderColor, width: isCurrent ? 2 : 1),
                  ),
                  alignment: Alignment.center,
                  child: isCompleted
                      ? Icon(Icons.check, size: 13, color: textColor)
                      : Text(
                          '$roundNum',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isCurrent ? FontWeight.w900 : FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                );
              }),
            ),
          ] else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: LinearProgressIndicator(
                value: currentEvent.isWaitingForHr ? null : phaseProgress,
                minHeight: 6,
                backgroundColor: isDark ? Colors.white12 : AppColors.lightBorder,
                valueColor: AlwaysStoppedAnimation<Color>(phaseColor),
              ),
            ),
            const SizedBox(height: 8),
            // Open-ended / Continuous mode split breakdown
            Row(
              children: [
                Expanded(
                  child: _buildSplitPill(
                    context,
                    label: 'TOTAL WORK',
                    value: _formatDuration(workTimeSec),
                    color: isDark ? AppColors.mintNeon : AppColors.mintLightPrimary,
                    icon: Icons.timer,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildSplitPill(
                    context,
                    label: 'TOTAL REST',
                    value: _formatDuration(restTimeSec),
                    color: isDark ? AppColors.orangeNeon : AppColors.orangeLightSecondary,
                    icon: Icons.coffee,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildSplitPill(
                    context,
                    label: 'COMPLETED',
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

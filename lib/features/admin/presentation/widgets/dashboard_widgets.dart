import 'package:flutter/material.dart';
import 'package:apx_pro/core/theme/colors.dart';
import 'package:apx_pro/core/theme/glass.dart';
import 'package:apx_pro/features/consultation/data/appointment_model.dart';
import 'package:apx_pro/features/rehab/data/rehab_models.dart';

// ── Shared status → label/color mappers ───────────────────────────────────────
// One source of truth for how a workout or appointment status is worded and
// coloured, reused by the dashboard section, the workout-history screen, and
// the appointment-detail screen.

String workoutStatusLabel(WorkoutTodayStatus s) {
  switch (s) {
    case WorkoutTodayStatus.completed:
      return 'Completed';
    case WorkoutTodayStatus.inProgress:
      return 'In Progress';
    case WorkoutTodayStatus.notStarted:
      return 'Not Started';
  }
}

Color workoutStatusColor(WorkoutTodayStatus s) {
  switch (s) {
    case WorkoutTodayStatus.completed:
      return AppColors.success;
    case WorkoutTodayStatus.inProgress:
      return AppColors.warning;
    case WorkoutTodayStatus.notStarted:
      return AppColors.textMuted;
  }
}

/// Patient-facing appointment status label (collapses the backend's finer
/// states into what a therapist needs to see at a glance).
String appointmentStatusLabel(AppointmentModel a) {
  if (a.isCompleted) return 'Completed';
  if (a.status == 'cancelled') return 'Cancelled';
  if (a.status == 'rejected') return 'Rejected';
  if (a.isApproved) return a.isUpcoming ? 'Upcoming' : 'Approved';
  if (a.isPending) return 'Pending';
  return a.status;
}

Color appointmentStatusColor(AppointmentModel a) {
  if (a.isCompleted) return AppColors.success;
  if (a.isCancelled) return AppColors.error;
  if (a.isApproved) return AppColors.primary;
  if (a.isPending) return AppColors.warning;
  return AppColors.textMuted;
}

/// Reusable building blocks for the admin patient dashboard (patient info,
/// workout progress, medical records, appointment history). Centralised here so
/// the sections share one visual language and no card re-implements a pill,
/// stat tile, or progress bar. All match the existing AppColors + GlassCard
/// design language used across the admin screens.

/// A bold section title with a consistent top gap, e.g. "Workout Progress".
class DashboardSectionHeader extends StatelessWidget {
  const DashboardSectionHeader(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// A small uppercase caption used above values inside cards (e.g. "OVERALL
/// PROGRESS", "COMPLIANCE").
class DashboardCaption extends StatelessWidget {
  const DashboardCaption(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: 10,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
      ),
    );
  }
}

/// Rounded progress bar with an inline percentage, matching the dashboard's
/// `home_tab` bar (6px, cyan on translucent track).
class DashboardProgressBar extends StatelessWidget {
  const DashboardProgressBar({
    super.key,
    required this.fraction,
    this.color = AppColors.primary,
    this.showPercentLabel = true,
  });

  /// 0.0 – 1.0
  final double fraction;
  final Color color;
  final bool showPercentLabel;

  @override
  Widget build(BuildContext context) {
    final f = fraction.clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: f,
                  minHeight: 8,
                  backgroundColor: Colors.white.withValues(alpha: 0.1),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
            ),
            if (showPercentLabel) ...[
              const SizedBox(width: 12),
              Text(
                '${(f * 100).round()}%',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// A compact stat cell: big value over a muted label, with an accent icon.
/// Used for Assigned / Completed / Remaining and Compliance.
class DashboardStatTile extends StatelessWidget {
  const DashboardStatTile({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.color = AppColors.primary,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 18,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

/// A colored status pill (Active / Completed / Cancelled / today's status …).
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// A neutral icon+text chip (meeting type, duration, exercise count …).
class MetaChip extends StatelessWidget {
  const MetaChip({super.key, required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: c, size: 13),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: c, fontSize: 11)),
        ],
      ),
    );
  }
}

/// Consistent empty-state card used by every section that can be empty.
class DashboardEmptyState extends StatelessWidget {
  const DashboardEmptyState({super.key, required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textMuted, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// Consistent inline error + retry card used by async sections.
class DashboardErrorState extends StatelessWidget {
  const DashboardErrorState({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onRetry,
            child: const Text('Retry', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }
}

/// A small centered spinner for inline section loading.
class DashboardLoading extends StatelessWidget {
  const DashboardLoading({super.key, this.height = 80});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
        ),
      ),
    );
  }
}

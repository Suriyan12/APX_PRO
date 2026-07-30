import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:apx_pro/core/theme/colors.dart';
import 'package:apx_pro/core/theme/glass.dart';
import 'package:apx_pro/features/admin/presentation/widgets/dashboard_widgets.dart';
import 'package:apx_pro/features/consultation/data/appointment_model.dart';

/// Read-only detail of a single appointment (admin/therapist view), opened from
/// the Appointment History section of the patient dashboard.
///
/// FUTURE — Therapist Notes: this screen is the intended home for per-
/// appointment therapist notes. When that feature is built, add a
/// `TherapistNotesSection(appointmentId: appointment.id)` widget below the
/// details card here, backed by its own repository/provider and a
/// `therapist_notes` table keyed by appointment_id. No notes logic exists yet
/// by design; nothing else on this screen needs to change to add it.
class AppointmentDetailScreen extends StatelessWidget {
  const AppointmentDetailScreen({super.key, required this.appointment});

  final AppointmentModel? appointment;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: 'Appointment',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: GlassOrbBackground(
        child: SafeArea(
          child: appointment == null
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: DashboardEmptyState(
                    icon: Icons.event_busy_rounded,
                    message: 'This appointment is no longer available.',
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                  child: _DetailBody(appointment: appointment!),
                ),
        ),
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.appointment});

  final AppointmentModel appointment;

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    final dateStr = DateFormat('EEEE, MMM d, y').format(a.startTime);
    final timeStr =
        '${DateFormat('h:mm a').format(a.startTime)} – ${DateFormat('h:mm a').format(a.endTime)}';
    final statusColor = appointmentStatusColor(a);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GlassCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      dateStr,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  StatusPill(text: appointmentStatusLabel(a), color: statusColor),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                timeStr,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 14),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  MetaChip(
                    icon: a.isOnline
                        ? Icons.videocam_rounded
                        : Icons.location_on_outlined,
                    label: a.isOnline ? 'Google Meet' : 'In Person',
                    color: a.isOnline ? AppColors.secondary : AppColors.primary,
                  ),
                  if (a.patientName != null)
                    MetaChip(
                        icon: Icons.person_outline_rounded,
                        label: a.patientName!),
                ],
              ),
            ],
          ),
        ),
        if (a.notes != null && a.notes!.isNotEmpty) ...[
          const SizedBox(height: 16),
          _labelledCard('Patient Notes', a.notes!),
        ],
        if (a.cancellationReason != null &&
            a.cancellationReason!.isNotEmpty) ...[
          const SizedBox(height: 16),
          _labelledCard('Reason', a.cancellationReason!, tint: AppColors.error),
        ],
        if (a.isOnline &&
            a.isApproved &&
            a.meetingLink != null &&
            a.meetingLink!.isNotEmpty) ...[
          const SizedBox(height: 16),
          const DashboardSectionHeader('Meeting Link'),
          const SizedBox(height: 12),
          GlassCard(
            padding: const EdgeInsets.all(14),
            child: SelectableText(
              a.meetingLink!,
              style: const TextStyle(color: AppColors.primary, fontSize: 13),
            ),
          ),
        ],
        if (a.finalAmount > 0) ...[
          const SizedBox(height: 16),
          const DashboardSectionHeader('Payment'),
          const SizedBox(height: 12),
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _amountRow('Consultation Fee', a.consultationFee),
                if (a.discountAmount > 0) ...[
                  const SizedBox(height: 8),
                  _amountRow('Discount', -a.discountAmount,
                      valueColor: AppColors.success),
                ],
                const SizedBox(height: 8),
                const Divider(color: AppColors.border),
                const SizedBox(height: 8),
                _amountRow('Total Paid', a.finalAmount, bold: true),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _labelledCard(String label, String value, {Color? tint}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DashboardSectionHeader(label),
        const SizedBox(height: 12),
        GlassCard(
          padding: const EdgeInsets.all(16),
          child: Text(
            value,
            style: TextStyle(
              color: tint ?? AppColors.textSecondary,
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _amountRow(String label, double value,
      {bool bold = false, Color? valueColor}) {
    final sign = value < 0 ? '-' : '';
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
              color: bold ? AppColors.textPrimary : AppColors.textSecondary,
              fontSize: 13,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            )),
        Text(
          '$sign₹${value.abs().toStringAsFixed(2)}',
          style: TextStyle(
            color: valueColor ??
                (bold ? AppColors.textPrimary : AppColors.textSecondary),
            fontSize: 13,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

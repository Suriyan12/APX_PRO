import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:apx_pro/core/network/api_client.dart';
import 'package:apx_pro/core/theme/app_theme_extension.dart';
import 'package:apx_pro/core/theme/glass.dart';
import 'package:apx_pro/features/consultation/data/appointment_model.dart';
import 'package:apx_pro/features/consultation/presentation/controllers/appointment_controller.dart';

/// Standalone route wrapper (e.g. deep links) around [AdminAppointmentsView].
/// The Admin Panel embeds the view directly and does NOT use this wrapper.
class AdminAppointmentsScreen extends StatelessWidget {
  const AdminAppointmentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ext = context.ext;
    return Scaffold(
      backgroundColor: ext.background,
      appBar: GlassAppBar(
        title: 'Appointments',
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: ext.textPrimary, size: 18),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: const GlassOrbBackground(
        child: SafeArea(child: AdminAppointmentsView(embedded: false)),
      ),
    );
  }
}

/// Embeddable Appointment Management interface: approve (entering a Google Meet
/// link for online consults), reject, or cancel. Rendered directly inside the
/// Admin Panel "Appointments" tab (no Scaffold of its own), and also wrapped by
/// [AdminAppointmentsScreen] for standalone routing.
class AdminAppointmentsView extends ConsumerStatefulWidget {
  /// When embedded in the Admin Panel tab (default) the content renders behind
  /// the panel's tall glass app bar (users/appointments/notes tab chrome), so
  /// the list top is padded to clear it. The standalone route has its own
  /// (shorter) app bar that occupies its own space, and passes `false`.
  final bool embedded;
  const AdminAppointmentsView({super.key, this.embedded = true});

  @override
  ConsumerState<AdminAppointmentsView> createState() =>
      _AdminAppointmentsViewState();
}

class _AdminAppointmentsViewState
    extends ConsumerState<AdminAppointmentsView> {
  // Admin's action queue first. Filters: pending | approved | completed | cancelled | all
  String _filter = 'pending';
  String? _busyId;

  static const _filters = <String, String>{
    'pending': 'Pending',
    'approved': 'Approved',
    'completed': 'Completed',
    'cancelled': 'Cancelled',
    'all': 'All',
  };

  bool _matches(AppointmentModel a) {
    switch (_filter) {
      case 'pending':
        return a.isPending;
      case 'approved':
        return a.isApproved;
      case 'completed':
        return a.isCompleted;
      case 'cancelled':
        return a.isCancelled; // includes rejected
      default:
        return true;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => ref.read(appointmentProvider.notifier).load());
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  Future<void> _approve(AppointmentModel apt) async {
    final ext = context.ext;
    String? provider;
    String? link;
    if (apt.isOnline) {
      link = await _askMeetingLink();
      if (link == null) return; // cancelled
      provider = 'google_meet';
    }
    setState(() => _busyId = apt.id);
    try {
      await ref.read(appointmentProvider.notifier).approve(
            apt.id,
            meetingProvider: provider,
            meetingLink: link,
          );
      _snack('Appointment approved.', ext.success);
    } on ApiException catch (e) {
      _snack(e.message, ext.error);
    } catch (_) {
      _snack('Could not approve the appointment.', ext.error);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _reject(AppointmentModel apt) async {
    final ext = context.ext;
    final reason = await _askText(
      title: 'Reject appointment',
      hint: 'Reason (optional)',
      confirmLabel: 'Reject',
    );
    if (reason == null) return; // cancelled dialog
    setState(() => _busyId = apt.id);
    try {
      await ref
          .read(appointmentProvider.notifier)
          .reject(apt.id, reason: reason.isEmpty ? null : reason);
      _snack('Appointment rejected.', ext.error);
    } on ApiException catch (e) {
      _snack(e.message, ext.error);
    } catch (_) {
      _snack('Could not reject the appointment.', ext.error);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _cancel(AppointmentModel apt) async {
    final ext = context.ext;
    setState(() => _busyId = apt.id);
    try {
      await ref.read(appointmentProvider.notifier).cancel(apt.id);
      _snack('Appointment cancelled.', ext.error);
    } on ApiException catch (e) {
      _snack(e.message, ext.error);
    } catch (_) {
      _snack('Could not cancel the appointment.', ext.error);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  /// Google Meet link entry with light client-side validation (the backend
  /// re-validates authoritatively).
  Future<String?> _askMeetingLink() async {
    final controller = TextEditingController();
    final ext = context.ext;
    // Accept a full Meet URL OR a bare meeting code (abc-defg-hij); the backend
    // normalizes and re-validates authoritatively.
    final meetPattern = RegExp(
        r'^([a-z]{3}-[a-z]{4}-[a-z]{3}|https?://(www\.)?meet\.google\.com/([a-z]{3}-[a-z]{4}-[a-z]{3}|lookup/[A-Za-z0-9_-]+))',
        caseSensitive: false);
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        String? error;
        return StatefulBuilder(builder: (ctx, setLocal) {
          return _GlassDialog(
            title: 'Google Meet Link',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Paste the Google Meet link or code for this online '
                  'consultation.',
                  style: TextStyle(color: ext.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  autofocus: true,
                  style: TextStyle(color: ext.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'https://meet.google.com/abc-defg-hij',
                    hintStyle: TextStyle(color: ext.textMuted, fontSize: 12),
                    errorText: error,
                    filled: true,
                    fillColor: ext.glassTextFieldFill,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: ext.glassBorder),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: GlassButton(
                        label: 'Cancel',
                        onTap: () => Navigator.pop(ctx),
                        style: GlassButtonStyle.ghost,
                        width: double.infinity,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GlassButton(
                        label: 'Approve',
                        onTap: () {
                          final v = controller.text.trim();
                          if (!meetPattern.hasMatch(v)) {
                            setLocal(() => error =
                                'Enter a valid Google Meet link.');
                            return;
                          }
                          Navigator.pop(ctx, v);
                        },
                        style: GlassButtonStyle.primary,
                        width: double.infinity,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        });
      },
    );
  }

  Future<String?> _askText({
    required String title,
    required String hint,
    required String confirmLabel,
  }) async {
    final controller = TextEditingController();
    final ext = context.ext;
    return showDialog<String>(
      context: context,
      builder: (ctx) => _GlassDialog(
        title: title,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: 500,
              style: TextStyle(color: ext.textPrimary),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(color: ext.textMuted, fontSize: 12),
                filled: true,
                fillColor: ext.glassTextFieldFill,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: ext.glassBorder),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: GlassButton(
                    label: 'Cancel',
                    onTap: () => Navigator.pop(ctx),
                    style: GlassButtonStyle.ghost,
                    width: double.infinity,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GlassButton(
                    label: confirmLabel,
                    onTap: () =>
                        Navigator.pop(ctx, controller.text.trim()),
                    style: GlassButtonStyle.danger,
                    width: double.infinity,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ext = context.ext;
    final state = ref.watch(appointmentProvider);
    final all = state.appointments;
    final list = all.where(_matches).toList();
    final pendingCount = all.where((a) => a.isPending).length;

    // Content-only (no Scaffold): the Admin Panel provides the app bar,
    // background and tab chrome — this renders directly inside the tab.
    return RefreshIndicator(
      onRefresh: () => ref.read(appointmentProvider.notifier).load(),
      color: ext.primary,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          // Clear the Admin Panel's tall glass app bar (tab chrome) when embedded.
          if (widget.embedded)
            SizedBox(
              height: MediaQuery.of(context).padding.top + kToolbarHeight + 82.0,
            ),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final entry in _filters.entries) ...[
                  _filterChip(
                    entry.key,
                    entry.key == 'pending' && pendingCount > 0
                        ? '${entry.value} ($pendingCount)'
                        : entry.value,
                  ),
                  const SizedBox(width: 10),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (state.loading && all.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 80),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 80),
              child: Center(
                child: Text(
                  _filter == 'pending'
                      ? 'No appointments awaiting review.'
                      : 'No ${_filters[_filter]!.toLowerCase()} appointments.',
                  style: TextStyle(color: ext.textSecondary),
                ),
              ),
            )
          else
            ...list.map(_card),
        ],
      ),
    );
  }

  Widget _filterChip(String value, String label) {
    final ext = context.ext;
    final selected = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? ext.primary.withValues(alpha: 0.16)
              : ext.glassTextFieldFill,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? ext.primary.withValues(alpha: 0.6) : ext.glassBorder,
          ),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? ext.primary : ext.textSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 13)),
      ),
    );
  }

  Widget _card(AppointmentModel apt) {
    final ext = context.ext;
    final busy = _busyId == apt.id;
    final df = DateFormat('EEE, MMM d · h:mm a');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  apt.isOnline
                      ? Icons.videocam_outlined
                      : Icons.location_on_outlined,
                  size: 18,
                  color: ext.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    apt.patientName ?? 'Patient',
                    style: TextStyle(
                        color: ext.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 15),
                  ),
                ),
                _statusPill(apt.status),
              ],
            ),
            const SizedBox(height: 8),
            Text(df.format(apt.startTime),
                style: TextStyle(color: ext.textSecondary, fontSize: 13)),
            Text(
              apt.isOnline ? 'Online consultation' : 'Physical visit',
              style: TextStyle(color: ext.textMuted, fontSize: 12),
            ),
            if (apt.notes != null && apt.notes!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(apt.notes!,
                  style: TextStyle(color: ext.textSecondary, fontSize: 13),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis),
            ],
            if (apt.isOnline &&
                apt.isApproved &&
                (apt.meetingLink?.isNotEmpty ?? false)) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.link_rounded, size: 14, color: ext.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(apt.meetingLink!,
                        style: TextStyle(color: ext.primary, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            if (busy)
              const Center(
                  child: Padding(
                padding: EdgeInsets.all(4),
                child: SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              ))
            else
              _actions(apt),
          ],
        ),
      ),
    );
  }

  Widget _actions(AppointmentModel apt) {
    if (apt.isPending) {
      return Row(
        children: [
          Expanded(
            child: GlassButton(
              label: 'Reject',
              icon: Icons.close_rounded,
              onTap: () => _reject(apt),
              style: GlassButtonStyle.danger,
              width: double.infinity,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GlassButton(
              label: 'Approve',
              icon: Icons.check_rounded,
              onTap: () => _approve(apt),
              style: GlassButtonStyle.primary,
              width: double.infinity,
            ),
          ),
        ],
      );
    }
    if (apt.isApproved && apt.isUpcoming) {
      return Align(
        alignment: Alignment.centerRight,
        child: GlassButton(
          label: 'Cancel',
          icon: Icons.cancel_outlined,
          onTap: () => _cancel(apt),
          style: GlassButtonStyle.danger,
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _statusPill(String status) {
    Color c;
    switch (status) {
      case 'approved':
      case 'scheduled':
        c = Colors.green;
        break;
      case 'rescheduled':
        c = Colors.orange;
        break;
      case 'pending':
        c = Colors.amber;
        break;
      case 'cancelled':
      case 'rejected':
        c = Colors.redAccent;
        break;
      default:
        c = context.ext.textMuted;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(status.toUpperCase(),
          style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }
}

class _GlassDialog extends StatelessWidget {
  final String title;
  final Widget child;
  const _GlassDialog({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final ext = context.ext;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: ext.glassDialogTint,
              border: Border.all(color: ext.glassDialogBorder),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: ext.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 14),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

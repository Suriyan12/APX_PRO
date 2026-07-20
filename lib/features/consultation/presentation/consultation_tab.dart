import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:apx_pro/core/theme/app_theme_extension.dart';
import 'package:apx_pro/core/theme/colors.dart';
import 'package:apx_pro/core/theme/glass.dart';
import 'package:apx_pro/core/network/api_client.dart';
import 'package:apx_pro/features/consultation/data/appointment_model.dart';
import 'package:apx_pro/features/consultation/presentation/controllers/appointment_controller.dart';

class ConsultationTab extends ConsumerStatefulWidget {
  const ConsultationTab({super.key});

  @override
  ConsumerState<ConsultationTab> createState() => _ConsultationTabState();
}

class _ConsultationTabState extends ConsumerState<ConsultationTab> {
  final _notesController = TextEditingController();
  final _scrollController = ScrollController();

  late DateTime _selectedDate;
  late List<DateTime> _dateRange;
  SlotModel? _selectedSlot;
  String _selectedType = 'physical'; // 'physical' | 'online'

  List<SlotModel> _availableSlots = [];
  bool _loadingSlots = false;
  bool _booking = false;

  String _filter = 'all';
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _dateRange =
        List.generate(14, (i) => DateTime.now().add(Duration(days: i)));
    // Refresh the UI periodically so countdowns tick and the Join button
    // unlocks exactly at the 15-minutes-before mark without a manual refresh.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    _loadSlots(_selectedDate);
    // Load appointments from server if not already loaded
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final s = ref.read(appointmentProvider);
      if (!s.loading && s.appointments.isEmpty) {
        ref.read(appointmentProvider.notifier).load();
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _notesController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Open the online consultation's meeting link in the external app/browser.
  Future<void> _joinMeeting(AppointmentModel apt) async {
    final link = apt.meetingLink;
    if (link == null || link.isEmpty) {
      _showSnack('Meeting link is not available yet.', AppColors.error);
      return;
    }
    final uri = Uri.tryParse(link);
    if (uri == null) {
      _showSnack('The meeting link looks invalid.', AppColors.error);
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      _showSnack('Could not open the meeting link.', AppColors.error);
    }
  }

  // ── Slot loading (date-specific, tab-local) ───────────────────────────────

  Future<void> _loadSlots(DateTime date) async {
    setState(() {
      _loadingSlots = true;
      _availableSlots = [];
      _selectedSlot = null;
    });
    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(date);
      final repo = ref.read(appointmentRepositoryProvider);
      final slots = await repo.fetchAvailableSlots(dateStr);
      setState(() {
        _availableSlots = slots;
        _loadingSlots = false;
      });
    } catch (_) {
      setState(() => _loadingSlots = false);
    }
  }

  // ── Booking ───────────────────────────────────────────────────────────────

  Future<void> _showConfirmationDialog() async {
    if (_selectedSlot == null) {
      _showSnack('Please select a time slot first.', Colors.orange.shade700);
      return;
    }
    final start = _selectedSlot!.startTime;
    final end = _selectedSlot!.endTime;
    final notes = _notesController.text.trim();

    final confirmed = await showGlassDialog<bool>(
      context: context,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Confirm Booking',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 18),
            ),
            const SizedBox(height: 20),
            _dialogRow(Icons.calendar_today_outlined,
                DateFormat('EEEE, MMM d, y').format(start)),
            const SizedBox(height: 8),
            _dialogRow(Icons.access_time_outlined,
                '${DateFormat('hh:mm a').format(start)} – ${DateFormat('hh:mm a').format(end)}'),
            const SizedBox(height: 8),
            _dialogRow(Icons.timelapse_outlined, 'half hour session'),
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              _dialogRow(Icons.note_outlined, notes),
            ],
            const SizedBox(height: 16),
            GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              tint: const Color(0x1400E676),
              child: const Row(
                children: [
                  Icon(Icons.check_circle_outline,
                      color: AppColors.success, size: 16),
                  SizedBox(width: 8),
                  Text(
                    'This consultation is completely FREE',
                    style: TextStyle(
                        color: AppColors.success,
                        fontWeight: FontWeight.w600,
                        fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: GlassButton(
                    label: 'Back',
                    onTap: () => Navigator.of(context).pop(false),
                    style: GlassButtonStyle.ghost,
                    width: double.infinity,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GlassButton(
                    label: 'Confirm',
                    onTap: () => Navigator.of(context).pop(true),
                    style: GlassButtonStyle.primary,
                    width: double.infinity,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) _bookSlot();
  }

  Future<void> _bookSlot() async {
    if (_selectedSlot == null) return;
    setState(() => _booking = true);
    try {
      await ref.read(appointmentProvider.notifier).book(
            startTime: _selectedSlot!.startIso,
            endTime: _selectedSlot!.endIso,
            consultationType: _selectedType,
            notes: _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
          );
      _notesController.clear();
      setState(() {
        _selectedSlot = null;
        _filter = 'all';
      });
      // Refresh slots to remove the just-booked slot
      await _loadSlots(_selectedDate);
      if (mounted) {
        _showSnack('Request sent! We\'ll email you once it\'s confirmed.',
            AppColors.success);
        await Future.delayed(const Duration(milliseconds: 300));
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOut,
          );
        }
      }
    } on ApiException catch (e) {
      if (mounted) _showSnack(e.message, AppColors.error);
    } catch (e) {
      if (mounted) _showSnack(e.toString(), AppColors.error);
    } finally {
      if (mounted) setState(() => _booking = false);
    }
  }

  // ── Cancel ────────────────────────────────────────────────────────────────

  Future<void> _confirmCancel(String id) async {
    final confirmed = await showGlassDialog<bool>(
      context: context,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Cancel Appointment?',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 18),
            ),
            const SizedBox(height: 12),
            const Text(
              'Are you sure you want to cancel this appointment? '
              'You can rebook anytime.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: GlassButton(
                    label: 'Keep It',
                    onTap: () => Navigator.of(context).pop(false),
                    style: GlassButtonStyle.primary,
                    width: double.infinity,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GlassButton(
                    label: 'Yes, Cancel',
                    onTap: () => Navigator.of(context).pop(true),
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
    if (confirmed == true) {
      try {
        await ref.read(appointmentProvider.notifier).cancel(id);
        // Reload slots in case the cancelled slot reopened on the selected date
        await _loadSlots(_selectedDate);
        if (mounted) _showSnack('Appointment cancelled.', AppColors.textMuted);
      } on ApiException catch (e) {
        if (mounted) _showSnack(e.message, AppColors.error);
      } catch (e) {
        if (mounted) _showSnack(e.toString(), AppColors.error);
      }
    }
  }

  // ── Reschedule ────────────────────────────────────────────────────────────

  Future<void> _confirmReschedule(AppointmentModel apt) async {
    final slot = await showModalBottomSheet<SlotModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RescheduleSheet(appointment: apt),
    );
    if (slot == null || !mounted) return;
    try {
      await ref.read(appointmentProvider.notifier).reschedule(
            apt.id,
            startTime: slot.startIso,
            endTime: slot.endIso,
            notes: apt.notes, // preserve existing notes
          );
      if (mounted) _showSnack('Appointment rescheduled.', AppColors.primary);
      await _loadSlots(_selectedDate);
    } on ApiException catch (e) {
      if (mounted) _showSnack(e.message, AppColors.error);
    } catch (e) {
      if (mounted) _showSnack(e.toString(), AppColors.error);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _showSnack(String msg, Color bg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  String _formatSlotTime(DateTime dt) {
    return DateFormat('hh:mm a').format(dt);
  }

  String _formatDate(DateTime dt) {
    final today = DateTime.now();
    final tomorrow = today.add(const Duration(days: 1));
    if (_sameDay(dt, today))
      return 'Today · ${DateFormat('hh:mm a').format(dt)}';
    if (_sameDay(dt, tomorrow))
      return 'Tomorrow · ${DateFormat('hh:mm a').format(dt)}';
    return DateFormat('EEE, MMM d · hh:mm a').format(dt);
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<AppointmentModel> get _filteredAppointments {
    final apptState = ref.read(appointmentProvider);
    switch (_filter) {
      case 'upcoming':
        return apptState.upcoming;
      case 'past':
        return apptState.past;
      default:
        return apptState.appointments;
    }
  }

  Widget _dialogRow(IconData icon, String text) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 14)),
          ),
        ],
      );

  Color _statusColor(String status) {
    switch (status) {
      case 'approved':
      case 'scheduled':
        return Colors.green;
      case 'rescheduled':
        return Colors.orange;
      case 'pending':
        return Colors.amber;
      case 'completed':
        return Colors.blueAccent;
      case 'cancelled':
      case 'rejected':
        return Colors.redAccent;
      default:
        return AppColors.textMuted;
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final apptState = ref.watch(appointmentProvider);
    final ext = context.ext;

    return GlassOrbBackground(
      child: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([
            ref.read(appointmentProvider.notifier).load(),
            _loadSlots(_selectedDate),
          ]);
        },
        color: ext.primary,
        child: SingleChildScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 20),
              _buildFeeCard(),
              const SizedBox(height: 20),
              _buildTypeToggle(),
              const SizedBox(height: 24),
              _buildDateSelector(),
              const SizedBox(height: 24),
              _buildSlots(),
              const SizedBox(height: 20),
              _buildNotesField(),
              const SizedBox(height: 24),
              _buildBookButton(),
              const SizedBox(height: 36),
              _buildAppointmentSection(apptState),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final ext = context.ext;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Book a Consultation',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: ext.textPrimary,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'One-on-one session with our physiotherapy experts.',
          style: TextStyle(color: ext.textSecondary, fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildFeeCard() {
    final ext = context.ext;
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      borderRadius: BorderRadius.circular(14),
      tint: ext.primary.withValues(alpha: ext.isDark ? 0.08 : 0.12),
      glowColor: ext.isDark ? null : ext.primary.withValues(alpha: 0.45),
      child: Row(
        children: [
          Icon(Icons.medical_services_outlined, color: ext.primary, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Physiotherapy Session',
                  style: TextStyle(
                      color: ext.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 15),
                ),
                const SizedBox(height: 2),
                Text(
                  '30 min · Confirmed after review',
                  style: TextStyle(color: ext.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'FREE',
                style: TextStyle(
                    color: ext.success,
                    fontSize: 20,
                    fontWeight: FontWeight.bold),
              ),
              Text(
                'consultation',
                style: TextStyle(color: ext.textSecondary, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTypeToggle() {
    final ext = context.ext;
    Widget option(String value, IconData icon, String label) {
      final selected = _selectedType == value;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _selectedType = value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: selected
                  ? ext.primary.withValues(alpha: ext.isDark ? 0.18 : 0.14)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? ext.primary.withValues(alpha: 0.6)
                    : ext.glassBorder,
                width: 1.4,
              ),
            ),
            child: Column(
              children: [
                Icon(icon,
                    color: selected ? ext.primary : ext.textSecondary, size: 22),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? ext.primary : ext.textSecondary,
                    fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Consultation Type',
            style: TextStyle(
                color: ext.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 14)),
        const SizedBox(height: 10),
        Row(
          children: [
            option('physical', Icons.location_on_outlined, 'Physical Visit'),
            const SizedBox(width: 12),
            option('online', Icons.videocam_outlined, 'Online'),
          ],
        ),
        if (_selectedType == 'online')
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'A video meeting link will be shared once your appointment is approved.',
              style: TextStyle(color: ext.textMuted, fontSize: 11.5),
            ),
          ),
      ],
    );
  }

  Widget _buildDateSelector() {
    final ext = context.ext;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          DateFormat('MMMM y').format(_selectedDate),
          style: TextStyle(
              color: ext.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 72,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _dateRange.length,
            itemBuilder: (context, index) {
              final date = _dateRange[index];
              final selected = _sameDay(date, _selectedDate);
              final isToday = _sameDay(date, DateTime.now());
              return GestureDetector(
                onTap: () {
                  setState(() => _selectedDate = date);
                  _loadSlots(date);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 52,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: selected
                        ? ext.primary
                            .withValues(alpha: ext.isDark ? 0.25 : 0.18)
                        : ext.glassTint,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected
                          ? ext.primary
                          : isToday
                              ? ext.primary.withValues(alpha: 0.5)
                              : ext.glassBorder,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        isToday ? 'Today' : DateFormat('EEE').format(date),
                        style: TextStyle(
                          color: selected || isToday
                              ? ext.primary
                              : ext.textSecondary,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('d').format(date),
                        style: TextStyle(
                          color: ext.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSlots() {
    final ext = context.ext;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Available Slots',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: ext.textPrimary,
                  fontSize: 16),
            ),
            if (!_loadingSlots && _availableSlots.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: ext.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_availableSlots.length} free',
                  style: TextStyle(
                      color: ext.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        if (_loadingSlots)
          Center(child: CircularProgressIndicator(color: ext.primary))
        else if (_availableSlots.isEmpty)
          GlassCard(
            padding: const EdgeInsets.all(16),
            borderRadius: BorderRadius.circular(12),
            child: Row(
              children: [
                Icon(Icons.event_busy_outlined,
                    color: ext.textSecondary, size: 20),
                const SizedBox(width: 10),
                Text('No slots available for this date.',
                    style: TextStyle(color: ext.textSecondary)),
              ],
            ),
          )
        else
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _availableSlots.map((slot) {
              final label =
                  '${_formatSlotTime(slot.startTime)} – ${_formatSlotTime(slot.endTime)}';
              final selected = _selectedSlot == slot;
              return GestureDetector(
                onTap: () =>
                    setState(() => _selectedSlot = selected ? null : slot),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: selected
                        ? ext.primary.withValues(alpha: ext.isDark ? 0.2 : 0.16)
                        : ext.glassTint,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected ? ext.primary : ext.glassBorder,
                      width: selected ? 1.5 : 1,
                    ),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: selected ? ext.primary : ext.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildNotesField() {
    final ext = context.ext;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        children: [
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Container(color: Colors.transparent),
            ),
          ),
          TextField(
            controller: _notesController,
            maxLines: 3,
            maxLength: 200,
            style: TextStyle(color: ext.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              hintText:
                  'Notes (optional) — describe your condition or reason for visit...',
              hintStyle: TextStyle(color: ext.textMuted, fontSize: 13),
              prefixIcon: Padding(
                padding: const EdgeInsets.only(bottom: 32),
                child:
                    Icon(Icons.note_outlined, color: ext.textMuted, size: 18),
              ),
              counterStyle: TextStyle(color: ext.textMuted),
              filled: true,
              fillColor: ext.glassTextFieldFill,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: ext.glassBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: ext.glassBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                    color: ext.primary.withValues(alpha: 0.65), width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBookButton() {
    final enabled = !_booking && _selectedSlot != null;
    return GlassButton(
      label: 'Book Free Appointment',
      icon: Icons.calendar_month_outlined,
      onTap: enabled ? _showConfirmationDialog : null,
      style: GlassButtonStyle.primary,
      loading: _booking,
      width: double.infinity,
    );
  }

  Widget _buildAppointmentSection(AppointmentState apptState) {
    final ext = context.ext;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'My Appointments',
          style: TextStyle(
              fontWeight: FontWeight.bold,
              color: ext.textPrimary,
              fontSize: 18),
        ),
        const SizedBox(height: 12),
        _buildFilterChips(),
        const SizedBox(height: 16),
        if (apptState.loading)
          Center(child: CircularProgressIndicator(color: ext.primary))
        else if (apptState.error != null)
          GlassCard(
            padding: const EdgeInsets.all(20),
            borderRadius: BorderRadius.circular(14),
            child: Column(
              children: [
                Icon(Icons.error_outline_rounded, color: ext.error, size: 32),
                const SizedBox(height: 10),
                Text(
                  apptState.error!,
                  style: TextStyle(color: ext.textSecondary, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 14),
                GlassButton(
                  label: 'Retry',
                  onTap: () => ref.read(appointmentProvider.notifier).load(),
                  style: GlassButtonStyle.ghost,
                ),
              ],
            ),
          )
        else if (_filteredAppointments.isEmpty)
          _buildEmptyState()
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _filteredAppointments.length,
            itemBuilder: (context, index) =>
                _buildAppointmentCard(_filteredAppointments[index]),
          ),
      ],
    );
  }

  Widget _buildFilterChips() => Row(
        children: [
          _filterChip('Upcoming', 'upcoming'),
          const SizedBox(width: 8),
          _filterChip('Past', 'past'),
          const SizedBox(width: 8),
          _filterChip('All', 'all'),
        ],
      );

  Widget _filterChip(String label, String value) {
    final ext = context.ext;
    final selected = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? ext.primary.withValues(alpha: 0.15) : ext.glassTint,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? ext.primary : ext.glassBorder),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? ext.primary : ext.textSecondary,
            fontSize: 13,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final ext = context.ext;
    return GlassCard(
      padding: const EdgeInsets.all(24),
      borderRadius: BorderRadius.circular(14),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.calendar_today_outlined,
                color: ext.textSecondary.withValues(alpha: 0.5), size: 36),
            const SizedBox(height: 10),
            Text(
              _filter == 'upcoming'
                  ? 'No upcoming appointments'
                  : _filter == 'past'
                      ? 'No past appointments'
                      : 'No appointments yet',
              style: TextStyle(color: ext.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppointmentCard(AppointmentModel apt) {
    final ext = context.ext;
    final statusColor = _statusColor(apt.status);
    final isCancellable = apt.isUpcoming && apt.isActive;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        borderRadius: BorderRadius.circular(16),
        tint: apt.isCancelled
            ? ext.accentPink.withValues(alpha: 0.06)
            : apt.isCompleted
                ? ext.secondary.withValues(alpha: 0.06)
                : ext.glassTint,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.medical_services_outlined,
                      color: statusColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Physiotherapy Session',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: ext.textPrimary,
                            fontSize: 14),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _formatDate(apt.startTime),
                        style: TextStyle(
                          color: apt.isUpcoming && apt.status == 'scheduled'
                              ? ext.primary
                              : ext.textMuted,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    apt.status.toUpperCase(),
                    style: TextStyle(
                        color: statusColor,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8),
                  ),
                ),
              ],
            ),
            if (apt.notes != null && apt.notes!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.note_outlined, size: 14, color: ext.textMuted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      apt.notes!,
                      style: TextStyle(color: ext.textSecondary, fontSize: 12),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            _buildStatusRow(apt),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildTypeBadge(apt),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: ext.success.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'FREE',
                        style: TextStyle(
                            color: ext.success,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8),
                      ),
                    ),
                  ],
                ),
                if (isCancellable)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: () => _confirmReschedule(apt),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.edit_calendar_outlined,
                                size: 16, color: ext.primary),
                            const SizedBox(width: 4),
                            Text(
                              'Reschedule',
                              style:
                                  TextStyle(color: ext.primary, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      GestureDetector(
                        onTap: () => _confirmCancel(apt.id),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.cancel_outlined,
                                size: 16, color: Colors.redAccent),
                            SizedBox(width: 4),
                            Text(
                              'Cancel',
                              style: TextStyle(
                                  color: Colors.redAccent, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeBadge(AppointmentModel apt) {
    final ext = context.ext;
    final online = apt.isOnline;
    final color = online ? ext.primary : ext.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(online ? Icons.videocam_outlined : Icons.location_on_outlined,
              size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            online ? 'ONLINE' : 'IN-PERSON',
            style: TextStyle(
                color: color,
                fontSize: 10.5,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.6),
          ),
        ],
      ),
    );
  }

  /// Status-driven row enforcing the appointment lifecycle UI rules:
  ///  • PENDING  → "Waiting for Admin Approval" (NO countdown, NO join).
  ///  • APPROVED → live countdown; Join button (online only) that unlocks
  ///               15 min before start once a valid meeting link exists.
  ///  • otherwise (completed/cancelled/rejected) → nothing extra (the status
  ///    pill already conveys it).
  Widget _buildStatusRow(AppointmentModel apt) {
    final ext = context.ext;

    // Pending re-review — never show a countdown or a meeting link.
    if (apt.isPending) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.hourglass_top_rounded,
                  size: 16, color: Colors.amber),
              const SizedBox(width: 8),
              Text('Waiting for Admin Approval',
                  style: TextStyle(
                      color: ext.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
            ],
          ),
        ),
      );
    }

    // Only approved & upcoming appointments get a countdown / Join button.
    if (!apt.isApproved || !apt.isUpcoming) return const SizedBox.shrink();

    final mins = apt.minutesUntilStart;
    String countdownLabel() {
      if (mins <= 0) return 'Starting now';
      if (mins < 60) return 'Starts in $mins min';
      final h = mins ~/ 60;
      final m = mins % 60;
      return 'Starts in ${h}h ${m}m';
    }

    // Physical (or online before the join window) → countdown chip only.
    final canJoin = apt.canJoinNow; // online + approved + valid link + ≤15 min
    if (!canJoin) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Icon(Icons.schedule_rounded, size: 15, color: ext.textMuted),
            const SizedBox(width: 6),
            Text(countdownLabel(),
                style: TextStyle(color: ext.textMuted, fontSize: 12.5)),
          ],
        ),
      );
    }

    // Online + within the join window → active Join Consultation button.
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassButton(
        label: 'Join Consultation',
        icon: Icons.video_call_rounded,
        onTap: () => _joinMeeting(apt),
        style: GlassButtonStyle.primary,
        width: double.infinity,
      ),
    );
  }
}

// ── Reschedule bottom sheet ───────────────────────────────────────────────────

class _RescheduleSheet extends ConsumerStatefulWidget {
  final AppointmentModel appointment;
  const _RescheduleSheet({required this.appointment});

  @override
  ConsumerState<_RescheduleSheet> createState() => _RescheduleSheetState();
}

class _RescheduleSheetState extends ConsumerState<_RescheduleSheet> {
  late DateTime _selectedDate;
  late List<DateTime> _dateRange;
  List<SlotModel> _slots = [];
  bool _loading = false;
  SlotModel? _selectedSlot;

  @override
  void initState() {
    super.initState();
    // Start from tomorrow — backend enforces 2h cancellation/reschedule notice
    _selectedDate = DateTime.now().add(const Duration(days: 1));
    _dateRange =
        List.generate(14, (i) => DateTime.now().add(Duration(days: i + 1)));
    _loadSlots(_selectedDate);
  }

  Future<void> _loadSlots(DateTime date) async {
    setState(() {
      _loading = true;
      _slots = [];
      _selectedSlot = null;
    });
    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(date);
      final slots = await ref
          .read(appointmentRepositoryProvider)
          .fetchAvailableSlots(dateStr);
      if (mounted)
        setState(() {
          _slots = slots;
          _loading = false;
        });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final ext = context.ext;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: BoxDecoration(
        color: ext.surfaceOverlay,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: ext.glassBorder)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: ext.textMuted.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Select New Time Slot',
                style: TextStyle(
                  color: ext.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Date strip
          SizedBox(
            height: 72,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _dateRange.length,
              itemBuilder: (context, i) {
                final date = _dateRange[i];
                final selected = _sameDay(date, _selectedDate);
                return GestureDetector(
                  onTap: () {
                    setState(() => _selectedDate = date);
                    _loadSlots(date);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 52,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      color: selected
                          ? ext.primary
                              .withValues(alpha: ext.isDark ? 0.25 : 0.18)
                          : ext.glassTint,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected ? ext.primary : ext.glassBorder,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          DateFormat('EEE').format(date),
                          style: TextStyle(
                            color: selected ? ext.primary : ext.textSecondary,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          DateFormat('d').format(date),
                          style: TextStyle(
                            color: ext.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          // Slot grid
          Flexible(
            child: _loading
                ? Center(child: CircularProgressIndicator(color: ext.primary))
                : _slots.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            'No slots available for this date.',
                            style: TextStyle(color: ext.textSecondary),
                          ),
                        ),
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: _slots.map((slot) {
                            final label =
                                '${DateFormat('hh:mm a').format(slot.startTime)} – ${DateFormat('hh:mm a').format(slot.endTime)}';
                            final selected = _selectedSlot == slot;
                            return GestureDetector(
                              onTap: () => setState(
                                  () => _selectedSlot = selected ? null : slot),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? ext.primary.withValues(
                                          alpha: ext.isDark ? 0.2 : 0.16)
                                      : ext.glassTint,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: selected
                                        ? ext.primary
                                        : ext.glassBorder,
                                    width: selected ? 1.5 : 1,
                                  ),
                                ),
                                child: Text(
                                  label,
                                  style: TextStyle(
                                    color: selected
                                        ? ext.primary
                                        : ext.textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
          ),
          const SizedBox(height: 16),
          // Confirm button
          Padding(
            padding: EdgeInsets.fromLTRB(
                20, 0, 20, MediaQuery.of(context).padding.bottom + 16),
            child: GlassButton(
              label: 'Confirm New Slot',
              onTap: _selectedSlot == null
                  ? null
                  : () => Navigator.of(context).pop(_selectedSlot),
              style: GlassButtonStyle.primary,
              width: double.infinity,
            ),
          ),
        ],
      ),
    );
  }
}

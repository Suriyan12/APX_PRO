import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:apx_pro/core/theme/app_theme_extension.dart';
import 'package:apx_pro/core/theme/glass.dart';
import 'package:apx_pro/features/auth/presentation/controllers/auth_controller.dart';
import 'package:apx_pro/features/consultation/data/appointment_model.dart';
import 'package:apx_pro/features/consultation/presentation/controllers/appointment_controller.dart';
import 'package:apx_pro/features/notifications/presentation/widgets/notification_bell.dart';
import 'package:apx_pro/features/rehab/data/rehab_models.dart';
import 'package:apx_pro/features/rehab/presentation/controllers/rehab_controller.dart';

class HomeTab extends ConsumerStatefulWidget {
  const HomeTab({super.key});

  @override
  ConsumerState<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends ConsumerState<HomeTab> {
  @override
  void initState() {
    super.initState();
    // Populate the shared providers if they haven't loaded yet. The rehab
    // program uses the SAME provider (and backend endpoint) as the
    // Rehabilitation tab, so the Dashboard and that screen read one source of
    // truth and can never disagree (previously the Dashboard read the legacy
    // /programs system, which stays empty when a /rehab program is assigned).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final appt = ref.read(appointmentProvider);
      if (!appt.loading && appt.appointments.isEmpty) {
        ref.read(appointmentProvider.notifier).load();
      }
      final rehab = ref.read(myRehabProgramProvider);
      if (!rehab.loading && rehab.data == null && rehab.error == null) {
        ref.read(myRehabProgramProvider.notifier).load();
      }
    });
  }

  Future<void> _refresh() async {
    await Future.wait([
      ref.read(appointmentProvider.notifier).load(),
      ref.read(myRehabProgramProvider.notifier).load(),
    ]);
  }

  void _startWorkout(RehabProgramModel program) {
    context.push('/rehab/workout', extra: program);
  }

  String _formatAppointmentTime(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final apptDay = DateTime(dt.year, dt.month, dt.day);
    final diff = apptDay.difference(today).inDays;
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour < 12 ? 'AM' : 'PM';
    final timeStr = '$h:$m $period';
    if (diff == 0) return 'Today at $timeStr';
    if (diff == 1) return 'Tomorrow at $timeStr';
    return '${['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][dt.weekday - 1]} at $timeStr';
  }

  @override
  Widget build(BuildContext context) {
    final ext = context.ext;
    final authState = ref.watch(authControllerProvider);
    final userName = authState.userName ?? 'there';
    final firstName = userName.split(' ').first;
    final isAdmin = authState.isAdmin;

    // Watch the global appointment provider — updates automatically when
    // an appointment is booked or cancelled from any tab.
    final apptState = ref.watch(appointmentProvider);
    final nextAppointment = apptState.nextUpcoming;

    // Same provider the Rehabilitation tab watches — one source of truth.
    final rehabState = ref.watch(myRehabProgramProvider);

    return RefreshIndicator(
      onRefresh: _refresh,
      color: ext.primary,
      backgroundColor: ext.surface,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 110),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hello, $firstName 👋',
                      style: TextStyle(
                        color: ext.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 24,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Let's continue your rehabilitation.",
                      style: TextStyle(
                          color: ext.textSecondary, fontSize: 14),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const NotificationBell(),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: () => context.push('/settings'),
                      child: GlassCard(
                        padding: const EdgeInsets.all(10),
                        borderRadius: BorderRadius.circular(50),
                        child: Icon(Icons.settings_rounded,
                            color: ext.primary, size: 22),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 28),

            // ── Core Services ────────────────────────────────────────────
            _sectionLabel(context, 'Core Services'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _GlassServiceCard(
                    title: 'Assessment',
                    subtitle: 'Medical Reports',
                    icon: Icons.assignment_outlined,
                    color: ext.primary,
                    onTap: () => context.push('/assessment'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _GlassServiceCard(
                    title: 'Progress Log',
                    subtitle: 'Metrics & Charts',
                    icon: Icons.bar_chart_rounded,
                    color: ext.secondary,
                    onTap: () => context.push('/progress'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _GlassServiceCard(
              title: 'Study Notes',
              subtitle: 'Premium PDF notes, slides & more',
              icon: Icons.menu_book_rounded,
              color: ext.success,
              isFullWidth: true,
              onTap: () => context.push('/notes'),
            ),
            if (isAdmin) ...[
              const SizedBox(height: 12),
              _GlassServiceCard(
                title: 'Admin Panel',
                subtitle: 'Manage users · Appointments · Notes',
                icon: Icons.admin_panel_settings_rounded,
                color: ext.secondary,
                isFullWidth: true,
                onTap: () => context.push('/admin/panel'),
              ),
            ],
            const SizedBox(height: 28),

            // ── Today's Workout ──────────────────────────────────────────
            // Patients only — an admin has no personal rehab program.
            if (!isAdmin) ...[
              _sectionLabel(context, "Today's Workout"),
              const SizedBox(height: 12),
              GlassCard(child: _todayWorkoutBody(rehabState)),
              const SizedBox(height: 28),
            ],

            // ── Upcoming Consultation ────────────────────────────────────
            _sectionLabel(context, 'Upcoming Consultation'),
            const SizedBox(height: 12),
            if (apptState.loading)
              Center(
                  child: CircularProgressIndicator(color: ext.primary))
            else if (nextAppointment != null)
              _buildAppointmentCard(nextAppointment)
            else
              GlassCard(
                child: Center(
                  child: Text(
                    'No upcoming appointments.\nBook one in the Consult tab.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: ext.textSecondary, height: 1.6),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// The Today's Workout card body, driven entirely by [myRehabProgramProvider]
  /// — the same state the Rehabilitation tab renders. Counts mirror that
  /// screen's logic: when a session exists it is authoritative for today,
  /// otherwise today's total is the program's exercise count with 0 completed.
  Widget _todayWorkoutBody(MyRehabProgramState state) {
    final ext = context.ext;

    if (state.loading && state.data == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator(color: ext.primary)),
      );
    }

    // No active rehab program (backend 404 → data null) or a transient error.
    // Show a helpful empty state — never a bare "None".
    if (state.data == null) {
      return Row(
        children: [
          Icon(Icons.self_improvement_rounded, color: ext.textMuted, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No active program',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: ext.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  state.error ?? "Your therapist hasn't assigned a program yet.",
                  style: TextStyle(color: ext.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final data = state.data!;
    final program = data.program;
    final session = data.todaySession;
    final total =
        session != null ? session.exercisesTotal : program.exercises.length;
    final completed = session != null
        ? (session.isCompleted ? session.exercisesTotal : session.exercisesCompleted)
        : 0;
    final pct = total > 0 ? completed / total : 0.0;
    final isDone = session?.isCompleted == true;
    final inProgress = session != null && !isDone;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Program',
                      style: TextStyle(color: ext.textSecondary, fontSize: 11)),
                  const SizedBox(height: 2),
                  Text(
                    program.title,
                    style: TextStyle(
                      color: ext.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
            if (isDone) _completedBadge(ext),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '$total ${total == 1 ? 'Exercise' : 'Exercises'}',
              style: TextStyle(
                color: ext.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              isDone
                  ? '$total/$total exercises'
                  : '$completed/$total completed today',
              style: TextStyle(
                color: ext.primary,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: pct.clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor: Colors.white.withValues(alpha: 0.1),
            valueColor: AlwaysStoppedAnimation<Color>(
                isDone ? ext.success : ext.primary),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          isDone ? '100% Complete' : '${(pct * 100).toInt()}% complete today',
          style: TextStyle(color: ext.textSecondary, fontSize: 12),
        ),
        if (!isDone) ...[
          const SizedBox(height: 16),
          GlassButton(
            width: double.infinity,
            label: program.isActive
                ? (inProgress ? 'Continue Workout' : 'Start Workout')
                : 'Program Inactive',
            icon: Icons.play_arrow_rounded,
            onTap: program.isActive ? () => _startWorkout(program) : null,
          ),
        ],
      ],
    );
  }

  Widget _completedBadge(AppThemeExtension ext) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: ext.success.withValues(alpha: 0.15),
        border: Border.all(color: ext.success.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_rounded, color: ext.success, size: 16),
          const SizedBox(width: 4),
          Text(
            'Completed Today',
            style: TextStyle(
              color: ext.success,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppointmentCard(AppointmentModel apt) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: context.ext.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: context.ext.primary.withValues(alpha: 0.3),
              ),
            ),
            child: Icon(
              Icons.medical_services_outlined,
              color: context.ext.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Physiotherapy Session',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: context.ext.textPrimary,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _formatAppointmentTime(apt.startTime),
                  style: TextStyle(
                      color: context.ext.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: context.ext.textMuted,
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.bold,
        color: context.ext.textPrimary,
        letterSpacing: 0.2,
      ),
    );
  }
}

class _GlassServiceCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool isFullWidth;

  const _GlassServiceCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
    this.isFullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(18),
      onTap: onTap,
      child: isFullWidth
          ? Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: color.withValues(alpha: 0.3)),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: context.ext.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 11,
                          color: context.ext.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: color.withValues(alpha: 0.7)),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: color.withValues(alpha: 0.3)),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(height: 14),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: context.ext.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: context.ext.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
    );
  }
}

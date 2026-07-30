import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:apx_pro/core/theme/app_theme_extension.dart';
import 'package:apx_pro/core/theme/glass.dart';
import 'package:apx_pro/core/network/api_client.dart';
import 'package:apx_pro/features/auth/presentation/controllers/auth_controller.dart';
import 'package:apx_pro/features/consultation/data/appointment_model.dart';
import 'package:apx_pro/features/consultation/presentation/controllers/appointment_controller.dart';
import 'package:apx_pro/features/notifications/presentation/widgets/notification_bell.dart';

class HomeTab extends ConsumerStatefulWidget {
  const HomeTab({super.key});

  @override
  ConsumerState<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends ConsumerState<HomeTab> {
  final ApiClient _apiClient = ApiClient();
  int _todayCompleted = 0;
  int _todayTotal = 0;
  bool _loadingProgram = true;

  @override
  void initState() {
    super.initState();
    _loadProgramData();
    // Trigger appointment load if provider is empty
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final s = ref.read(appointmentProvider);
      if (!s.loading && s.appointments.isEmpty) {
        ref.read(appointmentProvider.notifier).load();
      }
    });
  }

  Future<void> _loadProgramData() async {
    setState(() { _loadingProgram = true; });
    try {
      final results = await Future.wait([
        _apiClient.get('/programs/workout-logs/today'),
        _apiClient.get('/programs/my-active'),
      ]);

      final todayLogs = results[0].data as List;
      final programs = results[1].data as List;

      int total = 0;
      if (programs.isNotEmpty) {
        try {
          final exResp = await _apiClient.get('/programs/${programs[0]['id']}/exercises');
          total = (exResp.data as List).length;
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _todayCompleted = todayLogs.length;
          _todayTotal = total;
          _loadingProgram = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingProgram = false;
        });
      }
    }
  }

  Future<void> _refresh() async {
    await Future.wait([
      ref.read(appointmentProvider.notifier).load(),
      _loadProgramData(),
    ]);
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
    final progress = _todayTotal > 0 ? _todayCompleted / _todayTotal : 0.0;

    // Watch the global appointment provider — updates automatically when
    // an appointment is booked or cancelled from any tab.
    final apptState = ref.watch(appointmentProvider);
    final nextAppointment = apptState.nextUpcoming;

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

            // ── Daily Checklist ──────────────────────────────────────────
            _sectionLabel(context, 'Daily Checklist'),
            const SizedBox(height: 12),
            GlassCard(
              child: _loadingProgram
                  ? Center(
                      child: CircularProgressIndicator(
                          color: ext.primary))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Physiotherapy Exercises',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: ext.textPrimary,
                              ),
                            ),
                            Text(
                              _todayTotal > 0
                                  ? '$_todayCompleted / $_todayTotal'
                                  : 'None',
                              style: TextStyle(
                                color: ext.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: progress.clamp(0.0, 1.0),
                            minHeight: 6,
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.1),
                            valueColor: AlwaysStoppedAnimation<Color>(
                                ext.primary),
                          ),
                        ),
                        if (_todayTotal > 0) ...[
                          const SizedBox(height: 10),
                          Text(
                            '${(progress * 100).toInt()}% complete today',
                            style: TextStyle(
                                color: ext.textSecondary, fontSize: 12),
                          ),
                        ],
                      ],
                    ),
            ),
            const SizedBox(height: 28),

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

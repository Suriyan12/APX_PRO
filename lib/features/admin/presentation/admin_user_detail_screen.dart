import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:apx_pro/core/theme/colors.dart';
import 'package:apx_pro/core/theme/glass.dart';
import 'package:apx_pro/core/network/api_client.dart';
import 'package:apx_pro/features/admin/presentation/widgets/dashboard_widgets.dart';
import 'package:apx_pro/features/assessment/data/medical_record_model.dart';
import 'package:apx_pro/features/assessment/data/medical_records_repository.dart';
import 'package:apx_pro/features/assessment/presentation/record_viewer_screen.dart';
import 'package:apx_pro/features/consultation/data/appointment_model.dart';
import 'package:apx_pro/features/consultation/presentation/controllers/appointment_controller.dart';
import 'package:apx_pro/features/rehab/data/rehab_models.dart';
import 'package:apx_pro/features/rehab/presentation/controllers/rehab_controller.dart';

/// The admin/therapist patient dashboard. Sections, in order:
///   1. Patient Information
///   2. Rehabilitation Program (active program)
///   3. Workout Progress
///   4. Medical Records
///   5. Appointment History
///
/// Each async section loads through its own provider so no section blocks
/// another: the profile + medical records use the screen's own [ApiClient]
/// (unchanged), workout progress uses [patientWorkoutDashboardProvider], and
/// appointment history uses [patientAppointmentsProvider].
class AdminUserDetailScreen extends ConsumerStatefulWidget {
  final String userId;

  const AdminUserDetailScreen({super.key, required this.userId});

  @override
  ConsumerState<AdminUserDetailScreen> createState() =>
      _AdminUserDetailScreenState();
}

class _AdminUserDetailScreenState extends ConsumerState<AdminUserDetailScreen> {
  final ApiClient _api = ApiClient();
  late final MedicalRecordsRepository _recordsRepo =
      MedicalRecordsRepository(_api);

  Map<String, dynamic>? _user;
  List<MedicalRecord> _medicalRecords = [];
  bool _loadingUser = true;
  bool _loadingRecords = true;
  bool _togglingStatus = false;
  String? _downloadingRecordId;

  @override
  void initState() {
    super.initState();
    _loadUser();
    _loadMedicalRecords();
  }

  Future<void> _loadUser() async {
    setState(() => _loadingUser = true);
    try {
      final resp = await _api.get('/users/${widget.userId}');
      if (mounted) {
        setState(() {
          _user = resp.data as Map<String, dynamic>;
          _loadingUser = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingUser = false);
    }
  }

  Future<void> _loadMedicalRecords() async {
    setState(() => _loadingRecords = true);
    try {
      final records = await _recordsRepo.listForPatient(widget.userId);
      if (mounted) {
        setState(() {
          _medicalRecords = records;
          _loadingRecords = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingRecords = false);
    }
  }

  /// Pull-to-refresh: re-fetch every section, so an admin sees the latest
  /// workout completion / new appointment without leaving the screen.
  Future<void> _refresh() async {
    ref.invalidate(patientWorkoutDashboardProvider(widget.userId));
    ref.invalidate(patientAppointmentsProvider(widget.userId));
    await Future.wait([_loadUser(), _loadMedicalRecords()]);
  }

  String _patientName() => _user?['full_name'] as String? ?? 'Patient';

  // ── Medical records actions (unchanged) ─────────────────────────────────────

  void _previewMedicalRecord(MedicalRecord record) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RecordViewerScreen(
          recordId: record.id,
          fileName: record.fileName,
          mimeType: record.mimeType,
        ),
      ),
    );
  }

  Future<void> _downloadMedicalRecord(MedicalRecord record) async {
    if (_downloadingRecordId != null) return;
    setState(() => _downloadingRecordId = record.id);
    try {
      final bytes = await _recordsRepo.downloadBytes(record.id);
      final path = await saveRecordToDevice(record.fileName, bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Saved to $path'),
              backgroundColor: AppColors.success),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _downloadingRecordId = null);
    }
  }

  Future<void> _deleteMedicalRecord(MedicalRecord record) async {
    final confirmed = await showGlassDialog<bool>(
      context: context,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: AppColors.error, size: 22),
                SizedBox(width: 8),
                Text(
                  'Delete Medical Record?',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 18),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'This will permanently delete "${record.fileName}". This cannot be undone.',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: GlassButton(
                    label: 'Cancel',
                    onTap: () => Navigator.of(context).pop(false),
                    style: GlassButtonStyle.ghost,
                    width: double.infinity,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GlassButton(
                    label: 'Delete',
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

    if (confirmed != true) return;

    try {
      await _recordsRepo.delete(record.id);
      setState(() => _medicalRecords.removeWhere((r) => r.id == record.id));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Medical record deleted.')),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _toggleStatus() async {
    if (_user == null) return;
    final name = _user!['full_name'] as String;
    final isActive = _user!['is_active'] as bool;
    final isAdmin = (_user!['role'] as String?)?.toLowerCase() == 'admin';
    if (isAdmin) return;

    final confirmed = await showGlassDialog<bool>(
      context: context,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isActive ? 'Deactivate User?' : 'Activate User?',
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 18),
            ),
            const SizedBox(height: 12),
            Text(
              isActive
                  ? '$name will be unable to access the app.'
                  : '$name will regain full access to the app.',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: GlassButton(
                    label: 'Cancel',
                    onTap: () => Navigator.of(context).pop(false),
                    style: GlassButtonStyle.ghost,
                    width: double.infinity,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GlassButton(
                    label: isActive ? 'Deactivate' : 'Activate',
                    onTap: () => Navigator.of(context).pop(true),
                    style: isActive
                        ? GlassButtonStyle.danger
                        : GlassButtonStyle.primary,
                    width: double.infinity,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    setState(() => _togglingStatus = true);
    try {
      final resp = await _api.patch('/users/${widget.userId}/status');
      setState(() {
        _user = resp.data as Map<String, dynamic>;
        _togglingStatus = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _user!['is_active'] == true
                  ? '$name activated.'
                  : '$name deactivated.',
            ),
            backgroundColor: _user!['is_active'] == true
                ? AppColors.success
                : AppColors.error,
          ),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _togglingStatus = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
        );
      }
    }
  }

  String _formatDate(String? isoDate) {
    if (isoDate == null) return '—';
    try {
      return DateFormat('MMM d, yyyy').format(DateTime.parse(isoDate).toLocal());
    } catch (_) {
      return isoDate;
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isPatient =
        ((_user?['role'] as String?) ?? '').toUpperCase() == 'PATIENT';

    // Only patients have programs / appointments; watch those providers lazily.
    final dashAsync = (_user != null && isPatient)
        ? ref.watch(patientWorkoutDashboardProvider(widget.userId))
        : null;
    final apptAsync = (_user != null && isPatient)
        ? ref.watch(patientAppointmentsProvider(widget.userId))
        : null;

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: _user?['full_name'] as String? ?? 'User Detail',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (_user != null &&
              (_user!['role'] as String?)?.toLowerCase() != 'admin')
            _togglingStatus
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.primary),
                    ),
                  )
                : IconButton(
                    tooltip: _user!['is_active'] == true
                        ? 'Deactivate User'
                        : 'Activate User',
                    icon: Icon(
                      _user!['is_active'] == true
                          ? Icons.person_off_rounded
                          : Icons.person_rounded,
                      color: _user!['is_active'] == true
                          ? AppColors.error
                          : AppColors.success,
                    ),
                    onPressed: _toggleStatus,
                  ),
        ],
      ),
      body: GlassOrbBackground(
        child: _loadingUser
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary))
            : _user == null
                ? const Center(
                    child: Text('User not found.',
                        style: TextStyle(color: AppColors.textSecondary)))
                : SafeArea(
                    child: RefreshIndicator(
                      color: AppColors.primary,
                      onRefresh: _refresh,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 1. Patient Information
                            _buildProfileCard(),

                            // 2. Rehabilitation Program + 3. Workout Progress
                            if (isPatient) ...[
                              const SizedBox(height: 24),
                              const DashboardSectionHeader(
                                  'Rehabilitation Program'),
                              const SizedBox(height: 12),
                              _buildRehabProgramCard(dashAsync),
                              const SizedBox(height: 24),
                              const DashboardSectionHeader('Workout Progress'),
                              const SizedBox(height: 12),
                              _buildWorkoutProgress(dashAsync!),
                            ],

                            // 4. Medical Records
                            const SizedBox(height: 24),
                            const DashboardSectionHeader('Medical Records'),
                            const SizedBox(height: 12),
                            _buildMedicalRecordsList(),

                            // 5. Appointment History
                            if (isPatient) ...[
                              const SizedBox(height: 24),
                              const DashboardSectionHeader('Appointment History'),
                              const SizedBox(height: 12),
                              _buildAppointmentHistory(apptAsync!),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
      ),
    );
  }

  // ── 1. Patient Information ──────────────────────────────────────────────────

  Widget _buildProfileCard() {
    final user = _user!;
    final name = user['full_name'] as String? ?? 'Unknown';
    final email = user['email'] as String? ?? '';
    final phone = user['phone'] as String? ?? '—';
    final role = (user['role'] as String?)?.toUpperCase() ?? 'PATIENT';
    final isActive = user['is_active'] as bool? ?? true;
    final joinedDate = _formatDate(user['created_at'] as String?);

    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 22,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color:
                                    AppColors.primary.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            role,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: isActive
                                ? AppColors.success.withValues(alpha: 0.1)
                                : AppColors.error.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            isActive ? 'Active' : 'Inactive',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color:
                                  isActive ? AppColors.success : AppColors.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: AppColors.border),
          const SizedBox(height: 12),
          _infoRow(Icons.email_outlined, 'Email', email),
          const SizedBox(height: 8),
          _infoRow(Icons.phone_outlined, 'Phone', phone),
          const SizedBox(height: 8),
          _infoRow(Icons.calendar_today_rounded, 'Joined', joinedDate),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.textMuted),
        const SizedBox(width: 8),
        Text('$label: ',
            style:
                const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _kvRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: ',
            style:
                const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  // ── 2. Rehabilitation Program ───────────────────────────────────────────────

  Widget _buildRehabProgramCard(AsyncValue<WorkoutDashboardModel>? dashAsync) {
    final subtitle = dashAsync?.maybeWhen(
          data: (d) => d.hasActiveProgram
              ? (d.programTitle ?? 'Active program')
              : 'No active program — tap to assign',
          orElse: () => 'Manage assigned rehab programs',
        ) ??
        'Manage assigned rehab programs';

    return GlassCard(
      tint: const Color(0x1000F2FE),
      onTap: () => context.push(
        '/admin/rehab/patients/${widget.userId}/programs',
        extra: _patientName(),
      ),
      child: Row(
        children: [
          const Icon(Icons.fitness_center_rounded,
              color: AppColors.primary, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Rehabilitation Programs',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_ios_rounded,
              color: AppColors.textMuted, size: 16),
        ],
      ),
    );
  }

  // ── 3. Workout Progress ─────────────────────────────────────────────────────

  Widget _buildWorkoutProgress(AsyncValue<WorkoutDashboardModel> dashAsync) {
    return dashAsync.when(
      loading: () => const DashboardLoading(),
      error: (_, __) => DashboardErrorState(
        message: 'Could not load workout progress.',
        onRetry: () =>
            ref.invalidate(patientWorkoutDashboardProvider(widget.userId)),
      ),
      data: (d) {
        if (!d.hasActiveProgram) {
          return const DashboardEmptyState(
            icon: Icons.fitness_center_rounded,
            message:
                'No active program. Workout progress will appear once a program is assigned.',
          );
        }
        return _workoutProgressCard(d);
      },
    );
  }

  Widget _workoutProgressCard(WorkoutDashboardModel d) {
    final todayColor = workoutStatusColor(d.todayStatus);
    final lastCompleted = d.lastCompletedAt != null
        ? DateFormat('MMM d, yyyy · h:mm a').format(d.lastCompletedAt!)
        : '—';
    final complianceColor = d.compliancePercent >= 80
        ? AppColors.success
        : d.compliancePercent >= 50
            ? AppColors.warning
            : AppColors.error;

    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DashboardCaption('Overall Progress'),
          const SizedBox(height: 10),
          DashboardProgressBar(fraction: d.overallFraction),
          const SizedBox(height: 18),
          const Divider(color: AppColors.border),
          const SizedBox(height: 14),
          _kvRow('Current Program', d.programTitle ?? '—'),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text("Today's Status",
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 13)),
              const Spacer(),
              StatusPill(
                  text: workoutStatusLabel(d.todayStatus), color: todayColor),
            ],
          ),
          const SizedBox(height: 12),
          _kvRow('Last Completed', lastCompleted),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: DashboardStatTile(
                  icon: Icons.assignment_outlined,
                  value: '${d.assignedSessions}',
                  label: 'Assigned',
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DashboardStatTile(
                  icon: Icons.check_circle_outline_rounded,
                  value: '${d.completedSessions}',
                  label: 'Completed',
                  color: AppColors.success,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DashboardStatTile(
                  icon: Icons.pending_outlined,
                  value: '${d.remainingSessions}',
                  label: 'Remaining',
                  color: AppColors.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              const DashboardCaption('Compliance'),
              const Spacer(),
              Text(
                '${d.compliancePercent.round()}%',
                style: TextStyle(
                    color: complianceColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 8),
          DashboardProgressBar(
            fraction: (d.compliancePercent / 100).clamp(0.0, 1.0),
            color: complianceColor,
            showPercentLabel: false,
          ),
          const SizedBox(height: 20),
          GlassButton(
            label: 'View Workout History',
            icon: Icons.history_rounded,
            style: GlassButtonStyle.primary,
            width: double.infinity,
            onTap: () => context.push(
              '/admin/rehab/patients/${widget.userId}/history',
              extra: _patientName(),
            ),
          ),
        ],
      ),
    );
  }

  // ── 4. Medical Records ──────────────────────────────────────────────────────

  Widget _buildMedicalRecordsList() {
    if (_loadingRecords) {
      return const DashboardLoading();
    }
    if (_medicalRecords.isEmpty) {
      return const DashboardEmptyState(
        icon: Icons.folder_open_rounded,
        message: 'No medical records uploaded.',
      );
    }
    return Column(
      children:
          _medicalRecords.map((r) => _buildMedicalRecordCard(r)).toList(),
    );
  }

  Widget _buildMedicalRecordCard(MedicalRecord record) {
    final icon = record.isPdf
        ? Icons.picture_as_pdf_rounded
        : record.isImage
            ? Icons.image_rounded
            : Icons.insert_drive_file_rounded;
    final iconColor = record.isPdf
        ? AppColors.error
        : record.isImage
            ? AppColors.secondary
            : AppColors.primary;
    final date = DateFormat('MMM d, yyyy').format(record.uploadedAt.toLocal());

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.fileName,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '$date · ${record.formattedSize} · ${record.fileExtension.toUpperCase()}'
                    '${record.category != null ? ' · ${record.category}' : ''}',
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Preview',
              icon: const Icon(Icons.visibility_outlined,
                  color: AppColors.primary, size: 18),
              onPressed: () => _previewMedicalRecord(record),
            ),
            IconButton(
              tooltip: 'Download',
              icon: _downloadingRecordId == record.id
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.primary),
                    )
                  : const Icon(Icons.download_rounded,
                      color: AppColors.primary, size: 18),
              onPressed: () => _downloadMedicalRecord(record),
            ),
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline_rounded,
                  color: AppColors.error, size: 18),
              onPressed: () => _deleteMedicalRecord(record),
            ),
          ],
        ),
      ),
    );
  }

  // ── 5. Appointment History ──────────────────────────────────────────────────

  Widget _buildAppointmentHistory(
      AsyncValue<List<AppointmentModel>> apptAsync) {
    return apptAsync.when(
      loading: () => const DashboardLoading(),
      error: (_, __) => DashboardErrorState(
        message: 'Could not load appointments.',
        onRetry: () =>
            ref.invalidate(patientAppointmentsProvider(widget.userId)),
      ),
      data: (list) {
        if (list.isEmpty) {
          return const DashboardEmptyState(
            icon: Icons.event_note_rounded,
            message: 'No appointments yet.',
          );
        }
        // Backend returns newest first.
        return Column(
          children: list.map(_appointmentCard).toList(),
        );
      },
    );
  }

  Widget _appointmentCard(AppointmentModel a) {
    final dateStr = DateFormat('EEE, MMM d, y').format(a.startTime);
    final timeStr = DateFormat('h:mm a').format(a.startTime);
    final statusColor = appointmentStatusColor(a);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        onTap: () => context.push('/admin/appointments/${a.id}', extra: a),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: (a.isOnline ? AppColors.secondary : AppColors.primary)
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                a.isOnline
                    ? Icons.videocam_rounded
                    : Icons.location_on_outlined,
                color: a.isOnline ? AppColors.secondary : AppColors.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$dateStr · $timeStr',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    a.isOnline ? 'Google Meet' : 'In Person',
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            StatusPill(text: appointmentStatusLabel(a), color: statusColor),
            const SizedBox(width: 6),
            const Icon(Icons.arrow_forward_ios_rounded,
                color: AppColors.textMuted, size: 14),
          ],
        ),
      ),
    );
  }
}

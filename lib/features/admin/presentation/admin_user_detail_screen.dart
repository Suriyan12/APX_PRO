import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:apx_pro/core/theme/colors.dart';
import 'package:apx_pro/core/theme/glass.dart';
import 'package:apx_pro/core/network/api_client.dart';
import 'package:apx_pro/features/assessment/data/medical_record_model.dart';
import 'package:apx_pro/features/assessment/data/medical_records_repository.dart';
import 'package:apx_pro/features/assessment/presentation/record_viewer_screen.dart';

class AdminUserDetailScreen extends StatefulWidget {
  final String userId;

  const AdminUserDetailScreen({super.key, required this.userId});

  @override
  State<AdminUserDetailScreen> createState() => _AdminUserDetailScreenState();
}

class _AdminUserDetailScreenState extends State<AdminUserDetailScreen> {
  final ApiClient _api = ApiClient();
  late final MedicalRecordsRepository _recordsRepo =
      MedicalRecordsRepository(_api);

  Map<String, dynamic>? _user;
  List<Map<String, dynamic>> _reports = [];
  List<MedicalRecord> _medicalRecords = [];
  bool _loadingUser = true;
  bool _loadingReports = true;
  bool _loadingRecords = true;
  bool _togglingStatus = false;
  String? _downloadingRecordId;

  @override
  void initState() {
    super.initState();
    _loadUserAndReports();
    _loadMedicalRecords();
  }

  Future<void> _loadUserAndReports() async {
    setState(() {
      _loadingUser = true;
      _loadingReports = true;
    });
    try {
      final results = await Future.wait([
        _api.get('/users/${widget.userId}'),
        _api.get('/reports/', queryParameters: {'patient_id': widget.userId}),
      ]);
      if (mounted) {
        setState(() {
          _user = results[0].data as Map<String, dynamic>;
          _reports = (results[1].data as List).cast<Map<String, dynamic>>();
          _loadingUser = false;
          _loadingReports = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingUser = false;
          _loadingReports = false;
        });
      }
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
      setState(() =>
          _medicalRecords.removeWhere((r) => r.id == record.id));
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
              _user!['is_active'] == true ? '$name activated.' : '$name deactivated.',
            ),
            backgroundColor:
                _user!['is_active'] == true ? AppColors.success : AppColors.error,
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
      final dt = DateTime.parse(isoDate).toLocal();
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return isoDate;
    }
  }

  @override
  Widget build(BuildContext context) {
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
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildProfileCard(),
                          if (((_user!['role'] as String?) ?? '').toUpperCase() == 'PATIENT') ...[
                            const SizedBox(height: 16),
                            GlassCard(
                              tint: const Color(0x1000F2FE),
                              onTap: () => context.push(
                                '/admin/rehab/patients/${widget.userId}/programs',
                                extra: _user!['full_name'] as String? ?? 'Patient',
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.fitness_center_rounded, color: AppColors.primary, size: 24),
                                  const SizedBox(width: 12),
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Rehabilitation Programs',
                                          style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
                                        ),
                                        Text(
                                          'Manage assigned rehab programs',
                                          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.textMuted, size: 16),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 24),
                          const Text(
                            'Medical Reports',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildReportsList(),
                          const SizedBox(height: 24),
                          const Text(
                            'Medical Records',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildMedicalRecordsList(),
                        ],
                      ),
                    ),
                  ),
      ),
    );
  }

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
                                color: AppColors.primary.withValues(alpha: 0.3)),
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
                              color: isActive ? AppColors.success : AppColors.error,
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
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
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

  Widget _buildReportsList() {
    if (_loadingReports) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_reports.isEmpty) {
      return GlassCard(
        padding: const EdgeInsets.all(20),
        child: const Center(
          child: Text(
            'No medical reports uploaded.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    return Column(
      children: _reports.map((report) => _buildReportCard(report)).toList(),
    );
  }

  Widget _buildMedicalRecordsList() {
    if (_loadingRecords) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_medicalRecords.isEmpty) {
      return GlassCard(
        padding: const EdgeInsets.all(20),
        child: const Center(
          child: Text(
            'No medical records uploaded.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
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

  Widget _buildReportCard(Map<String, dynamic> report) {
    final title = report['title'] as String? ?? 'Untitled Report';
    final fileType = (report['file_type'] as String? ?? '').toLowerCase();
    final uploadDate = _formatDate(report['uploaded_at'] as String?);

    final isPdf = fileType.contains('pdf');
    final isImage = fileType.contains('image') ||
        fileType.contains('jpeg') ||
        fileType.contains('png');

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isPdf
                    ? AppColors.error.withValues(alpha: 0.1)
                    : isImage
                        ? AppColors.secondary.withValues(alpha: 0.1)
                        : AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isPdf
                    ? Icons.picture_as_pdf_rounded
                    : isImage
                        ? Icons.image_rounded
                        : Icons.insert_drive_file_rounded,
                color: isPdf
                    ? AppColors.error
                    : isImage
                        ? AppColors.secondary
                        : AppColors.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Uploaded $uploadDate',
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.open_in_new_rounded,
                  color: AppColors.primary, size: 18),
              tooltip: 'View Report',
              onPressed: () => _viewReport(report['id'] as String?),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _viewReport(String? reportId) async {
    if (reportId == null) return;
    try {
      final resp = await _api.get('/reports/$reportId/view-url');
      final url = resp.data['view_url'] as String;
      // Show URL in dialog — admin reads in browser
      if (mounted) {
        showGlassDialog<void>(
          context: context,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'View Report',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 18),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Copy this URL and open it in a new browser tab to view the report. The link is valid for 1 hour.',
                  style:
                      TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 12),
                GlassCard(
                  padding: const EdgeInsets.all(10),
                  child: SelectableText(
                    url,
                    style: const TextStyle(
                        color: AppColors.primary, fontSize: 11),
                  ),
                ),
                const SizedBox(height: 20),
                GlassButton(
                  label: 'Close',
                  onTap: () => Navigator.of(context).pop(),
                  style: GlassButtonStyle.ghost,
                  width: double.infinity,
                ),
              ],
            ),
          ),
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
}

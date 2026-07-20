import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:apx_pro/core/network/api_client.dart';
import 'package:apx_pro/core/theme/colors.dart';
import 'package:apx_pro/core/theme/glass.dart';
import 'package:apx_pro/features/assessment/data/medical_record_model.dart';
import 'package:apx_pro/features/assessment/data/medical_records_repository.dart';
import 'package:apx_pro/features/assessment/presentation/controllers/medical_records_controller.dart';
import 'package:apx_pro/features/assessment/presentation/record_viewer_screen.dart';
import 'package:apx_pro/features/auth/presentation/controllers/auth_controller.dart';

const _kRecordCategories = [
  'MRI',
  'X-Ray',
  'Blood Test',
  'Prescription',
  'Scan Report',
  'Assessment Report',
];

class AssessmentScreen extends ConsumerStatefulWidget {
  const AssessmentScreen({super.key});

  @override
  ConsumerState<AssessmentScreen> createState() => _AssessmentScreenState();
}

class _AssessmentScreenState extends ConsumerState<AssessmentScreen> {
  String? _downloadingId;

  String? get _patientId => ref.read(authControllerProvider).userId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final id = _patientId;
      if (id != null) {
        ref.read(medicalRecordsProvider(id).notifier).load();
      }
    });
  }

  Future<void> _pickAndUpload() async {
    final id = _patientId;
    if (id == null) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final picked = result.files.single;
    final bytes = picked.bytes;
    if (bytes == null) return;

    if (!mounted) return;
    final category = await _pickCategory();
    if (!mounted) return;

    final error = await ref.read(medicalRecordsProvider(id).notifier).upload(
          fileName: picked.name,
          bytes: bytes,
          category: category,
        );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error ?? 'Medical record uploaded successfully!'),
        backgroundColor: error == null ? AppColors.success : AppColors.error,
      ),
    );
  }

  /// Optional category chooser shown after picking a file.
  Future<String?> _pickCategory() async {
    return showGlassDialog<String>(
      context: context,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Record Type',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Optional — helps keep your records organized.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _kRecordCategories.map((c) {
                return GestureDetector(
                  onTap: () => Navigator.of(context).pop(c),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: AppColors.primary.withValues(alpha: 0.12),
                      border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      c,
                      style: const TextStyle(
                          color: AppColors.primary, fontSize: 13),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            Center(
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(null),
                child: const Text(
                  'Skip',
                  style: TextStyle(
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _viewRecord(MedicalRecord record) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RecordViewerScreen(
          recordId: record.id,
          fileName: record.fileName,
          mimeType: record.mimeType,
        ),
      ),
    );
  }

  Future<void> _downloadRecord(MedicalRecord record) async {
    if (_downloadingId != null) return;
    setState(() => _downloadingId = record.id);
    try {
      final repo = ref.read(medicalRecordsRepositoryProvider);
      final bytes = await repo.downloadBytes(record.id);
      final path = await saveRecordToDevice(record.fileName, bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved to $path'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _downloadingId = null);
    }
  }

  Future<void> _deleteRecord(MedicalRecord record) async {
    final id = _patientId;
    if (id == null) return;

    final confirmed = await showGlassDialog<bool>(
      context: context,
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Delete Record',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'This will permanently delete "${record.fileName}". Continue?',
              style:
                  const TextStyle(color: AppColors.textSecondary, fontSize: 14),
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

    final error =
        await ref.read(medicalRecordsProvider(id).notifier).delete(record.id);
    if (mounted && error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: AppColors.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final patientId = ref.watch(authControllerProvider).userId;

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: 'Medical Records',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
      ),
      body: GlassOrbBackground(
        child: SafeArea(
          child: patientId == null
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primary))
              : _buildContent(patientId),
        ),
      ),
    );
  }

  Widget _buildContent(String patientId) {
    final state = ref.watch(medicalRecordsProvider(patientId));

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Upload & access your medical records',
            style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),

          // Upload zone
          if (state.uploading)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0x2200F2FE),
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.5),
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        vertical: 28, horizontal: 20),
                    child: Column(
                      children: [
                        LinearProgressIndicator(
                          value: state.uploadProgress,
                          backgroundColor: AppColors.border,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                              AppColors.primary),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Uploading: ${(state.uploadProgress * 100).toInt()}%',
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else ...[
            GlassButton(
              label: 'Upload Medical Records',
              icon: Icons.cloud_upload_outlined,
              onTap: _pickAndUpload,
              style: GlassButtonStyle.primary,
              width: double.infinity,
            ),
            const SizedBox(height: 8),
            const Text(
              'MRI · X-Ray · Blood Test · Prescription (PDF, JPG, PNG)',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 28),

          const Text(
            'My Medical Records',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary),
          ),
          const SizedBox(height: 16),

          Expanded(child: _buildList(patientId, state)),
        ],
      ),
    );
  }

  Widget _buildList(String patientId, MedicalRecordsState state) {
    if (state.loading && state.records.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (state.error != null && state.records.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              state.error!,
              style: const TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            GlassButton(
              label: 'Retry',
              onTap: () =>
                  ref.read(medicalRecordsProvider(patientId).notifier).load(),
              style: GlassButtonStyle.ghost,
            ),
          ],
        ),
      );
    }

    if (state.records.isEmpty) {
      return const Center(
        child: Text(
          'No medical records uploaded yet.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () =>
          ref.read(medicalRecordsProvider(patientId).notifier).load(),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: state.records.length,
        itemBuilder: (context, index) =>
            _buildRecordCard(state.records[index]),
      ),
    );
  }

  Widget _buildRecordCard(MedicalRecord record) {
    final icon = record.isPdf
        ? Icons.picture_as_pdf_outlined
        : record.isImage
            ? Icons.image_outlined
            : Icons.insert_drive_file_outlined;
    final date = DateFormat('MMM d, yyyy').format(record.uploadedAt.toLocal());

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        onTap: () => _viewRecord(record),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.fileName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$date · ${record.formattedSize} · ${record.fileExtension.toUpperCase()}'
                    '${record.category != null ? ' · ${record.category}' : ''}',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Download',
              icon: _downloadingId == record.id
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.primary),
                    )
                  : const Icon(Icons.download_rounded,
                      color: AppColors.primary, size: 20),
              onPressed: () => _downloadRecord(record),
            ),
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline_rounded,
                  color: AppColors.error, size: 20),
              onPressed: () => _deleteRecord(record),
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:apx_pro/core/theme/colors.dart';
import 'package:apx_pro/core/theme/glass.dart';
import 'package:apx_pro/features/notes/presentation/controllers/notes_controller.dart';

class UploadNoteScreen extends ConsumerStatefulWidget {
  const UploadNoteScreen({super.key});

  @override
  ConsumerState<UploadNoteScreen> createState() => _UploadNoteScreenState();
}

class _UploadNoteScreenState extends ConsumerState<UploadNoteScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _categoryController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _tagsController = TextEditingController();

  PlatformFile? _pickedFile;
  bool _uploading = false;

  @override
  void dispose() {
    _titleController.dispose();
    _categoryController.dispose();
    _descriptionController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'ppt', 'pptx', 'jpg', 'jpeg', 'png', 'txt'],
      withData: true,
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() => _pickedFile = result.files.first);
    }
  }

  Future<void> _upload() async {
    if (!_formKey.currentState!.validate()) return;
    if (_pickedFile == null || _pickedFile!.bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a file to upload.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _uploading = true);
    try {
      final repo = ref.read(notesRepositoryProvider);
      await repo.uploadNote(
        title: _titleController.text.trim(),
        category: _categoryController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        tags: _tagsController.text.trim().isEmpty
            ? null
            : _tagsController.text.trim(),
        fileBytes: _pickedFile!.bytes!,
        fileName: _pickedFile!.name,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Note uploaded successfully!'),
            backgroundColor: AppColors.success,
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(title: 'Upload Note'),
      body: GlassOrbBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLabel('Title *'),
                  _buildTextField(
                    controller: _titleController,
                    hint: 'e.g. Anatomy of the Spine',
                    icon: Icons.title,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Title is required' : null,
                  ),
                  const SizedBox(height: 16),

                  _buildLabel('Category *'),
                  _buildTextField(
                    controller: _categoryController,
                    hint: 'e.g. Anatomy',
                    icon: Icons.category_outlined,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Category is required' : null,
                  ),
                  const SizedBox(height: 16),

                  _buildLabel('Description'),
                  _buildTextField(
                    controller: _descriptionController,
                    hint: 'Optional description...',
                    icon: Icons.description_outlined,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),

                  _buildLabel('Tags'),
                  _buildTextField(
                    controller: _tagsController,
                    hint: 'comma-separated e.g. anatomy, spine, vertebrae',
                    icon: Icons.label_outline,
                  ),
                  const SizedBox(height: 24),

                  // File picker
                  _buildLabel('File *'),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: _uploading ? null : _pickFile,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: const Color(0x12FFFFFF),
                                  border: Border.all(
                                    color: _pickedFile != null
                                        ? AppColors.primary.withValues(alpha: 0.6)
                                        : const Color(0x1AFFFFFF),
                                    width: _pickedFile != null ? 1.5 : 1,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Icon(
                                  _pickedFile != null
                                      ? Icons.insert_drive_file
                                      : Icons.upload_file,
                                  color: _pickedFile != null
                                      ? AppColors.primary
                                      : AppColors.textSecondary,
                                  size: 28,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _pickedFile != null
                                            ? _pickedFile!.name
                                            : 'Tap to select file',
                                        style: TextStyle(
                                          color: _pickedFile != null
                                              ? AppColors.textPrimary
                                              : AppColors.textSecondary,
                                          fontWeight: _pickedFile != null
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (_pickedFile != null && _pickedFile!.size > 0)
                                        Text(
                                          _formatSize(_pickedFile!.size),
                                          style: const TextStyle(
                                            color: AppColors.textSecondary,
                                            fontSize: 12,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                if (_pickedFile != null)
                                  IconButton(
                                    icon: const Icon(Icons.close, color: AppColors.textSecondary),
                                    onPressed: () => setState(() => _pickedFile = null),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),
                  const Text(
                    'Supported: PDF, DOC, DOCX, PPT, PPTX, JPG, PNG, TXT',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),

                  const SizedBox(height: 40),

                  // Upload button
                  GlassButton(
                    label: 'Upload Note',
                    icon: Icons.cloud_upload,
                    onTap: _uploading ? null : _upload,
                    style: GlassButtonStyle.primary,
                    loading: _uploading,
                    width: double.infinity,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    IconData? icon,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
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
          TextFormField(
            controller: controller,
            maxLines: maxLines,
            style: const TextStyle(color: AppColors.textPrimary),
            validator: validator,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
              prefixIcon: icon != null
                  ? Icon(icon, color: AppColors.textMuted, size: 18)
                  : null,
              filled: true,
              fillColor: const Color(0x12FFFFFF),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0x1AFFFFFF)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0x1AFFFFFF)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                    color: AppColors.primary.withValues(alpha: 0.6), width: 1.5),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.error),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.error),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

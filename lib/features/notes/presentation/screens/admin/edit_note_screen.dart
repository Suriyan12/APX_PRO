import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:apx_pro/core/theme/colors.dart';
import 'package:apx_pro/core/theme/glass.dart';
import 'package:apx_pro/features/notes/data/note_model.dart';
import 'package:apx_pro/features/notes/presentation/controllers/notes_controller.dart';

class EditNoteScreen extends ConsumerStatefulWidget {
  final String noteId;

  const EditNoteScreen({super.key, required this.noteId});

  @override
  ConsumerState<EditNoteScreen> createState() => _EditNoteScreenState();
}

class _EditNoteScreenState extends ConsumerState<EditNoteScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _categoryController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _tagsController = TextEditingController();

  NoteModel? _note;
  PlatformFile? _replacementFile;
  bool _loading = true;
  bool _saving = false;
  bool _deleting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadNote();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _categoryController.dispose();
    _descriptionController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _loadNote() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final repo = ref.read(notesRepositoryProvider);
      final note = await repo.getNote(widget.noteId);
      _note = note;
      _titleController.text = note.title;
      _categoryController.text = note.category;
      _descriptionController.text = note.description ?? '';
      _tagsController.text = note.tags ?? '';
      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _pickReplacementFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'ppt', 'pptx', 'jpg', 'jpeg', 'png', 'txt'],
      withData: true,
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() => _replacementFile = result.files.first);
    }
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      final repo = ref.read(notesRepositoryProvider);
      await repo.updateNote(
        id: widget.noteId,
        title: _titleController.text.trim(),
        category: _categoryController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        tags: _tagsController.text.trim().isEmpty
            ? null
            : _tagsController.text.trim(),
        fileBytes: _replacementFile?.bytes,
        fileName: _replacementFile?.name,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Note updated successfully!'),
            backgroundColor: AppColors.success,
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteNote() async {
    final confirmed = await showGlassDialog<bool>(
      context: context,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Delete Note',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Are you sure you want to delete "${_note?.title ?? 'this note'}"? This cannot be undone.',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
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

    setState(() => _deleting = true);
    try {
      await ref.read(notesControllerProvider.notifier).deleteNote(widget.noteId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Note deleted.'),
            backgroundColor: AppColors.success,
          ),
        );
        // Pop twice — back to admin list
        context.pop();
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _deleting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Delete failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: 'Edit Note',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
      ),
      body: GlassOrbBackground(
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: AppColors.error, size: 48),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: const TextStyle(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              GlassButton(
                label: 'Retry',
                icon: Icons.refresh,
                onTap: _loadNote,
                style: GlassButtonStyle.primary,
              ),
            ],
          ),
        ),
      );
    }

    final isBusy = _saving || _deleting;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Current file info
              if (_note != null) ...[
                GlassCard(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      const Icon(Icons.insert_drive_file,
                          color: AppColors.textSecondary, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _note!.fileName,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '${_note!.fileTypeLabel} • ${_note!.formattedSize}',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],

              _buildLabel('Title *'),
              _buildTextField(
                controller: _titleController,
                hint: 'Note title',
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Title is required' : null,
              ),
              const SizedBox(height: 16),

              _buildLabel('Category *'),
              _buildTextField(
                controller: _categoryController,
                hint: 'e.g. Anatomy',
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Category is required' : null,
              ),
              const SizedBox(height: 16),

              _buildLabel('Description'),
              _buildTextField(
                controller: _descriptionController,
                hint: 'Optional description...',
                maxLines: 3,
              ),
              const SizedBox(height: 16),

              _buildLabel('Tags'),
              _buildTextField(
                controller: _tagsController,
                hint: 'comma-separated e.g. anatomy, spine',
              ),
              const SizedBox(height: 24),

              // Replace file section
              _buildLabel('Replace File (Optional)'),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: isBusy ? null : _pickReplacementFile,
                child: GlassCard(
                  padding: const EdgeInsets.all(14),
                  tint: _replacementFile != null
                      ? const Color(0x1400F2FE)
                      : const Color(0x12FFFFFF),
                  child: Row(
                    children: [
                      Icon(
                        _replacementFile != null
                            ? Icons.insert_drive_file
                            : Icons.swap_horiz,
                        color: _replacementFile != null
                            ? AppColors.primary
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _replacementFile != null
                                  ? _replacementFile!.name
                                  : 'Tap to select replacement file',
                              style: TextStyle(
                                color: _replacementFile != null
                                    ? AppColors.textPrimary
                                    : AppColors.textSecondary,
                                fontWeight: _replacementFile != null
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (_replacementFile != null)
                              Text(
                                _formatSize(_replacementFile!.size),
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (_replacementFile != null)
                        IconButton(
                          icon: const Icon(Icons.close, color: AppColors.textSecondary),
                          onPressed: () => setState(() => _replacementFile = null),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 40),

              // Save button
              GlassButton(
                label: 'Save Changes',
                icon: Icons.save,
                onTap: isBusy ? null : _saveChanges,
                style: GlassButtonStyle.primary,
                loading: _saving,
                width: double.infinity,
              ),

              const SizedBox(height: 16),

              // Delete button
              GlassButton(
                label: 'Delete Note',
                icon: Icons.delete_forever,
                onTap: isBusy ? null : _deleteNote,
                style: GlassButtonStyle.danger,
                loading: _deleting,
                width: double.infinity,
              ),

              const SizedBox(height: 32),
            ],
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
                  color: AppColors.primary.withValues(alpha: 0.6),
                  width: 1.5,
                ),
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

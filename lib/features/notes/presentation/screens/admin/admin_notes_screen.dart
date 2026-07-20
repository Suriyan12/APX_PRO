import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:apx_pro/core/theme/colors.dart';
import 'package:apx_pro/core/theme/glass.dart';
import 'package:apx_pro/features/notes/data/note_model.dart';
import 'package:apx_pro/features/notes/presentation/controllers/notes_controller.dart';

final _adminNotesSearchProvider = StateProvider<String>((ref) => '');

final adminNotesListProvider = FutureProvider.autoDispose<List<NoteModel>>((ref) async {
  final repo = ref.watch(notesRepositoryProvider);
  final search = ref.watch(_adminNotesSearchProvider);
  return repo.adminListNotes(search: search.isNotEmpty ? search : null);
});

/// Standalone route wrapper (e.g. deep links) around [AdminNotesView]. The
/// Admin Panel embeds the view directly and does NOT use this wrapper.
class AdminNotesScreen extends StatelessWidget {
  const AdminNotesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.background,
      appBar: GlassAppBar(title: 'Manage Notes'),
      body: GlassOrbBackground(
        child: SafeArea(child: AdminNotesView(embedded: false)),
      ),
    );
  }
}

/// Embeddable Notes Management interface — search, list, upload, edit, delete.
/// Content-only (no Scaffold), so it renders directly inside the Admin Panel
/// "Notes" tab and is also wrapped by [AdminNotesScreen] for standalone routing.
class AdminNotesView extends ConsumerStatefulWidget {
  /// When embedded in the Admin Panel tab (default) the content renders behind
  /// the panel's tall glass app bar, so the top is padded to clear it. The
  /// standalone route has its own app bar and passes `false`.
  final bool embedded;
  const AdminNotesView({super.key, this.embedded = true});

  @override
  ConsumerState<AdminNotesView> createState() => _AdminNotesViewState();
}

class _AdminNotesViewState extends ConsumerState<AdminNotesView> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _confirmDelete(BuildContext context, NoteModel note) async {
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
              'Are you sure you want to delete "${note.title}"? This cannot be undone.',
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

    if (confirmed == true && mounted) {
      try {
        await ref.read(notesControllerProvider.notifier).deleteNote(note.id);
        ref.invalidate(adminNotesListProvider);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Note deleted.'),
              backgroundColor: AppColors.success,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete: $e'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final notesAsync = ref.watch(adminNotesListProvider);

    return Stack(
      children: [
        Column(
          children: [
              // Clear the Admin Panel's tall glass app bar (tab chrome) when embedded.
              if (widget.embedded)
                SizedBox(
                  height: MediaQuery.of(context).padding.top + kToolbarHeight + 82.0,
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: ClipRRect(
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
                        controller: _searchController,
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: InputDecoration(
                          hintText: 'Search notes...',
                          hintStyle: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 13,
                          ),
                          prefixIcon: const Icon(
                            Icons.search,
                            color: AppColors.textMuted,
                            size: 18,
                          ),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(
                                    Icons.clear,
                                    color: AppColors.textMuted,
                                    size: 18,
                                  ),
                                  onPressed: () {
                                    _searchController.clear();
                                    ref.read(_adminNotesSearchProvider.notifier).state = '';
                                  },
                                )
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
                              color: AppColors.primary.withValues(alpha: 0.6),
                              width: 1.5,
                            ),
                          ),
                        ),
                        onChanged: (val) {
                          setState(() {});
                          ref.read(_adminNotesSearchProvider.notifier).state = val;
                        },
                      ),
                    ],
                  ),
                ),
              ),

              Expanded(
                child: notesAsync.when(
                  loading: () => const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                  error: (err, _) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline, color: AppColors.error, size: 48),
                          const SizedBox(height: 12),
                          Text(
                            err.toString(),
                            style: const TextStyle(color: AppColors.textSecondary),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          GlassButton(
                            label: 'Retry',
                            icon: Icons.refresh,
                            onTap: () => ref.invalidate(adminNotesListProvider),
                            style: GlassButtonStyle.primary,
                          ),
                        ],
                      ),
                    ),
                  ),
                  data: (notes) {
                    if (notes.isEmpty) {
                      return const Center(
                        child: Text(
                          'No notes found.',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                      itemCount: notes.length,
                      itemBuilder: (context, index) {
                        final note = notes[index];
                        return _AdminNoteItem(
                          note: note,
                          onTap: () async {
                            await context.push('/admin/notes/${note.id}/edit');
                            ref.invalidate(adminNotesListProvider);
                          },
                          onDelete: () => _confirmDelete(context, note),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
          // Upload entry — single source of the action, present both when the
          // view is embedded in the Notes tab and when routed standalone.
          Positioned(
            right: 20,
            bottom: 20,
            child: GlassButton(
              label: 'Upload Note',
              icon: Icons.upload_file,
              onTap: () async {
                await context.push('/admin/notes/upload');
                ref.invalidate(adminNotesListProvider);
              },
            ),
          ),
        ],
      );
  }
}

class _AdminNoteItem extends StatelessWidget {
  final NoteModel note;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _AdminNoteItem({
    required this.note,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(note.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        onDelete();
        return false; // We handle deletion ourselves
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: GlassCard(
          padding: const EdgeInsets.all(14),
          onTap: onTap,
          child: GestureDetector(
            onLongPress: onDelete,
            child: Row(
              children: [
                // File type indicator
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    note.fileTypeLabel,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              note.title,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: note.isActive ? AppColors.success : AppColors.error,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            note.category,
                            style: const TextStyle(
                              color: AppColors.secondary,
                              fontSize: 12,
                            ),
                          ),
                          const Text(
                            ' • ',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                          ),
                          Text(
                            note.formattedSize,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const Icon(Icons.chevron_right, color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

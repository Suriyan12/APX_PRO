import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:apx_pro/core/theme/colors.dart';
import 'package:apx_pro/core/theme/glass.dart';
import 'package:apx_pro/features/notes/data/note_model.dart';
import 'package:apx_pro/features/notes/presentation/controllers/notes_controller.dart';

class NotesHomeScreen extends ConsumerStatefulWidget {
  const NotesHomeScreen({super.key});

  @override
  ConsumerState<NotesHomeScreen> createState() => _NotesHomeScreenState();
}

class _NotesHomeScreenState extends ConsumerState<NotesHomeScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notesState = ref.watch(notesControllerProvider);
    final controller = ref.read(notesControllerProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: 'Study Notes',
        actions: [
          if (notesState.isAdmin)
            IconButton(
              icon: const Icon(Icons.admin_panel_settings, color: AppColors.primary),
              tooltip: 'Manage Notes',
              onPressed: () => context.push('/admin/notes'),
            ),
        ],
      ),
      body: GlassOrbBackground(
        child: SafeArea(
          child: Column(
            children: [
              // Search bar
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
                          hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                          prefixIcon: const Icon(Icons.search, color: AppColors.textMuted, size: 18),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, color: AppColors.textMuted, size: 18),
                                  onPressed: () {
                                    _searchController.clear();
                                    controller.setSearch('');
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
                          controller.setSearch(val);
                        },
                      ),
                    ],
                  ),
                ),
              ),

              // Category chips
              if (notesState.categories.isNotEmpty)
                SizedBox(
                  height: 44,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: notesState.categories.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        final isSelected = notesState.selectedCategory == null;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: const Text('All'),
                            selected: isSelected,
                            onSelected: (_) => controller.setCategory(null),
                            backgroundColor: const Color(0x12FFFFFF),
                            selectedColor: AppColors.primary.withValues(alpha: 0.2),
                            labelStyle: TextStyle(
                              color: isSelected ? AppColors.primary : AppColors.textSecondary,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                            side: BorderSide(
                              color: isSelected ? AppColors.primary : const Color(0x1AFFFFFF),
                            ),
                            checkmarkColor: AppColors.primary,
                          ),
                        );
                      }
                      final cat = notesState.categories[index - 1];
                      final isSelected = notesState.selectedCategory == cat;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(cat),
                          selected: isSelected,
                          onSelected: (_) =>
                              controller.setCategory(isSelected ? null : cat),
                          backgroundColor: const Color(0x12FFFFFF),
                          selectedColor: AppColors.primary.withValues(alpha: 0.2),
                          labelStyle: TextStyle(
                            color: isSelected ? AppColors.primary : AppColors.textSecondary,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                          side: BorderSide(
                            color: isSelected ? AppColors.primary : const Color(0x1AFFFFFF),
                          ),
                          checkmarkColor: AppColors.primary,
                        ),
                      );
                    },
                  ),
                ),

              const SizedBox(height: 8),

              // Notes grid
              Expanded(
                child: _buildBody(notesState, controller, context),
              ),
            ],
          ),
        ),
      ),

      // Lock banner
      bottomNavigationBar: (!notesState.hasAccess && !notesState.isAdmin)
          ? _buildUnlockBanner(context)
          : null,
    );
  }

  Widget _buildBody(
    NotesState notesState,
    NotesController controller,
    BuildContext context,
  ) {
    if (notesState.loadingNotes && notesState.notes.isEmpty) {
      return _buildShimmer();
    }

    if (notesState.errorMessage != null && notesState.notes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 48),
            const SizedBox(height: 12),
            Text(
              notesState.errorMessage!,
              style: const TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            GlassButton(
              label: 'Retry',
              icon: Icons.refresh,
              onTap: controller.loadNotes,
              style: GlassButtonStyle.primary,
            ),
          ],
        ),
      );
    }

    if (notesState.notes.isEmpty) {
      return const Center(
        child: Text(
          'No notes found.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    final locked = !notesState.hasAccess && !notesState.isAdmin;

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.78,
      ),
      itemCount: notesState.notes.length,
      itemBuilder: (context, index) {
        final note = notesState.notes[index];
        return _NoteCard(
          note: note,
          locked: locked,
          onTap: () {
            if (locked) {
              context.push('/notes/purchase');
            } else {
              context.push('/notes/${note.id}/view');
            }
          },
        );
      },
    );
  }

  Widget _buildShimmer() {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.78,
      ),
      itemCount: 6,
      itemBuilder: (_, __) => ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  decoration: const BoxDecoration(
                    color: Color(0x12FFFFFF),
                    border: Border.fromBorderSide(
                      BorderSide(color: Color(0x1AFFFFFF)),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnlockBanner(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: GlassButton(
          label: 'Unlock All Notes — ₹100',
          icon: Icons.lock_open,
          onTap: () => context.push('/notes/purchase'),
          style: GlassButtonStyle.primary,
          width: double.infinity,
        ),
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  final NoteModel note;
  final bool locked;
  final VoidCallback onTap;

  const _NoteCard({
    required this.note,
    required this.locked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(12),
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // File type chip
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                ),
                child: Text(
                  note.fileTypeLabel,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Title
              Text(
                note.title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              // Category badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.secondary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  note.category,
                  style: const TextStyle(
                    color: AppColors.secondary,
                    fontSize: 10,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 8),
              // Description snippet
              if (note.description != null && note.description!.isNotEmpty)
                Text(
                  note.description!,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              const Spacer(),
              // File size
              Text(
                note.formattedSize,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 10,
                ),
              ),
            ],
          ),

          // Lock overlay
          if (locked)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                          ),
                        ),
                      ),
                    ),
                    const Positioned.fill(
                      child: Align(
                        alignment: Alignment.center,
                        child: Icon(Icons.lock, color: AppColors.primary, size: 32),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

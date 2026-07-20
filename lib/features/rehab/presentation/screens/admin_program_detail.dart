import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:apx_pro/core/theme/colors.dart';
import 'package:apx_pro/core/theme/glass.dart';
import 'package:apx_pro/features/rehab/data/rehab_models.dart';
import 'package:apx_pro/features/rehab/presentation/controllers/rehab_controller.dart';

class AdminProgramDetailScreen extends ConsumerStatefulWidget {
  final String programId;

  const AdminProgramDetailScreen({super.key, required this.programId});

  @override
  ConsumerState<AdminProgramDetailScreen> createState() => _AdminProgramDetailState();
}

class _AdminProgramDetailState extends ConsumerState<AdminProgramDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(programDetailProvider(widget.programId).notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(programDetailProvider(widget.programId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: GlassAppBar(
        title: state.program?.title ?? 'Program Detail',
        leading: GestureDetector(
          onTap: context.pop,
          child: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textSecondary, size: 20),
        ),
        actions: [
          if (state.program != null)
            GestureDetector(
              onTap: () => _showEditDialog(context, state.program!),
              child: const Padding(
                padding: EdgeInsets.only(right: 16),
                child: Icon(Icons.edit_rounded, color: AppColors.textSecondary, size: 20),
              ),
            ),
        ],
      ),
      floatingActionButton: state.program != null ? _buildFab(context) : null,
      body: GlassOrbBackground(
        child: _buildBody(context, state),
      ),
    );
  }

  Widget _buildFab(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0x4D00F2FE)),
        boxShadow: [
          BoxShadow(color: AppColors.primary.withValues(alpha: 0.25), blurRadius: 20, spreadRadius: -4),
        ],
      ),
      child: ClipOval(
        child: Material(
          color: const Color(0x2200F2FE),
          child: InkWell(
            onTap: () => context.push('/admin/rehab/programs/${widget.programId}/exercises/add'),
            child: const SizedBox(
              width: 56, height: 56,
              child: Icon(Icons.add_rounded, color: AppColors.primary),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, ProgramDetailState state) {
    if (state.loading && state.program == null) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }

    if (state.error != null && state.program == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: GlassCard(
            tint: const Color(0x22D50000),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 40),
                const SizedBox(height: 12),
                Text(state.error!, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                GlassButton(
                  label: 'Retry',
                  style: GlassButtonStyle.ghost,
                  onTap: () => ref.read(programDetailProvider(widget.programId).notifier).load(),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Catches the initial frame before load() fires (not loading, no error, no data yet)
    if (state.program == null) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }

    final program = state.program!;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(program.title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: program.isActive ? const Color(0x1000E676) : const Color(0x10FFFFFF),
                        border: Border.all(color: program.isActive ? const Color(0x3000E676) : const Color(0x22FFFFFF)),
                      ),
                      child: Text(
                        program.isActive ? 'Active' : 'Inactive',
                        style: TextStyle(
                          color: program.isActive ? AppColors.success : AppColors.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                if (program.description != null) ...[
                  const SizedBox(height: 8),
                  Text(program.description!, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    _InfoChip(Icons.fitness_center_rounded, '${program.exercises.length} exercises'),
                    const SizedBox(width: 8),
                    _InfoChip(Icons.calendar_today_rounded, '${program.estimatedDurationDays} days'),
                  ],
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              const Text('EXERCISES', style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
              const Spacer(),
              const Text('Hold to reorder', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
            ],
          ),
        ),
        Expanded(
          child: program.exercises.isEmpty
              ? Center(
                  child: GlassCard(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.fitness_center_rounded, color: AppColors.textMuted, size: 48),
                        const SizedBox(height: 12),
                        const Text('No exercises yet', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        const Text('Tap + to add the first exercise', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                      ],
                    ),
                  ),
                )
              : ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                  itemCount: program.exercises.length,
                  onReorder: _onReorder,
                  proxyDecorator: (child, index, animation) => Material(
                    color: Colors.transparent,
                    child: child,
                  ),
                  itemBuilder: (_, i) {
                    final ex = program.exercises[i];
                    return _ExerciseCard(
                      key: ValueKey(ex.id),
                      exercise: ex,
                      index: i,
                      onEdit: () => context.push(
                        '/admin/rehab/programs/${widget.programId}/exercises/edit',
                        extra: ex,
                      ),
                      onDelete: () => _confirmDeleteExercise(context, ex),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _onReorder(int oldIndex, int newIndex) {
    final program = ref.read(programDetailProvider(widget.programId)).program!;
    if (newIndex > oldIndex) newIndex -= 1;
    final items = List<RehabExerciseModel>.from(program.exercises);
    final moved = items.removeAt(oldIndex);
    items.insert(newIndex, moved);
    final reorderData = items.asMap().entries
        .map((e) => {'id': e.value.id, 'order_index': e.key})
        .toList();
    ref.read(programDetailProvider(widget.programId).notifier).reorder(reorderData);
  }

  Future<void> _confirmDeleteExercise(BuildContext context, RehabExerciseModel exercise) async {
    final confirmed = await showGlassDialog<bool>(
      context: context,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 36),
            const SizedBox(height: 12),
            const Text('Delete Exercise?', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Remove "${exercise.name}" from this program?', style: const TextStyle(color: AppColors.textSecondary, fontSize: 14), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(child: GlassButton(label: 'Cancel', style: GlassButtonStyle.ghost, onTap: () => Navigator.of(context).pop(false))),
                const SizedBox(width: 12),
                Expanded(child: GlassButton(label: 'Delete', style: GlassButtonStyle.danger, onTap: () => Navigator.of(context).pop(true))),
              ],
            ),
          ],
        ),
      ),
    );
    if (confirmed == true && mounted) {
      try {
        await ref.read(programDetailProvider(widget.programId).notifier).deleteExercise(exercise.id);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to delete exercise.'), backgroundColor: AppColors.error),
          );
        }
      }
    }
  }

  Future<void> _showEditDialog(BuildContext context, RehabProgramModel program) async {
    final titleCtrl = TextEditingController(text: program.title);
    final descCtrl = TextEditingController(text: program.description ?? '');
    final daysCtrl = TextEditingController(text: program.estimatedDurationDays.toString());

    final saved = await showGlassDialog<bool>(
      context: context,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Edit Program', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            GlassTextField(controller: titleCtrl, hintText: 'Program title'),
            const SizedBox(height: 12),
            GlassTextField(controller: descCtrl, hintText: 'Description (optional)', maxLines: 3),
            const SizedBox(height: 12),
            GlassTextField(controller: daysCtrl, hintText: 'Duration in days', keyboardType: TextInputType.number),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(child: GlassButton(label: 'Cancel', style: GlassButtonStyle.ghost, onTap: () => Navigator.of(context).pop(false))),
                const SizedBox(width: 12),
                Expanded(child: GlassButton(label: 'Save', onTap: () => Navigator.of(context).pop(true))),
              ],
            ),
          ],
        ),
      ),
    );

    if (saved == true && titleCtrl.text.trim().isNotEmpty && mounted) {
      try {
        await ref.read(programDetailProvider(widget.programId).notifier)
            .updateProgram(
          title: titleCtrl.text.trim(),
          description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
          estimatedDurationDays: int.tryParse(daysCtrl.text) ?? program.estimatedDurationDays,
        );
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to save changes.'), backgroundColor: AppColors.error),
          );
        }
      }
    }
    titleCtrl.dispose();
    descCtrl.dispose();
    daysCtrl.dispose();
  }
}

class _ExerciseCard extends StatelessWidget {
  final RehabExerciseModel exercise;
  final int index;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ExerciseCard({
    super.key,
    required this.exercise,
    required this.index,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.drag_handle_rounded, color: AppColors.textMuted, size: 22),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0x1500F2FE),
              ),
              child: Center(
                child: Text(
                  '${exercise.orderIndex + 1}',
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(exercise.name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      _TypeChip(exercise.exerciseType),
                      const SizedBox(width: 6),
                      _DifficultyChip(exercise.difficulty),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(_subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                ],
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(onTap: onEdit, child: const Icon(Icons.edit_outlined, color: AppColors.textSecondary, size: 20)),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: onDelete,
                  child: Icon(Icons.delete_outline_rounded, color: AppColors.error.withValues(alpha: 0.7), size: 20),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String get _subtitle {
    if (exercise.exerciseType == ExerciseType.timed) {
      return '${exercise.sets} sets × ${exercise.durationSeconds ?? 30}s · ${exercise.restSeconds}s rest';
    }
    return '${exercise.sets} sets × ${exercise.reps ?? '?'} reps · ${exercise.restSeconds}s rest';
  }
}

class _TypeChip extends StatelessWidget {
  final ExerciseType type;
  const _TypeChip(this.type);

  @override
  Widget build(BuildContext context) {
    final isTimer = type == ExerciseType.timed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: isTimer ? const Color(0x158A2BE2) : const Color(0x1500F2FE),
        border: Border.all(color: isTimer ? const Color(0x308A2BE2) : const Color(0x3000F2FE)),
      ),
      child: Text(
        isTimer ? 'Timed' : 'Reps',
        style: TextStyle(color: isTimer ? AppColors.secondary : AppColors.primary, fontSize: 9, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _DifficultyChip extends StatelessWidget {
  final RehabDifficulty difficulty;
  const _DifficultyChip(this.difficulty);

  @override
  Widget build(BuildContext context) {
    final color = switch (difficulty) {
      RehabDifficulty.easy => AppColors.success,
      RehabDifficulty.moderate => AppColors.warning,
      RehabDifficulty.hard => AppColors.accent,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(difficulty.name, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold)),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoChip(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: const Color(0x10FFFFFF),
        border: Border.all(color: const Color(0x20FFFFFF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.textSecondary, size: 13),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }
}

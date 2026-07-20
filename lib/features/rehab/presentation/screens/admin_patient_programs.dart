import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:apx_pro/core/theme/colors.dart';
import 'package:apx_pro/core/theme/glass.dart';
import 'package:apx_pro/features/rehab/data/rehab_models.dart';
import 'package:apx_pro/features/rehab/presentation/controllers/rehab_controller.dart';

class AdminPatientProgramsScreen extends ConsumerStatefulWidget {
  final String patientId;
  final String patientName;

  const AdminPatientProgramsScreen({
    super.key,
    required this.patientId,
    required this.patientName,
  });

  @override
  ConsumerState<AdminPatientProgramsScreen> createState() => _AdminPatientProgramsState();
}

class _AdminPatientProgramsState extends ConsumerState<AdminPatientProgramsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(patientProgramsProvider(widget.patientId).notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(patientProgramsProvider(widget.patientId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: GlassAppBar(
        title: 'Rehab — ${widget.patientName}',
        leading: GestureDetector(
          onTap: context.pop,
          child: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textSecondary, size: 20),
        ),
      ),
      floatingActionButton: _buildFab(context),
      body: GlassOrbBackground(
        child: RefreshIndicator(
          color: AppColors.primary,
          backgroundColor: AppColors.surface,
          onRefresh: () async => ref.read(patientProgramsProvider(widget.patientId).notifier).load(),
          child: _buildBody(context, state),
        ),
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
            onTap: () => _showCreateDialog(context),
            child: const SizedBox(
              width: 56, height: 56,
              child: Icon(Icons.add_rounded, color: AppColors.primary),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, PatientProgramsState state) {
    if (state.loading && state.programs.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }

    if (state.error != null && state.programs.isEmpty) {
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
                  onTap: () => ref.read(patientProgramsProvider(widget.patientId).notifier).load(),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (state.programs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: GlassCard(
            padding: const EdgeInsets.all(40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.folder_open_rounded, color: AppColors.textMuted, size: 64),
                const SizedBox(height: 16),
                const Text('No programs yet', style: TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(
                  'Create the first program for ${widget.patientName}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                GlassButton(label: 'Create Program', icon: Icons.add_rounded, onTap: () => _showCreateDialog(context)),
              ],
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: state.programs.length,
      itemBuilder: (_, i) => _ProgramCard(
        program: state.programs[i],
        onTap: () => context.push('/admin/rehab/programs/${state.programs[i].id}'),
        onToggle: () => _toggleActive(state.programs[i]),
        onDelete: () => _confirmDelete(context, state.programs[i]),
      ),
    );
  }

  Future<void> _showCreateDialog(BuildContext context) async {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final daysCtrl = TextEditingController(text: '30');

    final created = await showGlassDialog<bool>(
      context: context,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('New Program', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            GlassTextField(controller: titleCtrl, hintText: 'Program title (required)'),
            const SizedBox(height: 12),
            GlassTextField(controller: descCtrl, hintText: 'Description (optional)', maxLines: 3),
            const SizedBox(height: 12),
            GlassTextField(controller: daysCtrl, hintText: 'Duration in days', keyboardType: TextInputType.number),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(child: GlassButton(label: 'Cancel', style: GlassButtonStyle.ghost, onTap: () => Navigator.of(context).pop(false))),
                const SizedBox(width: 12),
                Expanded(child: GlassButton(label: 'Create', onTap: () => Navigator.of(context).pop(true))),
              ],
            ),
          ],
        ),
      ),
    );

    if (created == true && titleCtrl.text.trim().isNotEmpty) {
      final program = await ref.read(patientProgramsProvider(widget.patientId).notifier).createProgram(
        title: titleCtrl.text.trim(),
        description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
        estimatedDurationDays: int.tryParse(daysCtrl.text) ?? 30,
      );
      if (program != null && mounted) {
        context.push('/admin/rehab/programs/${program.id}');
      }
    }
    titleCtrl.dispose();
    descCtrl.dispose();
    daysCtrl.dispose();
  }

  Future<void> _toggleActive(RehabProgramListItem program) async {
    if (program.isActive) {
      final confirmed = await showGlassDialog<bool>(
        context: context,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Deactivate Program?', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('The patient will no longer see this as their active program.', style: TextStyle(color: AppColors.textSecondary, fontSize: 14), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(child: GlassButton(label: 'Cancel', style: GlassButtonStyle.ghost, onTap: () => Navigator.of(context).pop(false))),
                  const SizedBox(width: 12),
                  Expanded(child: GlassButton(label: 'Deactivate', style: GlassButtonStyle.danger, onTap: () => Navigator.of(context).pop(true))),
                ],
              ),
            ],
          ),
        ),
      );
      if (confirmed != true) return;
    }
    await ref.read(patientProgramsProvider(widget.patientId).notifier).toggleProgram(program.id);
  }

  Future<void> _confirmDelete(BuildContext context, RehabProgramListItem program) async {
    final confirmed = await showGlassDialog<bool>(
      context: context,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.delete_forever_rounded, color: AppColors.error, size: 40),
            const SizedBox(height: 12),
            const Text('Delete Program?', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('This will permanently delete "${program.title}" and all its exercises.', style: const TextStyle(color: AppColors.textSecondary, fontSize: 14), textAlign: TextAlign.center),
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
      await ref.read(patientProgramsProvider(widget.patientId).notifier).deleteProgram(program.id);
    }
  }
}

class _ProgramCard extends StatelessWidget {
  final RehabProgramListItem program;
  final VoidCallback onTap;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _ProgramCard({
    required this.program,
    required this.onTap,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        onTap: onTap,
        tint: program.isActive ? const Color(0x1000F2FE) : const Color(0x18FFFFFF),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (program.isActive) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            color: const Color(0x1000E676),
                            border: Border.all(color: const Color(0x3000E676)),
                          ),
                          child: const Text('ACTIVE', style: TextStyle(color: AppColors.success, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Text(program.title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('${program.exerciseCount} exercises · ${program.estimatedDurationDays} days', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text(DateFormat('MMM d, y').format(program.createdAt), style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: onToggle,
                  child: Icon(
                    program.isActive ? Icons.toggle_on_rounded : Icons.toggle_off_rounded,
                    color: program.isActive ? AppColors.success : AppColors.textMuted,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: onDelete,
                  child: Icon(Icons.delete_outline_rounded, color: AppColors.error.withValues(alpha: 0.7), size: 22),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:apx_pro/core/theme/colors.dart';
import 'package:apx_pro/core/theme/glass.dart';
import 'package:apx_pro/features/rehab/data/rehab_models.dart';
import 'package:apx_pro/features/rehab/presentation/controllers/rehab_controller.dart';

class ProgramsTab extends ConsumerStatefulWidget {
  const ProgramsTab({super.key});

  @override
  ConsumerState<ProgramsTab> createState() => _ProgramsTabState();
}

class _ProgramsTabState extends ConsumerState<ProgramsTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final s = ref.read(myRehabProgramProvider);
      if (!s.loading && s.data == null && s.error == null) {
        ref.read(myRehabProgramProvider.notifier).load();
      }
    });
  }

  void _startWorkout() {
    final data = ref.read(myRehabProgramProvider).data;
    if (data == null) return;
    context.push('/rehab/workout', extra: data.program);
  }

  int _estimatedMinutes(RehabProgramModel p) {
    int total = 0;
    for (final ex in p.exercises) {
      if (ex.exerciseType == ExerciseType.timed) {
        total += ex.sets * ((ex.durationSeconds ?? 30) + ex.restSeconds);
      } else {
        total += ex.sets * (30 + ex.restSeconds);
      }
    }
    return (total / 60).ceil().clamp(1, 999);
  }

  String _exerciseSubtitle(RehabExerciseModel ex) {
    if (ex.exerciseType == ExerciseType.timed) {
      return '${ex.sets} sets × ${ex.durationSeconds ?? 30}s • ${ex.restSeconds}s rest';
    }
    return '${ex.sets} sets × ${ex.reps ?? '?'} reps • ${ex.restSeconds}s rest';
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(myRehabProgramProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GlassOrbBackground(
        child: SafeArea(
          child: RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () async {
              await ref.read(myRehabProgramProvider.notifier).load();
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: _buildContent(state),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(MyRehabProgramState state) {
    if (state.loading) {
      return const SizedBox(
        height: 400,
        child: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    if (state.error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: GlassCard(
          tint: const Color(0x22D50000),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                state.error!,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              GlassButton(
                label: 'Retry',
                style: GlassButtonStyle.ghost,
                onTap: () => ref.read(myRehabProgramProvider.notifier).load(),
              ),
            ],
          ),
        ),
      );
    }

    if (state.data == null) {
      return SizedBox(
        height: 400,
        child: Center(
          child: GlassCard(
            padding: const EdgeInsets.all(40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.fitness_center, size: 64, color: AppColors.textMuted),
                SizedBox(height: 16),
                Text(
                  'No Rehabilitation Program',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  "Your therapist hasn't assigned a program yet.",
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final data = state.data!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(data),
          const SizedBox(height: 20),
          _buildProgressCard(data),
          const SizedBox(height: 16),
          _buildProgramInfoCard(data),
          const SizedBox(height: 16),
          _buildTodayWorkoutCard(data),
          const SizedBox(height: 16),
          _buildExercisePreview(data),
        ],
      ),
    );
  }

  Widget _buildHeader(RehabMyProgramData data) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'Rehabilitation',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Your recovery program',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0x30FFD600)),
            color: const Color(0x15FFD600),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.local_fire_department, color: AppColors.warning, size: 18),
              const SizedBox(width: 4),
              Text(
                '${data.progress.streakDays} day streak',
                style: const TextStyle(color: AppColors.warning, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProgressCard(RehabMyProgramData data) {
    return GlassCardCyan(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'PROGRESS',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${data.progress.completionPercent.toStringAsFixed(0)}%',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Text(
                  'completion',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _StatChip(
                      icon: Icons.check_circle_outline,
                      value: '${data.progress.totalSessions}',
                      label: 'sessions',
                    ),
                    const SizedBox(width: 12),
                    _StatChip(
                      icon: Icons.timer_outlined,
                      value: '${data.progress.totalMinutes}',
                      label: 'minutes',
                    ),
                  ],
                ),
              ],
            ),
          ),
          _ProgressRing(
            progress: data.progress.completionPercent / 100,
            color: AppColors.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildProgramInfoCard(RehabMyProgramData data) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.assignment_rounded, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  data.program.title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (!data.program.isActive)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0x30FF2A54)),
                    color: const Color(0x15FF2A54),
                  ),
                  child: const Text(
                    'Inactive',
                    style: TextStyle(color: AppColors.accent, fontSize: 11),
                  ),
                ),
            ],
          ),
          if (data.program.description != null) ...[
            const SizedBox(height: 8),
            Text(
              data.program.description!,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              _InfoChip(Icons.fitness_center, '${data.program.exercises.length} exercises'),
              const SizedBox(width: 8),
              _InfoChip(Icons.calendar_today, '${data.program.estimatedDurationDays} days'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTodayWorkoutCard(RehabMyProgramData data) {
    if (data.todaySession?.isCompleted == true) {
      return GlassCard(
        tint: const Color(0x1500E676),
        glowColor: AppColors.success,
        child: Row(
          children: [
            const Icon(Icons.check_circle, color: AppColors.success, size: 28),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Workout Complete!',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Great job! See you tomorrow.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (data.todaySession != null && !data.todaySession!.isCompleted) {
      return GlassCardCyan(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Continue Today's Workout",
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Session started, ${data.todaySession!.exercisesCompleted}/${data.todaySession!.exercisesTotal} exercises done',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            GlassButton(
              label: 'Continue Workout',
              icon: Icons.play_arrow_rounded,
              onTap: _startWorkout,
            ),
          ],
        ),
      );
    }

    return GlassCardCyan(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Ready for Today's Workout?",
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${data.program.exercises.length} exercises • Est. ${_estimatedMinutes(data.program)} min',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 16),
          GlassButton(
            label: data.program.isActive ? 'Start Workout' : 'Program Inactive',
            icon: Icons.play_arrow_rounded,
            onTap: data.program.isActive ? _startWorkout : null,
          ),
        ],
      ),
    );
  }

  Widget _buildExercisePreview(RehabMyProgramData data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'EXERCISES',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
            letterSpacing: 1.5,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: data.program.exercises.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) => _ExercisePreviewCard(
            exercise: data.program.exercises[i],
            subtitle: _exerciseSubtitle(data.program.exercises[i]),
            onTap: () => context.push('/rehab/exercise', extra: {
              'program': data.program,
              'index': i,
            }),
          ),
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _StatChip({required this.icon, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: AppColors.textSecondary, size: 16),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              label,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
            ),
          ],
        ),
      ],
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
        border: Border.all(color: const Color(0x20FFFFFF)),
        color: const Color(0x10FFFFFF),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.textSecondary, size: 14),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _ExercisePreviewCard extends StatelessWidget {
  final RehabExerciseModel exercise;
  final String subtitle;
  final VoidCallback? onTap;

  const _ExercisePreviewCard({
    required this.exercise,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0x1500F2FE),
              border: Border.all(color: const Color(0x3000F2FE)),
            ),
            child: Center(
              child: Text(
                '${exercise.orderIndex + 1}',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  exercise.name,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _DifficultyChip(exercise.difficulty, exercise.difficultyLabel),
          if (onTap != null) ...[
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.textMuted, size: 14),
          ],
        ],
      ),
    );
  }
}

class _DifficultyChip extends StatelessWidget {
  final RehabDifficulty difficulty;
  final String label;

  const _DifficultyChip(this.difficulty, this.label);

  @override
  Widget build(BuildContext context) {
    final Color color;
    switch (difficulty) {
      case RehabDifficulty.easy:
        color = AppColors.success;
        break;
      case RehabDifficulty.moderate:
        color = AppColors.warning;
        break;
      case RehabDifficulty.hard:
        color = AppColors.accent;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(0x30)),
        color: color.withAlpha(0x15),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _ProgressRing extends StatelessWidget {
  final double progress;
  final Color color;

  const _ProgressRing({required this.progress, required this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(90, 90),
      painter: _RingPainter(progress: progress, color: color),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;

  const _RingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - 6;
    final bg = Paint()
      ..color = const Color(0x1AFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8;
    canvas.drawCircle(center, radius, bg);
    if (progress > 0) {
      final fg = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi * progress.clamp(0.0, 1.0),
        false,
        fg,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}

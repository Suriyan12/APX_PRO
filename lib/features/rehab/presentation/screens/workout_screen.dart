import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:apx_pro/core/theme/colors.dart';
import 'package:apx_pro/core/theme/glass.dart';
import 'package:apx_pro/features/rehab/data/rehab_models.dart';
import 'package:apx_pro/features/rehab/data/rehab_video_source.dart';
import 'package:apx_pro/features/rehab/presentation/controllers/rehab_controller.dart';

class WorkoutScreen extends ConsumerStatefulWidget {
  final RehabProgramModel program;
  final int startingIndex;

  const WorkoutScreen({
    super.key,
    required this.program,
    this.startingIndex = 0,
  });

  @override
  ConsumerState<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends ConsumerState<WorkoutScreen> {
  bool _sessionStarted = false;
  bool _completed = false;

  VideoPlayerController? _videoCtrl;
  ChewieController? _chewieCtrl;
  int _loadedVideoIndex = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(workoutSessionProvider.notifier).startSession(
        widget.program,
        startingIndex: widget.startingIndex,
      );
      if (mounted) setState(() => _sessionStarted = true);
    });
  }

  void _loadVideoForIndex(int index) {
    if (_loadedVideoIndex == index) return;
    final exercises = widget.program.exercises;
    if (index < 0 || index >= exercises.length) return;
    final ex = exercises[index];
    _disposeVideo();
    _loadedVideoIndex = index;
    if (ex.videoType == VideoType.upload) {
      _initMp4Video(ex.id);
    }
  }

  Future<void> _initMp4Video(String exerciseId) async {
    try {
      // Authenticated Range streaming from the backend (Google Drive behind it).
      final headers = await RehabVideoSource.authHeaders();
      final ctrl = VideoPlayerController.networkUrl(
        RehabVideoSource.streamUri(exerciseId),
        httpHeaders: headers,
      );
      await ctrl.initialize();
      if (!mounted) { ctrl.dispose(); return; }
      final chewie = ChewieController(
        videoPlayerController: ctrl,
        autoPlay: false,
        looping: false,
        allowFullScreen: true,
        showControlsOnInitialize: true,
        materialProgressColors: ChewieProgressColors(
          playedColor: AppColors.primary,
          handleColor: AppColors.primary,
          backgroundColor: const Color(0x33FFFFFF),
          bufferedColor: const Color(0x55FFFFFF),
        ),
      );
      if (mounted) setState(() { _videoCtrl = ctrl; _chewieCtrl = chewie; });
    } catch (_) {}
  }

  void _disposeVideo() {
    _chewieCtrl?.dispose();
    _videoCtrl?.dispose();
    _chewieCtrl = null;
    _videoCtrl = null;
  }

  @override
  void dispose() {
    _disposeVideo();
    if (!_completed) {
      // Defer the reset: mutating the provider synchronously during unmount
      // notifies this already-defunct element (markNeedsBuild assertion) and
      // aborts dispose, leaking the subscription. After a microtask the
      // element is fully unmounted and its listener removed.
      final notifier = ref.read(workoutSessionProvider.notifier);
      Future.microtask(() {
        if (notifier.mounted) notifier.reset();
      });
    }
    super.dispose();
  }

  Future<void> _finishWorkout() async {
    final session = await ref.read(workoutSessionProvider.notifier).finishWorkout();
    if (!mounted) return;
    if (session != null) {
      _completed = true;
      ref.read(myRehabProgramProvider.notifier).load();
      context.pop();
    }
  }

  Future<void> _onExit() async {
    final confirmed = await showGlassDialog<bool>(
      context: context,
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Exit Workout?',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your progress will be lost.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: GlassButton(
                    label: 'Stay',
                    style: GlassButtonStyle.ghost,
                    onTap: () => Navigator.of(context).pop(false),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GlassButton(
                    label: 'Exit',
                    style: GlassButtonStyle.danger,
                    onTap: () => Navigator.of(context).pop(true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (confirmed == true && mounted) {
      ref.read(workoutSessionProvider.notifier).reset();
      _completed = true;
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(workoutSessionProvider);
    final notifier = ref.read(workoutSessionProvider.notifier);

    // Swap video whenever exercise index changes
    ref.listen(workoutSessionProvider, (prev, next) {
      if (prev?.currentExerciseIndex != next.currentExerciseIndex) {
        _loadVideoForIndex(next.currentExerciseIndex);
      }
      if (next.sessionId != null && _loadedVideoIndex == -1) {
        _loadVideoForIndex(next.currentExerciseIndex);
      }
    });

    if (!_sessionStarted || state.sessionId == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: GlassOrbBackground(
          child: const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: GlassOrbBackground(
        child: SafeArea(
          child: Column(
            children: [
              _buildTopBar(state, notifier),
              _buildProgressBar(state),
              Expanded(
                child: state.phase == WorkoutPhase.complete
                    ? _buildCompletePhase(state)
                    : _buildExercisePhase(state, notifier),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(WorkoutSessionState state, WorkoutSessionNotifier notifier) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: _onExit,
            child: const Icon(Icons.close_rounded, color: AppColors.textSecondary, size: 24),
          ),
          Expanded(
            child: Center(
              child: Text(
                widget.program.title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          GestureDetector(
            onTap: state.isPaused ? notifier.resume : notifier.pause,
            child: Icon(
              state.isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              color: AppColors.primary,
              size: 24,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar(WorkoutSessionState state) {
    final progress = state.exercises.isEmpty
        ? 0.0
        : state.currentExerciseIndex / state.exercises.length;
    return LinearProgressIndicator(
      value: progress,
      backgroundColor: const Color(0x1AFFFFFF),
      valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
      minHeight: 3,
    );
  }

  Widget _buildExercisePhase(WorkoutSessionState state, WorkoutSessionNotifier notifier) {
    final currentExercise = state.currentExercise;
    if (currentExercise == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          _ExerciseVideoPlayer(
            exercise: currentExercise,
            chewieCtrl: _chewieCtrl,
            onYouTubeTap: () {
              // Play inside APX PRO — never launch the external YouTube app.
              final id = currentExercise.youtubeVideoId;
              if (id == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                        "This video link isn't valid. Please contact your therapist."),
                    backgroundColor: AppColors.error,
                  ),
                );
                return;
              }
              context.push('/rehab/video', extra: {
                'videoId': id,
                'title': currentExercise.name,
              });
            },
          ),
          const SizedBox(height: 12),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0x3000F2FE)),
                color: const Color(0x1000F2FE),
              ),
              child: Text(
                'Exercise ${state.currentExerciseIndex + 1} of ${state.exercises.length}',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        currentExercise.name,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    _DifficultyChip(currentExercise.difficulty, currentExercise.difficultyLabel),
                  ],
                ),
                if (currentExercise.targetArea != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.place_outlined, color: AppColors.textMuted, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        currentExercise.targetArea!,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                ],
                const GlassDivider(),
                const SizedBox(height: 12),
                if (currentExercise.exerciseType == ExerciseType.reps)
                  _RepsPhase(state: state, notifier: notifier, exercise: currentExercise)
                else
                  _TimedPhase(state: state, notifier: notifier, exercise: currentExercise),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GlassButton(
                label: '← Prev',
                style: GlassButtonStyle.ghost,
                onTap: state.currentExerciseIndex > 0
                    ? notifier.goToPreviousExercise
                    : null,
              ),
              GlassButton(
                label: 'Skip →',
                style: GlassButtonStyle.ghost,
                icon: Icons.skip_next,
                onTap: notifier.skipExercise,
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildCompletePhase(WorkoutSessionState state) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          const SizedBox(height: 40),
          GlassCard(
            tint: const Color(0x1500E676),
            glowColor: AppColors.success,
            child: Column(
              children: [
                const Icon(Icons.emoji_events_rounded, color: AppColors.warning, size: 64),
                const SizedBox(height: 16),
                const Text(
                  'Workout Complete!',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Amazing work! You crushed it.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 15),
                ),
                const SizedBox(height: 24),
                IntrinsicHeight(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${state.exercises.length}',
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Text(
                            'exercises',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                      const VerticalDivider(),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${state.results.where((r) => !r.isSkipped).length}',
                            style: const TextStyle(
                              color: AppColors.success,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Text(
                            'completed',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                      const VerticalDivider(),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${state.results.where((r) => r.isSkipped).length}',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Text(
                            'skipped',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                if (state.isSaving)
                  const CircularProgressIndicator(color: AppColors.primary)
                else if (state.error != null) ...[
                  Text(
                    state.error!,
                    style: const TextStyle(color: AppColors.error, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  GlassButton(label: 'Try Again', onTap: _finishWorkout),
                ] else
                  GlassButton(
                    label: 'Finish & Save',
                    icon: Icons.save_rounded,
                    onTap: _finishWorkout,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

// ── Inline video player shown during workout ──────────────────────────────────

class _ExerciseVideoPlayer extends StatelessWidget {
  final RehabExerciseModel exercise;
  final ChewieController? chewieCtrl;
  final VoidCallback onYouTubeTap;

  const _ExerciseVideoPlayer({
    required this.exercise,
    required this.chewieCtrl,
    required this.onYouTubeTap,
  });

  @override
  Widget build(BuildContext context) {
    if (exercise.videoType == VideoType.none) return const SizedBox.shrink();

    if (exercise.videoType == VideoType.youtube) {
      final thumb = exercise.youtubeThumbnail;
      return GestureDetector(
        onTap: onYouTubeTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (thumb != null)
                  Image.network(thumb, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(color: AppColors.surface))
                else
                  Container(color: AppColors.surface),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withAlpha(0x88)],
                    ),
                  ),
                ),
                Center(
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.red.withAlpha(0xCC),
                    ),
                    child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 32),
                  ),
                ),
                const Positioned(
                  bottom: 8,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.play_circle_outline_rounded, color: Colors.white70, size: 12),
                      SizedBox(width: 4),
                      Text('Watch Video',
                          style: TextStyle(color: Colors.white70, fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // MP4 via Chewie
    if (chewieCtrl == null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
            color: AppColors.surface,
            child: const Center(
              child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2),
            ),
          ),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Chewie(controller: chewieCtrl!),
      ),
    );
  }
}

class _RepsPhase extends StatelessWidget {
  final WorkoutSessionState state;
  final WorkoutSessionNotifier notifier;
  final RehabExerciseModel exercise;

  const _RepsPhase({
    required this.state,
    required this.notifier,
    required this.exercise,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'SET ${state.currentSet} OF ${exercise.sets}',
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${exercise.reps ?? '?'} REPS',
          style: const TextStyle(
            color: AppColors.primary,
            fontSize: 48,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 24),
        if (state.phase == WorkoutPhase.resting)
          _RestCountdown(state: state, notifier: notifier)
        else
          GlassButton(
            label: 'Mark Set Done',
            icon: Icons.check_rounded,
            onTap: notifier.markSetDone,
          ),
      ],
    );
  }
}

class _TimedPhase extends StatelessWidget {
  final WorkoutSessionState state;
  final WorkoutSessionNotifier notifier;
  final RehabExerciseModel exercise;

  const _TimedPhase({
    required this.state,
    required this.notifier,
    required this.exercise,
  });

  @override
  Widget build(BuildContext context) {
    if (state.phase == WorkoutPhase.resting) {
      return _RestCountdown(state: state, notifier: notifier);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'SET ${state.currentSet} OF ${exercise.sets}',
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: _CircularCountdown(
            seconds: state.timerSeconds ?? exercise.durationSeconds ?? 30,
            total: exercise.durationSeconds ?? 30,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 16),
        GlassButton(
          label: 'Skip Timer',
          style: GlassButtonStyle.ghost,
          onTap: notifier.markSetDone,
        ),
      ],
    );
  }
}

class _RestCountdown extends StatelessWidget {
  final WorkoutSessionState state;
  final WorkoutSessionNotifier notifier;

  const _RestCountdown({required this.state, required this.notifier});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text(
          'REST',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${state.timerSeconds ?? 0}s',
          style: const TextStyle(
            color: AppColors.warning,
            fontSize: 48,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        GlassButton(
          label: 'Skip Rest',
          style: GlassButtonStyle.ghost,
          onTap: notifier.skipRestTimer,
        ),
      ],
    );
  }
}

class _CircularCountdown extends StatelessWidget {
  final int seconds;
  final int total;
  final Color color;

  const _CircularCountdown({
    required this.seconds,
    required this.total,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    const size = 160.0;
    final progress = total > 0 ? seconds / total : 0.0;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(size, size),
            painter: _CountdownPainter(
              progress: progress.clamp(0.0, 1.0),
              color: color,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$seconds',
                style: TextStyle(
                  color: color,
                  fontSize: size * 0.3,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
              Text(
                'sec',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: size * 0.1,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CountdownPainter extends CustomPainter {
  final double progress;
  final Color color;

  const _CountdownPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - 10;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0x1AFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10,
    );

    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_CountdownPainter old) => old.progress != progress;
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

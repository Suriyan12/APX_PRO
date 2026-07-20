import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:apx_pro/core/theme/colors.dart';
import 'package:apx_pro/core/theme/glass.dart';
import 'package:apx_pro/features/rehab/data/rehab_models.dart';
import 'package:apx_pro/features/rehab/data/rehab_video_source.dart';

class ExerciseDetailScreen extends ConsumerStatefulWidget {
  final RehabProgramModel program;
  final int exerciseIndex;

  const ExerciseDetailScreen({
    super.key,
    required this.program,
    required this.exerciseIndex,
  });

  @override
  ConsumerState<ExerciseDetailScreen> createState() => _ExerciseDetailScreenState();
}

class _ExerciseDetailScreenState extends ConsumerState<ExerciseDetailScreen> {
  VideoPlayerController? _videoCtrl;
  ChewieController? _chewieCtrl;
  bool _videoLoading = false;
  bool _videoError = false;

  RehabExerciseModel get _exercise => widget.program.exercises[widget.exerciseIndex];

  @override
  void initState() {
    super.initState();
    if (_exercise.videoType == VideoType.upload) {
      _initVideo(_exercise.id);
    }
  }

  Future<void> _initVideo(String exerciseId) async {
    setState(() { _videoLoading = true; _videoError = false; });
    try {
      // Uploaded videos stream from the authenticated backend endpoint
      // (Google Drive behind it) with Range support — starts fast, seeks work.
      final headers = await RehabVideoSource.authHeaders();
      final ctrl = VideoPlayerController.networkUrl(
        RehabVideoSource.streamUri(exerciseId),
        httpHeaders: headers,
      );
      await ctrl.initialize();
      final chewie = ChewieController(
        videoPlayerController: ctrl,
        autoPlay: false,
        looping: false,
        allowFullScreen: true,
        allowMuting: true,
        showControlsOnInitialize: true,
        materialProgressColors: ChewieProgressColors(
          playedColor: AppColors.primary,
          handleColor: AppColors.primary,
          backgroundColor: const Color(0x33FFFFFF),
          bufferedColor: const Color(0x55FFFFFF),
        ),
      );
      if (mounted) {
        setState(() {
          _videoCtrl = ctrl;
          _chewieCtrl = chewie;
          _videoLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _videoLoading = false; _videoError = true; });
    }
  }

  @override
  void dispose() {
    _chewieCtrl?.dispose();
    _videoCtrl?.dispose();
    super.dispose();
  }

  void _startExercise() {
    // Pause the preview so its audio doesn't keep playing behind the workout
    // (this screen stays mounted under the pushed route).
    _videoCtrl?.pause();
    context.push('/rehab/workout', extra: {
      'program': widget.program,
      'startAt': widget.exerciseIndex,
    });
  }

  /// Opens the exercise's YouTube video in the in-app player — the external
  /// YouTube app is never launched.
  void _openYouTubePlayer() {
    final id = _exercise.youtubeVideoId;
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("This video link isn't valid. Please contact your therapist."),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    context.push('/rehab/video', extra: {
      'videoId': id,
      'title': _exercise.name,
    });
  }

  @override
  Widget build(BuildContext context) {
    final ex = _exercise;
    return Scaffold(
      backgroundColor: AppColors.background,
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: 'Exercise ${widget.exerciseIndex + 1} of ${widget.program.exercises.length}',
        leading: GestureDetector(
          onTap: context.pop,
          child: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textSecondary, size: 20),
        ),
      ),
      body: GlassOrbBackground(
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildVideoSection(ex),
                      const SizedBox(height: 20),
                      _buildHeader(ex),
                      const SizedBox(height: 16),
                      _buildStatsGrid(ex),
                      if (ex.instructions != null && ex.instructions!.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _buildSection(
                          icon: Icons.list_alt_rounded,
                          title: 'Instructions',
                          child: _buildInstructions(ex.instructions!),
                        ),
                      ],
                      if (ex.targetArea != null && ex.targetArea!.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _buildSection(
                          icon: Icons.place_outlined,
                          title: 'Target Area',
                          child: Text(
                            ex.targetArea!,
                            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, height: 1.5),
                          ),
                        ),
                      ],
                      if (ex.notes != null && ex.notes!.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _buildSection(
                          icon: Icons.sticky_note_2_outlined,
                          title: 'Therapist Notes',
                          tint: const Color(0x1000F2FE),
                          child: Text(
                            ex.notes!,
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.5),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
              _buildStartButton(ex),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideoSection(RehabExerciseModel ex) {
    if (ex.videoType == VideoType.none) {
      return _buildVideoPlaceholder();
    }

    if (ex.videoType == VideoType.youtube) {
      return _buildYouTubeThumbnail(ex);
    }

    // Upload / MP4
    if (_videoLoading) {
      return _videoShell(
        child: const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }
    if (_videoError || _chewieCtrl == null) {
      return _videoShell(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.videocam_off_rounded, color: AppColors.textMuted, size: 40),
            const SizedBox(height: 8),
            const Text('Video unavailable', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
          ],
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Chewie(controller: _chewieCtrl!),
      ),
    );
  }

  Widget _buildYouTubeThumbnail(RehabExerciseModel ex) {
    final thumb = ex.youtubeThumbnail;
    return GestureDetector(
      onTap: _openYouTubePlayer,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (thumb != null)
                Image.network(
                  thumb,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(color: AppColors.surface),
                )
              else
                Container(color: AppColors.surface),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withAlpha(0x99)],
                  ),
                ),
              ),
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.red.withAlpha(0xCC),
                  ),
                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 40),
                ),
              ),
              Positioned(
                bottom: 10,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.play_circle_outline_rounded, color: Colors.white70, size: 14),
                    SizedBox(width: 4),
                    Text('Watch Video', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideoPlaceholder() {
    return _videoShell(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.fitness_center_rounded, color: AppColors.textMuted, size: 40),
          SizedBox(height: 8),
          Text('No video for this exercise', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _videoShell({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          color: AppColors.surface,
          child: child,
        ),
      ),
    );
  }

  Widget _buildHeader(RehabExerciseModel ex) {
    final Color diffColor;
    switch (ex.difficulty) {
      case RehabDifficulty.easy: diffColor = AppColors.success; break;
      case RehabDifficulty.hard: diffColor = AppColors.accent; break;
      default: diffColor = AppColors.warning;
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            ex.name,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 24, fontWeight: FontWeight.bold, height: 1.2),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: diffColor.withAlpha(0x20),
            border: Border.all(color: diffColor.withAlpha(0x40)),
          ),
          child: Text(
            ex.difficultyLabel,
            style: TextStyle(color: diffColor, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
          ),
        ),
      ],
    );
  }

  Widget _buildStatsGrid(RehabExerciseModel ex) {
    final items = <_StatItem>[
      _StatItem(Icons.layers_rounded, '${ex.sets}', 'Sets'),
      if (ex.exerciseType == ExerciseType.reps)
        _StatItem(Icons.repeat_rounded, '${ex.reps ?? '—'}', 'Reps per set')
      else
        _StatItem(Icons.timer_outlined, '${ex.durationSeconds ?? 30}s', 'Duration'),
      _StatItem(Icons.hourglass_bottom_rounded, '${ex.restSeconds}s', 'Rest'),
      _StatItem(
        Icons.schedule_rounded,
        _estimatedTime(ex),
        'Est. time',
      ),
    ];
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: items.map((item) => _buildStatCell(item)).toList(),
      ),
    );
  }

  String _estimatedTime(RehabExerciseModel ex) {
    int secs;
    if (ex.exerciseType == ExerciseType.timed) {
      secs = ex.sets * ((ex.durationSeconds ?? 30) + ex.restSeconds);
    } else {
      secs = ex.sets * (30 + ex.restSeconds);
    }
    if (secs < 60) return '${secs}s';
    return '${(secs / 60).ceil()}min';
  }

  Widget _buildStatCell(_StatItem item) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(item.icon, color: AppColors.primary, size: 20),
        const SizedBox(height: 4),
        Text(item.value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
        Text(item.label, style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
      ],
    );
  }

  Widget _buildSection({
    required IconData icon,
    required String title,
    required Widget child,
    Color? tint,
  }) {
    return GlassCard(
      tint: tint ?? const Color(0x18FFFFFF),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 16),
              const SizedBox(width: 6),
              Text(
                title.toUpperCase(),
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _buildInstructions(String raw) {
    final lines = raw.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.length <= 1) {
      return Text(raw, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, height: 1.6));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines.asMap().entries.map((entry) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 22,
                height: 22,
                margin: const EdgeInsets.only(top: 1, right: 10),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withAlpha(0x20),
                ),
                child: Center(
                  child: Text(
                    '${entry.key + 1}',
                    style: const TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  entry.value.trim(),
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, height: 1.5),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildStartButton(RehabExerciseModel ex) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: GlassButton(
        label: 'Start Exercise',
        icon: Icons.play_arrow_rounded,
        width: double.infinity,
        onTap: _startExercise,
      ),
    );
  }
}

class _StatItem {
  final IconData icon;
  final String value;
  final String label;
  const _StatItem(this.icon, this.value, this.label);
}

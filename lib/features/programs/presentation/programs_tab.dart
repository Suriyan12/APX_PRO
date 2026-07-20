import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:chewie/chewie.dart';
import 'package:video_player/video_player.dart';
import 'package:apx_pro/core/theme/colors.dart';
import 'package:apx_pro/core/theme/glass.dart';
import 'package:apx_pro/core/network/api_client.dart';

class ProgramsTab extends StatefulWidget {
  const ProgramsTab({super.key});

  @override
  State<ProgramsTab> createState() => _ProgramsTabState();
}

class _ProgramsTabState extends State<ProgramsTab> {
  final ApiClient _apiClient = ApiClient();
  List<Map<String, dynamic>> _exercises = [];
  String? _programTitle;
  String? _programId;
  bool _loading = true;
  String? _error;

  // Track which exercise IDs were logged today (avoids duplicate API calls)
  final Set<String> _loggedToday = {};

  @override
  void initState() {
    super.initState();
    _loadProgram();
  }

  Future<void> _loadProgram() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final programsResp = await _apiClient.get('/programs/my-active');
      final programs = programsResp.data as List;

      if (programs.isEmpty) {
        setState(() {
          _loading = false;
          _programTitle = null;
        });
        return;
      }

      final program = programs.first as Map<String, dynamic>;
      _programId = program['id'] as String;
      _programTitle = program['title'] as String;

      final exResp = await _apiClient.get('/programs/$_programId/exercises');
      final exercises = (exResp.data as List).cast<Map<String, dynamic>>();

      // Load today's completed logs
      final logsResp = await _apiClient.get('/programs/workout-logs/today');
      final todayIds = (logsResp.data as List)
          .map((l) => l['exercise_id'] as String)
          .toSet();

      setState(() {
        _exercises = exercises;
        _loggedToday.addAll(todayIds);
        _loading = false;
      });
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load program. Please try again.';
        _loading = false;
      });
    }
  }

  Future<void> _toggleComplete(int index) async {
    final exercise = _exercises[index];
    final exerciseId = exercise['id'] as String;
    final wasCompleted = _loggedToday.contains(exerciseId);

    if (wasCompleted) {
      // Optimistically remove (no DELETE endpoint for logs — toggle is add-only)
      setState(() => _loggedToday.remove(exerciseId));
      return;
    }

    setState(() => _loggedToday.add(exerciseId));

    try {
      await _apiClient.post('/programs/workout-logs', data: {'exercise_id': exerciseId});
    } on ApiException catch (e) {
      setState(() => _loggedToday.remove(exerciseId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to log: ${e.message}'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _openVideoPlayer(String videoUrl, String exerciseName) {
    showGlassDialog(
      context: context,
      child: _VideoPlayerDialog(videoUrl: videoUrl, title: exerciseName),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (_error != null) {
      return GlassOrbBackground(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: GlassCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 40),
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 20),
                  GlassButton(
                    label: 'Retry',
                    onTap: _loadProgram,
                    style: GlassButtonStyle.ghost,
                    width: double.infinity,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (_programTitle == null) {
      return GlassOrbBackground(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: GlassCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.fitness_center_rounded, color: AppColors.textMuted, size: 48),
                  SizedBox(height: 16),
                  Text(
                    'No program assigned yet.\nYour physiotherapist will assign a rehab program after your assessment.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary, height: 1.6),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return GlassOrbBackground(
      child: RefreshIndicator(
        color: AppColors.primary,
        backgroundColor: AppColors.surface,
        onRefresh: _loadProgram,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Home Programs',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _programTitle!,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_loggedToday.length} / ${_exercises.length} completed today',
                      style: const TextStyle(color: AppColors.primary, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final ex = _exercises[index];
                    final id = ex['id'] as String;
                    final isCompleted = _loggedToday.contains(id);
                    final videoUrl = ex['video_url'] as String? ?? '';
                    final name = ex['name'] as String? ?? 'Exercise';
                    final sets = ex['sets'] as int? ?? 3;
                    final reps = ex['reps'] as int?;
                    final durationSec = ex['duration_seconds'] as int?;
                    final setsLabel = reps != null
                        ? '$sets Sets × $reps Reps'
                        : durationSec != null
                            ? '$sets Sets × ${durationSec}s'
                            : '$sets Sets';

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: GlassCard(
                        padding: EdgeInsets.zero,
                        borderRadius: BorderRadius.circular(16),
                        tint: isCompleted
                            ? const Color(0x1400F2FE)
                            : const Color(0x12FFFFFF),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          leading: GestureDetector(
                            onTap: videoUrl.isNotEmpty
                                ? () => _openVideoPlayer(videoUrl, name)
                                : null,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: SizedBox(
                                width: 56,
                                height: 56,
                                child: Stack(
                                  children: [
                                    Positioned.fill(
                                      child: BackdropFilter(
                                        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: AppColors.primary.withValues(alpha: 0.12),
                                            border: Border.all(
                                              color: AppColors.primary.withValues(alpha: 0.25),
                                              width: 1,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Center(
                                      child: Icon(
                                        videoUrl.isNotEmpty
                                            ? Icons.play_circle_fill_rounded
                                            : Icons.fitness_center_rounded,
                                        color: AppColors.primary,
                                        size: 36,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          title: Text(
                            name,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                              decoration:
                                  isCompleted ? TextDecoration.lineThrough : null,
                              decorationColor: AppColors.textSecondary,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 6.0),
                            child: Text(
                              setsLabel,
                              style: const TextStyle(
                                  color: AppColors.textSecondary, fontSize: 13),
                            ),
                          ),
                          trailing: IconButton(
                            icon: Icon(
                              isCompleted
                                  ? Icons.check_circle_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              color: isCompleted
                                  ? AppColors.success
                                  : AppColors.textMuted,
                              size: 28,
                            ),
                            onPressed: () => _toggleComplete(index),
                          ),
                        ),
                      ),
                    );
                  },
                  childCount: _exercises.length,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoPlayerDialog extends StatefulWidget {
  final String videoUrl;
  final String title;
  const _VideoPlayerDialog({required this.videoUrl, required this.title});

  @override
  State<_VideoPlayerDialog> createState() => _VideoPlayerDialogState();
}

class _VideoPlayerDialogState extends State<_VideoPlayerDialog> {
  late VideoPlayerController _videoController;
  ChewieController? _chewieController;

  @override
  void initState() {
    super.initState();
    _videoController =
        VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
    _videoController.initialize().then((_) {
      if (mounted) {
        setState(() {
          _chewieController = ChewieController(
            videoPlayerController: _videoController,
            autoPlay: true,
            looping: false,
            aspectRatio: _videoController.value.aspectRatio,
          );
        });
      }
    });
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _videoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Text(
            widget.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: _chewieController != null
                ? Chewie(controller: _chewieController!)
                : const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: GlassButton(
            label: 'Close',
            onTap: () => Navigator.of(context).pop(),
            style: GlassButtonStyle.ghost,
            width: double.infinity,
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

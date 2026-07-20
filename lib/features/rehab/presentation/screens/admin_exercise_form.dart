import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:apx_pro/core/theme/colors.dart';
import 'package:apx_pro/core/theme/glass.dart';
import 'package:apx_pro/features/rehab/data/rehab_models.dart';
import 'package:apx_pro/features/rehab/data/rehab_video_source.dart';
import 'package:apx_pro/features/rehab/presentation/controllers/rehab_controller.dart';
import 'package:apx_pro/features/rehab/presentation/widgets/video_preview.dart';

class AdminExerciseFormScreen extends ConsumerStatefulWidget {
  final String programId;
  final RehabExerciseModel? exercise;

  const AdminExerciseFormScreen({
    super.key,
    required this.programId,
    this.exercise,
  });

  @override
  ConsumerState<AdminExerciseFormScreen> createState() => _AdminExerciseFormState();
}

class _AdminExerciseFormState extends ConsumerState<AdminExerciseFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _instructionsCtrl;
  late final TextEditingController _setsCtrl;
  late final TextEditingController _repsCtrl;
  late final TextEditingController _durationCtrl;
  late final TextEditingController _restCtrl;
  late final TextEditingController _targetCtrl;
  late final TextEditingController _notesCtrl;
  late final TextEditingController _videoUrlCtrl;
  String _exerciseType = 'reps';
  String _difficulty = 'moderate';
  String _videoType = 'none';
  bool _loading = false;
  PlatformFile? _pickedVideoFile;
  bool _uploadingVideo = false;

  // ── YouTube preview state ──
  String? _ytPreviewId;       // set once the link is verified → player shows
  String? _ytTitle;           // from oEmbed — lets the admin confirm the video
  String? _ytVerifyError;     // extraction / oEmbed failure reason
  bool _ytChecking = false;
  VideoPreviewInfo? _ytInfo;  // playability + duration from the player

  // ── MP4 preview state ──
  VideoPreviewInfo? _mp4Info;

  @override
  void initState() {
    super.initState();
    final ex = widget.exercise;
    _nameCtrl = TextEditingController(text: ex?.name ?? '');
    _descCtrl = TextEditingController(text: ex?.description ?? '');
    _instructionsCtrl = TextEditingController(text: ex?.instructions ?? '');
    _setsCtrl = TextEditingController(text: ex?.sets.toString() ?? '3');
    _repsCtrl = TextEditingController(text: ex?.reps?.toString() ?? '10');
    _durationCtrl = TextEditingController(text: ex?.durationSeconds?.toString() ?? '30');
    _restCtrl = TextEditingController(text: ex?.restSeconds.toString() ?? '30');
    _targetCtrl = TextEditingController(text: ex?.targetArea ?? '');
    _notesCtrl = TextEditingController(text: ex?.notes ?? '');
    _videoUrlCtrl = TextEditingController(text: ex?.videoUrl ?? '');
    if (ex != null) {
      _exerciseType = ex.exerciseType == ExerciseType.timed ? 'timed' : 'reps';
      _difficulty = ex.difficulty.name;
      _videoType = ex.videoType == VideoType.youtube ? 'youtube' : ex.videoType == VideoType.upload ? 'upload' : 'none';
      // Editing an exercise that already has a YouTube link → verify + preview
      // it right away so the admin sees the current video.
      if (_videoType == 'youtube' && (ex.videoUrl ?? '').isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _verifyYouTube());
      }
    }
    // Any edit to the URL invalidates the previous verification.
    _videoUrlCtrl.addListener(() {
      if (_ytPreviewId != null || _ytVerifyError != null) {
        final currentId =
            RehabExerciseModel.extractYouTubeId(_videoUrlCtrl.text.trim());
        if (currentId != _ytPreviewId) {
          setState(() {
            _ytPreviewId = null;
            _ytTitle = null;
            _ytVerifyError = null;
            _ytInfo = null;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _instructionsCtrl.dispose();
    _setsCtrl.dispose();
    _repsCtrl.dispose();
    _durationCtrl.dispose();
    _restCtrl.dispose();
    _targetCtrl.dispose();
    _notesCtrl.dispose();
    _videoUrlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.exercise != null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: GlassAppBar(
        title: isEditing ? 'Edit Exercise' : 'Add Exercise',
        leading: GestureDetector(
          onTap: context.pop,
          child: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textSecondary, size: 20),
        ),
      ),
      body: GlassOrbBackground(
        child: SafeArea(
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionLabel('Exercise Name *'),
                  const SizedBox(height: 8),
                  GlassTextField(
                    controller: _nameCtrl,
                    hintText: 'e.g. Calf Raises',
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 20),
                  _sectionLabel('Exercise Type'),
                  const SizedBox(height: 8),
                  _ToggleChips(
                    options: const ['Reps', 'Timed'],
                    selected: _exerciseType == 'reps' ? 0 : 1,
                    onSelect: (i) => setState(() => _exerciseType = i == 0 ? 'reps' : 'timed'),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _sectionLabel('Sets'),
                            const SizedBox(height: 8),
                            GlassTextField(
                              controller: _setsCtrl,
                              hintText: '3',
                              keyboardType: TextInputType.number,
                              textInputAction: TextInputAction.next,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _sectionLabel(_exerciseType == 'reps' ? 'Reps per Set' : 'Duration (sec)'),
                            const SizedBox(height: 8),
                            GlassTextField(
                              controller: _exerciseType == 'reps' ? _repsCtrl : _durationCtrl,
                              hintText: _exerciseType == 'reps' ? '10' : '30',
                              keyboardType: TextInputType.number,
                              textInputAction: TextInputAction.next,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _sectionLabel('Rest Between Sets (sec)'),
                  const SizedBox(height: 8),
                  GlassTextField(
                    controller: _restCtrl,
                    hintText: '30',
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 20),
                  _sectionLabel('Difficulty'),
                  const SizedBox(height: 8),
                  _ToggleChips(
                    options: const ['Easy', 'Moderate', 'Hard'],
                    selected: _difficulty == 'easy' ? 0 : _difficulty == 'hard' ? 2 : 1,
                    onSelect: (i) => setState(() => _difficulty = ['easy', 'moderate', 'hard'][i]),
                    activeColors: const [AppColors.success, AppColors.warning, AppColors.accent],
                  ),
                  const SizedBox(height: 20),
                  _sectionLabel('Target Area'),
                  const SizedBox(height: 8),
                  GlassTextField(
                    controller: _targetCtrl,
                    hintText: 'e.g. Lower Back, Quadriceps',
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 20),
                  _sectionLabel('Instructions'),
                  const SizedBox(height: 8),
                  GlassTextField(
                    controller: _instructionsCtrl,
                    hintText: 'Step-by-step instructions...',
                    maxLines: 4,
                  ),
                  const SizedBox(height: 20),
                  _sectionLabel('Video'),
                  const SizedBox(height: 8),
                  _ToggleChips(
                    options: const ['None', 'YouTube', 'Upload'],
                    selected: _videoType == 'youtube' ? 1 : _videoType == 'upload' ? 2 : 0,
                    onSelect: (i) => setState(() {
                      _videoType = ['none', 'youtube', 'upload'][i];
                      _mp4Info = null; // preview belongs to the other mode
                    }),
                  ),
                  if (_videoType == 'youtube') ...[
                    const SizedBox(height: 12),
                    GlassTextField(
                      controller: _videoUrlCtrl,
                      hintText: 'https://youtube.com/watch?v=...',
                      keyboardType: TextInputType.url,
                    ),
                    const SizedBox(height: 10),
                    GlassButton(
                      label: _ytChecking ? 'Verifying…' : 'Verify & Preview',
                      style: GlassButtonStyle.ghost,
                      icon: Icons.play_circle_outline_rounded,
                      loading: _ytChecking,
                      onTap: _ytChecking ? null : _verifyYouTube,
                    ),
                    if (_ytVerifyError != null) ...[
                      const SizedBox(height: 12),
                      VideoStatusCard(rows: const [], error: _ytVerifyError),
                    ],
                    if (_ytPreviewId != null) ...[
                      const SizedBox(height: 12),
                      YouTubePreviewPlayer(
                        key: ValueKey('yt-$_ytPreviewId'),
                        videoId: _ytPreviewId!,
                        onInfo: (info) => setState(() => _ytInfo = info),
                      ),
                      const SizedBox(height: 12),
                      if (_ytInfo?.error != null)
                        VideoStatusCard(rows: const [], error: _ytInfo!.error)
                      else
                        VideoStatusCard(rows: _youtubeStatusRows()),
                    ],
                  ],
                  if (_videoType == 'upload') ...[
                    const SizedBox(height: 12),
                    if (_pickedVideoFile != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            const Icon(Icons.videocam_rounded, color: AppColors.success, size: 16),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _pickedVideoFile!.name,
                                style: const TextStyle(color: AppColors.success, fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            GestureDetector(
                              onTap: () => setState(() {
                                _pickedVideoFile = null;
                                _mp4Info = null;
                              }),
                              child: const Icon(Icons.close_rounded, color: AppColors.textMuted, size: 16),
                            ),
                          ],
                        ),
                      ),
                    _uploadingVideo
                        ? const Center(child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2),
                          ))
                        : GlassButton(
                            label: _pickedVideoFile == null ? 'Pick Video File' : 'Change Video',
                            style: GlassButtonStyle.ghost,
                            icon: Icons.upload_file_rounded,
                            onTap: _pickVideo,
                          ),
                    // Preview the freshly picked file BEFORE saving/uploading so
                    // the admin verifies video + audio + duration first.
                    if (_pickedVideoFile != null && !kIsWeb && _pickedVideoFile!.path != null) ...[
                      const SizedBox(height: 12),
                      Mp4PreviewPlayer(
                        key: ValueKey('local-${_pickedVideoFile!.path}'),
                        filePath: _pickedVideoFile!.path,
                        onInfo: (info) => setState(() => _mp4Info = info),
                      ),
                      const SizedBox(height: 12),
                      if (_mp4Info?.error != null)
                        VideoStatusCard(rows: const [], error: _mp4Info!.error)
                      else
                        VideoStatusCard(
                          rows: _mp4StatusRows(
                            uploaded: false,
                            sizeBytes: _pickedVideoFile!.size,
                          ),
                        ),
                    ],
                    // Editing an exercise whose video is already in Google Drive
                    // (and no replacement picked) → preview the stored video.
                    if (_pickedVideoFile == null &&
                        widget.exercise != null &&
                        widget.exercise!.videoType == VideoType.upload) ...[
                      const SizedBox(height: 12),
                      FutureBuilder<Map<String, String>>(
                        future: RehabVideoSource.authHeaders(),
                        builder: (context, snap) {
                          if (!snap.hasData) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.all(12),
                                child: CircularProgressIndicator(
                                    color: AppColors.primary, strokeWidth: 2),
                              ),
                            );
                          }
                          return Column(
                            children: [
                              Mp4PreviewPlayer(
                                key: ValueKey('drive-${widget.exercise!.id}'),
                                networkUri:
                                    RehabVideoSource.streamUri(widget.exercise!.id),
                                httpHeaders: snap.data,
                                onInfo: (info) => setState(() => _mp4Info = info),
                              ),
                              const SizedBox(height: 12),
                              if (_mp4Info?.error != null)
                                VideoStatusCard(
                                    rows: const [],
                                    error:
                                        'The stored video could not be played. It may '
                                        'have been removed from storage — upload it again.')
                              else
                                VideoStatusCard(
                                  rows: _mp4StatusRows(
                                    uploaded: true,
                                    sizeBytes: widget.exercise!.videoFileSize,
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ],
                  ],
                  const SizedBox(height: 20),
                  _sectionLabel('Notes'),
                  const SizedBox(height: 8),
                  GlassTextField(
                    controller: _notesCtrl,
                    hintText: 'Additional notes for the therapist...',
                    maxLines: 3,
                  ),
                  const SizedBox(height: 32),
                  GlassButton(
                    label: isEditing ? 'Save Changes' : 'Add Exercise',
                    icon: isEditing ? Icons.save_rounded : Icons.add_rounded,
                    loading: _loading,
                    onTap: _submit,
                    width: double.infinity,
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickVideo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: false,
      withData: kIsWeb,
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.single;
    if (!kIsWeb && picked.path == null) return;
    setState(() => _pickedVideoFile = picked);
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  /// Checks whether a YouTube video allows embedded playback using YouTube's
  /// public oEmbed endpoint (no API key needed). Returns (error, title):
  /// error == null means the video is embeddable; title is the video's name
  /// so the admin can confirm it's the right one. Network failures return
  /// (null, null) — validation must never block saving when offline.
  Future<(String?, String?)> _checkYouTubeEmbeddable(String videoId) async {
    try {
      final resp = await Dio().get(
        'https://www.youtube.com/oembed',
        queryParameters: {
          'url': 'https://www.youtube.com/watch?v=$videoId',
          'format': 'json',
        },
        options: Options(
          validateStatus: (_) => true,
          sendTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ),
      );
      switch (resp.statusCode) {
        case 200:
          final title = resp.data is Map ? resp.data['title'] as String? : null;
          return (null, title); // embeddable
        case 401:
        case 403:
          return (
            'This video does not allow playback inside other apps '
                '(embedding disabled by its owner). Choose a different video, '
                'or enable embedding in YouTube Studio if it is your own.',
            null,
          );
        case 404:
          return ('This YouTube video does not exist or has been removed.', null);
        default:
          return (null, null); // inconclusive — don't block the save
      }
    } catch (_) {
      return (null, null); // offline / oEmbed unreachable — don't block
    }
  }

  /// Validates the pasted YouTube link and, on success, shows the embedded
  /// preview player + status card so the admin can confirm the video plays
  /// before assigning it to a patient.
  Future<void> _verifyYouTube() async {
    final url = _videoUrlCtrl.text.trim();
    setState(() {
      _ytPreviewId = null;
      _ytTitle = null;
      _ytInfo = null;
      _ytVerifyError = null;
      _ytChecking = true;
    });

    if (url.isEmpty) {
      setState(() {
        _ytChecking = false;
        _ytVerifyError = 'Paste a YouTube link first.';
      });
      return;
    }
    final videoId = RehabExerciseModel.extractYouTubeId(url);
    if (videoId == null) {
      setState(() {
        _ytChecking = false;
        _ytVerifyError = 'Invalid YouTube link. Paste a video URL like '
            'https://youtube.com/watch?v=... or https://youtu.be/... '
            '(playlist links are not supported).';
      });
      return;
    }
    final (embedError, title) = await _checkYouTubeEmbeddable(videoId);
    if (!mounted) return;
    if (embedError != null) {
      setState(() {
        _ytChecking = false;
        _ytVerifyError = embedError;
      });
      return;
    }
    setState(() {
      _ytChecking = false;
      _ytPreviewId = videoId;
      _ytTitle = title;
    });
  }

  List<VideoStatusRow> _youtubeStatusRows() => [
        const VideoStatusRow('YouTube Link Verified'),
        if (_ytTitle != null) VideoStatusRow('Video:', value: _ytTitle),
        VideoStatusRow(
          'Video Playable',
          ok: _ytInfo?.playable ?? true,
          value: _ytInfo == null ? 'tap play to confirm' : null,
        ),
        if (_ytInfo?.duration != null)
          VideoStatusRow('Duration:', value: formatDuration(_ytInfo!.duration!)),
        const VideoStatusRow('Source:', value: 'YouTube'),
      ];

  List<VideoStatusRow> _mp4StatusRows({required bool uploaded, int? sizeBytes}) {
    final info = _mp4Info;
    return [
      VideoStatusRow(uploaded ? 'Upload Successful' : 'File Selected',
          value: uploaded ? null : _pickedVideoFile?.name),
      VideoStatusRow('Video Playable', ok: info?.playable ?? true,
          value: info == null ? 'loading…' : null),
      if (info?.duration != null)
        VideoStatusRow('Duration:', value: formatDuration(info!.duration!)),
      if (info?.resolution != null && info!.resolution!.shortestSide > 0)
        VideoStatusRow('Resolution:', value: resolutionLabel(info.resolution!)),
      if (sizeBytes != null)
        VideoStatusRow('Size:',
            value: '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB'),
      VideoStatusRow('Source:',
          value: uploaded ? 'Google Drive' : 'Will upload to Google Drive'),
    ];
  }

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Exercise name is required.'), backgroundColor: AppColors.error),
      );
      return;
    }

    // Preview gates — the workout may only be saved once the admin has a
    // working, verified preview of whatever the patient will see.
    if (_videoType == 'youtube') {
      if (_videoUrlCtrl.text.trim().isEmpty) {
        _showError('Paste a YouTube link and tap "Verify & Preview" first.');
        return;
      }
      if (_ytPreviewId == null || _ytVerifyError != null) {
        _showError('Please tap "Verify & Preview" and confirm the video plays '
            'before saving.');
        return;
      }
      if (_ytInfo?.error != null) {
        _showError('The previewed video cannot be played. Choose a different one.');
        return;
      }
    }
    if (_videoType == 'upload' && _pickedVideoFile != null && _mp4Info?.error != null) {
      _showError('The selected video file cannot be played. Please pick a '
          'standard MP4 (H.264) file.');
      return;
    }

    setState(() => _loading = true);

    final data = <String, dynamic>{
      'name': _nameCtrl.text.trim(),
      'exercise_type': _exerciseType,
      'sets': int.tryParse(_setsCtrl.text) ?? 3,
      'rest_seconds': int.tryParse(_restCtrl.text) ?? 30,
      'difficulty': _difficulty,
      'video_type': _videoType,
    };

    if (_descCtrl.text.trim().isNotEmpty) data['description'] = _descCtrl.text.trim();
    if (_instructionsCtrl.text.trim().isNotEmpty) data['instructions'] = _instructionsCtrl.text.trim();
    if (_targetCtrl.text.trim().isNotEmpty) data['target_area'] = _targetCtrl.text.trim();
    if (_notesCtrl.text.trim().isNotEmpty) data['notes'] = _notesCtrl.text.trim();

    if (_exerciseType == 'reps') {
      data['reps'] = int.tryParse(_repsCtrl.text) ?? 10;
    } else {
      data['duration_seconds'] = int.tryParse(_durationCtrl.text) ?? 30;
    }

    if (_videoType == 'youtube' && _videoUrlCtrl.text.trim().isNotEmpty) {
      // Already validated by the preview gate above (id extraction + oEmbed
      // embeddability + verified preview); the URL listener resets the gate
      // whenever the link changes, so this value is guaranteed verified.
      data['video_url'] = _videoUrlCtrl.text.trim();
    }

    try {
      final notifier = ref.read(programDetailProvider(widget.programId).notifier);
      final String exerciseId;
      if (widget.exercise == null) {
        // Use the id returned by the create call — never guess it from list
        // order (a wrong guess would attach the video to another exercise).
        exerciseId = await notifier.addExercise(data);
      } else {
        await notifier.updateExercise(widget.exercise!.id, data);
        exerciseId = widget.exercise!.id;
      }

      if (_pickedVideoFile != null) {
        if (mounted) setState(() { _loading = false; _uploadingVideo = true; });
        await notifier.uploadVideo(exerciseId, _pickedVideoFile!);
      }

      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() { _loading = false; _uploadingVideo = false; });
    }
  }
}

class _ToggleChips extends StatelessWidget {
  final List<String> options;
  final int selected;
  final void Function(int) onSelect;
  final List<Color>? activeColors;

  const _ToggleChips({
    required this.options,
    required this.selected,
    required this.onSelect,
    this.activeColors,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: List.generate(options.length, (i) {
        final isSelected = i == selected;
        final color = activeColors?[i] ?? AppColors.primary;
        return GestureDetector(
          onTap: () => onSelect(i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: isSelected ? color.withValues(alpha: 0.15) : const Color(0x0AFFFFFF),
              border: Border.all(
                color: isSelected ? color.withValues(alpha: 0.55) : const Color(0x22FFFFFF),
              ),
            ),
            child: Text(
              options[i],
              style: TextStyle(
                color: isSelected ? color : AppColors.textSecondary,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
            ),
          ),
        );
      }),
    );
  }
}

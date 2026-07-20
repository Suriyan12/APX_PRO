import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:chewie/chewie.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'package:apx_pro/core/theme/colors.dart';
import 'package:apx_pro/core/theme/glass.dart';

/// Result of a completed preview validation — feeds the status card.
class VideoPreviewInfo {
  final bool playable;
  final Duration? duration;
  final Size? resolution; // null for YouTube (player doesn't expose it)
  final String? error;
  const VideoPreviewInfo({
    required this.playable,
    this.duration,
    this.resolution,
    this.error,
  });
}

String formatDuration(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

String resolutionLabel(Size size) {
  final h = size.shortestSide.round(); // handles portrait videos too
  if (h >= 2160) return '4K';
  if (h >= 1440) return '1440p';
  if (h >= 1080) return '1080p';
  if (h >= 720) return '720p';
  if (h >= 480) return '480p';
  return '${h}p';
}

// ─────────────────────────────────────────────────────────────────────────────
// Status card
// ─────────────────────────────────────────────────────────────────────────────

class VideoStatusRow {
  final String label;
  final String? value;
  final bool ok;
  const VideoStatusRow(this.label, {this.value, this.ok = true});
}

/// "Video Status" card shown under a preview — professional ✓/✗ checklist.
class VideoStatusCard extends StatelessWidget {
  final List<VideoStatusRow> rows;
  final String? error; // when set, the card renders in a failure state
  const VideoStatusCard({super.key, required this.rows, this.error});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                error == null ? Icons.verified_rounded : Icons.error_rounded,
                color: error == null ? AppColors.success : AppColors.error,
                size: 18,
              ),
              const SizedBox(width: 8),
              const Text(
                'Video Status',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (error != null)
            Text(
              error!,
              style: const TextStyle(
                  color: AppColors.error, fontSize: 13, height: 1.4),
            )
          else
            ...rows.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        r.ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
                        color: r.ok ? AppColors.success : AppColors.error,
                        size: 15,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        r.label,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 13),
                      ),
                      if (r.value != null) ...[
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            r.value!,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                )),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// YouTube preview (embedded — never leaves the app)
// ─────────────────────────────────────────────────────────────────────────────

class YouTubePreviewPlayer extends StatefulWidget {
  final String videoId;

  /// Fired when playability/duration is known (or an error occurs).
  final ValueChanged<VideoPreviewInfo> onInfo;
  const YouTubePreviewPlayer({
    super.key,
    required this.videoId,
    required this.onInfo,
  });

  @override
  State<YouTubePreviewPlayer> createState() => _YouTubePreviewPlayerState();
}

class _YouTubePreviewPlayerState extends State<YouTubePreviewPlayer> {
  late final YoutubePlayerController _controller;
  bool _reportedPlayable = false;

  @override
  void initState() {
    super.initState();
    _controller = YoutubePlayerController.fromVideoId(
      videoId: widget.videoId,
      autoPlay: false,
      params: const YoutubePlayerParams(
        showControls: true,
        showFullscreenButton: true,
        strictRelatedVideos: true,
        enableCaption: false,
        playsInline: true,
      ),
    );
    _controller.stream.listen((value) {
      if (!mounted) return;
      if (value.error != YoutubeError.none) {
        widget.onInfo(const VideoPreviewInfo(
          playable: false,
          error: 'This video cannot be played in an embedded player. It may '
              'be private, deleted, or embedding may be disabled by its owner.',
        ));
        return;
      }
      final d = value.metaData.duration;
      if (!_reportedPlayable && d > Duration.zero) {
        _reportedPlayable = true;
        widget.onInfo(VideoPreviewInfo(playable: true, duration: d));
      }
    });
  }

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: YoutubePlayer(controller: _controller),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MP4 preview — local picked file OR authenticated network stream
// ─────────────────────────────────────────────────────────────────────────────

class Mp4PreviewPlayer extends StatefulWidget {
  /// Exactly one of [filePath] or [networkUri] must be provided.
  final String? filePath;
  final Uri? networkUri;
  final Map<String, String>? httpHeaders;
  final ValueChanged<VideoPreviewInfo> onInfo;

  const Mp4PreviewPlayer({
    super.key,
    this.filePath,
    this.networkUri,
    this.httpHeaders,
    required this.onInfo,
  }) : assert(filePath != null || networkUri != null);

  @override
  State<Mp4PreviewPlayer> createState() => _Mp4PreviewPlayerState();
}

class _Mp4PreviewPlayerState extends State<Mp4PreviewPlayer> {
  VideoPlayerController? _video;
  ChewieController? _chewie;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final ctrl = widget.filePath != null
          ? VideoPlayerController.file(File(widget.filePath!))
          : VideoPlayerController.networkUrl(
              widget.networkUri!,
              httpHeaders: widget.httpHeaders ?? const {},
            );
      await ctrl.initialize();
      if (!mounted) {
        ctrl.dispose();
        return;
      }
      final chewie = ChewieController(
        videoPlayerController: ctrl,
        autoPlay: false,
        looping: false,
        allowFullScreen: true,
        allowMuting: true,
        materialProgressColors: ChewieProgressColors(
          playedColor: AppColors.primary,
          handleColor: AppColors.primary,
          backgroundColor: const Color(0x33FFFFFF),
          bufferedColor: const Color(0x55FFFFFF),
        ),
      );
      setState(() {
        _video = ctrl;
        _chewie = chewie;
        _loading = false;
      });
      widget.onInfo(VideoPreviewInfo(
        playable: true,
        duration: ctrl.value.duration,
        resolution: ctrl.value.size,
      ));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
      widget.onInfo(const VideoPreviewInfo(
        playable: false,
        error: 'This video could not be played. The file may be corrupted or '
            'in an unsupported format — please try a standard MP4 (H.264).',
      ));
    }
  }

  @override
  void dispose() {
    _chewie?.dispose();
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb && widget.filePath != null) {
      // Local-file preview isn't available on web builds.
      return const SizedBox.shrink();
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: _loading
            ? Container(
                color: AppColors.surface,
                child: const Center(
                  child: CircularProgressIndicator(
                      color: AppColors.primary, strokeWidth: 2),
                ),
              )
            : _failed
                ? Container(
                    color: AppColors.surface,
                    child: const Center(
                      child: Icon(Icons.videocam_off_rounded,
                          color: AppColors.textMuted, size: 40),
                    ),
                  )
                : Chewie(controller: _chewie!),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'package:apx_pro/core/theme/app_theme_extension.dart';
import 'package:apx_pro/core/theme/glass.dart';

/// In-app YouTube playback for workout/exercise videos.
///
/// The video plays entirely inside APX PRO via an embedded iframe player —
/// the external YouTube app is never launched. The 6.x player handles
/// fullscreen internally (landscape rotation, position-preserving resume on
/// exit). Back returns to the previous screen.
class YouTubePlayerScreen extends StatefulWidget {
  final String videoId;
  final String title;
  const YouTubePlayerScreen({
    super.key,
    required this.videoId,
    this.title = 'Exercise Video',
  });

  @override
  State<YouTubePlayerScreen> createState() => _YouTubePlayerScreenState();
}

class _YouTubePlayerScreenState extends State<YouTubePlayerScreen> {
  late final YoutubePlayerController _controller;
  bool _playerError = false;

  @override
  void initState() {
    super.initState();
    _controller = YoutubePlayerController.fromVideoId(
      videoId: widget.videoId,
      autoPlay: true,
      params: const YoutubePlayerParams(
        showControls: true,        // play/pause + seek bar + quality (auto)
        showFullscreenButton: true,
        strictRelatedVideos: true, // keep suggestions within the same channel
        enableCaption: false,
        playsInline: true,
      ),
    );
    _controller.stream.listen((state) {
      // Any reported error (video not found, not embeddable, invalid id…)
      // switches to the friendly error view instead of a blank player.
      if (state.error != YoutubeError.none && mounted && !_playerError) {
        setState(() => _playerError = true);
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
    final ext = context.ext;
    // 6.x: YoutubePlayer handles fullscreen internally (OverlayPortal) — no
    // scaffold wrapper needed.
    return Scaffold(
          backgroundColor: ext.background,
          appBar: GlassAppBar(
            title: widget.title,
            leading: GestureDetector(
              onTap: context.pop,
              child: Icon(Icons.arrow_back_ios_new_rounded,
                  color: ext.textSecondary, size: 20),
            ),
          ),
          body: GlassOrbBackground(
            child: SafeArea(
              child: _playerError
                  ? _ErrorView(ext: ext)
                  : Column(
                      children: [
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: AspectRatio(
                              aspectRatio: 16 / 9,
                              child: YoutubePlayer(controller: _controller),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Row(
                            children: [
                              Icon(Icons.play_circle_outline_rounded,
                                  color: ext.primary, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  widget.title,
                                  style: TextStyle(
                                    color: ext.textPrimary,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Text(
                            'Tip: use the fullscreen button for landscape viewing.',
                            style:
                                TextStyle(color: ext.textMuted, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        );
  }
}

class _ErrorView extends StatelessWidget {
  final AppThemeExtension ext;
  const _ErrorView({required this.ext});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off_rounded, color: ext.textMuted, size: 56),
            const SizedBox(height: 16),
            Text(
              'This video can\'t be played',
              style: TextStyle(
                color: ext.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'The video may have been removed, made private, or its owner '
              'may not allow playback inside other apps. Please contact your '
              'therapist so they can replace it.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: ext.textSecondary, fontSize: 13.5, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

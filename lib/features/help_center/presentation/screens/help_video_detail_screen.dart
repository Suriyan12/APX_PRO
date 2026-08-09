import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import 'package:apx_pro/core/theme/app_theme_extension.dart';
import 'package:apx_pro/core/theme/glass.dart';
import 'package:apx_pro/features/help_center/data/help_models.dart';
import 'package:apx_pro/features/help_center/presentation/controllers/help_controller.dart';

/// Full-screen Help video: an embedded YouTube player (in-app, fullscreen +
/// landscape supported by the 6.x iframe player), the title/description, and a
/// list of related videos from the same category.
///
/// Reached by tapping a card in the Help tab, or via a deep-link notification
/// (`/help/{id}`). Loads by help-video id, then plays the extracted YouTube id.
class HelpVideoDetailScreen extends ConsumerWidget {
  final String helpId;
  const HelpVideoDetailScreen({super.key, required this.helpId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ext = context.ext;
    final async = ref.watch(helpVideoDetailProvider(helpId));

    return Scaffold(
      backgroundColor: ext.background,
      appBar: GlassAppBar(
        title: 'Help',
        leading: GestureDetector(
          onTap: () => context.canPop() ? context.pop() : context.go('/dashboard'),
          child: Icon(Icons.arrow_back_ios_new_rounded,
              color: ext.textSecondary, size: 20),
        ),
      ),
      body: GlassOrbBackground(
        child: SafeArea(
          child: async.when(
            loading: () =>
                Center(child: CircularProgressIndicator(color: ext.primary)),
            error: (e, _) => _ErrorView(
              ext: ext,
              onRetry: () => ref.invalidate(helpVideoDetailProvider(helpId)),
            ),
            data: (detail) => _DetailBody(detail: detail),
          ),
        ),
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  final HelpVideoDetail detail;
  const _DetailBody({required this.detail});

  @override
  Widget build(BuildContext context) {
    final ext = context.ext;
    final v = detail.video;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Player(videoId: v.youtubeVideoId),
          const SizedBox(height: 16),
          Text(
            v.category.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: ext.primary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            v.title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: ext.textPrimary,
              height: 1.25,
            ),
          ),
          if (v.description != null && v.description!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              v.description!,
              style: TextStyle(
                  fontSize: 14, color: ext.textSecondary, height: 1.5),
            ),
          ],
          if (detail.related.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              'Related videos',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: ext.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            ...detail.related.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _RelatedCard(video: r),
                )),
          ],
        ],
      ),
    );
  }
}

/// Isolated player so its controller lifecycle (create/close) is self-contained.
class _Player extends StatefulWidget {
  final String videoId;
  const _Player({required this.videoId});

  @override
  State<_Player> createState() => _PlayerState();
}

class _PlayerState extends State<_Player> {
  YoutubePlayerController? _controller;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    if (widget.videoId.isEmpty) {
      _error = true;
      return;
    }
    _controller = YoutubePlayerController.fromVideoId(
      videoId: widget.videoId,
      autoPlay: false,
      params: const YoutubePlayerParams(
        showControls: true,
        showFullscreenButton: true,
        strictRelatedVideos: true,
        enableCaption: true,
        playsInline: true,
      ),
    );
    _controller!.stream.listen((state) {
      if (state.error != YoutubeError.none && mounted && !_error) {
        setState(() => _error = true);
      }
    });
  }

  @override
  void dispose() {
    _controller?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ext = context.ext;
    if (_error || _controller == null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
            color: ext.surfaceOverlay,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.videocam_off_rounded, color: ext.textMuted, size: 40),
                const SizedBox(height: 8),
                Text('This video can\'t be played',
                    style: TextStyle(color: ext.textSecondary, fontSize: 13)),
              ],
            ),
          ),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: YoutubePlayer(controller: _controller!),
      ),
    );
  }
}

class _RelatedCard extends StatelessWidget {
  final HelpVideoModel video;
  const _RelatedCard({required this.video});

  @override
  Widget build(BuildContext context) {
    final ext = context.ext;
    return GlassCard(
      padding: const EdgeInsets.all(10),
      // Replace (not stack) so the back stack doesn't grow with each hop.
      onTap: () => context.pushReplacement('/help/${video.id}'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(color: ext.surfaceOverlay),
                    if (video.thumbnail != null)
                      Image.network(
                        video.thumbnail!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(
                            Icons.ondemand_video_rounded,
                            color: ext.textMuted,
                            size: 28),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              video.title,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: ext.textPrimary,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final AppThemeExtension ext;
  final VoidCallback onRetry;
  const _ErrorView({required this.ext, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, color: ext.error, size: 48),
            const SizedBox(height: 12),
            Text(
              'Couldn\'t load this video',
              style: TextStyle(
                  color: ext.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'It may have been removed or is temporarily unavailable.',
              textAlign: TextAlign.center,
              style: TextStyle(color: ext.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            GlassButton(
                label: 'Retry', style: GlassButtonStyle.ghost, onTap: onRetry),
          ],
        ),
      ),
    );
  }
}

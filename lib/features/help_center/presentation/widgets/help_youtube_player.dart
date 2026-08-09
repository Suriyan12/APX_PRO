import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import 'package:apx_pro/core/theme/app_theme_extension.dart';

/// Load state of [HelpYoutubePlayer], surfaced to parents so they can gate
/// actions (e.g. the admin form only enables Save once the preview is `ready`).
enum HelpPlayerStatus { loading, ready, error }

/// The single embeddable YouTube player for the Help Center — used by both the
/// user-facing video detail screen and the admin preview. It wraps the same
/// `youtube_player_iframe` controller the Rehab Program module uses
/// (YouTubePlayerScreen), with the same params and error-stream handling, so
/// there is one canonical in-app player rather than a per-screen copy.
///
/// Playback only: play / pause / seek / fullscreen. No download, save, or share
/// affordance is exposed. A broken video (deleted / private / region-locked /
/// invalid) degrades to a graceful "unavailable" message instead of crashing.
class HelpYoutubePlayer extends StatefulWidget {
  final String videoId;
  final bool autoPlay;

  /// Fired when the load state changes (loading → ready | error). Parents use
  /// this to verify playback before allowing publish.
  final ValueChanged<HelpPlayerStatus>? onStatusChanged;

  /// Fired once the video's title metadata resolves (may never fire if YouTube
  /// withholds it). "if available" per the admin details display.
  final ValueChanged<String>? onTitleResolved;

  const HelpYoutubePlayer({
    super.key,
    required this.videoId,
    this.autoPlay = false,
    this.onStatusChanged,
    this.onTitleResolved,
  });

  @override
  State<HelpYoutubePlayer> createState() => _HelpYoutubePlayerState();
}

class _HelpYoutubePlayerState extends State<HelpYoutubePlayer> {
  YoutubePlayerController? _controller;
  HelpPlayerStatus _status = HelpPlayerStatus.loading;
  String? _emittedTitle;

  // Player states that mean the video actually loaded (metadata + first frame
  // cued). Reaching any of these with no error == a verified, playable video.
  static const _loadedStates = {
    PlayerState.cued,
    PlayerState.playing,
    PlayerState.paused,
    PlayerState.buffering,
    PlayerState.ended,
  };

  @override
  void initState() {
    super.initState();
    _init();
  }

  void _init() {
    if (widget.videoId.isEmpty) {
      _status = HelpPlayerStatus.error;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => widget.onStatusChanged?.call(_status),
      );
      return;
    }
    _controller = YoutubePlayerController.fromVideoId(
      videoId: widget.videoId,
      autoPlay: widget.autoPlay,
      params: const YoutubePlayerParams(
        showControls: true, // play/pause + seek bar
        showFullscreenButton: true,
        strictRelatedVideos: true,
        enableCaption: true,
        playsInline: true,
      ),
    );
    _controller!.stream.listen(_onValue);
  }

  void _onValue(YoutubePlayerValue value) {
    if (!mounted) return;

    if (value.error != YoutubeError.none) {
      if (_status != HelpPlayerStatus.error) {
        setState(() => _status = HelpPlayerStatus.error);
        widget.onStatusChanged?.call(_status);
      }
      return;
    }

    final title = value.metaData.title;
    if (title.isNotEmpty && title != _emittedTitle) {
      _emittedTitle = title;
      widget.onTitleResolved?.call(title);
    }

    if (_loadedStates.contains(value.playerState) &&
        _status != HelpPlayerStatus.ready) {
      setState(() => _status = HelpPlayerStatus.ready);
      widget.onStatusChanged?.call(_status);
    }
  }

  @override
  void didUpdateWidget(covariant HelpYoutubePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Rebuild the controller when the target video changes (e.g. the admin
    // edits the URL to a different video).
    if (oldWidget.videoId != widget.videoId) {
      _controller?.close();
      _controller = null;
      _status = HelpPlayerStatus.loading;
      _emittedTitle = null;
      _init();
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller?.close();
    super.dispose();
  }

  Widget _frame({required Widget child}) => ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(aspectRatio: 16 / 9, child: child),
      );

  @override
  Widget build(BuildContext context) {
    final ext = context.ext;

    if (_status == HelpPlayerStatus.error || _controller == null) {
      return _frame(
        child: Container(
          color: ext.surfaceOverlay,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.videocam_off_rounded, color: ext.textMuted, size: 40),
              const SizedBox(height: 8),
              Text(
                'This help video is currently unavailable.',
                textAlign: TextAlign.center,
                style: TextStyle(color: ext.textSecondary, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return _frame(
      child: Stack(
        fit: StackFit.expand,
        children: [
          YoutubePlayer(controller: _controller!),
          if (_status == HelpPlayerStatus.loading)
            IgnorePointer(
              child: Container(
                color: Colors.black26,
                alignment: Alignment.center,
                child: CircularProgressIndicator(color: ext.primary),
              ),
            ),
        ],
      ),
    );
  }
}

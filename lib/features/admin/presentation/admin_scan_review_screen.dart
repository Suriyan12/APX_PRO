import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:apx_pro/core/theme/colors.dart';
import 'package:apx_pro/core/theme/glass.dart';
import 'package:apx_pro/core/network/api_client.dart';

class AdminScanReviewScreen extends StatefulWidget {
  final Map<String, dynamic> scan;

  const AdminScanReviewScreen({super.key, required this.scan});

  @override
  State<AdminScanReviewScreen> createState() => _AdminScanReviewScreenState();
}

class _AdminScanReviewScreenState extends State<AdminScanReviewScreen> {
  final ApiClient _api = ApiClient();
  final _feedbackController = TextEditingController();

  VideoPlayerController? _videoController;
  ChewieController? _chewieController;

  bool _loadingVideo = true;
  bool _submitting = false;
  String? _videoError;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    final existingFeedback = widget.scan['feedback'] as String?;
    if (existingFeedback != null) {
      _feedbackController.text = existingFeedback;
    }
    _fetchAndLoadVideo();
  }

  @override
  void dispose() {
    _feedbackController.dispose();
    _chewieController?.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _fetchAndLoadVideo() async {
    setState(() {
      _loadingVideo = true;
      _videoError = null;
    });
    try {
      final resp = await _api.get('/scans/${widget.scan['id']}/view-url');
      final viewUrl = resp.data['view_url'] as String;
      _videoController = VideoPlayerController.networkUrl(Uri.parse(viewUrl));
      await _videoController!.initialize();
      _chewieController = ChewieController(
        videoPlayerController: _videoController!,
        autoPlay: false,
        looping: false,
        aspectRatio: _videoController!.value.aspectRatio,
        placeholder: Container(
          color: AppColors.background,
          child: const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
        ),
      );
      if (mounted) setState(() => _loadingVideo = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingVideo = false;
          _videoError = e is ApiException ? e.message : 'Failed to load video.';
        });
      }
    }
  }

  Future<void> _submitReview() async {
    final feedback = _feedbackController.text.trim();
    if (feedback.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter your clinical feedback before submitting.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await _api.put(
        '/scans/${widget.scan['id']}/review',
        data: {'feedback': feedback},
      );
      if (mounted) {
        setState(() {
          _submitting = false;
          _submitted = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Feedback submitted successfully.'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
        );
      }
    }
  }

  String _formatDate(String? isoDate) {
    if (isoDate == null) return '—';
    try {
      final dt = DateTime.parse(isoDate).toLocal();
      return '${dt.day}/${dt.month}/${dt.year}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return isoDate;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scan = widget.scan;
    final patient = scan['patient'] as Map<String, dynamic>?;
    final patientName = patient?['full_name'] as String? ?? 'Unknown Patient';
    final patientEmail = patient?['email'] as String? ?? '';
    final status = (scan['status'] as String?)?.toUpperCase() ?? 'PENDING_REVIEW';
    final isReviewed = status == 'REVIEWED';

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: 'Scan Review',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: GlassOrbBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Patient info card
                GlassCard(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: AppColors.secondary.withValues(alpha: 0.15),
                        child: Text(
                          patientName.isNotEmpty ? patientName[0].toUpperCase() : '?',
                          style: const TextStyle(
                            color: AppColors.secondary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              patientName,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            if (patientEmail.isNotEmpty)
                              Text(
                                patientEmail,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isReviewed
                              ? AppColors.success.withValues(alpha: 0.1)
                              : AppColors.warning.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isReviewed
                                ? AppColors.success.withValues(alpha: 0.3)
                                : AppColors.warning.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          isReviewed ? 'Reviewed' : 'Pending',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isReviewed ? AppColors.success : AppColors.warning,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child: Text(
                    'Uploaded ${_formatDate(scan['created_at'] as String?)}',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                ),
                const SizedBox(height: 12),

                // Video player
                GlassCard(
                  padding: EdgeInsets.zero,
                  borderRadius: const BorderRadius.all(Radius.circular(20)),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: _loadingVideo
                        ? const SizedBox(
                            height: 220,
                            child: Center(
                              child: CircularProgressIndicator(color: AppColors.primary),
                            ),
                          )
                        : _videoError != null
                            ? SizedBox(
                                height: 220,
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                        Icons.videocam_off_rounded,
                                        color: AppColors.error,
                                        size: 40,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        _videoError!,
                                        style: const TextStyle(
                                          color: AppColors.textSecondary,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 12),
                                      GlassButton(
                                        label: 'Retry',
                                        onTap: _fetchAndLoadVideo,
                                        style: GlassButtonStyle.ghost,
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : AspectRatio(
                                aspectRatio:
                                    _videoController?.value.aspectRatio ?? 16 / 9,
                                child: Chewie(controller: _chewieController!),
                              ),
                  ),
                ),
                const SizedBox(height: 24),

                // Feedback section
                const Text(
                  'Clinical Feedback',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                          child: Container(color: Colors.transparent),
                        ),
                      ),
                      TextField(
                        controller: _feedbackController,
                        style: const TextStyle(color: AppColors.textPrimary),
                        maxLines: 6,
                        minLines: 4,
                        enabled: !_submitted,
                        decoration: InputDecoration(
                          hintText:
                              'Enter your clinical assessment and recommendations for this patient...',
                          hintStyle: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 13,
                          ),
                          filled: true,
                          fillColor: const Color(0x12FFFFFF),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Color(0x1AFFFFFF)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Color(0x1AFFFFFF)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: AppColors.primary.withValues(alpha: 0.6),
                              width: 1.5,
                            ),
                          ),
                          disabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Color(0x0DFFFFFF)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Submit button
                _submitted
                    ? const GlassButton(
                        label: 'Feedback Submitted',
                        icon: Icons.check_circle_rounded,
                        onTap: null,
                        width: double.infinity,
                      )
                    : GlassButton(
                        label: 'Submit Feedback',
                        icon: Icons.send_rounded,
                        onTap: _submitting ? null : _submitReview,
                        loading: _submitting,
                        width: double.infinity,
                      ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

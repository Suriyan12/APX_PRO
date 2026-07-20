import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:apx_pro/core/network/auth_interceptor.dart';
import 'package:apx_pro/core/theme/colors.dart';
import 'package:apx_pro/core/theme/glass.dart';
import 'package:apx_pro/features/notes/data/note_model.dart';
import 'package:apx_pro/features/notes/presentation/controllers/notes_controller.dart';

class NoteViewerScreen extends ConsumerStatefulWidget {
  final String noteId;

  const NoteViewerScreen({super.key, required this.noteId});

  @override
  ConsumerState<NoteViewerScreen> createState() => _NoteViewerScreenState();
}

class _NoteViewerScreenState extends ConsumerState<NoteViewerScreen> {
  bool _loading = true;
  String? _errorMessage;
  Uint8List? _bytes;
  String _contentType = '';
  String _noteTitle = 'Note';

  // Fast PDF path: stream via range requests instead of buffering all bytes.
  bool _isPdfViaUri = false;
  Uri? _pdfUri;
  Map<String, String>? _pdfHeaders;

  // Backend denied access (pack not purchased) — show a purchase prompt
  // instead of feeding a 403 body to the PDF renderer.
  bool _purchaseRequired = false;

  PdfViewerController? _pdfController;
  int _currentPage = 1;

  @override
  void initState() {
    super.initState();
    _loadNote();
  }

  @override
  void dispose() {
    // PdfViewerController does not implement Disposable — no dispose() call needed
    super.dispose();
  }

  Future<void> _loadNote() async {
    _pdfController = null;

    setState(() {
      _loading = true;
      _errorMessage = null;
      _bytes = null;
      _isPdfViaUri = false;
      _pdfUri = null;
      _purchaseRequired = false;
      _currentPage = 1;
    });

    try {
      final repo = ref.read(notesRepositoryProvider);

      // Fetch metadata first so we can pick the fast path for PDFs.
      NoteModel? note;
      try {
        note = await repo.getNote(widget.noteId);
        if (mounted) setState(() => _noteTitle = note!.title);
      } catch (_) {}

      // Authoritative access gate — the backend decides. This prevents a 403
      // response body from ever being handed to the PDF renderer, and routes
      // locked users to the purchase flow instead.
      final canView = await repo.canView(widget.noteId);
      if (!canView) {
        if (mounted) {
          setState(() {
            _purchaseRequired = true;
            _loading = false;
          });
        }
        return;
      }

      // Fast path: stream the PDF progressively via range requests so the first
      // page renders almost immediately instead of downloading the whole file.
      if (note != null && note.isPdf) {
        final token =
            await const FlutterSecureStorage().read(key: 'jwt_access_token');
        if (mounted) {
          setState(() {
            _pdfUri = Uri.parse(
                '${AuthInterceptor.baseUrl}/notes/${widget.noteId}/viewer');
            _pdfHeaders = {
              if (token != null) 'Authorization': 'Bearer $token',
            };
            _pdfController = PdfViewerController();
            _contentType = 'application/pdf';
            _isPdfViaUri = true;
            _loading = false;
          });
        }
        return;
      }

      // Everything else (images, text, extracted office docs) → fetch bytes.
      final result = await repo.viewNote(widget.noteId);
      final contentType = result.contentType.toLowerCase();

      PdfViewerController? pdfController;
      if (contentType.contains('application/pdf')) {
        pdfController = PdfViewerController();
      }

      if (mounted) {
        setState(() {
          _bytes = result.bytes;
          _contentType = contentType;
          _pdfController = pdfController;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: _noteTitle,
      ),
      body: GlassOrbBackground(
        child: _buildBody(),
      ),
    );
  }

  Widget _buildPurchaseRequired() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: GlassCard(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.primary, width: 2),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.lock_rounded,
                    color: AppColors.primary, size: 30),
              ),
              const SizedBox(height: 16),
              const Text(
                'Premium Content',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Unlock the Notes Pack to view this and every study material — now and in the future.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              GlassButton(
                label: 'Unlock Now',
                icon: Icons.lock_open_rounded,
                // Open the purchase/Razorpay flow; on return, re-check access
                // and auto-open the PDF if the purchase succeeded.
                onTap: () async {
                  await context.push('/notes/purchase');
                  if (mounted) _loadNote();
                },
                style: GlassButtonStyle.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (_purchaseRequired) {
      return _buildPurchaseRequired();
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: AppColors.error, size: 48),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: const TextStyle(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              GlassButton(
                label: 'Retry',
                icon: Icons.refresh,
                onTap: _loadNote,
                style: GlassButtonStyle.primary,
              ),
            ],
          ),
        ),
      );
    }

    // PDF fast path renders straight from the URI (no buffered bytes).
    if (_isPdfViaUri && _pdfController != null) {
      return _buildPdfViewer();
    }

    if (_bytes == null) {
      return const Center(
        child:
            Text('No content', style: TextStyle(color: AppColors.textSecondary)),
      );
    }

    final ct = _contentType;

    if (ct.contains('application/pdf') && _pdfController != null) {
      return _buildPdfViewer();
    } else if (ct.contains('image/')) {
      return _buildImageViewer();
    } else if (ct.contains('text/plain')) {
      return _buildTextViewer();
    } else if (ct.contains('application/json')) {
      return _buildJsonViewer();
    } else {
      return _buildGenericPlaceholder();
    }
  }

  Widget _buildPdfViewer() {
    final params = PdfViewerParams(
      backgroundColor: AppColors.background,
      onPageChanged: (page) {
        if (mounted && page != null) {
          setState(() => _currentPage = page);
        }
      },
      loadingBannerBuilder: (context, bytesDownloaded, totalBytes) {
        return const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        );
      },
      errorBannerBuilder: (context, error, stackTrace, documentRef) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.picture_as_pdf,
                    color: AppColors.error, size: 48),
                const SizedBox(height: 12),
                Text(
                  'Failed to render PDF: $error',
                  style: const TextStyle(color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                GlassButton(
                  label: 'Retry',
                  icon: Icons.refresh,
                  onTap: _loadNote,
                  style: GlassButtonStyle.primary,
                ),
              ],
            ),
          ),
        );
      },
    );

    // URI + range access for the fast path; buffered bytes for the fallback.
    final viewer = _pdfUri != null
        ? PdfViewer.uri(
            _pdfUri!,
            headers: _pdfHeaders,
            preferRangeAccess: true,
            useProgressiveLoading: true,
            controller: _pdfController!,
            params: params,
          )
        : PdfViewer.data(
            _bytes!,
            sourceName: _noteTitle,
            controller: _pdfController!,
            params: params,
          );

    return Stack(
      children: [
        viewer,

        // Page indicator — uses ListenableBuilder since PdfViewerController
        // implements ValueListenable. Guards pageCount behind isReady to avoid
        // a null-document throw before the PDF finishes loading.
        Positioned(
          bottom: 16,
          left: 0,
          right: 0,
          child: ListenableBuilder(
            listenable: _pdfController!,
            builder: (context, _) {
              final ctrl = _pdfController!;
              if (!ctrl.isReady) return const SizedBox.shrink();
              final page = ctrl.pageNumber ?? _currentPage;
              final total = ctrl.pageCount;
              if (total == 0) return const SizedBox.shrink();
              return Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0x2200F2FE),
                              border: Border.all(
                                  color: AppColors.primary.withValues(alpha: 0.4),
                                  width: 1),
                            ),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        child: Text(
                          '$page / $total',
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildImageViewer() {
    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 4.0,
      child: Center(
        child: Image.memory(
          _bytes!,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Center(
            child: Text(
              'Failed to render image',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextViewer() {
    final text = utf8.decode(_bytes!, allowMalformed: true);
    return Scrollbar(
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        padding: const EdgeInsets.fromLTRB(16, kToolbarHeight + 16, 16, 40),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Text(
            text,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontFamily: 'monospace',
              fontSize: 13,
              height: 1.6,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildJsonViewer() {
    try {
      final json = jsonDecode(utf8.decode(_bytes!)) as Map<String, dynamic>;
      final type = json['type'] as String?;

      if (type == 'extracted_text') {
        final paragraphs = (json['paragraphs'] as List<dynamic>?) ?? [];
        return ListView.builder(
          padding:
              const EdgeInsets.fromLTRB(16, kToolbarHeight + 16, 16, 40),
          itemCount: paragraphs.length,
          itemBuilder: (context, index) {
            final para = paragraphs[index] as Map<String, dynamic>;
            final isHeading = (para['heading'] as bool?) ?? false;
            final text = (para['text'] as String?) ?? '';
            return Padding(
              padding: EdgeInsets.only(bottom: isHeading ? 12 : 6),
              child: Text(
                text,
                style: TextStyle(
                  color: isHeading
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                  fontWeight:
                      isHeading ? FontWeight.bold : FontWeight.normal,
                  fontSize: isHeading ? 16 : 14,
                  height: 1.5,
                ),
              ),
            );
          },
        );
      } else if (type == 'extracted_slides') {
        final slides = (json['slides'] as List<dynamic>?) ?? [];
        return ListView.builder(
          padding:
              const EdgeInsets.fromLTRB(16, kToolbarHeight + 16, 16, 40),
          itemCount: slides.length,
          itemBuilder: (context, index) {
            final slide = slides[index] as Map<String, dynamic>;
            final slideNum = (slide['slide_num'] as int?) ?? (index + 1);
            final title = (slide['title'] as String?) ?? '';
            final content = (slide['content'] as String?) ?? '';
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: GlassCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color:
                                AppColors.primary.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '$slideNum',
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (content.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        content,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      } else {
        return _buildGenericPlaceholder();
      }
    } catch (e) {
      return Center(
        child: Text(
          'Failed to parse content: $e',
          style: const TextStyle(color: AppColors.error),
        ),
      );
    }
  }

  Widget _buildGenericPlaceholder() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: GlassCard(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.insert_drive_file,
                  color: AppColors.textSecondary, size: 64),
              const SizedBox(height: 16),
              Text(
                _noteTitle,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Content type: $_contentType\nSize: ${(_bytes!.length / 1024).toStringAsFixed(1)} KB',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

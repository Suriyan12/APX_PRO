import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pdfrx/pdfrx.dart';

import 'package:apx_pro/core/network/api_client.dart';
import 'package:apx_pro/core/network/auth_interceptor.dart';
import 'package:apx_pro/core/theme/colors.dart';
import 'package:apx_pro/core/theme/glass.dart';
import 'package:apx_pro/features/assessment/data/medical_records_repository.dart';
import 'package:apx_pro/features/assessment/presentation/controllers/medical_records_controller.dart';

/// In-app preview for a medical record. Bytes are streamed through the
/// authenticated backend — no Google Drive URL ever reaches the client.
class RecordViewerScreen extends ConsumerStatefulWidget {
  final String recordId;
  final String fileName;
  final String mimeType;

  const RecordViewerScreen({
    super.key,
    required this.recordId,
    required this.fileName,
    required this.mimeType,
  });

  @override
  ConsumerState<RecordViewerScreen> createState() => _RecordViewerScreenState();
}

class _RecordViewerScreenState extends ConsumerState<RecordViewerScreen> {
  late final MedicalRecordsRepository _repo =
      ref.read(medicalRecordsRepositoryProvider);

  Uint8List? _bytes;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  // Fast PDF path: stream via range requests instead of buffering all bytes.
  bool _isPdfViaUri = false;
  Uri? _pdfUri;
  Map<String, String>? _pdfHeaders;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _isPdfViaUri = false;
      _pdfUri = null;
    });
    try {
      // PDFs stream progressively via range requests (first page loads fast).
      if (widget.mimeType.contains('pdf')) {
        final token =
            await const FlutterSecureStorage().read(key: 'jwt_access_token');
        if (mounted) {
          setState(() {
            _pdfUri = Uri.parse(
                '${AuthInterceptor.baseUrl}/medical-records/${widget.recordId}/download?inline=true');
            _pdfHeaders = {
              if (token != null) 'Authorization': 'Bearer $token',
            };
            _isPdfViaUri = true;
            _loading = false;
          });
        }
        return;
      }

      final bytes = await _repo.downloadBytes(widget.recordId, inline: true);
      if (mounted) {
        setState(() {
          _bytes = bytes;
          _loading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load the document.';
        });
      }
    }
  }

  Future<void> _saveToDevice() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      // Fetch bytes on demand for the PDF (range) path, which doesn't buffer.
      final bytes = _bytes ?? await _repo.downloadBytes(widget.recordId);
      final path = await saveRecordToDevice(widget.fileName, bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved to $path'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save the file.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: GlassAppBar(
        title: widget.fileName,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.textPrimary, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (_bytes != null || _isPdfViaUri)
            IconButton(
              tooltip: 'Download',
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.primary),
                    )
                  : const Icon(Icons.download_rounded,
                      color: AppColors.primary),
              onPressed: _saveToDevice,
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    // PDF fast path renders straight from the URI (range requests, no buffer).
    if (_isPdfViaUri && _pdfUri != null) {
      return PdfViewer.uri(
        _pdfUri!,
        headers: _pdfHeaders,
        preferRangeAccess: true,
        useProgressiveLoading: true,
        params: const PdfViewerParams(backgroundColor: AppColors.background),
      );
    }

    if (_error != null || _bytes == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: AppColors.error, size: 44),
            const SizedBox(height: 12),
            Text(
              _error ?? 'Could not load the document.',
              style: const TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            GlassCard(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              onTap: _load,
              child: const Text(
                'Retry',
                style: TextStyle(
                    color: AppColors.primary, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
    }

    if (widget.mimeType.contains('pdf')) {
      return PdfViewer.data(
        _bytes!,
        sourceName: widget.fileName,
        params: const PdfViewerParams(backgroundColor: AppColors.background),
      );
    }

    if (widget.mimeType.startsWith('image/')) {
      return InteractiveViewer(
        maxScale: 5,
        child: Center(
          child: Image.memory(
            _bytes!,
            errorBuilder: (_, __, ___) => const Text(
              'Failed to render image',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ),
      );
    }

    return const Center(
      child: Text(
        'Preview not available for this file type.',
        style: TextStyle(color: AppColors.textSecondary),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:apx_pro/core/theme/colors.dart';
import 'package:apx_pro/core/theme/glass.dart';
import 'package:apx_pro/core/network/api_client.dart';
import 'package:apx_pro/features/admin/presentation/admin_scan_review_screen.dart';

class AdminScansScreen extends StatefulWidget {
  const AdminScansScreen({super.key});

  @override
  State<AdminScansScreen> createState() => _AdminScansScreenState();
}

class _AdminScansScreenState extends State<AdminScansScreen> {
  final ApiClient _api = ApiClient();
  List<Map<String, dynamic>> _scans = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadScans();
  }

  Future<void> _loadScans() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resp = await _api.get('/scans/pending');
      setState(() {
        _scans = (resp.data as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } on ApiException catch (e) {
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  String _formatDate(String? isoDate) {
    if (isoDate == null) return '—';
    try {
      final dt = DateTime.parse(isoDate).toLocal();
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return isoDate;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(title: 'Pending Scans'),
      body: GlassOrbBackground(
        child: SafeArea(
          child: _buildBody(),
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

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 40),
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              onTap: _loadScans,
              child: const Text(
                'Retry',
                style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
    }

    if (_scans.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline_rounded,
                color: AppColors.success, size: 52),
            SizedBox(height: 16),
            Text(
              'All caught up!',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'No posture scans are pending review.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadScans,
      color: AppColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        itemCount: _scans.length,
        itemBuilder: (ctx, i) => _buildScanCard(_scans[i]),
      ),
    );
  }

  Widget _buildScanCard(Map<String, dynamic> scan) {
    final patient = scan['patient'] as Map<String, dynamic>?;
    final patientName = patient?['full_name'] as String? ?? 'Unknown Patient';
    final patientEmail = patient?['email'] as String? ?? '';
    final uploadDate = _formatDate(scan['created_at'] as String?);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        padding: EdgeInsets.zero,
        onTap: () async {
          final reviewed = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => AdminScanReviewScreen(scan: scan),
            ),
          );
          if (reviewed == true) {
            _loadScans();
          }
        },
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.videocam_rounded, color: AppColors.warning, size: 22),
          ),
          title: Text(
            patientName,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (patientEmail.isNotEmpty)
                Text(patientEmail,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              const SizedBox(height: 2),
              Text(
                'Uploaded $uploadDate',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
              ),
            ],
          ),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Pending',
              style: TextStyle(
                color: AppColors.warning,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

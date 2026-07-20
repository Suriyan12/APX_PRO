import 'dart:ui';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:apx_pro/core/theme/colors.dart';
import 'package:apx_pro/core/theme/glass.dart';
import 'package:apx_pro/core/network/api_client.dart';

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  final ApiClient _apiClient = ApiClient();
  final _weightController = TextEditingController();
  final _waistController = TextEditingController();

  List<Map<String, dynamic>> _logs = [];
  bool _loading = true;
  bool _saving = false;

  double? get _latestWeight {
    for (final log in _logs.reversed) {
      final w = log['weight'];
      if (w != null) return (w as num).toDouble();
    }
    return null;
  }

  double? get _latestWaist {
    for (final log in _logs.reversed) {
      final w = log['waist'];
      if (w != null) return (w as num).toDouble();
    }
    return null;
  }

  List<FlSpot> get _weightSpots {
    final withWeight = _logs
        .where((l) => l['weight'] != null)
        .toList();
    return List.generate(withWeight.length, (i) {
      return FlSpot(i.toDouble() + 1, (withWeight[i]['weight'] as num).toDouble());
    });
  }

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  @override
  void dispose() {
    _weightController.dispose();
    _waistController.dispose();
    super.dispose();
  }

  Future<void> _loadLogs() async {
    setState(() => _loading = true);
    try {
      final resp = await _apiClient.get('/progress/logs');
      setState(() {
        _logs = (resp.data as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _logMetrics() async {
    final weightText = _weightController.text.trim();
    final waistText = _waistController.text.trim();

    if (weightText.isEmpty && waistText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter at least one measurement')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      await _apiClient.post('/progress/logs', data: {
        if (weightText.isNotEmpty) 'weight': double.parse(weightText),
        if (waistText.isNotEmpty) 'waist': double.parse(waistText),
      });

      _weightController.clear();
      _waistController.clear();
      FocusScope.of(context).unfocus();

      await _loadLogs();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Measurements logged successfully!'),
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
          const SnackBar(content: Text('Please enter valid numbers'), backgroundColor: AppColors.error),
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
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: 'Progress Tracking',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
      ),
      body: GlassOrbBackground(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            : SafeArea(
                child: RefreshIndicator(
                  onRefresh: _loadLogs,
                  color: AppColors.primary,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Current metrics summary
                        Row(
                          children: [
                            Expanded(
                              child: _buildMetricCard(
                                title: 'Current Weight',
                                value: _latestWeight != null
                                    ? '${_latestWeight!.toStringAsFixed(1)} kg'
                                    : '—',
                                icon: Icons.monitor_weight_outlined,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildMetricCard(
                                title: 'Waist Size',
                                value: _latestWaist != null
                                    ? '${_latestWaist!.toStringAsFixed(1)} cm'
                                    : '—',
                                icon: Icons.straighten_rounded,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 28),

                        const Text(
                          "Log Today's Measurements",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 12),

                        GlassCard(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(child: _buildGlassTextField(
                                    controller: _weightController,
                                    hint: 'Weight (kg)',
                                    icon: Icons.monitor_weight_outlined,
                                  )),
                                  const SizedBox(width: 16),
                                  Expanded(child: _buildGlassTextField(
                                    controller: _waistController,
                                    hint: 'Waist (cm)',
                                    icon: Icons.straighten_rounded,
                                  )),
                                ],
                              ),
                              const SizedBox(height: 20),
                              GlassButton(
                                label: 'Log Entry',
                                onTap: _saving ? null : _logMetrics,
                                style: GlassButtonStyle.primary,
                                loading: _saving,
                                width: double.infinity,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 28),

                        // Weight chart
                        if (_weightSpots.length >= 2) ...[
                          const Text(
                            'Weight Trend',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 16),
                          GlassCard(
                            padding: const EdgeInsets.fromLTRB(10, 20, 20, 10),
                            child: SizedBox(
                              height: 220,
                              child: LineChart(
                                LineChartData(
                                  gridData: const FlGridData(show: false),
                                  titlesData: FlTitlesData(
                                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                    leftTitles: AxisTitles(
                                      sideTitles: SideTitles(
                                        showTitles: true,
                                        reservedSize: 36,
                                        interval: 1.0,
                                        getTitlesWidget: _leftTitleWidget,
                                      ),
                                    ),
                                    bottomTitles: AxisTitles(
                                      sideTitles: SideTitles(
                                        showTitles: true,
                                        reservedSize: 22,
                                        interval: 1,
                                        getTitlesWidget: _bottomTitleWidget,
                                      ),
                                    ),
                                  ),
                                  borderData: FlBorderData(show: false),
                                  lineBarsData: [
                                    LineChartBarData(
                                      spots: _weightSpots,
                                      isCurved: true,
                                      color: AppColors.primary,
                                      barWidth: 3.5,
                                      dotData: const FlDotData(show: true),
                                      belowBarData: BarAreaData(
                                        show: true,
                                        color: AppColors.primary.withValues(alpha: 0.15),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ] else if (_logs.isNotEmpty) ...[
                          const Text(
                            'Log at least 2 weight entries to see the trend chart.',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildGlassTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
  }) {
    return ClipRRect(
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
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
              prefixIcon: Icon(icon, color: AppColors.textMuted, size: 18),
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
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required IconData icon,
  }) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _leftTitleWidget(double value, TitleMeta meta) {
    return Text(
      value.toStringAsFixed(0),
      style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
    );
  }

  Widget _bottomTitleWidget(double value, TitleMeta meta) {
    return Text(
      value.toStringAsFixed(0),
      style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
    );
  }
}

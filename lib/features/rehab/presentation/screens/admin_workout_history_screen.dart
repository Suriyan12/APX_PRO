import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:apx_pro/core/theme/colors.dart';
import 'package:apx_pro/core/theme/glass.dart';
import 'package:apx_pro/features/admin/presentation/widgets/dashboard_widgets.dart';
import 'package:apx_pro/features/rehab/data/rehab_models.dart';
import 'package:apx_pro/features/rehab/presentation/controllers/rehab_controller.dart';

/// A patient's full workout history, newest first. Loads the first page on
/// open and lazily fetches more as the admin scrolls (see
/// [patientWorkoutHistoryProvider]).
class AdminWorkoutHistoryScreen extends ConsumerStatefulWidget {
  const AdminWorkoutHistoryScreen({
    super.key,
    required this.patientId,
    this.patientName,
  });

  final String patientId;
  final String? patientName;

  @override
  ConsumerState<AdminWorkoutHistoryScreen> createState() =>
      _AdminWorkoutHistoryScreenState();
}

class _AdminWorkoutHistoryScreenState
    extends ConsumerState<AdminWorkoutHistoryScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(patientWorkoutHistoryProvider(widget.patientId).notifier)
          .loadInitial();
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Prefetch the next page when within 300px of the bottom.
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      ref
          .read(patientWorkoutHistoryProvider(widget.patientId).notifier)
          .loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(patientWorkoutHistoryProvider(widget.patientId));
    final notifier =
        ref.read(patientWorkoutHistoryProvider(widget.patientId).notifier);

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: widget.patientName != null
            ? 'Workout History · ${widget.patientName}'
            : 'Workout History',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: GlassOrbBackground(
        child: SafeArea(
          child: _buildBody(state, notifier),
        ),
      ),
    );
  }

  Widget _buildBody(WorkoutHistoryState state, WorkoutHistoryNotifier notifier) {
    if (state.loading && state.items.isEmpty) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (state.error != null && state.items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: DashboardErrorState(
          message: state.error!,
          onRetry: notifier.loadInitial,
        ),
      );
    }
    if (state.items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: DashboardEmptyState(
          icon: Icons.fitness_center_rounded,
          message: 'No workouts recorded yet.',
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: notifier.refresh,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        // +1 for the trailing "loading more" / "end" footer.
        itemCount: state.items.length + 1,
        itemBuilder: (context, i) {
          if (i == state.items.length) return _footer(state);
          return _HistoryCard(item: state.items[i]);
        },
      ),
    );
  }

  Widget _footer(WorkoutHistoryState state) {
    if (state.loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.primary),
          ),
        ),
      );
    }
    if (state.error != null && state.items.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: DashboardErrorState(
          message: state.error!,
          onRetry: () => ref
              .read(patientWorkoutHistoryProvider(widget.patientId).notifier)
              .loadMore(),
        ),
      );
    }
    if (!state.hasMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Text('End of history',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
        ),
      );
    }
    return const SizedBox(height: 24);
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.item});

  final WorkoutHistoryItemModel item;

  String _durationLabel(int? seconds) {
    if (seconds == null || seconds <= 0) return '—';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m == 0) return '${s}s';
    return s == 0 ? '${m}m' : '${m}m ${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final dateSource = item.sessionDate ?? item.startedAt.toLocal();
    final dateStr = DateFormat('MMM d, yyyy').format(dateSource);
    final completedStr = item.completedAt != null
        ? DateFormat('h:mm a').format(item.completedAt!)
        : null;
    final color = workoutStatusColor(item.status);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    dateStr,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                StatusPill(text: workoutStatusLabel(item.status), color: color),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              item.programTitle,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                MetaChip(
                  icon: Icons.check_circle_outline_rounded,
                  label:
                      '${item.exercisesCompleted}/${item.exercisesTotal} exercises',
                ),
                MetaChip(
                  icon: Icons.timer_outlined,
                  label: _durationLabel(item.durationSeconds),
                ),
                if (completedStr != null)
                  MetaChip(
                    icon: Icons.event_available_rounded,
                    label: 'Done $completedStr',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

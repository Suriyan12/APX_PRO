import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:apx_pro/core/theme/app_theme_extension.dart';
import 'package:apx_pro/core/theme/glass.dart';
import 'package:apx_pro/features/help_center/data/help_models.dart';
import 'package:apx_pro/features/help_center/presentation/controllers/help_controller.dart';

/// The "Help" bottom-nav tab: an admin-curated library of instructional
/// YouTube videos, grouped by category, with a featured tutorial, search, and
/// category filters. All playback happens inside the app via the embedded
/// YouTube player (see HelpVideoDetailScreen).
class HelpTab extends ConsumerStatefulWidget {
  const HelpTab({super.key});

  @override
  ConsumerState<HelpTab> createState() => _HelpTabState();
}

class _HelpTabState extends ConsumerState<HelpTab> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = ref.read(helpCenterProvider);
      if (state.all.isEmpty && !state.loading) {
        ref.read(helpCenterProvider.notifier).load();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openVideo(HelpVideoModel v) => context.push('/help/${v.id}');

  @override
  Widget build(BuildContext context) {
    final ext = context.ext;
    final state = ref.watch(helpCenterProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        color: ext.primary,
        onRefresh: () => ref.read(helpCenterProvider.notifier).refresh(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(ext),
              const SizedBox(height: 16),
              _searchBox(ext),
              const SizedBox(height: 12),
              if (state.categories.isNotEmpty) _categoryChips(ext, state),
              const SizedBox(height: 8),
              _body(ext, state),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(AppThemeExtension ext) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Help Center',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: ext.textPrimary,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Short tutorials to help you get the most out of APX PRO.',
          style: TextStyle(fontSize: 13.5, color: ext.textSecondary, height: 1.4),
        ),
      ],
    );
  }

  Widget _searchBox(AppThemeExtension ext) {
    return GlassTextField(
      controller: _searchController,
      hintText: 'Search tutorials…',
      prefixIcon: Icon(Icons.search_rounded, color: ext.textMuted, size: 20),
      suffixIcon: _searchController.text.isEmpty
          ? null
          : GestureDetector(
              onTap: () {
                _searchController.clear();
                ref.read(helpCenterProvider.notifier).setSearch('');
                setState(() {});
              },
              child: Icon(Icons.close_rounded, color: ext.textMuted, size: 18),
            ),
      onChanged: (v) {
        ref.read(helpCenterProvider.notifier).setSearch(v);
        setState(() {}); // refresh the clear button
      },
    );
  }

  Widget _categoryChips(AppThemeExtension ext, HelpCenterState state) {
    final chips = <Widget>[
      _chip(ext, label: 'All', selected: state.categoryFilter == null,
          onTap: () => ref.read(helpCenterProvider.notifier).setCategory(null)),
    ];
    for (final c in state.categories) {
      chips.add(_chip(ext,
          label: c,
          selected: state.categoryFilter == c,
          onTap: () => ref.read(helpCenterProvider.notifier).setCategory(c)));
    }
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => chips[i],
      ),
    );
  }

  Widget _chip(AppThemeExtension ext,
      {required String label, required bool selected, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? ext.primary.withValues(alpha: 0.18)
              : ext.glassTint,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? ext.primary.withValues(alpha: 0.5)
                : ext.glassBorder,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
            color: selected ? ext.primary : ext.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _body(AppThemeExtension ext, HelpCenterState state) {
    if (state.loading && state.all.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 80),
        child: Center(child: CircularProgressIndicator(color: ext.primary)),
      );
    }
    if (state.error != null && state.all.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 24),
        child: GlassCard(
          tint: const Color(0x22D50000),
          child: Column(
            children: [
              Icon(Icons.error_outline_rounded, color: ext.error, size: 40),
              const SizedBox(height: 12),
              Text(state.error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: ext.textPrimary, fontSize: 14)),
              const SizedBox(height: 16),
              GlassButton(
                label: 'Retry',
                style: GlassButtonStyle.ghost,
                onTap: () => ref.read(helpCenterProvider.notifier).load(),
              ),
            ],
          ),
        ),
      );
    }
    if (state.isEmptyResult) {
      return _emptyState(ext, state);
    }

    final featured = state.featured;
    final grouped = state.grouped;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (featured != null) ...[
          const SizedBox(height: 8),
          _sectionLabel(ext, 'Featured Tutorial'),
          const SizedBox(height: 10),
          _FeaturedCard(video: featured, onTap: () => _openVideo(featured)),
        ],
        for (final entry in grouped.entries) ...[
          const SizedBox(height: 20),
          _sectionLabel(ext, entry.key),
          const SizedBox(height: 10),
          ...entry.value.map((v) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _VideoCard(video: v, onTap: () => _openVideo(v)),
              )),
        ],
      ],
    );
  }

  Widget _emptyState(AppThemeExtension ext, HelpCenterState state) {
    final searching = state.isSearching || state.categoryFilter != null;
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: GlassCard(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              searching ? Icons.search_off_rounded : Icons.ondemand_video_rounded,
              size: 56,
              color: ext.textMuted,
            ),
            const SizedBox(height: 14),
            Text(
              searching ? 'No matching tutorials' : 'No tutorials yet',
              style: TextStyle(
                  color: ext.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              searching
                  ? 'Try a different search or category.'
                  : 'Help videos will appear here once they are published.',
              textAlign: TextAlign.center,
              style: TextStyle(color: ext.textSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(AppThemeExtension ext, String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.bold,
        color: ext.textPrimary,
        letterSpacing: 0.2,
      ),
    );
  }
}

// ── Cards ─────────────────────────────────────────────────────────────────────

/// A thumbnail widget with graceful loading/error fallbacks.
class _Thumbnail extends StatelessWidget {
  final HelpVideoModel video;
  const _Thumbnail({required this.video});

  @override
  Widget build(BuildContext context) {
    final ext = context.ext;
    final url = video.thumbnail;
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: ext.surfaceOverlay),
          if (url != null)
            Image.network(
              url,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) =>
                  progress == null ? child : Container(color: ext.surfaceOverlay),
              errorBuilder: (context, _, __) => Container(
                color: ext.surfaceOverlay,
                child: Icon(Icons.ondemand_video_rounded,
                    color: ext.textMuted, size: 36),
              ),
            ),
          // Play glyph overlay.
          Center(
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.play_arrow_rounded,
                  color: Colors.white, size: 28),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeaturedCard extends StatelessWidget {
  final HelpVideoModel video;
  final VoidCallback onTap;
  const _FeaturedCard({required this.video, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final ext = context.ext;
    return GlassCard(
      padding: EdgeInsets.zero,
      onTap: onTap,
      glowColor: ext.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: _Thumbnail(video: video),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.star_rounded, color: ext.primary, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      video.category.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: ext.primary,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  video.title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: ext.textPrimary,
                  ),
                ),
                if (video.description != null &&
                    video.description!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    video.description!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13, color: ext.textSecondary, height: 1.4),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoCard extends StatelessWidget {
  final HelpVideoModel video;
  final VoidCallback onTap;
  const _VideoCard({required this.video, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final ext = context.ext;
    return GlassCard(
      padding: const EdgeInsets.all(10),
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _Thumbnail(video: video),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: ext.textPrimary,
                      height: 1.3,
                    ),
                  ),
                  if (video.description != null &&
                      video.description!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      video.description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12, color: ext.textSecondary, height: 1.35),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

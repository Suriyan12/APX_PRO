import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:apx_pro/core/network/api_client.dart';
import 'package:apx_pro/core/theme/app_theme_extension.dart';
import 'package:apx_pro/core/theme/glass.dart';
import 'package:apx_pro/features/help_center/data/help_models.dart';
import 'package:apx_pro/features/help_center/presentation/controllers/help_controller.dart';

/// Admin management view for the Help Center, embedded as a tab in the Admin
/// Panel. Supports create, edit, activate/deactivate, feature (single at a
/// time), delete, and drag-to-reorder. The parent panel's FAB calls
/// [showAddSheet] via a GlobalKey (mirroring AdminUsersScreen).
class AdminHelpCenterScreen extends ConsumerStatefulWidget {
  const AdminHelpCenterScreen({super.key});

  @override
  AdminHelpCenterScreenState createState() => AdminHelpCenterScreenState();
}

class AdminHelpCenterScreenState extends ConsumerState<AdminHelpCenterScreen> {
  final _searchController = TextEditingController();
  String _search = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final s = ref.read(adminHelpProvider);
      if (s.all.isEmpty && !s.loading) {
        ref.read(adminHelpProvider.notifier).load();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Called by AdminPanelScreen's FAB via GlobalKey.
  void showAddSheet() => _showForm();

  List<HelpVideoModel> _filtered(List<HelpVideoModel> all) {
    final q = _search.trim().toLowerCase();
    final list = [...all]..sort((a, b) {
        final c = a.category.compareTo(b.category);
        return c != 0 ? c : a.displayOrder.compareTo(b.displayOrder);
      });
    if (q.isEmpty) return list;
    return list
        .where((v) =>
            v.title.toLowerCase().contains(q) ||
            (v.description ?? '').toLowerCase().contains(q) ||
            v.category.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final ext = context.ext;
    final state = ref.watch(adminHelpProvider);
    final videos = _filtered(state.all);

    return Column(
      children: [
        SizedBox(
            height: MediaQuery.of(context).padding.top + kToolbarHeight + 82.0),
        _searchBox(ext),
        const SizedBox(height: 8),
        Expanded(child: _list(ext, state, videos)),
      ],
    );
  }

  Widget _searchBox(AppThemeExtension ext) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0x12FFFFFF),
                    border: Border.all(color: const Color(0x1AFFFFFF)),
                  ),
                ),
              ),
            ),
            TextField(
              controller: _searchController,
              style: TextStyle(color: ext.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search help videos...',
                hintStyle: TextStyle(color: ext.textMuted, fontSize: 13),
                prefixIcon:
                    Icon(Icons.search_rounded, color: ext.textMuted, size: 20),
                suffixIcon: _search.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear_rounded,
                            color: ext.textMuted, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _search = '');
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(
      AppThemeExtension ext, AdminHelpState state, List<HelpVideoModel> videos) {
    if (state.loading && state.all.isEmpty) {
      return Center(child: CircularProgressIndicator(color: ext.primary));
    }
    if (state.error != null && state.all.isEmpty) {
      return Center(
        child: GlassCard(
          tint: const Color(0x22D50000),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, color: ext.error, size: 40),
              const SizedBox(height: 12),
              Text(state.error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: ext.textPrimary)),
              const SizedBox(height: 16),
              GlassButton(
                label: 'Retry',
                style: GlassButtonStyle.ghost,
                onTap: () => ref.read(adminHelpProvider.notifier).load(),
              ),
            ],
          ),
        ),
      );
    }
    if (videos.isEmpty) {
      return Center(
        child: GlassCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.ondemand_video_rounded,
                  color: ext.textMuted, size: 40),
              const SizedBox(height: 12),
              Text(_search.isEmpty ? 'No help videos yet.' : 'No matches.',
                  style: TextStyle(color: ext.textSecondary)),
            ],
          ),
        ),
      );
    }

    final notifier = ref.read(adminHelpProvider.notifier);
    // Reorder only makes sense on the full, unfiltered, ordered list.
    if (_search.isEmpty) {
      return RefreshIndicator(
        color: ext.primary,
        onRefresh: notifier.refresh,
        child: ReorderableListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
          itemCount: videos.length,
          onReorder: (oldIndex, newIndex) {
            if (newIndex > oldIndex) newIndex -= 1;
            final reordered = [...videos];
            final moved = reordered.removeAt(oldIndex);
            reordered.insert(newIndex, moved);
            notifier.reorder(reordered);
          },
          itemBuilder: (context, i) => Padding(
            key: ValueKey(videos[i].id),
            padding: const EdgeInsets.only(bottom: 10),
            child: _row(ext, videos[i], reorderable: true, index: i),
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: ext.primary,
      onRefresh: notifier.refresh,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
        itemCount: videos.length,
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _row(ext, videos[i], reorderable: false, index: i),
        ),
      ),
    );
  }

  Widget _row(AppThemeExtension ext, HelpVideoModel v,
      {required bool reorderable, required int index}) {
    return GlassCard(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          if (reorderable)
            ReorderableDragStartListener(
              index: index,
              child: Icon(Icons.drag_indicator_rounded,
                  color: ext.textMuted, size: 20),
            ),
          if (reorderable) const SizedBox(width: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 84,
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(color: ext.surfaceOverlay),
                    if (v.thumbnail != null)
                      Image.network(v.thumbnail!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(
                              Icons.ondemand_video_rounded,
                              color: ext.textMuted,
                              size: 22)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(v.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: ext.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(v.category,
                    style: TextStyle(color: ext.textMuted, fontSize: 11.5)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _statusChip(
                      ext,
                      v.isActive ? 'Active' : 'Hidden',
                      v.isActive ? ext.success : ext.textMuted,
                    ),
                    if (v.isFeatured) ...[
                      const SizedBox(width: 6),
                      _statusChip(ext, 'Featured', ext.primary,
                          icon: Icons.star_rounded),
                    ],
                  ],
                ),
              ],
            ),
          ),
          _menu(ext, v),
        ],
      ),
    );
  }

  Widget _statusChip(AppThemeExtension ext, String label, Color color,
      {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 11, color: color), const SizedBox(width: 3)],
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 10.5, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _menu(AppThemeExtension ext, HelpVideoModel v) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert_rounded, color: ext.textSecondary),
      color: ext.surface,
      onSelected: (action) => _onAction(action, v),
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'edit', child: Text('Edit')),
        PopupMenuItem(
          value: 'active',
          child: Text(v.isActive ? 'Deactivate' : 'Activate'),
        ),
        PopupMenuItem(
          value: 'featured',
          child: Text(v.isFeatured ? 'Unfeature' : 'Set as Featured'),
        ),
        const PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
  }

  Future<void> _onAction(String action, HelpVideoModel v) async {
    final notifier = ref.read(adminHelpProvider.notifier);
    try {
      switch (action) {
        case 'edit':
          await _showForm(existing: v);
          break;
        case 'active':
          await notifier.setActive(v.id, !v.isActive);
          _toast(v.isActive ? 'Video hidden.' : 'Video published.');
          break;
        case 'featured':
          await notifier.setFeatured(v.id, !v.isFeatured);
          _toast(v.isFeatured ? 'Removed from featured.' : 'Marked as featured.');
          break;
        case 'delete':
          await _confirmDelete(v);
          break;
      }
    } on ApiException catch (e) {
      _toast(e.message, error: true);
    }
  }

  Future<void> _confirmDelete(HelpVideoModel v) async {
    final ext = context.ext;
    final confirmed = await showGlassDialog<bool>(
      context: context,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: ext.error, size: 22),
                const SizedBox(width: 8),
                Text('Delete video?',
                    style: TextStyle(
                        color: ext.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 18)),
              ],
            ),
            const SizedBox(height: 12),
            Text('"${v.title}" will be permanently removed.',
                style: TextStyle(color: ext.textSecondary, fontSize: 14)),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(false),
                    child: GlassCard(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                          child: Text('Cancel',
                              style: TextStyle(color: ext.textSecondary))),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(true),
                    child: GlassCard(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      tint: const Color(0x18D50000),
                      child: Center(
                        child: Text('Delete',
                            style: TextStyle(
                                color: ext.error,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    await ref.read(adminHelpProvider.notifier).delete(v.id);
    _toast('Video deleted.');
  }

  Future<void> _showForm({HelpVideoModel? existing}) async {
    final categories = ref.read(adminHelpProvider).categories;
    final result = await showModalBottomSheet<_HelpFormResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _HelpVideoFormSheet(
        existing: existing,
        categories: categories.isNotEmpty
            ? categories
            : const [
                'Getting Started',
                'Appointments',
                'Rehabilitation',
                'Medical Records',
                'Study Materials',
                'Notifications',
                'Other',
              ],
      ),
    );
    if (result == null) return;
    final notifier = ref.read(adminHelpProvider.notifier);
    try {
      if (existing == null) {
        await notifier.create(
          title: result.title,
          description: result.description,
          category: result.category,
          youtubeUrl: result.youtubeUrl,
          isActive: result.isActive,
          isFeatured: result.isFeatured,
        );
        _toast('Video created.');
      } else {
        await notifier.update(
          existing.id,
          title: result.title,
          description: result.description,
          category: result.category,
          youtubeUrl: result.youtubeUrl,
          isActive: result.isActive,
          isFeatured: result.isFeatured,
        );
        _toast('Video updated.');
      }
    } on ApiException catch (e) {
      _toast(e.message, error: true);
    }
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    final ext = context.ext;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? ext.error : ext.success,
    ));
  }
}

// ── Form result + sheet ───────────────────────────────────────────────────────

class _HelpFormResult {
  final String title;
  final String? description;
  final String category;
  final String youtubeUrl;
  final bool isActive;
  final bool isFeatured;
  _HelpFormResult({
    required this.title,
    this.description,
    required this.category,
    required this.youtubeUrl,
    required this.isActive,
    required this.isFeatured,
  });
}

class _HelpVideoFormSheet extends StatefulWidget {
  final HelpVideoModel? existing;
  final List<String> categories;
  const _HelpVideoFormSheet({required this.existing, required this.categories});

  @override
  State<_HelpVideoFormSheet> createState() => _HelpVideoFormSheetState();
}

class _HelpVideoFormSheetState extends State<_HelpVideoFormSheet> {
  late final TextEditingController _title;
  late final TextEditingController _desc;
  late final TextEditingController _url;
  late String _category;
  late bool _isActive;
  late bool _isFeatured;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?.title ?? '');
    _desc = TextEditingController(text: e?.description ?? '');
    _url = TextEditingController(text: e?.youtubeUrl ?? '');
    _category = e?.category ??
        (widget.categories.isNotEmpty ? widget.categories.first : 'Other');
    if (!widget.categories.contains(_category) && widget.categories.isNotEmpty) {
      _category = widget.categories.first;
    }
    _isActive = e?.isActive ?? true;
    _isFeatured = e?.isFeatured ?? false;
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _url.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _title.text.trim();
    final url = _url.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Title is required.');
      return;
    }
    if (HelpVideoModel.extractYouTubeId(url) == null) {
      setState(() => _error =
          'Enter a valid YouTube URL (youtube.com/watch?v=… or youtu.be/…).');
      return;
    }
    if (_isFeatured && !_isActive) {
      setState(() => _error = 'A featured video must be active.');
      return;
    }
    Navigator.of(context).pop(_HelpFormResult(
      title: title,
      description: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
      category: _category,
      youtubeUrl: url,
      isActive: _isActive,
      isFeatured: _isFeatured,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final ext = context.ext;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            decoration: BoxDecoration(
              color: ext.glassDialogTint,
              border: Border.all(color: ext.glassDialogBorder),
            ),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: ext.textMuted,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.existing == null ? 'Add Help Video' : 'Edit Help Video',
                    style: TextStyle(
                        color: ext.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 18),
                  ),
                  const SizedBox(height: 16),
                  _label(ext, 'Title'),
                  GlassTextField(controller: _title, hintText: 'e.g. How to Use APX PRO'),
                  const SizedBox(height: 12),
                  _label(ext, 'Description'),
                  GlassTextField(
                      controller: _desc,
                      hintText: 'Short summary',
                      maxLines: 3),
                  const SizedBox(height: 12),
                  _label(ext, 'Category'),
                  _categoryDropdown(ext),
                  const SizedBox(height: 12),
                  _label(ext, 'YouTube URL'),
                  GlassTextField(
                      controller: _url,
                      hintText: 'https://youtube.com/watch?v=…',
                      keyboardType: TextInputType.url),
                  const SizedBox(height: 16),
                  _switchRow(ext, 'Active (visible to users)', _isActive,
                      (val) => setState(() {
                            _isActive = val;
                            if (!val) _isFeatured = false;
                          })),
                  _switchRow(ext, 'Featured tutorial', _isFeatured,
                      (val) => setState(() {
                            _isFeatured = val;
                            if (val) _isActive = true;
                          })),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!,
                        style: TextStyle(color: ext.error, fontSize: 12.5)),
                  ],
                  const SizedBox(height: 20),
                  GlassButton(
                    label: widget.existing == null ? 'Create' : 'Save',
                    icon: Icons.check_rounded,
                    width: double.infinity,
                    onTap: _submit,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(AppThemeExtension ext, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: TextStyle(
                color: ext.textSecondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600)),
      );

  Widget _categoryDropdown(AppThemeExtension ext) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: ext.glassTextFieldFill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ext.glassBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _category,
          isExpanded: true,
          dropdownColor: ext.surface,
          style: TextStyle(color: ext.textPrimary, fontSize: 14),
          icon: Icon(Icons.arrow_drop_down_rounded, color: ext.textMuted),
          items: widget.categories
              .map((c) => DropdownMenuItem(value: c, child: Text(c)))
              .toList(),
          onChanged: (v) => setState(() => _category = v ?? _category),
        ),
      ),
    );
  }

  Widget _switchRow(
      AppThemeExtension ext, String label, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(color: ext.textPrimary, fontSize: 14)),
          ),
          Switch(
            value: value,
            activeColor: ext.primary,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

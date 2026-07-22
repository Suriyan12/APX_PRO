import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:apx_pro/core/theme/colors.dart';
import 'package:apx_pro/core/theme/glass.dart';
import 'package:apx_pro/core/network/api_client.dart';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  AdminUsersScreenState createState() => AdminUsersScreenState();
}

class AdminUsersScreenState extends State<AdminUsersScreen> {
  final ApiClient _api = ApiClient();
  final _searchController = TextEditingController();

  List<Map<String, dynamic>> _users = [];
  bool _loading = true;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    setState(() => _loading = true);
    try {
      final resp = await _api.get(
        '/users/',
        queryParameters: _search.isNotEmpty ? {'search': _search} : null,
      );
      setState(() {
        _users = (resp.data as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  // Called by AdminPanelScreen's FAB via GlobalKey
  void showAddUserSheet() {
    _showUserFormSheet();
  }

  Future<void> _showUserFormSheet({Map<String, dynamic>? existing}) async {
    // The sheet owns its own TextEditingControllers via [_UserFormSheet]'s
    // State, so they are disposed in State.dispose() — which Flutter calls only
    // after the sheet's exit transition finishes and the element is unmounted.
    // (Disposing them here, right after the await, freed them WHILE the sheet
    // was still animating out and rebuilding — the use-after-dispose crash.)
    final createdName = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _UserFormSheet(api: _api, existing: existing),
    );

    // On success the sheet pops with the created user's name.
    if (createdName != null) {
      _loadUsers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$createdName created successfully.'),
          backgroundColor: AppColors.success,
        ));
      }
    }
  }

  Future<void> _toggleStatus(Map<String, dynamic> user) async {
    final name = user['full_name'] as String;
    final isActive = user['is_active'] as bool;

    final confirmed = await showGlassDialog<bool>(
      context: context,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isActive ? 'Deactivate User?' : 'Activate User?',
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 18),
            ),
            const SizedBox(height: 12),
            Text(
              isActive
                  ? '$name will be unable to access the app.'
                  : '$name will regain full access.',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(false),
                    child: GlassCard(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: const Center(
                        child: Text('Cancel',
                            style:
                                TextStyle(color: AppColors.textSecondary)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(true),
                    child: GlassCard(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      tint: isActive
                          ? const Color(0x18D50000)
                          : const Color(0x1800E676),
                      child: Center(
                        child: Text(
                          isActive ? 'Deactivate' : 'Activate',
                          style: TextStyle(
                            color: isActive
                                ? AppColors.error
                                : AppColors.success,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
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

    try {
      final resp = await _api.patch('/users/${user['id']}/status');
      final updated = resp.data as Map<String, dynamic>;
      setState(() {
        final idx = _users.indexWhere((u) => u['id'] == user['id']);
        if (idx != -1) _users[idx] = updated;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(updated['is_active'] == true
              ? '$name activated.'
              : '$name deactivated.'),
          backgroundColor: updated['is_active'] == true
              ? AppColors.success
              : AppColors.warning,
        ));
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e.message), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _deleteUser(Map<String, dynamic> user) async {
    final name = user['full_name'] as String;

    final confirmed = await showGlassDialog<bool>(
      context: context,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: AppColors.error, size: 22),
                SizedBox(width: 8),
                Text(
                  'Delete User?',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 18),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'This will permanently delete $name and all their data (reports, scans, progress). This cannot be undone.',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(false),
                    child: GlassCard(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: const Center(
                        child: Text('Cancel',
                            style:
                                TextStyle(color: AppColors.textSecondary)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(true),
                    child: GlassCard(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      tint: const Color(0x22D50000),
                      child: const Center(
                        child: Text(
                          'Delete Forever',
                          style: TextStyle(
                            color: AppColors.error,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
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

    try {
      await _api.delete('/users/${user['id']}');
      setState(() => _users.removeWhere((u) => u['id'] == user['id']));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$name deleted.'),
          backgroundColor: AppColors.error,
        ));
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e.message), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Add top padding for the glass app bar
        SizedBox(height: MediaQuery.of(context).padding.top + kToolbarHeight + 82.0),
        Padding(
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
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Search by name, email or phone...',
                    hintStyle:
                        const TextStyle(color: AppColors.textMuted, fontSize: 13),
                    prefixIcon: const Icon(Icons.search_rounded,
                        color: AppColors.textMuted, size: 20),
                    suffixIcon: _search.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded,
                                color: AppColors.textMuted, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _search = '');
                              _loadUsers();
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                  ),
                  onChanged: (val) => setState(() => _search = val.trim()),
                  onSubmitted: (_) => _loadUsers(),
                  textInputAction: TextInputAction.search,
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primary))
              : _users.isEmpty
                  ? Center(
                      child: GlassCard(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.search_off_rounded,
                                color: AppColors.textMuted, size: 40),
                            const SizedBox(height: 12),
                            const Text('No users found.',
                                style: TextStyle(
                                    color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadUsers,
                      color: AppColors.primary,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                        itemCount: _users.length,
                        itemBuilder: (_, i) => _buildUserCard(_users[i]),
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    final name = user['full_name'] as String? ?? 'Unknown';
    final email = user['email'] as String? ?? '';
    final phone = user['phone'] as String? ?? '—';
    final role = (user['role'] as String?)?.toLowerCase() ?? 'patient';
    final isActive = user['is_active'] as bool? ?? true;
    final isAdminUser = role == 'admin';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        onTap: () => context.push('/admin/users/${user['id']}'),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: isAdminUser
                  ? AppColors.primary.withValues(alpha: 0.15)
                  : AppColors.secondary.withValues(alpha: 0.15),
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: TextStyle(
                  color: isAdminUser ? AppColors.primary : AppColors.secondary,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    email,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    phone,
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildChip(
                  text: role.toUpperCase(),
                  color: isAdminUser ? AppColors.primary : AppColors.textMuted,
                  bgColor: isAdminUser
                      ? AppColors.primary.withValues(alpha: 0.12)
                      : Colors.white.withValues(alpha: 0.05),
                  borderColor: isAdminUser
                      ? AppColors.primary.withValues(alpha: 0.4)
                      : Colors.white.withValues(alpha: 0.15),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: isAdminUser ? null : () => _toggleStatus(user),
                  child: _buildChip(
                    text: isActive ? 'Active' : 'Inactive',
                    color: isActive ? AppColors.success : AppColors.error,
                    bgColor: isActive
                        ? AppColors.success.withValues(alpha: 0.12)
                        : AppColors.error.withValues(alpha: 0.12),
                    borderColor: isActive
                        ? AppColors.success.withValues(alpha: 0.3)
                        : AppColors.error.withValues(alpha: 0.3),
                  ),
                ),
                if (!isAdminUser) ...[
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => _deleteUser(user),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: AppColors.error.withValues(alpha: 0.25)),
                      ),
                      child: const Icon(Icons.delete_outline_rounded,
                          color: AppColors.error, size: 16),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChip({
    required String text,
    required Color color,
    required Color bgColor,
    required Color borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: color,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

// ─── Create-user bottom sheet ───────────────────────────────────────────────
//
// A StatefulWidget so the four TextEditingControllers live for the exact
// lifetime of the sheet's element. They are created once in initState (never in
// build) and freed in dispose(), which Flutter invokes only after the sheet is
// fully removed from the tree — so no rebuild during the exit transition can
// touch a disposed controller. On success it pops with the created user's name.

class _UserFormSheet extends StatefulWidget {
  final ApiClient api;
  final Map<String, dynamic>? existing;

  const _UserFormSheet({required this.api, this.existing});

  @override
  State<_UserFormSheet> createState() => _UserFormSheetState();
}

class _UserFormSheetState extends State<_UserFormSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _passCtrl;

  String _selectedRole = 'patient';
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?['full_name'] as String? ?? '');
    _emailCtrl = TextEditingController(text: e?['email'] as String? ?? '');
    _phoneCtrl = TextEditingController(text: e?['phone'] as String? ?? '');
    _passCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    if (name.isEmpty || email.isEmpty || pass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Name, email and password are required.'),
        backgroundColor: AppColors.error,
      ));
      return;
    }
    setState(() => _submitting = true);
    try {
      await widget.api.post('/users/', data: {
        'full_name': name,
        'email': email,
        'phone': _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        'password': pass,
        'role': _selectedRole,
      });
      // Success — hand the name back to the caller, which refreshes the list
      // and shows the confirmation snackbar after the sheet has closed.
      if (mounted) Navigator.of(context).pop(name);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.message),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        child: Stack(
          children: [
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(
                  decoration: const BoxDecoration(
                    color: Color(0x1EFFFFFF),
                    border: Border(
                        top: BorderSide(color: Color(0x30FFFFFF), width: 1)),
                  ),
                ),
              ),
            ),
            // Scrollable so a raised keyboard can never cause a RenderFlex
            // overflow on short screens.
            SingleChildScrollView(
              child: Container(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle bar
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const Text(
                      'Add New User',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _GlassTextField(
                        controller: _nameCtrl,
                        label: 'Full Name',
                        icon: Icons.person_outline_rounded),
                    const SizedBox(height: 12),
                    _GlassTextField(
                        controller: _emailCtrl,
                        label: 'Email',
                        icon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress),
                    const SizedBox(height: 12),
                    _GlassTextField(
                        controller: _phoneCtrl,
                        label: 'Phone (optional)',
                        icon: Icons.phone_outlined,
                        keyboardType: TextInputType.phone),
                    const SizedBox(height: 12),
                    _GlassTextField(
                        controller: _passCtrl,
                        label: 'Password',
                        icon: Icons.lock_outline_rounded,
                        obscure: true),
                    const SizedBox(height: 12),
                    // Role picker
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: const Color(0x12FFFFFF),
                                  border: Border.all(
                                      color: const Color(0x1AFFFFFF)),
                                ),
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 4),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedRole,
                                dropdownColor: const Color(0xFF1A1B28),
                                isExpanded: true,
                                icon: const Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    color: AppColors.textSecondary),
                                items: const [
                                  DropdownMenuItem(
                                      value: 'patient',
                                      child: Text('Patient',
                                          style: TextStyle(
                                              color: AppColors.textPrimary))),
                                  DropdownMenuItem(
                                      value: 'admin',
                                      child: Text('Admin',
                                          style: TextStyle(
                                              color: AppColors.primary))),
                                ],
                                onChanged: (v) {
                                  if (v != null) {
                                    setState(() => _selectedRole = v);
                                  }
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    GlassButton(
                      label: 'Create User',
                      style: GlassButtonStyle.primary,
                      width: double.infinity,
                      loading: _submitting,
                      onTap: _submitting ? null : _submit,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Glass text field ──────────────────────────────────────────────────────

class _GlassTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final bool obscure;

  const _GlassTextField({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
    this.obscure = false,
  });

  @override
  Widget build(BuildContext context) {
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
            keyboardType: keyboardType,
            obscureText: obscure,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: label,
              hintStyle:
                  const TextStyle(color: AppColors.textMuted, fontSize: 13),
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
                    color: AppColors.primary.withValues(alpha: 0.6), width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

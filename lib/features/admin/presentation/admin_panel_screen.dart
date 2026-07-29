import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:apx_pro/core/theme/colors.dart';
import 'package:apx_pro/core/theme/glass.dart';
import 'package:apx_pro/features/admin/presentation/admin_users_screen.dart';
import 'package:apx_pro/features/admin/presentation/admin_appointments_screen.dart';
import 'package:apx_pro/features/notes/presentation/screens/admin/admin_notes_screen.dart';

class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _usersKey = GlobalKey<AdminUsersScreenState>();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      extendBodyBehindAppBar: true,
      appBar: _buildGlassAppBar(context),
      body: GlassOrbBackground(
        child: TabBarView(
          controller: _tabController,
          children: [
            AdminUsersScreen(key: _usersKey),
            const AdminAppointmentsView(),
            const AdminNotesView(),
          ],
        ),
      ),
      floatingActionButton: _buildFab(),
    );
  }

  PreferredSizeWidget _buildGlassAppBar(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    const double tabSectionHeight = 82.0;
    return PreferredSize(
      preferredSize: Size.fromHeight(topPadding + kToolbarHeight + tabSectionHeight),
      child: ClipRect(
        child: Stack(
          children: [
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: const ColoredBox(color: Colors.transparent),
              ),
            ),
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  color: Color(0x18FFFFFF),
                  border: Border(
                    bottom: BorderSide(color: Color(0x22FFFFFF), width: 1),
                  ),
                ),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(height: topPadding),
                AppBar(
                  primary: false,
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: AppColors.textPrimary, size: 18),
                    onPressed: () => context.pop(),
                  ),
                  title: const Text(
                    'Admin Panel',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                // Glass tab bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: const ColoredBox(color: Colors.transparent),
                          ),
                        ),
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0x12FFFFFF),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: const Color(0x1AFFFFFF)),
                            ),
                          ),
                        ),
                        TabBar(
                          controller: _tabController,
                          indicator: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.45),
                            ),
                          ),
                          indicatorSize: TabBarIndicatorSize.tab,
                          indicatorPadding: const EdgeInsets.all(4),
                          dividerColor: Colors.transparent,
                          labelColor: AppColors.primary,
                          unselectedLabelColor: AppColors.textSecondary,
                          labelStyle: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 11),
                          unselectedLabelStyle:
                              const TextStyle(fontSize: 11),
                          tabs: const [
                            Tab(
                              iconMargin: EdgeInsets.only(bottom: 2),
                              icon: Icon(Icons.people_alt_rounded, size: 17),
                              text: 'Users',
                            ),
                            Tab(
                              iconMargin: EdgeInsets.only(bottom: 2),
                              icon: Icon(Icons.event_available_rounded, size: 17),
                              text: 'Appointments',
                            ),
                            Tab(
                              iconMargin: EdgeInsets.only(bottom: 2),
                              icon: Icon(Icons.menu_book_rounded, size: 17),
                              text: 'Notes',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget? _buildFab() {
    return AnimatedBuilder(
      animation: _tabController,
      builder: (_, __) {
        if (_tabController.index == 0) {
          return GlassButton(
            label: 'Add User',
            icon: Icons.person_add_rounded,
            onTap: () => _usersKey.currentState?.showAddUserSheet(),
          );
        }
        // Notes tab (index 2) provides its own in-view "Upload Note" button;
        // Appointments (index 1) has inline actions. No panel FAB for them.
        return const SizedBox.shrink();
      },
    );
  }

  // Notes tab embeds AdminNotesView directly — no landing card.
}

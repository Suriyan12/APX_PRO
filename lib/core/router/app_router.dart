import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:apx_pro/features/auth/presentation/controllers/auth_controller.dart';
import 'package:apx_pro/features/auth/presentation/screens/splash_screen.dart';
import 'package:apx_pro/features/auth/presentation/screens/onboarding_screen.dart';
import 'package:apx_pro/features/auth/presentation/screens/login_screen.dart';
import 'package:apx_pro/features/auth/presentation/screens/register_screen.dart';
import 'package:apx_pro/features/auth/presentation/screens/otp_screen.dart';
import 'package:apx_pro/features/auth/presentation/screens/verify_email_screen.dart';
import 'package:apx_pro/features/auth/presentation/screens/forgot_password_screen.dart';
import 'package:apx_pro/features/dashboard/presentation/dashboard_screen.dart';
import 'package:apx_pro/features/assessment/presentation/assessment_screen.dart';
import 'package:apx_pro/features/progress/presentation/progress_screen.dart';
import 'package:apx_pro/features/notes/presentation/screens/notes_home_screen.dart';
import 'package:apx_pro/features/notes/presentation/screens/note_viewer_screen.dart';
import 'package:apx_pro/features/notes/presentation/screens/notes_purchase_screen.dart';
import 'package:apx_pro/features/notes/presentation/screens/admin/admin_notes_screen.dart';
import 'package:apx_pro/features/notes/presentation/screens/admin/upload_note_screen.dart';
import 'package:apx_pro/features/notes/presentation/screens/admin/edit_note_screen.dart';
import 'package:apx_pro/features/admin/presentation/admin_panel_screen.dart';
import 'package:apx_pro/features/admin/presentation/admin_user_detail_screen.dart';
import 'package:apx_pro/features/admin/presentation/admin_appointments_screen.dart';
import 'package:apx_pro/features/rehab/data/rehab_models.dart';
import 'package:apx_pro/features/rehab/presentation/screens/workout_screen.dart';
import 'package:apx_pro/features/rehab/presentation/screens/youtube_player_screen.dart';
import 'package:apx_pro/features/rehab/presentation/screens/exercise_detail_screen.dart';
import 'package:apx_pro/features/rehab/presentation/screens/admin_patient_programs.dart';
import 'package:apx_pro/features/rehab/presentation/screens/admin_program_detail.dart';
import 'package:apx_pro/features/rehab/presentation/screens/admin_exercise_form.dart';
import 'package:apx_pro/features/rehab/presentation/screens/admin_workout_history_screen.dart';
import 'package:apx_pro/features/consultation/data/appointment_model.dart';
import 'package:apx_pro/features/consultation/presentation/screens/appointment_detail_screen.dart';
import 'package:apx_pro/features/settings/presentation/settings_screen.dart';
import 'package:apx_pro/features/settings/presentation/about_us_screen.dart';

// Routes that don't require authentication
const _publicRoutes = {'/splash', '/onboarding', '/login', '/register', '/otp', '/verify-email', '/forgot-password'};

final routerProvider = Provider<GoRouter>((ref) {
  // ValueNotifier so GoRouter re-evaluates redirect when auth changes
  final authNotifier = ValueNotifier<AuthState>(ref.read(authControllerProvider));
  ref.listen(authControllerProvider, (_, next) {
    authNotifier.value = next;
  });
  ref.onDispose(authNotifier.dispose);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: authNotifier,
    redirect: (BuildContext context, GoRouterState state) {
      final authStatus = authNotifier.value.status;
      final isPublic = _publicRoutes.contains(state.matchedLocation);

      // Still initialising — let splash handle it
      if (authStatus == AuthStatus.initial || authStatus == AuthStatus.loading) {
        return null;
      }

      final isLoggedIn = authStatus == AuthStatus.authenticated;

      if (!isLoggedIn && !isPublic) return '/login';
      if (isLoggedIn && state.matchedLocation == '/login') return '/dashboard';
      if (isLoggedIn && state.matchedLocation == '/onboarding') return '/dashboard';

      // Defense-in-depth: keep non-admins out of /admin/* even by deep link.
      // The backend already authorizes every admin endpoint; this stops a
      // patient build from ever loading an admin screen (which handles other
      // patients' medical data) in the first place.
      if (isLoggedIn &&
          state.matchedLocation.startsWith('/admin') &&
          !authNotifier.value.isAdmin) {
        return '/dashboard';
      }

      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
      GoRoute(
        path: '/otp',
        builder: (_, state) {
          final extra = state.extra;
          if (extra is Map) {
            return OtpScreen(
              phoneNumber: (extra['phone'] as String?) ?? '',
              mode: (extra['mode'] as String?) ?? 'login',
              email: extra['email'] as String?,
            );
          }
          return OtpScreen(phoneNumber: (extra as String?) ?? '');
        },
      ),
      GoRoute(
        path: '/verify-email',
        builder: (_, state) {
          final extra = state.extra;
          if (extra is Map) {
            return VerifyEmailScreen(
              email: (extra['email'] as String?) ?? '',
              channel: extra['channel'] as String?,
            );
          }
          return VerifyEmailScreen(email: (extra as String?) ?? '');
        },
      ),
      GoRoute(path: '/forgot-password', builder: (_, __) => const ForgotPasswordScreen()),
      GoRoute(path: '/dashboard', builder: (_, __) => const DashboardScreen()),
      GoRoute(path: '/settings',  builder: (_, __) => const SettingsScreen()),
      GoRoute(path: '/settings/about', builder: (_, __) => const AboutUsScreen()),
      GoRoute(path: '/assessment', builder: (_, __) => const AssessmentScreen()),
      GoRoute(path: '/progress', builder: (_, __) => const ProgressScreen()),

      // Notes routes
      GoRoute(path: '/notes', builder: (_, __) => const NotesHomeScreen()),
      GoRoute(path: '/notes/purchase', builder: (_, __) => const NotesPurchaseScreen()),
      GoRoute(
        path: '/notes/:noteId/view',
        builder: (_, state) =>
            NoteViewerScreen(noteId: state.pathParameters['noteId']!),
      ),
      GoRoute(path: '/admin/notes', builder: (_, __) => const AdminNotesScreen()),
      GoRoute(path: '/admin/notes/upload', builder: (_, __) => const UploadNoteScreen()),
      GoRoute(
        path: '/admin/notes/:noteId/edit',
        builder: (_, state) =>
            EditNoteScreen(noteId: state.pathParameters['noteId']!),
      ),

      // Rehab routes — patient
      GoRoute(
        path: '/rehab/video',
        builder: (_, state) {
          final extra = (state.extra as Map?) ?? const {};
          return YouTubePlayerScreen(
            videoId: (extra['videoId'] as String?) ?? '',
            title: (extra['title'] as String?) ?? 'Exercise Video',
          );
        },
      ),
      GoRoute(
        path: '/rehab/exercise',
        builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>;
          return ExerciseDetailScreen(
            program: extra['program'] as RehabProgramModel,
            exerciseIndex: extra['index'] as int,
          );
        },
      ),
      GoRoute(
        path: '/rehab/workout',
        builder: (_, state) {
          final extra = state.extra;
          if (extra is Map<String, dynamic>) {
            return WorkoutScreen(
              program: extra['program'] as RehabProgramModel,
              startingIndex: extra['startAt'] as int? ?? 0,
            );
          }
          return WorkoutScreen(program: extra as RehabProgramModel);
        },
      ),

      // Rehab routes — admin
      GoRoute(
        path: '/admin/rehab/patients/:patientId/programs',
        builder: (_, state) => AdminPatientProgramsScreen(
          patientId: state.pathParameters['patientId']!,
          patientName: (state.extra as String?) ?? 'Patient',
        ),
      ),
      GoRoute(
        path: '/admin/rehab/programs/:programId',
        builder: (_, state) => AdminProgramDetailScreen(
          programId: state.pathParameters['programId']!,
        ),
      ),
      GoRoute(
        path: '/admin/rehab/programs/:programId/exercises/add',
        builder: (_, state) => AdminExerciseFormScreen(
          programId: state.pathParameters['programId']!,
        ),
      ),
      GoRoute(
        path: '/admin/rehab/programs/:programId/exercises/edit',
        builder: (_, state) => AdminExerciseFormScreen(
          programId: state.pathParameters['programId']!,
          exercise: state.extra as RehabExerciseModel?,
        ),
      ),

      // Patient workout history (lazy, paginated)
      GoRoute(
        path: '/admin/rehab/patients/:patientId/history',
        builder: (_, state) => AdminWorkoutHistoryScreen(
          patientId: state.pathParameters['patientId']!,
          patientName: state.extra as String?,
        ),
      ),

      // Admin panel routes
      GoRoute(path: '/admin/panel', builder: (_, __) => const AdminPanelScreen()),
      GoRoute(path: '/admin/appointments', builder: (_, __) => const AdminAppointmentsScreen()),
      GoRoute(
        path: '/admin/appointments/:appointmentId',
        builder: (_, state) => AppointmentDetailScreen(
          appointment: state.extra as AppointmentModel?,
        ),
      ),
      GoRoute(
        path: '/admin/users/:userId',
        builder: (_, state) =>
            AdminUserDetailScreen(userId: state.pathParameters['userId']!),
      ),
    ],
  );
});

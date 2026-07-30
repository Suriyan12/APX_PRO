import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apx_pro/core/network/api_client.dart';
import 'package:apx_pro/features/auth/presentation/controllers/auth_controller.dart';
import 'package:apx_pro/features/consultation/data/appointment_model.dart';
import 'package:apx_pro/features/consultation/data/appointment_repository.dart';

// ── Providers ────────────────────────────────────────────────────────────────

final appointmentRepositoryProvider = Provider<AppointmentRepository>((ref) {
  return AppointmentRepository(ref.watch(apiClientProvider));
});

final appointmentProvider =
    StateNotifierProvider<AppointmentNotifier, AppointmentState>((ref) {
  return AppointmentNotifier(ref.watch(appointmentRepositoryProvider));
});

/// Admin/therapist: a specific patient's appointment history, newest first.
/// Keyed by patientId and autoDispose so each patient dashboard loads its own
/// list independently of the global (self/all) [appointmentProvider].
final patientAppointmentsProvider = FutureProvider.autoDispose
    .family<List<AppointmentModel>, String>((ref, patientId) {
  return ref.watch(appointmentRepositoryProvider).fetchForPatient(patientId);
});

// ── State ────────────────────────────────────────────────────────────────────

class AppointmentState {
  const AppointmentState({
    this.appointments = const [],
    this.loading = false,
    this.error,
  });

  final List<AppointmentModel> appointments;
  final bool loading;
  final String? error;

  /// Next upcoming appointment (earliest future/in-session active appointment).
  AppointmentModel? get nextUpcoming {
    final up = upcoming;
    return up.isEmpty ? null : up.first;
  }

  /// Upcoming appointments sorted by start time ascending.
  List<AppointmentModel> get upcoming {
    return [...appointments.where((a) => a.isUpcoming)]
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
  }

  /// Past appointments sorted by start time descending.
  List<AppointmentModel> get past {
    return [...appointments.where((a) => a.isPast)]
      ..sort((a, b) => b.startTime.compareTo(a.startTime));
  }

  AppointmentState copyWith({
    List<AppointmentModel>? appointments,
    bool? loading,
    String? error,
    bool clearError = false,
  }) {
    return AppointmentState(
      appointments: appointments ?? this.appointments,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

// ── Notifier ─────────────────────────────────────────────────────────────────

class AppointmentNotifier extends StateNotifier<AppointmentState> {
  AppointmentNotifier(this._repo) : super(const AppointmentState());

  final AppointmentRepository _repo;

  // ------------------------------------------------------------------
  // Load
  // ------------------------------------------------------------------

  Future<void> load() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final list = await _repo.fetchMyAppointments();
      state = state.copyWith(appointments: list, loading: false);
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: _extractMessage(e),
      );
    }
  }

  // ------------------------------------------------------------------
  // Book — optimistic: insert immediately, correct from server response
  // ------------------------------------------------------------------

  Future<AppointmentModel> book({
    required String startTime,
    required String endTime,
    String? notes,
    String consultationType = 'physical',
  }) async {
    final appt = await _repo.book(
      startTime: startTime,
      endTime: endTime,
      notes: notes,
      consultationType: consultationType,
    );
    // Insert at the front so newly booked appears first even before a sort
    state = state.copyWith(
      appointments: [appt, ...state.appointments],
    );
    return appt;
  }

  // ------------------------------------------------------------------
  // Cancel — optimistic: mark cancelled locally, fix from server truth
  // ------------------------------------------------------------------

  Future<void> cancel(String id) async {
    // Optimistic update
    final previous = state.appointments;
    state = state.copyWith(
      appointments: previous
          .map((a) => a.id == id ? a.copyWith(status: 'cancelled') : a)
          .toList(),
    );

    try {
      final updated = await _repo.cancel(id);
      state = state.copyWith(
        appointments: state.appointments
            .map((a) => a.id == id ? updated : a)
            .toList(),
      );
    } catch (e) {
      // Revert on failure and surface the error
      state = state.copyWith(
        appointments: previous,
        error: _extractMessage(e),
      );
      rethrow;
    }
  }

  // ------------------------------------------------------------------
  // Reschedule — replaces the appointment in state with the server response
  // ------------------------------------------------------------------

  Future<AppointmentModel> reschedule(
    String id, {
    required String startTime,
    required String endTime,
    String? notes,
  }) async {
    final updated = await _repo.reschedule(
      id,
      startTime: startTime,
      endTime: endTime,
      notes: notes,
    );
    state = state.copyWith(
      appointments: state.appointments
          .map((a) => a.id == id ? updated : a)
          .toList(),
    );
    return updated;
  }

  // ------------------------------------------------------------------
  // Admin: approve / reject — replace the appointment with server truth
  // ------------------------------------------------------------------

  Future<AppointmentModel> approve(
    String id, {
    String? meetingProvider,
    String? meetingLink,
  }) async {
    final updated = await _repo.approve(
      id,
      meetingProvider: meetingProvider,
      meetingLink: meetingLink,
    );
    state = state.copyWith(
      appointments:
          state.appointments.map((a) => a.id == id ? updated : a).toList(),
    );
    return updated;
  }

  Future<AppointmentModel> reject(String id, {String? reason}) async {
    final updated = await _repo.reject(id, reason: reason);
    state = state.copyWith(
      appointments:
          state.appointments.map((a) => a.id == id ? updated : a).toList(),
    );
    return updated;
  }

  // ------------------------------------------------------------------
  // Clear error
  // ------------------------------------------------------------------

  void clearError() => state = state.copyWith(clearError: true);

  // ------------------------------------------------------------------
  // Internal
  // ------------------------------------------------------------------

  String _extractMessage(Object e) {
    if (e is ApiException) return e.message;
    return e.toString();
  }
}

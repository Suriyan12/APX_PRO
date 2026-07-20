import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apx_pro/core/network/api_client.dart';
import 'package:apx_pro/features/auth/presentation/controllers/auth_controller.dart';
import 'package:apx_pro/features/rehab/data/rehab_models.dart';
import 'package:apx_pro/features/rehab/data/rehab_repository.dart';

// ── Core providers ───────────────────────────────────────────────────────────

final rehabRepositoryProvider = Provider<RehabRepository>((ref) {
  return RehabRepository(ref.watch(apiClientProvider));
});

// ── Patient: My Program ───────────────────────────────────────────────────────

class MyRehabProgramState {
  final bool loading;
  final String? error;
  final RehabMyProgramData? data;

  const MyRehabProgramState({this.loading = false, this.error, this.data});

  MyRehabProgramState copyWith({
    bool? loading,
    String? error,
    RehabMyProgramData? data,
    bool clearError = false,
  }) {
    return MyRehabProgramState(
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      data: data ?? this.data,
    );
  }
}

class MyRehabProgramNotifier extends StateNotifier<MyRehabProgramState> {
  MyRehabProgramNotifier(this._repo) : super(const MyRehabProgramState());
  final RehabRepository _repo;

  Future<void> load() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final data = await _repo.fetchMyProgram();
      state = state.copyWith(loading: false, data: data);
    } on ApiException catch (e) {
      if (e.statusCode == 404) {
        state = state.copyWith(loading: false, data: null, clearError: true);
      } else {
        state = state.copyWith(loading: false, error: e.message);
      }
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  void invalidate() {
    state = const MyRehabProgramState();
  }
}

final myRehabProgramProvider =
    StateNotifierProvider<MyRehabProgramNotifier, MyRehabProgramState>((ref) {
  return MyRehabProgramNotifier(ref.watch(rehabRepositoryProvider));
});

// ── Patient: Workout Session ──────────────────────────────────────────────────

enum WorkoutPhase { exercising, resting, complete }

class WorkoutSessionState {
  final String? sessionId;
  final List<RehabExerciseModel> exercises;
  final int currentExerciseIndex;
  final int currentSet;
  final WorkoutPhase phase;
  final int? timerSeconds;
  final bool isPaused;
  final bool isFinished;
  final bool isSaving;
  final List<ExerciseResult> results;
  final String? error;

  const WorkoutSessionState({
    this.sessionId,
    this.exercises = const [],
    this.currentExerciseIndex = 0,
    this.currentSet = 1,
    this.phase = WorkoutPhase.exercising,
    this.timerSeconds,
    this.isPaused = false,
    this.isFinished = false,
    this.isSaving = false,
    this.results = const [],
    this.error,
  });

  RehabExerciseModel? get currentExercise =>
      exercises.isNotEmpty && currentExerciseIndex < exercises.length
          ? exercises[currentExerciseIndex]
          : null;

  bool get isLastExercise => currentExerciseIndex >= exercises.length - 1;
  bool get isLastSet => currentSet >= (currentExercise?.sets ?? 1);

  WorkoutSessionState copyWith({
    String? sessionId,
    List<RehabExerciseModel>? exercises,
    int? currentExerciseIndex,
    int? currentSet,
    WorkoutPhase? phase,
    int? timerSeconds,
    bool? isPaused,
    bool? isFinished,
    bool? isSaving,
    List<ExerciseResult>? results,
    String? error,
    bool clearTimer = false,
    bool clearError = false,
  }) {
    return WorkoutSessionState(
      sessionId: sessionId ?? this.sessionId,
      exercises: exercises ?? this.exercises,
      currentExerciseIndex: currentExerciseIndex ?? this.currentExerciseIndex,
      currentSet: currentSet ?? this.currentSet,
      phase: phase ?? this.phase,
      timerSeconds: clearTimer ? null : (timerSeconds ?? this.timerSeconds),
      isPaused: isPaused ?? this.isPaused,
      isFinished: isFinished ?? this.isFinished,
      isSaving: isSaving ?? this.isSaving,
      results: results ?? this.results,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class WorkoutSessionNotifier extends StateNotifier<WorkoutSessionState> {
  WorkoutSessionNotifier(this._repo) : super(const WorkoutSessionState());
  final RehabRepository _repo;
  Timer? _countdownTimer;
  Timer? _elapsedTimer;
  int _elapsedSeconds = 0;

  void _cancelCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
  }

  void _startCountdown(int seconds, VoidCallback onComplete) {
    _cancelCountdown();
    state = state.copyWith(timerSeconds: seconds);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (state.isPaused) return;
      final remaining = (state.timerSeconds ?? 0) - 1;
      if (remaining <= 0) {
        t.cancel();
        state = state.copyWith(clearTimer: true);
        onComplete();
      } else {
        state = state.copyWith(timerSeconds: remaining);
      }
    });
  }

  void _startElapsedTracker() {
    _elapsedTimer?.cancel();
    _elapsedSeconds = 0;
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (!state.isFinished) _elapsedSeconds++;
    });
  }

  Future<void> startSession(RehabProgramModel program, {int startingIndex = 0}) async {
    try {
      final session = await _repo.startSession(program.id);
      // The screen may have been closed while the request was in flight —
      // never touch state after that (defunct-listener crash).
      if (!mounted) return;
      state = WorkoutSessionState(
        sessionId: session.id,
        exercises: program.exercises,
        currentExerciseIndex: startingIndex.clamp(0, (program.exercises.length - 1).clamp(0, 999)),
      );
      _startElapsedTracker();
      _maybeStartTimer();
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(error: 'Could not start the workout: $e');
    }
  }

  void _maybeStartTimer() {
    final ex = state.currentExercise;
    if (ex == null || ex.exerciseType != ExerciseType.timed) return;
    _startCountdown(ex.durationSeconds ?? 30, _onTimedSetComplete);
  }

  void _onTimedSetComplete() {
    _recordSetAndAdvance(actualDuration: state.currentExercise?.durationSeconds);
  }

  void markSetDone() {
    if (state.phase != WorkoutPhase.exercising) return;
    _recordSetAndAdvance();
  }

  void _recordSetAndAdvance({int? actualDuration}) {
    _cancelCountdown();
    final ex = state.currentExercise!;
    if (state.isLastSet) {
      final result = ExerciseResult(
        exerciseId: ex.id,
        setsCompleted: state.currentSet,
        actualDurationSeconds: actualDuration,
      );
      final newResults = [...state.results, result];
      if (state.isLastExercise) {
        state = state.copyWith(results: newResults, phase: WorkoutPhase.complete);
      } else {
        state = state.copyWith(results: newResults, phase: WorkoutPhase.resting);
        _startCountdown(ex.restSeconds > 0 ? ex.restSeconds : 1, _afterRest);
      }
    } else {
      state = state.copyWith(phase: WorkoutPhase.resting);
      _startCountdown(ex.restSeconds > 0 ? ex.restSeconds : 1, _afterRestSameExercise);
    }
  }

  void _afterRestSameExercise() {
    state = state.copyWith(
      currentSet: state.currentSet + 1,
      phase: WorkoutPhase.exercising,
    );
    _maybeStartTimer();
  }

  void _afterRest() {
    state = state.copyWith(
      currentExerciseIndex: state.currentExerciseIndex + 1,
      currentSet: 1,
      phase: WorkoutPhase.exercising,
    );
    _maybeStartTimer();
  }

  void skipRestTimer() {
    _cancelCountdown();
    if (state.phase != WorkoutPhase.resting) return;
    if (state.isLastSet && !state.isLastExercise) {
      _afterRest();
    } else {
      _afterRestSameExercise();
    }
  }

  void skipExercise() {
    _cancelCountdown();
    final ex = state.currentExercise;
    if (ex == null) return;
    final result = ExerciseResult(
      exerciseId: ex.id,
      setsCompleted: state.currentSet - 1,
      isSkipped: true,
    );
    final newResults = [...state.results, result];
    if (state.isLastExercise) {
      state = state.copyWith(results: newResults, phase: WorkoutPhase.complete);
    } else {
      state = state.copyWith(
        results: newResults,
        currentExerciseIndex: state.currentExerciseIndex + 1,
        currentSet: 1,
        phase: WorkoutPhase.exercising,
      );
      _maybeStartTimer();
    }
  }

  void goToPreviousExercise() {
    if (state.currentExerciseIndex == 0) return;
    _cancelCountdown();
    final prevExerciseId = state.exercises[state.currentExerciseIndex - 1].id;
    final newResults = state.results.where((r) => r.exerciseId != prevExerciseId).toList();
    state = state.copyWith(
      currentExerciseIndex: state.currentExerciseIndex - 1,
      currentSet: 1,
      phase: WorkoutPhase.exercising,
      results: newResults,
    );
    _maybeStartTimer();
  }

  void goToNextExercise() {
    if (state.isLastExercise) return;
    _cancelCountdown();
    final ex = state.currentExercise!;
    final result = ExerciseResult(
      exerciseId: ex.id,
      setsCompleted: state.currentSet,
    );
    final newResults = [...state.results, result];
    state = state.copyWith(
      results: newResults,
      currentExerciseIndex: state.currentExerciseIndex + 1,
      currentSet: 1,
      phase: WorkoutPhase.exercising,
    );
    _maybeStartTimer();
  }

  void pause() => state = state.copyWith(isPaused: true);
  void resume() => state = state.copyWith(isPaused: false);

  Future<RehabSessionModel?> finishWorkout() async {
    _cancelCountdown();
    // Stop the elapsed tracker — the finish path pops the screen without
    // calling reset(), and this provider is a non-autoDispose global, so a
    // missed cancel leaves the 1s Timer.periodic running for the app's life.
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    if (state.sessionId == null) return null;
    final recordedIds = state.results.map((r) => r.exerciseId).toSet();
    var finalResults = List<ExerciseResult>.from(state.results);
    final ex = state.currentExercise;
    if (ex != null && !recordedIds.contains(ex.id)) {
      finalResults.add(ExerciseResult(
        exerciseId: ex.id,
        setsCompleted: state.currentSet,
      ));
    }
    state = state.copyWith(isSaving: true);
    try {
      final session = await _repo.completeSession(
        state.sessionId!,
        durationSeconds: _elapsedSeconds,
        exercises: finalResults,
      );
      state = state.copyWith(isSaving: false, isFinished: true);
      return session;
    } catch (e) {
      state = state.copyWith(isSaving: false, error: e.toString());
      return null;
    }
  }

  void reset() {
    _cancelCountdown();
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    _elapsedSeconds = 0;
    state = const WorkoutSessionState();
  }

  @override
  void dispose() {
    _cancelCountdown();
    _elapsedTimer?.cancel();
    super.dispose();
  }
}

final workoutSessionProvider =
    StateNotifierProvider<WorkoutSessionNotifier, WorkoutSessionState>((ref) {
  return WorkoutSessionNotifier(ref.watch(rehabRepositoryProvider));
});

// ── Admin: Patient Programs ───────────────────────────────────────────────────

class PatientProgramsState {
  final bool loading;
  final String? error;
  final List<RehabProgramListItem> programs;

  const PatientProgramsState({
    this.loading = false,
    this.error,
    this.programs = const [],
  });

  PatientProgramsState copyWith({
    bool? loading,
    String? error,
    List<RehabProgramListItem>? programs,
    bool clearError = false,
  }) {
    return PatientProgramsState(
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      programs: programs ?? this.programs,
    );
  }
}

class PatientProgramsNotifier extends StateNotifier<PatientProgramsState> {
  PatientProgramsNotifier(this._repo, this._patientId) : super(const PatientProgramsState());
  final RehabRepository _repo;
  final String _patientId;

  Future<void> load() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final programs = await _repo.fetchPatientPrograms(_patientId);
      state = state.copyWith(loading: false, programs: programs);
    } catch (e) {
      state = state.copyWith(loading: false, error: _msg(e));
    }
  }

  Future<RehabProgramModel?> createProgram({
    required String title,
    String? description,
    int estimatedDurationDays = 30,
  }) async {
    try {
      final program = await _repo.createProgram(
        patientId: _patientId,
        title: title,
        description: description,
        estimatedDurationDays: estimatedDurationDays,
      );
      await load();
      return program;
    } catch (e) {
      state = state.copyWith(error: _msg(e));
      return null;
    }
  }

  Future<void> toggleProgram(String programId) async {
    try {
      await _repo.toggleProgram(programId);
      await load();
    } catch (e) {
      state = state.copyWith(error: _msg(e));
    }
  }

  Future<void> deleteProgram(String programId) async {
    try {
      await _repo.deleteProgram(programId);
      state = state.copyWith(
        programs: state.programs.where((p) => p.id != programId).toList(),
      );
    } catch (e) {
      state = state.copyWith(error: _msg(e));
    }
  }

  String _msg(Object e) => e is ApiException ? e.message : e.toString();
}

final patientProgramsProvider = StateNotifierProvider.family<
    PatientProgramsNotifier, PatientProgramsState, String>((ref, patientId) {
  return PatientProgramsNotifier(ref.watch(rehabRepositoryProvider), patientId);
});

// ── Admin: Program Detail ─────────────────────────────────────────────────────

class ProgramDetailState {
  final bool loading;
  final String? error;
  final RehabProgramModel? program;

  const ProgramDetailState({this.loading = false, this.error, this.program});

  ProgramDetailState copyWith({
    bool? loading,
    String? error,
    RehabProgramModel? program,
    bool clearError = false,
  }) {
    return ProgramDetailState(
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      program: program ?? this.program,
    );
  }
}

class ProgramDetailNotifier extends StateNotifier<ProgramDetailState> {
  ProgramDetailNotifier(this._repo, this._programId) : super(const ProgramDetailState());
  final RehabRepository _repo;
  final String _programId;

  Future<void> load() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final program = await _repo.fetchProgramDetail(_programId);
      state = state.copyWith(loading: false, program: program);
    } catch (e) {
      state = state.copyWith(loading: false, error: _msg(e));
    }
  }

  /// Returns the created exercise's id so callers can attach a video to the
  /// exact new row instead of guessing it from list order.
  Future<String> addExercise(Map<String, dynamic> data) async {
    try {
      final created = await _repo.addExercise(_programId, data);
      await load();
      return created.id;
    } catch (e) {
      state = state.copyWith(error: _msg(e));
      rethrow;
    }
  }

  Future<void> updateExercise(String exerciseId, Map<String, dynamic> data) async {
    try {
      await _repo.updateExercise(_programId, exerciseId, data);
      await load();
    } catch (e) {
      state = state.copyWith(error: _msg(e));
      rethrow;
    }
  }

  Future<void> deleteExercise(String exerciseId) async {
    try {
      await _repo.deleteExercise(_programId, exerciseId);
      if (state.program != null) {
        final updated = state.program!.exercises.where((e) => e.id != exerciseId).toList();
        state = state.copyWith(
          program: RehabProgramModel(
            id: state.program!.id,
            patientId: state.program!.patientId,
            createdBy: state.program!.createdBy,
            title: state.program!.title,
            description: state.program!.description,
            estimatedDurationDays: state.program!.estimatedDurationDays,
            isActive: state.program!.isActive,
            createdAt: state.program!.createdAt,
            exercises: updated,
          ),
        );
      }
    } catch (e) {
      state = state.copyWith(error: _msg(e));
      rethrow;
    }
  }

  Future<void> updateProgram({String? title, String? description, int? estimatedDurationDays}) async {
    try {
      await _repo.updateProgram(_programId, title: title, description: description, estimatedDurationDays: estimatedDurationDays);
      await load();
    } catch (e) {
      state = state.copyWith(error: _msg(e));
      rethrow;
    }
  }

  Future<String> uploadVideo(String exerciseId, PlatformFile file) async {
    try {
      final url = await _repo.uploadVideo(_programId, exerciseId, file);
      await load();
      return url;
    } catch (e) {
      state = state.copyWith(error: _msg(e));
      rethrow;
    }
  }

  Future<void> reorder(List<Map<String, dynamic>> items) async {
    try {
      await _repo.reorderExercises(_programId, items);
      await load();
    } catch (e) {
      state = state.copyWith(error: _msg(e));
    }
  }

  String _msg(Object e) => e is ApiException ? e.message : e.toString();
}

final programDetailProvider = StateNotifierProvider.family<
    ProgramDetailNotifier, ProgramDetailState, String>((ref, programId) {
  return ProgramDetailNotifier(ref.watch(rehabRepositoryProvider), programId);
});

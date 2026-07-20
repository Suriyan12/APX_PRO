import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:apx_pro/core/network/api_client.dart';
import 'package:apx_pro/features/rehab/data/rehab_models.dart';

class RehabRepository {
  final ApiClient _api;
  RehabRepository(this._api);

  // ── Patient ──────────────────────────────────────────────────────────────

  Future<RehabMyProgramData> fetchMyProgram() async {
    final r = await _api.get('/rehab/my');
    return RehabMyProgramData(
      program: RehabProgramModel.fromJson(r.data['program'] as Map<String, dynamic>),
      progress: RehabProgressModel.fromJson(r.data['progress'] as Map<String, dynamic>),
      todaySession: r.data['today_session'] != null
          ? RehabSessionModel.fromJson(r.data['today_session'] as Map<String, dynamic>)
          : null,
    );
  }

  Future<RehabProgressModel> fetchProgress() async {
    final r = await _api.get('/rehab/my/progress');
    return RehabProgressModel.fromJson(r.data as Map<String, dynamic>);
  }

  Future<RehabSessionModel?> fetchTodaySession() async {
    try {
      final r = await _api.get('/rehab/sessions/today');
      return RehabSessionModel.fromJson(r.data as Map<String, dynamic>);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<RehabSessionModel> startSession(String programId) async {
    final r = await _api.post('/rehab/sessions/start', data: {'program_id': programId});
    return RehabSessionModel.fromJson(r.data as Map<String, dynamic>);
  }

  Future<RehabSessionModel> completeSession(
    String sessionId, {
    required int durationSeconds,
    required List<ExerciseResult> exercises,
  }) async {
    final r = await _api.post('/rehab/sessions/$sessionId/complete', data: {
      'duration_seconds': durationSeconds,
      'exercises': exercises.map((e) => e.toJson()).toList(),
    });
    return RehabSessionModel.fromJson(r.data as Map<String, dynamic>);
  }

  // ── Admin: Programs ───────────────────────────────────────────────────────

  Future<List<RehabProgramListItem>> fetchPatientPrograms(String patientId) async {
    final r = await _api.get('/rehab/programs/patient/$patientId');
    return (r.data as List<dynamic>)
        .map((e) => RehabProgramListItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<RehabProgramModel> fetchProgramDetail(String programId) async {
    final r = await _api.get('/rehab/programs/$programId');
    return RehabProgramModel.fromJson(r.data as Map<String, dynamic>);
  }

  Future<RehabProgramModel> createProgram({
    required String patientId,
    required String title,
    String? description,
    int estimatedDurationDays = 30,
  }) async {
    final r = await _api.post('/rehab/programs', data: {
      'patient_id': patientId,
      'title': title,
      if (description != null) 'description': description,
      'estimated_duration_days': estimatedDurationDays,
    });
    return RehabProgramModel.fromJson(r.data as Map<String, dynamic>);
  }

  Future<RehabProgramModel> updateProgram(
    String programId, {
    String? title,
    String? description,
    int? estimatedDurationDays,
  }) async {
    final r = await _api.put('/rehab/programs/$programId', data: {
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (estimatedDurationDays != null) 'estimated_duration_days': estimatedDurationDays,
    });
    return RehabProgramModel.fromJson(r.data as Map<String, dynamic>);
  }

  Future<void> deleteProgram(String programId) async {
    await _api.delete('/rehab/programs/$programId');
  }

  Future<RehabProgramModel> duplicateProgram(
    String programId, {
    required String targetPatientId,
    String? newTitle,
  }) async {
    final r = await _api.post('/rehab/programs/$programId/duplicate', data: {
      'target_patient_id': targetPatientId,
      if (newTitle != null) 'new_title': newTitle,
    });
    return RehabProgramModel.fromJson(r.data as Map<String, dynamic>);
  }

  Future<RehabProgramModel> toggleProgram(String programId) async {
    final r = await _api.put('/rehab/programs/$programId/toggle');
    return RehabProgramModel.fromJson(r.data as Map<String, dynamic>);
  }

  // ── Admin: Exercises ──────────────────────────────────────────────────────

  Future<RehabExerciseModel> addExercise(
    String programId,
    Map<String, dynamic> data,
  ) async {
    final r = await _api.post('/rehab/programs/$programId/exercises', data: data);
    return RehabExerciseModel.fromJson(r.data as Map<String, dynamic>);
  }

  Future<RehabExerciseModel> updateExercise(
    String programId,
    String exerciseId,
    Map<String, dynamic> data,
  ) async {
    final r = await _api.put('/rehab/programs/$programId/exercises/$exerciseId', data: data);
    return RehabExerciseModel.fromJson(r.data as Map<String, dynamic>);
  }

  Future<void> deleteExercise(String programId, String exerciseId) async {
    await _api.delete('/rehab/programs/$programId/exercises/$exerciseId');
  }

  Future<void> reorderExercises(
    String programId,
    List<Map<String, dynamic>> items,
  ) async {
    await _api.put('/rehab/programs/$programId/reorder', data: items);
  }

  Future<String> uploadVideo(String programId, String exerciseId, PlatformFile picked) async {
    final MultipartFile multipart;
    if (kIsWeb) {
      multipart = MultipartFile.fromBytes(
        picked.bytes!,
        filename: picked.name.isNotEmpty ? picked.name : '$exerciseId.mp4',
      );
    } else {
      multipart = await MultipartFile.fromFile(
        picked.path!,
        filename: picked.name.isNotEmpty ? picked.name : '$exerciseId.mp4',
      );
    }
    final formData = FormData.fromMap({'file': multipart});
    final r = await _api.post(
      '/rehab/programs/$programId/exercises/$exerciseId/video',
      data: formData,
    );
    return r.data['video_path'] as String;
  }
}

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:apx_pro/core/network/api_client.dart';
import 'package:apx_pro/features/auth/presentation/controllers/auth_controller.dart';
import 'package:apx_pro/features/assessment/data/medical_record_model.dart';
import 'package:apx_pro/features/assessment/data/medical_records_repository.dart';

final medicalRecordsRepositoryProvider = Provider<MedicalRecordsRepository>(
  (ref) => MedicalRecordsRepository(ref.watch(apiClientProvider)),
);

class MedicalRecordsState {
  final List<MedicalRecord> records;
  final bool loading;
  final bool uploading;
  final double uploadProgress;
  final String? error;

  const MedicalRecordsState({
    this.records = const [],
    this.loading = false,
    this.uploading = false,
    this.uploadProgress = 0.0,
    this.error,
  });

  MedicalRecordsState copyWith({
    List<MedicalRecord>? records,
    bool? loading,
    bool? uploading,
    double? uploadProgress,
    String? error,
    bool clearError = false,
  }) {
    return MedicalRecordsState(
      records: records ?? this.records,
      loading: loading ?? this.loading,
      uploading: uploading ?? this.uploading,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class MedicalRecordsNotifier extends StateNotifier<MedicalRecordsState> {
  final MedicalRecordsRepository _repo;
  final String patientId;

  MedicalRecordsNotifier(this._repo, this.patientId)
      : super(const MedicalRecordsState());

  Future<void> load() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final records = await _repo.listForPatient(patientId);
      if (!mounted) return;
      state = state.copyWith(records: records, loading: false);
    } on ApiException catch (e) {
      if (!mounted) return;
      state = state.copyWith(loading: false, error: e.message);
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(
          loading: false, error: 'Could not load medical records.');
    }
  }

  /// Uploads a record. Returns an error message, or null on success.
  Future<String?> upload({
    required String fileName,
    required Uint8List bytes,
    String? category,
  }) async {
    state = state.copyWith(uploading: true, uploadProgress: 0, clearError: true);
    try {
      final record = await _repo.upload(
        fileName: fileName,
        bytes: bytes,
        category: category,
        patientId: patientId,
        onProgress: (sent, total) {
          if (total > 0 && mounted) {
            state = state.copyWith(uploadProgress: sent / total);
          }
        },
      );
      if (!mounted) return null;
      state = state.copyWith(
        records: [record, ...state.records],
        uploading: false,
      );
      return null;
    } on ApiException catch (e) {
      if (mounted) state = state.copyWith(uploading: false);
      return e.message;
    } catch (_) {
      if (mounted) state = state.copyWith(uploading: false);
      return 'Upload failed. Please try again.';
    }
  }

  /// Deletes a record. Returns an error message, or null on success.
  Future<String?> delete(String recordId) async {
    try {
      await _repo.delete(recordId);
      if (!mounted) return null;
      state = state.copyWith(
        records: state.records.where((r) => r.id != recordId).toList(),
      );
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Could not delete the record.';
    }
  }
}

final medicalRecordsProvider = StateNotifierProvider.family<
    MedicalRecordsNotifier, MedicalRecordsState, String>(
  (ref, patientId) => MedicalRecordsNotifier(
    ref.watch(medicalRecordsRepositoryProvider),
    patientId,
  ),
);

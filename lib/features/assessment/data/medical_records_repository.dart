import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

import 'package:apx_pro/core/network/api_client.dart';
import 'package:apx_pro/features/assessment/data/medical_record_model.dart';

/// All Medical Records traffic goes through the authenticated backend —
/// the app never talks to Google Drive directly.
class MedicalRecordsRepository {
  final ApiClient _api;

  MedicalRecordsRepository(this._api);

  Future<List<MedicalRecord>> listForPatient(String patientId) async {
    final resp = await _api.get('/medical-records/patient/$patientId');
    return (resp.data as List)
        .cast<Map<String, dynamic>>()
        .map(MedicalRecord.fromJson)
        .toList();
  }

  Future<MedicalRecord> upload({
    required String fileName,
    required Uint8List bytes,
    String? category,
    String? patientId,
    void Function(int sent, int total)? onProgress,
  }) async {
    final ext = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : '';
    final mimeType = ext == 'pdf'
        ? 'application/pdf'
        : ext == 'png'
            ? 'image/png'
            : 'image/jpeg';

    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        bytes,
        filename: fileName,
        contentType: DioMediaType.parse(mimeType),
      ),
      if (category != null && category.isNotEmpty) 'category': category,
      if (patientId != null) 'patient_id': patientId,
    });

    try {
      final resp = await _api.dio.post(
        '/medical-records/upload',
        data: formData,
        options: Options(
          // Server streams the file to Google Drive before responding, so the
          // response can arrive well after the send completes.
          sendTimeout: const Duration(minutes: 10),
          receiveTimeout: const Duration(minutes: 10),
        ),
        onSendProgress: onProgress,
      );
      return MedicalRecord.fromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      final detail = e.response?.data is Map
          ? (e.response!.data['detail']?.toString() ?? 'Upload failed')
          : 'Upload failed. Please try again.';
      throw ApiException(detail, e.response?.statusCode ?? 500);
    }
  }

  Future<Uint8List> downloadBytes(String recordId, {bool inline = false}) async {
    try {
      final resp = await _api.dio.get(
        '/medical-records/$recordId/download',
        queryParameters: {'inline': inline},
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(minutes: 3),
        ),
      );
      return Uint8List.fromList(resp.data as List<int>);
    } on DioException catch (e) {
      throw ApiException(
        'Could not load the document. Please try again.',
        e.response?.statusCode ?? 500,
      );
    }
  }

  Future<void> delete(String recordId) async {
    await _api.delete('/medical-records/$recordId');
  }
}

/// Saves downloaded bytes to the device and returns the saved path.
Future<String> saveRecordToDevice(String fileName, Uint8List bytes) async {
  if (kIsWeb) {
    throw ApiException('Download to device is not supported on web yet.', 400);
  }
  Directory? dir;
  try {
    dir = await getDownloadsDirectory();
  } catch (_) {}
  dir ??= await getApplicationDocumentsDirectory();

  // Avoid overwriting an existing file with the same name.
  var target = File('${dir.path}${Platform.pathSeparator}$fileName');
  var counter = 1;
  while (await target.exists()) {
    final dot = fileName.lastIndexOf('.');
    final base = dot > 0 ? fileName.substring(0, dot) : fileName;
    final ext = dot > 0 ? fileName.substring(dot) : '';
    target = File('${dir.path}${Platform.pathSeparator}$base ($counter)$ext');
    counter++;
  }
  await target.writeAsBytes(bytes);
  return target.path;
}

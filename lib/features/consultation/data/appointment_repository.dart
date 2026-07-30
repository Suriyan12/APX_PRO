import 'package:apx_pro/core/network/api_client.dart';
import 'package:apx_pro/features/consultation/data/appointment_model.dart';

class AppointmentRepository {
  AppointmentRepository(this._client);

  final ApiClient _client;

  Future<List<AppointmentModel>> fetchMyAppointments() async {
    final resp = await _client.get('/appointments/my');
    final list = resp.data as List;
    return list
        .map((e) => AppointmentModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Admin/therapist: a single patient's appointment history, newest first.
  Future<List<AppointmentModel>> fetchForPatient(String patientId) async {
    final resp = await _client.get('/appointments/patient/$patientId');
    final list = resp.data as List;
    return list
        .map((e) => AppointmentModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<AppointmentModel> book({
    required String startTime,
    required String endTime,
    String? notes,
    String consultationType = 'physical',
  }) async {
    final resp = await _client.post('/appointments/book', data: {
      'start_time': startTime,
      'end_time': endTime,
      'consultation_type': consultationType,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
    });
    return AppointmentModel.fromJson(resp.data as Map<String, dynamic>);
  }

  /// Admin: approve an appointment. For an online consult, pass the validated
  /// meeting provider + link (the backend re-validates the URL).
  Future<AppointmentModel> approve(
    String id, {
    String? meetingProvider,
    String? meetingLink,
  }) async {
    final resp = await _client.put('/appointments/$id/approve', data: {
      if (meetingProvider != null) 'meeting_provider': meetingProvider,
      if (meetingLink != null) 'meeting_link': meetingLink,
    });
    return AppointmentModel.fromJson(resp.data as Map<String, dynamic>);
  }

  /// Admin: reject a pending appointment with an optional reason.
  Future<AppointmentModel> reject(String id, {String? reason}) async {
    final resp = await _client.put('/appointments/$id/reject', data: {
      if (reason != null && reason.isNotEmpty) 'reason': reason,
    });
    return AppointmentModel.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<AppointmentModel> cancel(String id) async {
    final resp = await _client.put('/appointments/$id/cancel');
    return AppointmentModel.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<AppointmentModel> reschedule(
    String id, {
    required String startTime,
    required String endTime,
    String? notes,
  }) async {
    final resp = await _client.put('/appointments/$id/reschedule', data: {
      'start_time': startTime,
      'end_time': endTime,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
    });
    return AppointmentModel.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<List<SlotModel>> fetchAvailableSlots(String dateStr) async {
    final resp = await _client.get(
      '/appointments/available-slots',
      queryParameters: {'date_str': dateStr},
    );
    final list = resp.data as List;
    return list
        .map((e) => SlotModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

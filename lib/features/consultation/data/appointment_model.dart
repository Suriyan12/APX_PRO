import 'package:flutter/foundation.dart';

@immutable
class AppointmentModel {
  final String id;
  final String patientId;
  final String? patientName;
  final String? adminId;
  final DateTime startTime;
  final DateTime endTime;
  final String status;
  final String? notes;
  final double consultationFee;
  final double discountAmount;
  final double finalAmount;
  final String? discountCodeUsed;
  final DateTime createdAt;
  // Physical vs online consultation + (online, once approved) the meeting link.
  final String consultationType; // 'physical' | 'online'
  final String? meetingProvider; // e.g. 'google_meet'
  final String? meetingLink;
  final String? cancellationReason;

  const AppointmentModel({
    required this.id,
    required this.patientId,
    this.patientName,
    this.adminId,
    required this.startTime,
    required this.endTime,
    required this.status,
    this.notes,
    required this.consultationFee,
    required this.discountAmount,
    required this.finalAmount,
    this.discountCodeUsed,
    required this.createdAt,
    this.consultationType = 'physical',
    this.meetingProvider,
    this.meetingLink,
    this.cancellationReason,
  });

  // ── Status helpers ──────────────────────────────────────────────────────────

  bool get isCancelled => status == 'cancelled' || status == 'rejected';
  bool get isCompleted => status == 'completed';
  bool get isActive => !isCancelled && !isCompleted;
  // 'rescheduled' is legacy — a reschedule now returns the appointment to
  // 'pending' for re-approval, so only 'approved'/'scheduled' are "confirmed".
  bool get isPending => status == 'pending' || status == 'rescheduled';
  bool get isApproved => status == 'approved' || status == 'scheduled';
  bool get isOnline => consultationType == 'online';

  /// Minutes until the appointment starts (negative once it has started).
  int get minutesUntilStart => startTime.difference(DateTime.now()).inMinutes;

  /// The Join button unlocks 15 minutes before an approved online consult and
  /// stays available until 2 hours after the start (grace for a running call).
  bool get canJoinNow {
    if (!isOnline || !isApproved) return false;
    if (meetingLink == null || meetingLink!.isEmpty) return false;
    final now = DateTime.now();
    final opens = startTime.subtract(const Duration(minutes: 15));
    final closes = startTime.add(const Duration(hours: 2));
    return now.isAfter(opens) && now.isBefore(closes);
  }

  bool get isUpcoming {
    if (!isActive) return false;
    final now = DateTime.now();
    final recentlyStarted =
        startTime.isBefore(now) && now.difference(startTime).inHours < 2;
    return startTime.isAfter(now) || recentlyStarted;
  }

  bool get isPast {
    if (isCancelled || isCompleted) return true;
    final now = DateTime.now();
    return startTime.isBefore(now) && now.difference(startTime).inHours >= 2;
  }

  // ── Serialisation ───────────────────────────────────────────────────────────

  /// All API datetimes are UTC. The backend now sends an explicit +00:00
  /// offset, but if an offset is ever missing, Dart's `DateTime.parse` would
  /// silently treat the value as DEVICE-LOCAL time — so we force UTC first,
  /// then convert to local for display.
  static DateTime parseApiUtc(String iso) {
    final parsed = DateTime.parse(iso);
    if (parsed.isUtc) return parsed.toLocal();
    // Offset-less string: reinterpret the wall-clock as UTC.
    return DateTime.utc(parsed.year, parsed.month, parsed.day, parsed.hour,
            parsed.minute, parsed.second, parsed.millisecond)
        .toLocal();
  }

  factory AppointmentModel.fromJson(Map<String, dynamic> json) {
    return AppointmentModel(
      id: json['id'] as String,
      patientId: json['patient_id'] as String,
      patientName: json['patient_name'] as String?,
      adminId: json['admin_id'] as String?,
      startTime: parseApiUtc(json['start_time'] as String),
      endTime: parseApiUtc(json['end_time'] as String),
      status: json['status'] as String,
      notes: json['notes'] as String?,
      consultationFee: _toDouble(json['consultation_fee']),
      discountAmount: _toDouble(json['discount_amount']),
      finalAmount: _toDouble(json['final_amount']),
      discountCodeUsed: json['discount_code_used'] as String?,
      createdAt: parseApiUtc(json['created_at'] as String),
      consultationType: (json['consultation_type'] as String?) ?? 'physical',
      meetingProvider: json['meeting_provider'] as String?,
      meetingLink: json['meeting_link'] as String?,
      cancellationReason: json['cancellation_reason'] as String?,
    );
  }

  AppointmentModel copyWith({String? status}) {
    return AppointmentModel(
      id: id,
      patientId: patientId,
      patientName: patientName,
      adminId: adminId,
      startTime: startTime,
      endTime: endTime,
      status: status ?? this.status,
      notes: notes,
      consultationFee: consultationFee,
      discountAmount: discountAmount,
      finalAmount: finalAmount,
      discountCodeUsed: discountCodeUsed,
      createdAt: createdAt,
      consultationType: consultationType,
      meetingProvider: meetingProvider,
      meetingLink: meetingLink,
      cancellationReason: cancellationReason,
    );
  }

  static double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }
}

@immutable
class SlotModel {
  final DateTime startTime;
  final DateTime endTime;
  final String startIso;
  final String endIso;

  const SlotModel({
    required this.startTime,
    required this.endTime,
    required this.startIso,
    required this.endIso,
  });

  factory SlotModel.fromJson(Map<String, dynamic> json) {
    final startIso = json['start_time'] as String;
    final endIso = json['end_time'] as String;
    return SlotModel(
      startTime: DateTime.parse(startIso).toLocal(),
      endTime: DateTime.parse(endIso).toLocal(),
      startIso: startIso,
      endIso: endIso,
    );
  }
}

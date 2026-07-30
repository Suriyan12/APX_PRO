import 'package:flutter/foundation.dart';

/// A single in-app notification, mirroring the backend NotificationResponse.
@immutable
class NotificationModel {
  final String id;
  final String title;
  final String body;
  final String? type;
  final Map<String, dynamic>? data; // deep-link payload
  final bool isRead;
  final DateTime? readAt;
  final DateTime createdAt;

  const NotificationModel({
    required this.id,
    required this.title,
    required this.body,
    this.type,
    this.data,
    required this.isRead,
    this.readAt,
    required this.createdAt,
  });

  /// Backend datetimes carry an explicit UTC offset; parse then localize.
  static DateTime _parseUtc(String iso) => DateTime.parse(iso).toLocal();

  factory NotificationModel.fromJson(Map<String, dynamic> j) {
    return NotificationModel(
      id: j['id'] as String,
      title: j['title'] as String? ?? '',
      body: j['body'] as String? ?? '',
      type: j['type'] as String?,
      data: (j['data'] as Map?)?.cast<String, dynamic>(),
      isRead: j['is_read'] as bool? ?? false,
      readAt: j['read_at'] != null ? _parseUtc(j['read_at'] as String) : null,
      createdAt: _parseUtc(j['created_at'] as String),
    );
  }

  NotificationModel copyWith({bool? isRead, DateTime? readAt}) {
    return NotificationModel(
      id: id,
      title: title,
      body: body,
      type: type,
      data: data,
      isRead: isRead ?? this.isRead,
      readAt: readAt ?? this.readAt,
      createdAt: createdAt,
    );
  }

  /// The deep-link route the client should open when this notification is
  /// tapped, if the payload provides one.
  String? get deepLinkRoute => data?['route'] as String?;
  String? get appointmentId => data?['appointment_id'] as String?;
}

/// One page of notifications plus the total, for lazy pagination.
@immutable
class NotificationPage {
  final List<NotificationModel> items;
  final int total;
  final int limit;
  final int offset;

  const NotificationPage({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
  });

  factory NotificationPage.fromJson(Map<String, dynamic> j) {
    final raw = j['items'] as List<dynamic>? ?? [];
    return NotificationPage(
      items: raw
          .map((e) => NotificationModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: (j['total'] as num?)?.toInt() ?? 0,
      limit: (j['limit'] as num?)?.toInt() ?? raw.length,
      offset: (j['offset'] as num?)?.toInt() ?? 0,
    );
  }
}

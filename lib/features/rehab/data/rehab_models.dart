import 'package:flutter/foundation.dart';

enum ExerciseType { reps, timed }

enum VideoType { none, youtube, upload }

enum RehabDifficulty { easy, moderate, hard }

@immutable
class RehabExerciseModel {
  final String id;
  final String programId;
  final String name;
  final String? description;
  final String? instructions;
  final ExerciseType exerciseType;
  final int sets;
  final int? reps;
  final int? durationSeconds;
  final int restSeconds;
  final RehabDifficulty difficulty;
  final String? targetArea;
  final String? notes;
  final VideoType videoType;
  final String? videoUrl;
  final String? videoPath;
  final int? videoFileSize;   // bytes — uploaded (Drive) videos only
  final String? videoMimeType;
  final int orderIndex;

  const RehabExerciseModel({
    required this.id,
    required this.programId,
    required this.name,
    this.description,
    this.instructions,
    required this.exerciseType,
    required this.sets,
    this.reps,
    this.durationSeconds,
    required this.restSeconds,
    required this.difficulty,
    this.targetArea,
    this.notes,
    required this.videoType,
    this.videoUrl,
    this.videoPath,
    this.videoFileSize,
    this.videoMimeType,
    required this.orderIndex,
  });

  factory RehabExerciseModel.fromJson(Map<String, dynamic> j) {
    return RehabExerciseModel(
      id: j['id'] as String,
      programId: j['program_id'] as String,
      name: j['name'] as String,
      description: j['description'] as String?,
      instructions: j['instructions'] as String?,
      exerciseType: j['exercise_type'] == 'timed' ? ExerciseType.timed : ExerciseType.reps,
      sets: (j['sets'] as num).toInt(),
      reps: j['reps'] != null ? (j['reps'] as num).toInt() : null,
      durationSeconds: j['duration_seconds'] != null ? (j['duration_seconds'] as num).toInt() : null,
      restSeconds: (j['rest_seconds'] as num).toInt(),
      difficulty: _parseDifficulty(j['difficulty'] as String? ?? 'moderate'),
      targetArea: j['target_area'] as String?,
      notes: j['notes'] as String?,
      videoType: _parseVideoType(j['video_type'] as String? ?? 'none'),
      videoUrl: j['video_url'] as String?,
      videoPath: j['video_path'] as String?,
      videoFileSize: j['video_file_size'] != null ? (j['video_file_size'] as num).toInt() : null,
      videoMimeType: j['video_mime_type'] as String?,
      orderIndex: (j['order_index'] as num).toInt(),
    );
  }

  static RehabDifficulty _parseDifficulty(String v) {
    switch (v) {
      case 'easy':
        return RehabDifficulty.easy;
      case 'hard':
        return RehabDifficulty.hard;
      default:
        return RehabDifficulty.moderate;
    }
  }

  static VideoType _parseVideoType(String v) {
    switch (v) {
      case 'youtube':
        return VideoType.youtube;
      case 'upload':
        return VideoType.upload;
      default:
        return VideoType.none;
    }
  }

  /// Extracts the 11-character YouTube video id from any common URL shape:
  /// watch?v=ID, youtu.be/ID, shorts/ID, embed/ID, live/ID, or a bare id.
  String? get youtubeVideoId {
    if (videoType != VideoType.youtube || videoUrl == null) return null;
    return extractYouTubeId(videoUrl!);
  }

  static final _ytIdPattern = RegExp(r'^[A-Za-z0-9_-]{11}$');

  static String? extractYouTubeId(String url) {
    final raw = url.trim();
    if (_ytIdPattern.hasMatch(raw)) return raw; // bare video id
    final uri = Uri.tryParse(raw);
    if (uri == null) return null;

    String? candidate;
    if (uri.host == 'youtu.be') {
      candidate = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    } else if (uri.host.endsWith('youtube.com') ||
        uri.host.endsWith('youtube-nocookie.com')) {
      final segs = uri.pathSegments;
      if (uri.queryParameters['v'] != null) {
        candidate = uri.queryParameters['v'];
      } else if (segs.length >= 2 &&
          const {'shorts', 'embed', 'live', 'v'}.contains(segs.first)) {
        candidate = segs[1];
      }
    }
    if (candidate != null && _ytIdPattern.hasMatch(candidate)) return candidate;
    return null;
  }

  String? get youtubeThumbnail {
    final id = youtubeVideoId;
    return id != null ? 'https://img.youtube.com/vi/$id/hqdefault.jpg' : null;
  }

  String get difficultyLabel {
    switch (difficulty) {
      case RehabDifficulty.easy:
        return 'Easy';
      case RehabDifficulty.hard:
        return 'Hard';
      case RehabDifficulty.moderate:
        return 'Moderate';
    }
  }
}

@immutable
class RehabProgramModel {
  final String id;
  final String patientId;
  final String createdBy;
  final String title;
  final String? description;
  final int estimatedDurationDays;
  final bool isActive;
  final DateTime createdAt;
  final List<RehabExerciseModel> exercises;

  const RehabProgramModel({
    required this.id,
    required this.patientId,
    required this.createdBy,
    required this.title,
    this.description,
    required this.estimatedDurationDays,
    required this.isActive,
    required this.createdAt,
    required this.exercises,
  });

  factory RehabProgramModel.fromJson(Map<String, dynamic> j) {
    final rawEx = j['exercises'] as List<dynamic>? ?? [];
    return RehabProgramModel(
      id: j['id'] as String,
      patientId: j['patient_id'] as String,
      createdBy: j['created_by'] as String,
      title: j['title'] as String,
      description: j['description'] as String?,
      estimatedDurationDays: (j['estimated_duration_days'] as num).toInt(),
      isActive: j['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
      exercises: rawEx.map((e) => RehabExerciseModel.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}

@immutable
class RehabProgramListItem {
  final String id;
  final String patientId;
  final String title;
  final String? description;
  final int estimatedDurationDays;
  final bool isActive;
  final int exerciseCount;
  final DateTime createdAt;

  const RehabProgramListItem({
    required this.id,
    required this.patientId,
    required this.title,
    this.description,
    required this.estimatedDurationDays,
    required this.isActive,
    required this.exerciseCount,
    required this.createdAt,
  });

  factory RehabProgramListItem.fromJson(Map<String, dynamic> j) {
    return RehabProgramListItem(
      id: j['id'] as String,
      patientId: j['patient_id'] as String,
      title: j['title'] as String,
      description: j['description'] as String?,
      estimatedDurationDays: (j['estimated_duration_days'] as num).toInt(),
      isActive: j['is_active'] as bool? ?? false,
      exerciseCount: (j['exercise_count'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
    );
  }
}

@immutable
class RehabProgressModel {
  final int streakDays;
  final int totalSessions;
  final int totalMinutes;
  final double completionPercent;
  final DateTime? lastCompletedAt;

  const RehabProgressModel({
    required this.streakDays,
    required this.totalSessions,
    required this.totalMinutes,
    required this.completionPercent,
    this.lastCompletedAt,
  });

  factory RehabProgressModel.fromJson(Map<String, dynamic> j) {
    return RehabProgressModel(
      streakDays: (j['streak_days'] as num?)?.toInt() ?? 0,
      totalSessions: (j['total_sessions'] as num?)?.toInt() ?? 0,
      totalMinutes: (j['total_minutes'] as num?)?.toInt() ?? 0,
      completionPercent: (j['completion_percent'] as num?)?.toDouble() ?? 0.0,
      lastCompletedAt: j['last_completed_at'] != null
          ? DateTime.parse(j['last_completed_at'] as String).toLocal()
          : null,
    );
  }

  static const empty = RehabProgressModel(
    streakDays: 0,
    totalSessions: 0,
    totalMinutes: 0,
    completionPercent: 0.0,
  );
}

@immutable
class RehabSessionModel {
  final String id;
  final String patientId;
  final String programId;
  final DateTime startedAt;
  final DateTime? completedAt;
  final bool isCompleted;
  final int exercisesTotal;
  final int exercisesCompleted;
  final int? durationSeconds;

  const RehabSessionModel({
    required this.id,
    required this.patientId,
    required this.programId,
    required this.startedAt,
    this.completedAt,
    required this.isCompleted,
    required this.exercisesTotal,
    required this.exercisesCompleted,
    this.durationSeconds,
  });

  factory RehabSessionModel.fromJson(Map<String, dynamic> j) {
    return RehabSessionModel(
      id: j['id'] as String,
      patientId: j['patient_id'] as String,
      programId: j['program_id'] as String,
      startedAt: DateTime.parse(j['started_at'] as String).toLocal(),
      completedAt: j['completed_at'] != null
          ? DateTime.parse(j['completed_at'] as String).toLocal()
          : null,
      isCompleted: j['is_completed'] as bool? ?? false,
      exercisesTotal: (j['exercises_total'] as num).toInt(),
      exercisesCompleted: (j['exercises_completed'] as num?)?.toInt() ?? 0,
      durationSeconds: j['duration_seconds'] != null ? (j['duration_seconds'] as num).toInt() : null,
    );
  }
}

@immutable
class RehabMyProgramData {
  final RehabProgramModel program;
  final RehabProgressModel progress;
  final RehabSessionModel? todaySession;

  const RehabMyProgramData({
    required this.program,
    required this.progress,
    this.todaySession,
  });
}

/// Admin/therapist view of a patient's ACTIVE-program workout progress.
/// Every metric is scoped to the active program only, so each program keeps
/// its own independent progress. Mirrors the backend `/rehab/patients/{id}/progress`.
enum WorkoutTodayStatus { notStarted, inProgress, completed }

@immutable
class WorkoutDashboardModel {
  final bool hasActiveProgram;
  final String? programId;
  final String? programTitle;
  final int? estimatedDurationDays;
  final double overallProgressPercent; // 0..100
  final WorkoutTodayStatus todayStatus;
  final DateTime? lastCompletedAt;
  final int assignedSessions;
  final int completedSessions;
  final int remainingSessions;
  final double compliancePercent; // 0..100

  const WorkoutDashboardModel({
    required this.hasActiveProgram,
    this.programId,
    this.programTitle,
    this.estimatedDurationDays,
    required this.overallProgressPercent,
    required this.todayStatus,
    this.lastCompletedAt,
    required this.assignedSessions,
    required this.completedSessions,
    required this.remainingSessions,
    required this.compliancePercent,
  });

  factory WorkoutDashboardModel.fromJson(Map<String, dynamic> j) {
    return WorkoutDashboardModel(
      hasActiveProgram: j['has_active_program'] as bool? ?? false,
      programId: j['program_id'] as String?,
      programTitle: j['program_title'] as String?,
      estimatedDurationDays: (j['estimated_duration_days'] as num?)?.toInt(),
      overallProgressPercent:
          (j['overall_progress_percent'] as num?)?.toDouble() ?? 0.0,
      todayStatus: _parseTodayStatus(j['today_status'] as String?),
      lastCompletedAt: j['last_completed_at'] != null
          ? DateTime.parse(j['last_completed_at'] as String).toLocal()
          : null,
      assignedSessions: (j['assigned_sessions'] as num?)?.toInt() ?? 0,
      completedSessions: (j['completed_sessions'] as num?)?.toInt() ?? 0,
      remainingSessions: (j['remaining_sessions'] as num?)?.toInt() ?? 0,
      compliancePercent: (j['compliance_percent'] as num?)?.toDouble() ?? 0.0,
    );
  }

  static WorkoutTodayStatus _parseTodayStatus(String? v) {
    switch (v) {
      case 'completed':
        return WorkoutTodayStatus.completed;
      case 'in_progress':
        return WorkoutTodayStatus.inProgress;
      default:
        return WorkoutTodayStatus.notStarted;
    }
  }

  /// 0.0..1.0 for LinearProgressIndicator.
  double get overallFraction => (overallProgressPercent / 100).clamp(0.0, 1.0);
}

/// One row of a patient's workout history.
/// Mirrors the backend `/rehab/patients/{id}/sessions` items.
@immutable
class WorkoutHistoryItemModel {
  final String id;
  final String programId;
  final String programTitle;
  final DateTime? sessionDate;
  final DateTime startedAt;
  final DateTime? completedAt;
  final WorkoutTodayStatus status;
  final int? durationSeconds;
  final int exercisesTotal;
  final int exercisesCompleted;

  const WorkoutHistoryItemModel({
    required this.id,
    required this.programId,
    required this.programTitle,
    this.sessionDate,
    required this.startedAt,
    this.completedAt,
    required this.status,
    this.durationSeconds,
    required this.exercisesTotal,
    required this.exercisesCompleted,
  });

  factory WorkoutHistoryItemModel.fromJson(Map<String, dynamic> j) {
    return WorkoutHistoryItemModel(
      id: j['id'] as String,
      programId: j['program_id'] as String,
      programTitle: j['program_title'] as String? ?? '—',
      sessionDate: j['session_date'] != null
          ? DateTime.parse(j['session_date'] as String)
          : null,
      startedAt: DateTime.parse(j['started_at'] as String).toLocal(),
      completedAt: j['completed_at'] != null
          ? DateTime.parse(j['completed_at'] as String).toLocal()
          : null,
      status: WorkoutDashboardModel._parseTodayStatus(j['status'] as String?),
      durationSeconds:
          j['duration_seconds'] != null ? (j['duration_seconds'] as num).toInt() : null,
      exercisesTotal: (j['exercises_total'] as num?)?.toInt() ?? 0,
      exercisesCompleted: (j['exercises_completed'] as num?)?.toInt() ?? 0,
    );
  }

  bool get isCompleted => status == WorkoutTodayStatus.completed;
}

/// One page of workout history plus the total (for lazy pagination).
@immutable
class WorkoutHistoryPage {
  final List<WorkoutHistoryItemModel> items;
  final int total;
  final int limit;
  final int offset;

  const WorkoutHistoryPage({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
  });

  factory WorkoutHistoryPage.fromJson(Map<String, dynamic> j) {
    final raw = j['items'] as List<dynamic>? ?? [];
    return WorkoutHistoryPage(
      items: raw
          .map((e) => WorkoutHistoryItemModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: (j['total'] as num?)?.toInt() ?? 0,
      limit: (j['limit'] as num?)?.toInt() ?? raw.length,
      offset: (j['offset'] as num?)?.toInt() ?? 0,
    );
  }
}

@immutable
class ExerciseResult {
  final String exerciseId;
  final int setsCompleted;
  final bool isSkipped;
  final int? actualDurationSeconds;

  const ExerciseResult({
    required this.exerciseId,
    required this.setsCompleted,
    this.isSkipped = false,
    this.actualDurationSeconds,
  });

  Map<String, dynamic> toJson() => {
        'exercise_id': exerciseId,
        'sets_completed': setsCompleted,
        'is_skipped': isSkipped,
        if (actualDurationSeconds != null) 'actual_duration_seconds': actualDurationSeconds,
      };
}

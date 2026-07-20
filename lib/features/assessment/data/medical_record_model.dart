class MedicalRecord {
  final String id;
  final String patientId;
  final String fileName;
  final String fileExtension;
  final String mimeType;
  final int fileSize;
  final String? category;
  final DateTime uploadedAt;
  final String status;

  const MedicalRecord({
    required this.id,
    required this.patientId,
    required this.fileName,
    required this.fileExtension,
    required this.mimeType,
    required this.fileSize,
    required this.uploadedAt,
    required this.status,
    this.category,
  });

  factory MedicalRecord.fromJson(Map<String, dynamic> json) {
    return MedicalRecord(
      id: json['id'] as String,
      patientId: json['patient_id'] as String,
      fileName: json['file_name'] as String? ?? 'Document',
      fileExtension: json['file_extension'] as String? ?? '',
      mimeType: json['mime_type'] as String? ?? '',
      fileSize: (json['file_size'] as num?)?.toInt() ?? 0,
      category: json['category'] as String?,
      uploadedAt: DateTime.tryParse(json['uploaded_at'] as String? ?? '') ??
          DateTime.now(),
      status: json['status'] as String? ?? 'active',
    );
  }

  bool get isPdf => mimeType.contains('pdf');
  bool get isImage => mimeType.startsWith('image/');

  String get formattedSize {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

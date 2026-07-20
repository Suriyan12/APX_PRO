class NoteModel {
  final String id;
  final String title;
  final String? description;
  final String category;
  final String? tags;
  final String fileName;
  final String fileType;
  final int fileSize;
  final DateTime uploadedAt;
  final DateTime updatedAt;
  final bool isActive;
  final String? uploadedBy;

  NoteModel({
    required this.id,
    required this.title,
    this.description,
    required this.category,
    this.tags,
    required this.fileName,
    required this.fileType,
    required this.fileSize,
    required this.uploadedAt,
    required this.updatedAt,
    this.isActive = true,
    this.uploadedBy,
  });

  factory NoteModel.fromJson(Map<String, dynamic> json) {
    return NoteModel(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      category: json['category'] as String,
      tags: json['tags'] as String?,
      fileName: json['file_name'] as String,
      fileType: (json['file_type'] as String).toLowerCase(),
      fileSize: json['file_size'] as int,
      uploadedAt: DateTime.parse(json['uploaded_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      isActive: (json['is_active'] as bool?) ?? true,
      uploadedBy: json['uploaded_by'] as String?,
    );
  }

  List<String> get tagList =>
      tags?.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList() ??
      [];

  bool get isPdf => fileType == 'pdf';
  bool get isImage => ['jpg', 'jpeg', 'png'].contains(fileType);
  bool get isText => fileType == 'txt';
  bool get isOffice => ['doc', 'docx', 'ppt', 'pptx'].contains(fileType);

  String get fileTypeLabel {
    switch (fileType) {
      case 'pdf':
        return 'PDF';
      case 'doc':
        return 'DOC';
      case 'docx':
        return 'DOCX';
      case 'ppt':
        return 'PPT';
      case 'pptx':
        return 'PPTX';
      case 'jpg':
      case 'jpeg':
        return 'JPEG';
      case 'png':
        return 'PNG';
      case 'txt':
        return 'TXT';
      default:
        return fileType.toUpperCase();
    }
  }

  String get formattedSize {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

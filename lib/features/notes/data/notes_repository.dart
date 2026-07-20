import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:apx_pro/core/network/api_client.dart';
import 'package:apx_pro/features/notes/data/note_model.dart';

class NotesRepository {
  final ApiClient _client;

  NotesRepository(this._client);

  Future<Map<String, dynamic>> getAccessStatus() async {
    final response = await _client.get('/notes/access-status');
    return response.data as Map<String, dynamic>;
  }

  Future<List<NoteModel>> listNotes({String? category, String? search}) async {
    final params = <String, dynamic>{};
    if (category != null) params['category'] = category;
    if (search != null) params['search'] = search;

    final response = await _client.get(
      '/notes',
      queryParameters: params.isNotEmpty ? params : null,
    );
    final list = response.data as List<dynamic>;
    return list
        .map((e) => NoteModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<String>> getCategories() async {
    final response = await _client.get('/notes/categories');
    final list = response.data as List<dynamic>;
    return list.map((e) => e as String).toList();
  }

  Future<NoteModel> getNote(String id) async {
    final response = await _client.get('/notes/$id');
    return NoteModel.fromJson(response.data as Map<String, dynamic>);
  }

  /// Authoritative access check for a note. Does a tiny 1-byte ranged request
  /// against the viewer endpoint: 2xx means the backend will serve the file,
  /// a 403 means the pack must be purchased first. Avoids feeding a 403 body
  /// to the PDF renderer.
  Future<bool> canView(String id) async {
    try {
      await _client.get(
        '/notes/$id/viewer',
        options: Options(
          responseType: ResponseType.bytes,
          headers: {'Range': 'bytes=0-0'},
          receiveTimeout: const Duration(seconds: 30),
        ),
      );
      return true;
    } on ApiException catch (e) {
      if (e.statusCode == 403) return false;
      rethrow;
    }
  }

  Future<({Uint8List bytes, String contentType})> viewNote(String id) async {
    final response = await _client.get(
      '/notes/$id/viewer',
      options: Options(
        responseType: ResponseType.bytes,
        // Backend fetches the file from Google Drive before responding; large
        // materials (up to 250 MB) take far longer than the default 15 s.
        receiveTimeout: const Duration(minutes: 10),
      ),
    );
    final bytes = Uint8List.fromList(response.data as List<int>);
    final contentType =
        response.headers.value('content-type') ?? 'application/octet-stream';
    return (bytes: bytes, contentType: contentType);
  }

  Future<Map<String, dynamic>> purchaseNotes() async {
    final response = await _client.post('/notes/purchase');
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> verifyPurchase({
    required String orderId,
    required String paymentId,
    required String signature,
  }) async {
    final response = await _client.post(
      '/notes/purchase/verify',
      data: {
        'razorpay_order_id': orderId,
        'razorpay_payment_id': paymentId,
        'razorpay_signature': signature,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  // Admin methods

  Future<List<NoteModel>> adminListNotes({
    String? category,
    String? search,
  }) async {
    final params = <String, dynamic>{};
    if (category != null) params['category'] = category;
    if (search != null) params['search'] = search;

    final response = await _client.get(
      '/notes/admin/all',
      queryParameters: params.isNotEmpty ? params : null,
    );
    final list = response.data as List<dynamic>;
    return list
        .map((e) => NoteModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<NoteModel> uploadNote({
    required String title,
    required String category,
    String? description,
    String? tags,
    required Uint8List fileBytes,
    required String fileName,
  }) async {
    final formData = FormData.fromMap({
      'title': title,
      'category': category,
      if (description != null) 'description': description,
      if (tags != null) 'tags': tags,
      'file': MultipartFile.fromBytes(fileBytes, filename: fileName),
    });

    final response = await _client.post(
      '/notes/upload',
      data: formData,
      options: Options(
        contentType: 'multipart/form-data',
        // Large files (up to 250 MB) are streamed to Google Drive server-side
        // before the response returns — override the default 15 s timeouts.
        sendTimeout: const Duration(minutes: 10),
        receiveTimeout: const Duration(minutes: 10),
      ),
    );
    return NoteModel.fromJson(response.data as Map<String, dynamic>);
  }

  Future<NoteModel> updateNote({
    required String id,
    String? title,
    String? category,
    String? description,
    String? tags,
    Uint8List? fileBytes,
    String? fileName,
  }) async {
    final fields = <String, dynamic>{};
    if (title != null) fields['title'] = title;
    if (category != null) fields['category'] = category;
    if (description != null) fields['description'] = description;
    if (tags != null) fields['tags'] = tags;
    if (fileBytes != null && fileName != null) {
      fields['file'] = MultipartFile.fromBytes(fileBytes, filename: fileName);
    }

    final formData = FormData.fromMap(fields);
    final response = await _client.put(
      '/notes/$id',
      data: formData,
      options: Options(
        contentType: 'multipart/form-data',
        sendTimeout: const Duration(minutes: 10),
        receiveTimeout: const Duration(minutes: 10),
      ),
    );
    return NoteModel.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteNote(String id) async {
    await _client.delete('/notes/$id');
  }
}

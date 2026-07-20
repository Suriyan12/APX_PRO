import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apx_pro/core/network/api_client.dart';
import 'package:apx_pro/features/auth/presentation/controllers/auth_controller.dart';
import 'package:apx_pro/features/notes/data/note_model.dart';
import 'package:apx_pro/features/notes/data/notes_repository.dart';

class NotesState {
  final bool hasAccess;
  final bool isAdmin;
  final bool loadingAccess;
  final List<NoteModel> notes;
  final bool loadingNotes;
  final String? errorMessage;
  final String searchQuery;
  final String? selectedCategory;
  final List<String> categories;

  const NotesState({
    this.hasAccess = false,
    this.isAdmin = false,
    this.loadingAccess = true,
    this.notes = const [],
    this.loadingNotes = false,
    this.errorMessage,
    this.searchQuery = '',
    this.selectedCategory,
    this.categories = const [],
  });

  NotesState copyWith({
    bool? hasAccess,
    bool? isAdmin,
    bool? loadingAccess,
    List<NoteModel>? notes,
    bool? loadingNotes,
    String? errorMessage,
    bool clearError = false,
    String? searchQuery,
    Object? selectedCategory = _sentinel,
    List<String>? categories,
  }) {
    return NotesState(
      hasAccess: hasAccess ?? this.hasAccess,
      isAdmin: isAdmin ?? this.isAdmin,
      loadingAccess: loadingAccess ?? this.loadingAccess,
      notes: notes ?? this.notes,
      loadingNotes: loadingNotes ?? this.loadingNotes,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      searchQuery: searchQuery ?? this.searchQuery,
      selectedCategory: identical(selectedCategory, _sentinel)
          ? this.selectedCategory
          : selectedCategory as String?,
      categories: categories ?? this.categories,
    );
  }

  static const Object _sentinel = Object();
}

class NotesController extends StateNotifier<NotesState> {
  final NotesRepository _repo;
  Timer? _searchDebounce;
  int _loadSeq = 0; // guards against a slow older response overwriting a newer one

  NotesController(this._repo) : super(const NotesState()) {
    init();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> init() async {
    await Future.wait([checkAccess(), loadNotes(), loadCategories()]);
  }

  Future<void> checkAccess() async {
    try {
      final data = await _repo.getAccessStatus();
      state = state.copyWith(
        hasAccess: data['has_access'] as bool,
        isAdmin: data['is_admin'] as bool,
        loadingAccess: false,
      );
    } catch (_) {
      state = state.copyWith(loadingAccess: false);
    }
  }

  Future<void> loadNotes() async {
    final seq = ++_loadSeq;
    state = state.copyWith(loadingNotes: true, clearError: true);
    try {
      final notes = await _repo.listNotes(
        category: state.selectedCategory,
        search: state.searchQuery.isNotEmpty ? state.searchQuery : null,
      );
      if (seq != _loadSeq) return; // a newer search/filter superseded this one
      state = state.copyWith(notes: notes, loadingNotes: false);
    } catch (e) {
      if (seq != _loadSeq) return;
      state = state.copyWith(
        loadingNotes: false,
        errorMessage: e is ApiException ? e.message : 'Could not load study materials.',
      );
    }
  }

  Future<void> loadCategories() async {
    try {
      final cats = await _repo.getCategories();
      state = state.copyWith(categories: cats);
    } catch (_) {}
  }

  void setSearch(String q) {
    state = state.copyWith(searchQuery: q);
    // Debounce so we don't fire a request on every keystroke; the sequence
    // guard in loadNotes drops any stale response that still lands late.
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), loadNotes);
  }

  void setCategory(String? cat) {
    state = state.copyWith(selectedCategory: cat);
    loadNotes();
  }

  Future<Map<String, dynamic>> purchaseNotes() async {
    return await _repo.purchaseNotes();
  }

  Future<bool> verifyPurchase({
    required String orderId,
    required String paymentId,
    required String signature,
  }) async {
    try {
      await _repo.verifyPurchase(
        orderId: orderId,
        paymentId: paymentId,
        signature: signature,
      );
      await checkAccess();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> deleteNote(String id) async {
    await _repo.deleteNote(id);
    await loadNotes();
  }
}

final notesRepositoryProvider = Provider<NotesRepository>((ref) {
  return NotesRepository(ref.watch(apiClientProvider));
});

final notesControllerProvider =
    StateNotifierProvider<NotesController, NotesState>((ref) {
  return NotesController(ref.watch(notesRepositoryProvider));
});

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:raze_store/app/theme_mode_controller.dart';
import 'package:raze_store/features/catalog/domain/catalog_categories.dart';

final customCatalogCategoriesProvider =
    NotifierProvider<CustomCatalogCategoriesController, List<String>>(
      CustomCatalogCategoriesController.new,
    );

class CustomCatalogCategoriesController extends Notifier<List<String>> {
  bool _changedSinceBuild = false;

  @override
  List<String> build() {
    _load();
    return const <String>[];
  }

  Future<void> addCategory(String value) async {
    final category = _validateName(value);
    if (isStarterCatalogCategory(category) || _contains(state, category)) {
      throw const CatalogCategoryException(
        'A category with this name already exists.',
      );
    }
    if (state.length >= maxCustomCatalogCategories) {
      throw const CatalogCategoryException(
        'The custom category limit has been reached.',
      );
    }
    await _persist(distinctCatalogCategories([...state, category]));
  }

  Future<void> deleteCategory(String value) async {
    final normalized = normalizeCatalogCategoryName(value).toLowerCase();
    if (normalized.isEmpty) return;
    final next = state
        .where((category) => category.toLowerCase() != normalized)
        .toList(growable: false);
    if (next.length == state.length) return;
    await _persist(next);
  }

  Future<void> _persist(List<String> next) async {
    final previous = state;
    final wasChangedSinceBuild = _changedSinceBuild;
    final nextState = List<String>.unmodifiable(next);
    _changedSinceBuild = true;
    state = nextState;
    try {
      final preferences = await ref.read(sharedPreferencesProvider.future);
      final saved = await preferences.setStringList(
        customCatalogCategoriesPreferenceKey,
        next,
      );
      if (!saved) throw StateError('save failed');
    } catch (_) {
      if (ref.mounted && identical(state, nextState)) state = previous;
      _changedSinceBuild = wasChangedSinceBuild;
      if (!wasChangedSinceBuild) await _load();
      rethrow;
    }
  }

  Future<void> _load() async {
    try {
      final preferences = await ref.read(sharedPreferencesProvider.future);
      final saved = preferences.getStringList(
        customCatalogCategoriesPreferenceKey,
      );
      if (!ref.mounted || _changedSinceBuild || saved == null) return;
      state = _sanitizeSavedCategories(saved);
    } catch (_) {
      // Defaults remain usable when a saved preference is malformed.
    }
  }

  static String _validateName(String value) {
    final category = normalizeCatalogCategoryName(value);
    if (category.isEmpty) {
      throw const CatalogCategoryException('Enter a category name.');
    }
    if (category.length > maxCatalogCategoryNameLength) {
      throw const CatalogCategoryException('The category name is too long.');
    }
    return category;
  }

  static List<String> _sanitizeSavedCategories(Iterable<String> values) {
    final result = <String>[];
    for (final value in values) {
      final normalized = normalizeCatalogCategoryName(value);
      if (normalized.isEmpty ||
          normalized.length > maxCatalogCategoryNameLength ||
          isStarterCatalogCategory(normalized) ||
          _contains(result, normalized)) {
        continue;
      }
      result.add(normalized);
      if (result.length == maxCustomCatalogCategories) break;
    }
    return distinctCatalogCategories(result);
  }

  static bool _contains(Iterable<String> values, String category) {
    final normalized = category.toLowerCase();
    return values.any((value) => value.toLowerCase() == normalized);
  }
}

final class CatalogCategoryException implements Exception {
  const CatalogCategoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

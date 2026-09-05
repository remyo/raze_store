import 'catalog_taxonomy.dart';

/// Starter categories that work offline for a typical Filipino sari-sari
/// store. Products still store category as plain text, so a future API can add
/// suggestions without a schema migration and owners can always type their own.
const customCatalogCategoriesPreferenceKey =
    'raze_store.catalog.custom_categories';
const maxCustomCatalogCategories = 30;
const maxCatalogCategoryNameLength = 48;

const List<String> starterCatalogCategories = [
  'Beverages',
  'Biscuits',
  'Bread',
  'Canned Goods',
  'Condiments',
  'Cooking Essentials',
  'Dairy',
  'Frozen Goods',
  'Household',
  'Instant Coffee & Drinks',
  'Instant Noodles',
  'Loose Goods',
  'Personal Care',
  'Rice & Grains',
  'School Supplies',
  'Snacks',
  'Sweets & Candy',
  'Tobacco',
];

/// Every selectable offline category, flattened for the existing single-value
/// product field. Repeated taxonomy leaves appear once in autocomplete while
/// [generalCatalogCategoryGroups] retains their parent memberships.
final List<String> builtInCatalogCategories = distinctCatalogCategories([
  ...starterCatalogCategories,
  ...generalCatalogCategoryNames,
  ...generalCatalogSubcategories,
]);

/// Combines offline defaults with device and future API values while keeping
/// one consistently-cased suggestion for each category.
List<String> mergeCatalogCategories({
  Iterable<String> customCategories = const [],
  Iterable<String> storedCategories = const [],
  Iterable<String> apiCategories = const [],
}) => distinctCatalogCategories([
  ...builtInCatalogCategories,
  ...customCategories,
  ...storedCategories,
  ...apiCategories,
]);

String normalizeCatalogCategoryName(String category) =>
    category.trim().replaceAll(RegExp(r'\s+'), ' ');

bool isBuiltInCatalogCategory(String category) {
  final normalized = normalizeCatalogCategoryName(category).toLowerCase();
  return builtInCatalogCategories.any(
    (candidate) => candidate.toLowerCase() == normalized,
  );
}

/// Backwards-compatible name used by stored custom-category validation.
bool isStarterCatalogCategory(String category) =>
    isBuiltInCatalogCategory(category);

List<String> distinctCatalogCategories(Iterable<String?> categories) {
  final byNormalizedName = <String, String>{};
  for (final category in categories) {
    final trimmed = category == null
        ? null
        : normalizeCatalogCategoryName(category);
    if (trimmed == null || trimmed.isEmpty) continue;
    byNormalizedName.putIfAbsent(trimmed.toLowerCase(), () => trimmed);
  }
  final result = byNormalizedName.values.toList(growable: false)
    ..sort((left, right) {
      final normalizedOrder = left.toLowerCase().compareTo(right.toLowerCase());
      return normalizedOrder != 0 ? normalizedOrder : left.compareTo(right);
    });
  return List<String>.unmodifiable(result);
}

Iterable<String> matchingCatalogCategories(
  String query, {
  Iterable<String>? categories,
}) {
  final availableCategories = categories ?? builtInCatalogCategories;
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) return availableCategories;
  return availableCategories.where(
    (category) => category.toLowerCase().contains(normalized),
  );
}

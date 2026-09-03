/// Starter categories that work offline for a typical Filipino sari-sari
/// store. Products still store category as plain text, so a future API can add
/// suggestions without a schema migration and owners can always type their own.
const List<String> starterCatalogCategories = [
  'Beverages',
  'Biscuits & Snacks',
  'Bread & Bakery',
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
  'Sweets & Candy',
  'Tobacco',
];

/// Combines offline defaults with device and future API values while keeping
/// one consistently-cased suggestion for each category.
List<String> mergeCatalogCategories({
  Iterable<String> storedCategories = const [],
  Iterable<String> apiCategories = const [],
}) => distinctCatalogCategories([
  ...starterCatalogCategories,
  ...storedCategories,
  ...apiCategories,
]);

List<String> distinctCatalogCategories(Iterable<String?> categories) {
  final byNormalizedName = <String, String>{};
  for (final category in categories) {
    final trimmed = category?.trim();
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
  Iterable<String> categories = starterCatalogCategories,
}) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) return categories;
  return categories.where(
    (category) => category.toLowerCase().contains(normalized),
  );
}

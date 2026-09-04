/// Safe, read-only preview of one validated `.razepack` file.
///
/// Opening this model has not changed the local catalog. A caller must submit
/// an explicit [CatalogPackApplySelection] before any product is written.
final class CatalogPackReview {
  const CatalogPackReview({
    required this.reviewId,
    required this.packId,
    required this.revision,
    required this.createdAt,
    required this.products,
  });

  final String reviewId;
  final String packId;
  final int revision;
  final DateTime createdAt;
  final List<CatalogPackReviewProduct> products;

  List<CatalogPackReviewProduct> get newProducts => products
      .where((product) => product.existing == null)
      .toList(growable: false);

  List<CatalogPackReviewProduct> get existingProducts => products
      .where((product) => product.existing != null)
      .toList(growable: false);
}

final class CatalogPackReviewProduct {
  const CatalogPackReviewProduct({
    required this.targetId,
    required this.catalogProductId,
    required this.incoming,
    required this.existing,
    required this.hasBundledImage,
    this.incomingImagePath,
    this.existingImagePath,
  });

  /// Stable identifier used by the apply selection. It is an existing local
  /// product ID for matches and a collision-checked generated ID for new rows.
  final String targetId;
  final String catalogProductId;
  final CatalogPackProductDetails incoming;
  final CatalogPackProductDetails? existing;
  final bool hasBundledImage;

  /// Validated, local-only preview files. Remote image URLs are deliberately
  /// not loaded while reviewing an untrusted shared pack.
  final String? incomingImagePath;
  final String? existingImagePath;

  bool get isNew => existing == null;

  String? get primaryImagePath =>
      isNew ? incomingImagePath : existingImagePath ?? incomingImagePath;
}

final class CatalogPackProductDetails {
  const CatalogPackProductDetails({
    required this.barcode,
    required this.name,
    required this.brand,
    required this.unitLabel,
    required this.category,
    required this.priceCentavos,
    required this.hasImage,
  });

  final String? barcode;
  final String name;
  final String? brand;
  final String? unitLabel;
  final String? category;
  final int priceCentavos;
  final bool hasImage;
}

/// Catalog fields the owner permits a selected pack row to contribute.
///
/// The shared source identity is internal integrity metadata and is always
/// linked for selected rows. A new product's name is also always required so
/// SQLite can never receive an unusable blank product.
enum CatalogPackImportField {
  barcode,
  name,
  brand,
  category,
  unitLabel,
  suggestedPrice,
  image,
}

final class CatalogPackApplySelection {
  CatalogPackApplySelection({
    required Iterable<String> selectedProductIds,
    Iterable<CatalogPackImportField> fields = CatalogPackImportField.values,
  }) : selectedProductIds = Set.unmodifiable(selectedProductIds),
       fields = Set.unmodifiable(fields);

  final Set<String> selectedProductIds;
  final Set<CatalogPackImportField> fields;

  bool includes(String productId) => selectedProductIds.contains(productId);
  bool imports(CatalogPackImportField field) => fields.contains(field);
}

/// One-level, device-local undo information for the most recently applied
/// catalog pack. A later successful pack import replaces this checkpoint.
final class CatalogPackUndoSummary {
  const CatalogPackUndoSummary({
    required this.packId,
    required this.revision,
    required this.importedAt,
    required this.createdCount,
    required this.updatedCount,
  });

  final String packId;
  final int revision;
  final DateTime importedAt;
  final int createdCount;
  final int updatedCount;

  int get changedProductCount => createdCount + updatedCount;
}

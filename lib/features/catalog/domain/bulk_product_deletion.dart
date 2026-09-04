/// Result of one confirmed multi-product deletion.
///
/// Completed sales are intentionally outside this operation. Only matching
/// unfinished cart rows are removed alongside the selected catalog products.
final class BulkProductDeletionResult {
  const BulkProductDeletionResult({
    required this.deletedProductCount,
    required this.removedCartRowCount,
    required this.cleanedImageCount,
    required this.imageCleanupFailureCount,
  });

  const BulkProductDeletionResult.empty()
    : deletedProductCount = 0,
      removedCartRowCount = 0,
      cleanedImageCount = 0,
      imageCleanupFailureCount = 0;

  final int deletedProductCount;
  final int removedCartRowCount;
  final int cleanedImageCount;
  final int imageCleanupFailureCount;
}

abstract interface class BulkProductDeletionService {
  Future<BulkProductDeletionResult> deleteProducts(Iterable<String> productIds);
}

import 'catalog_product.dart';

abstract interface class CatalogRepository {
  Stream<List<StoreProduct>> watchProducts({String query = ''});

  Future<List<StoreProduct>> searchProducts(String query);

  Stream<StoreProduct?> watchProduct(String id);

  Future<StoreProduct?> getProduct(String id);

  Future<StoreProduct?> findByBarcode(String rawBarcode);

  Future<StoreProduct?> findBySource(String source, String sourceProductId);

  Future<StoreProduct> createProduct(ProductDraft draft);

  Future<StoreProduct> updateProduct(String id, ProductDraft draft);

  Future<void> deleteProduct(String id);
}

final class DuplicateBarcodeException implements Exception {
  const DuplicateBarcodeException(this.barcode);

  final String barcode;

  @override
  String toString() => 'A product with barcode $barcode already exists.';
}

final class DuplicateCatalogProductException implements Exception {
  const DuplicateCatalogProductException(this.source, this.sourceProductId);

  final String source;
  final String sourceProductId;

  @override
  String toString() =>
      'Catalog product $source/$sourceProductId already exists.';
}

final class ProductNotFoundException implements Exception {
  const ProductNotFoundException(this.id);

  final String id;

  @override
  String toString() => 'Product $id was not found.';
}

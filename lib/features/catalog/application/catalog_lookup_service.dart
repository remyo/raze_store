import '../../../core/barcode/barcode.dart';
import '../domain/catalog_product.dart';
import '../domain/catalog_repository.dart';
import '../domain/remote_catalog_product.dart';
import '../domain/remote_catalog_repository.dart';

enum CatalogLookupKind { local, remote, notFound, unavailable }

final class CatalogLookupResult {
  const CatalogLookupResult._({
    required this.kind,
    this.localProduct,
    this.remoteProduct,
    this.error,
  });

  const CatalogLookupResult.local(StoreProduct product)
    : this._(kind: CatalogLookupKind.local, localProduct: product);

  const CatalogLookupResult.remote(RemoteCatalogProduct product)
    : this._(kind: CatalogLookupKind.remote, remoteProduct: product);

  const CatalogLookupResult.notFound()
    : this._(kind: CatalogLookupKind.notFound);

  const CatalogLookupResult.unavailable(Object error)
    : this._(kind: CatalogLookupKind.unavailable, error: error);

  final CatalogLookupKind kind;
  final StoreProduct? localProduct;
  final RemoteCatalogProduct? remoteProduct;
  final Object? error;
}

/// Looks in the priced, offline store catalog before touching the network.
final class CatalogLookupService {
  const CatalogLookupService({required this.local, required this.remote});

  final CatalogRepository local;
  final RemoteCatalogRepository remote;

  Future<CatalogLookupResult> findByBarcode(String rawBarcode) async {
    final barcode = Barcode.tryParse(rawBarcode);
    if (barcode == null) return const CatalogLookupResult.notFound();

    final localProduct = await local.findByBarcode(barcode.value);
    if (localProduct != null) return CatalogLookupResult.local(localProduct);
    if (!remote.isConfigured) return const CatalogLookupResult.notFound();

    try {
      final remoteProduct = await remote.findByBarcode(barcode.value);
      if (remoteProduct == null) return const CatalogLookupResult.notFound();
      final source = remoteProduct.metadata.source;
      final sourceProductId = remoteProduct.metadata.sourceProductId;
      if (source != null && sourceProductId != null) {
        final existing = await local.findBySource(source, sourceProductId);
        if (existing != null) return CatalogLookupResult.local(existing);
      }
      // If the API resolved a barcode alias, retain the code actually printed
      // on this store's package so future scans work without the network.
      return CatalogLookupResult.remote(
        remoteProduct.barcode == barcode.value
            ? remoteProduct
            : remoteProduct.withBarcode(barcode.value),
      );
    } on Object catch (error) {
      return CatalogLookupResult.unavailable(error);
    }
  }
}

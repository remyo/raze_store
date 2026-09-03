import 'catalog_product.dart';

/// Product facts supplied by the shared API, before this store sets a price.
final class RemoteCatalogProduct {
  const RemoteCatalogProduct({
    required this.catalogProductId,
    required this.metadata,
    required this.updatedAt,
  });

  final String catalogProductId;
  final CatalogMetadata metadata;
  final DateTime updatedAt;

  String get barcode => metadata.barcode!;
  String get name => metadata.name;
  String? get brand => metadata.brand;
  String? get unitLabel => metadata.unitLabel;
  String? get category => metadata.category;
  String? get remoteImageUrl => metadata.remoteImageUrl;

  RemoteCatalogProduct withBarcode(String barcode) => RemoteCatalogProduct(
    catalogProductId: catalogProductId,
    metadata: CatalogMetadata(
      barcode: barcode,
      name: metadata.name,
      brand: metadata.brand,
      unitLabel: metadata.unitLabel,
      category: metadata.category,
      remoteImageUrl: metadata.remoteImageUrl,
      source: metadata.source,
      sourceProductId: metadata.sourceProductId,
      suggestedPriceCentavos: metadata.suggestedPriceCentavos,
    ),
    updatedAt: updatedAt,
  );
}

final class RemoteCatalogPage {
  const RemoteCatalogPage({
    required this.products,
    required this.totalCount,
    required this.page,
    required this.hasNextPage,
  });

  final List<RemoteCatalogProduct> products;
  final int totalCount;
  final int page;
  final bool hasNextPage;
}

final class CatalogApiHealth {
  const CatalogApiHealth({required this.service, required this.checkedAt});

  final String service;
  final DateTime checkedAt;
}

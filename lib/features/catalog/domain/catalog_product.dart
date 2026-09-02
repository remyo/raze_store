import '../../../core/barcode/barcode.dart';
import '../../../core/money/money.dart';

/// Product facts that may later be supplied by `raze_store_api`.
///
/// These values deliberately do not include this sari-sari store's price.
final class CatalogMetadata {
  CatalogMetadata({
    String? barcode,
    required String name,
    String? brand,
    String? unitLabel,
    String? category,
    String? remoteImageUrl,
    String? source,
    String? sourceProductId,
  }) : barcode = _optionalBarcode(barcode),
       name = _requiredText(name, 'name'),
       brand = _optionalText(brand),
       unitLabel = _optionalText(unitLabel),
       category = _optionalText(category),
       remoteImageUrl = _optionalText(remoteImageUrl),
       source = _optionalText(source),
       sourceProductId = _optionalText(sourceProductId);

  final String? barcode;
  final String name;
  final String? brand;
  final String? unitLabel;
  final String? category;
  final String? remoteImageUrl;
  final String? source;
  final String? sourceProductId;
}

/// A catalog product carried by this store, including its local selling price.
final class StoreProduct {
  const StoreProduct({
    required this.id,
    required this.metadata,
    required this.price,
    required this.createdAt,
    required this.updatedAt,
    this.localImagePath,
  });

  final String id;
  final CatalogMetadata metadata;
  final Money price;
  final String? localImagePath;
  final DateTime createdAt;
  final DateTime updatedAt;

  String? get barcode => metadata.barcode;
  String get name => metadata.name;
  String? get brand => metadata.brand;
  String? get unitLabel => metadata.unitLabel;
  String? get category => metadata.category;
  String? get remoteImageUrl => metadata.remoteImageUrl;
  int get priceCentavos => price.centavos;
}

/// Editable values used by both create and update product forms.
final class ProductDraft {
  ProductDraft({
    this.id,
    String? barcode,
    required String name,
    String? brand,
    String? unitLabel,
    String? category,
    String? remoteImageUrl,
    String? source,
    String? sourceProductId,
    String? localImagePath,
    required this.priceCentavos,
  }) : barcode = _optionalBarcode(barcode),
       name = _requiredText(name, 'name'),
       brand = _optionalText(brand),
       unitLabel = _optionalText(unitLabel),
       category = _optionalText(category),
       remoteImageUrl = _optionalText(remoteImageUrl),
       source = _optionalText(source),
       sourceProductId = _optionalText(sourceProductId),
       localImagePath = _optionalText(localImagePath) {
    if (priceCentavos < 0) {
      throw ArgumentError.value(
        priceCentavos,
        'priceCentavos',
        'Must not be negative.',
      );
    }
  }

  factory ProductDraft.fromProduct(StoreProduct product) => ProductDraft(
    id: product.id,
    barcode: product.barcode,
    name: product.name,
    brand: product.brand,
    unitLabel: product.unitLabel,
    category: product.category,
    remoteImageUrl: product.remoteImageUrl,
    source: product.metadata.source,
    sourceProductId: product.metadata.sourceProductId,
    localImagePath: product.localImagePath,
    priceCentavos: product.priceCentavos,
  );

  final String? id;
  final String? barcode;
  final String name;
  final String? brand;
  final String? unitLabel;
  final String? category;
  final String? remoteImageUrl;
  final String? source;
  final String? sourceProductId;
  final String? localImagePath;
  final int priceCentavos;

  CatalogMetadata get metadata => CatalogMetadata(
    barcode: barcode,
    name: name,
    brand: brand,
    unitLabel: unitLabel,
    category: category,
    remoteImageUrl: remoteImageUrl,
    source: source,
    sourceProductId: sourceProductId,
  );
}

String _requiredText(String value, String fieldName) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(value, fieldName, 'Must not be blank.');
  }
  return trimmed;
}

String? _optionalText(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

String? _optionalBarcode(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : Barcode(trimmed).value;
}

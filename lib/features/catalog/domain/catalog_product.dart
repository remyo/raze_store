import '../../../core/barcode/barcode.dart';
import '../../../core/money/money.dart';

const String fallbackMainSellingUnitLabel = 'Main item';

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
    this.sellingUnits = const [],
  });

  final String id;
  final CatalogMetadata metadata;
  final Money price;
  final String? localImagePath;
  final List<SellingUnit> sellingUnits;
  final DateTime createdAt;
  final DateTime updatedAt;

  String? get barcode => metadata.barcode;
  String get name => metadata.name;
  String? get brand => metadata.brand;
  String? get unitLabel => metadata.unitLabel;
  String? get category => metadata.category;
  String? get remoteImageUrl => metadata.remoteImageUrl;
  int get priceCentavos => price.centavos;

  String get defaultSellingUnitLabel =>
      effectiveMainSellingUnitLabel(unitLabel);

  List<ProductSaleOption> get saleOptions => [
    ProductSaleOption(
      sellingUnitId: null,
      label: defaultSellingUnitLabel,
      price: price,
      isDefault: true,
    ),
    for (final unit in sellingUnits)
      ProductSaleOption(
        sellingUnitId: unit.id,
        label: unit.label,
        price: unit.price,
        isDefault: false,
      ),
  ];
}

/// One optional loose or grouped selling price under a barcode product.
///
/// The parent product owns the barcode. A sub-unit such as `Stick`, `Piece`,
/// or `Tray` is selected only after the parent product has been found.
final class SellingUnit {
  const SellingUnit({
    required this.id,
    required this.label,
    required this.price,
  });

  final String id;
  final String label;
  final Money price;

  int get priceCentavos => price.centavos;
}

/// A cart-ready choice derived from the default product unit or a sub-unit.
final class ProductSaleOption {
  const ProductSaleOption({
    required this.sellingUnitId,
    required this.label,
    required this.price,
    required this.isDefault,
  });

  final String? sellingUnitId;
  final String label;
  final Money price;
  final bool isDefault;

  int get priceCentavos => price.centavos;
}

/// Editable values for a loose or grouped selling option.
final class SellingUnitDraft {
  SellingUnitDraft({
    this.id,
    required String label,
    required this.priceCentavos,
  }) : label = _requiredText(label, 'label') {
    if (priceCentavos < 0) {
      throw ArgumentError.value(
        priceCentavos,
        'priceCentavos',
        'Must not be negative.',
      );
    }
  }

  factory SellingUnitDraft.fromUnit(SellingUnit unit) => SellingUnitDraft(
    id: unit.id,
    label: unit.label,
    priceCentavos: unit.priceCentavos,
  );

  final String? id;
  final String label;
  final int priceCentavos;
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
    Iterable<SellingUnitDraft> sellingUnits = const [],
  }) : barcode = _optionalBarcode(barcode),
       name = _requiredText(name, 'name'),
       brand = _optionalText(brand),
       unitLabel = _optionalText(unitLabel),
       category = _optionalText(category),
       remoteImageUrl = _optionalText(remoteImageUrl),
       source = _optionalText(source),
       sourceProductId = _optionalText(sourceProductId),
       localImagePath = _optionalText(localImagePath),
       sellingUnits = List<SellingUnitDraft>.unmodifiable(sellingUnits) {
    if (priceCentavos < 0) {
      throw ArgumentError.value(
        priceCentavos,
        'priceCentavos',
        'Must not be negative.',
      );
    }
    if (this.sellingUnits.isNotEmpty && this.barcode == null) {
      throw ArgumentError.value(
        barcode,
        'barcode',
        'A main barcode is required when a product has sub-unit prices.',
      );
    }
    final normalizedLabels = <String>{};
    final normalizedMainLabel = effectiveMainSellingUnitLabel(
      this.unitLabel,
    ).toLowerCase();
    for (final unit in this.sellingUnits) {
      final normalizedLabel = unit.label.toLowerCase();
      if (normalizedLabel == normalizedMainLabel) {
        throw ArgumentError.value(
          unit.label,
          'sellingUnits',
          'A selling-unit label must differ from the main unit label.',
        );
      }
      if (!normalizedLabels.add(normalizedLabel)) {
        throw ArgumentError.value(
          unit.label,
          'sellingUnits',
          'Selling-unit labels must be unique.',
        );
      }
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
    sellingUnits: product.sellingUnits.map(SellingUnitDraft.fromUnit),
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
  final List<SellingUnitDraft> sellingUnits;

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

String effectiveMainSellingUnitLabel(String? unitLabel) =>
    _optionalText(unitLabel) ?? fallbackMainSellingUnitLabel;

String? _optionalBarcode(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : Barcode(trimmed).value;
}

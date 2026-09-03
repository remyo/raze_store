import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:raze_store/core/barcode/barcode.dart';
import 'package:raze_store/core/database/app_database.dart' as database;
import 'package:raze_store/core/money/money.dart';
import 'package:raze_store/features/catalog_transfer/data/csv_table_codec.dart';
import 'package:raze_store/features/catalog_transfer/domain/catalog_transfer_result.dart';
import 'package:uuid/uuid.dart';

final class CatalogCsvDocument {
  const CatalogCsvDocument({
    required this.contents,
    required this.productCount,
    required this.sellingUnitCount,
  });

  final String contents;
  final int productCount;
  final int sellingUnitCount;
}

/// Spreadsheet interchange for the product catalog.
///
/// CSV is intentionally merge-only and excludes local photo paths, store
/// settings, and the temporary cart. `.razestore` remains the lossless backup.
final class CatalogCsvService {
  CatalogCsvService(
    this._database, {
    CsvTableCodec codec = const CsvTableCodec(),
    Uuid uuid = const Uuid(),
    DateTime Function()? now,
  }) : _codec = codec,
       _uuid = uuid,
       _now = now ?? DateTime.now;

  static const csvVersion = 1;
  static const _maximumCsvBytes = 12 * 1024 * 1024;
  static const _maximumProducts = 50000;
  static const _maximumSellingUnits = 100000;
  static const _maximumSellingUnitsPerProduct = 100;
  static const _maximumFieldLength = 32768;
  static const headers = <String>[
    'csv_version',
    'product_id',
    'barcode',
    'name',
    'brand',
    'category',
    'default_unit_label',
    'default_price_php',
    'selling_units_json',
    'remote_image_url',
    'source',
    'source_product_id',
  ];

  final database.AppDatabase _database;
  final CsvTableCodec _codec;
  final Uuid _uuid;
  final DateTime Function() _now;

  Future<CatalogCsvDocument> buildDocument() async {
    final snapshot = await _database.transaction(() async {
      final products =
          await (_database.select(_database.storeProducts)..orderBy([
                (table) => OrderingTerm.asc(table.name),
                (table) => OrderingTerm.asc(table.id),
              ]))
              .get();
      final units =
          await (_database.select(_database.productSellingUnits)..orderBy([
                (table) => OrderingTerm.asc(table.productId),
                (table) => OrderingTerm.asc(table.position),
                (table) => OrderingTerm.asc(table.id),
              ]))
              .get();
      return (products: products, units: units);
    });
    final products = snapshot.products;
    final units = snapshot.units;
    if (products.length > _maximumProducts ||
        units.length > _maximumSellingUnits) {
      throw const _CsvValidationException(
        'The catalog has too many records to export safely.',
      );
    }
    final unitsByProduct = <String, List<database.ProductSellingUnit>>{};
    for (final unit in units) {
      unitsByProduct.putIfAbsent(unit.productId, () => []).add(unit);
    }

    final rows = <List<Object?>>[headers];
    for (final product in products) {
      final sellingUnits = unitsByProduct[product.id] ?? const [];
      if (sellingUnits.length > _maximumSellingUnitsPerProduct) {
        throw const _CsvValidationException(
          'A product has too many sub-unit prices to export safely.',
        );
      }
      if (sellingUnits.isNotEmpty && product.barcode == null) {
        throw const _CsvValidationException(
          'A product with sub-unit prices needs a main barcode.',
        );
      }
      final labels = <String>{};
      final mainLabel = (product.unitLabel ?? 'Main item').toLowerCase();
      for (final unit in sellingUnits) {
        final label = unit.label.toLowerCase();
        if (!labels.add(label) || label == mainLabel) {
          throw const _CsvValidationException(
            'A product has duplicate main or sub-unit labels.',
          );
        }
      }
      rows.add([
        '$csvVersion',
        _spreadsheetSafe(product.id, alwaysText: true),
        _spreadsheetSafe(product.barcode, alwaysText: true),
        _spreadsheetSafe(product.name),
        _spreadsheetSafe(product.brand),
        _spreadsheetSafe(product.category),
        _spreadsheetSafe(product.unitLabel),
        _formatPrice(product.priceCentavos),
        jsonEncode([
          for (final unit in sellingUnits)
            <String, Object?>{
              'id': unit.id,
              'label': unit.label,
              'pricePhp': _formatPrice(unit.priceCentavos),
              'position': unit.position,
            },
        ]),
        _spreadsheetSafe(product.remoteImageUrl),
        _spreadsheetSafe(product.source),
        _spreadsheetSafe(product.sourceProductId, alwaysText: true),
      ]);
    }
    final contents = '\uFEFF${_codec.encode(rows)}\r\n';
    if (utf8.encode(contents).length > _maximumCsvBytes) {
      throw const _CsvValidationException(
        'The catalog CSV is too large to export safely.',
      );
    }
    return CatalogCsvDocument(
      contents: contents,
      productCount: products.length,
      sellingUnitCount: units.length,
    );
  }

  Future<CatalogTransferResult> importMerging({
    required String sourcePath,
  }) async {
    try {
      final file = File(sourcePath);
      if (!await file.exists()) {
        return const CatalogTransferFailure(
          code: CatalogTransferFailureCode.sourceMissing,
          message: 'The selected CSV file is no longer available.',
        );
      }
      if (await file.length() > _maximumCsvBytes) {
        return const CatalogTransferFailure(
          code: CatalogTransferFailureCode.validationFailed,
          message: 'This CSV is too large to import safely.',
        );
      }
      final parsed = _parse(await file.readAsString());
      final summary = await _merge(parsed);
      final noun = summary.productCount == 1 ? 'product' : 'products';
      return CatalogTransferSuccess(
        action: CatalogTransferAction.csvImport,
        message:
            'CSV imported ${summary.productCount} $noun and ${summary.sellingUnitCount} sub-unit prices.',
        productCount: summary.productCount,
        sellingUnitCount: summary.sellingUnitCount,
        path: sourcePath,
      );
    } on _CsvValidationException catch (error) {
      return CatalogTransferFailure(
        code: CatalogTransferFailureCode.validationFailed,
        message: '${error.message} No products were changed.',
        cause: error,
      );
    } on FormatException catch (error) {
      return CatalogTransferFailure(
        code: CatalogTransferFailureCode.validationFailed,
        message: 'The CSV is malformed. No products were changed.',
        cause: error,
      );
    } on FileSystemException catch (error) {
      return CatalogTransferFailure(
        code: CatalogTransferFailureCode.ioFailure,
        message: 'The selected CSV could not be read.',
        cause: error,
      );
    } catch (error) {
      return CatalogTransferFailure(
        code: CatalogTransferFailureCode.databaseFailure,
        message: 'The CSV could not be imported. No products were changed.',
        cause: error,
      );
    }
  }

  List<_CsvProduct> _parse(String contents) {
    final table = _codec.decode(contents);
    if (table.isEmpty) {
      throw const _CsvValidationException('The CSV is empty.');
    }
    final fileHeaders = table.first
        .map((value) => value.trim().toLowerCase())
        .toList(growable: false);
    final duplicateHeaders = <String>{};
    for (final header in fileHeaders) {
      if (!duplicateHeaders.add(header)) {
        throw _CsvValidationException('The CSV repeats the “$header” column.');
      }
    }
    for (final required in headers) {
      if (!fileHeaders.contains(required)) {
        throw _CsvValidationException(
          'The CSV is missing the “$required” column.',
        );
      }
    }
    final indexes = <String, int>{
      for (final header in headers) header: fileHeaders.indexOf(header),
    };
    String valueAt(List<String> row, String key) {
      final index = indexes[key]!;
      return index < row.length ? row[index].trim() : '';
    }

    final products = <_CsvProduct>[];
    final productIds = <String>{};
    final barcodes = <String>{};
    final sourceIdentities = <(String, String)>{};
    final sellingUnitIds = <String>{};
    var totalSellingUnits = 0;
    for (var rowIndex = 1; rowIndex < table.length; rowIndex++) {
      final row = table[rowIndex];
      final displayRow = rowIndex + 1;
      if (row.every((value) => value.trim().isEmpty)) continue;
      if (row.any((value) => value.length > _maximumFieldLength)) {
        throw _CsvValidationException(
          'CSV row $displayRow contains a field that is too long.',
        );
      }
      if (valueAt(row, 'csv_version') != '$csvVersion') {
        throw _CsvValidationException(
          'CSV row $displayRow uses an unsupported CSV version.',
        );
      }
      final id = _restoreSpreadsheetText(valueAt(row, 'product_id'));
      if (id != null && !productIds.add(id)) {
        throw _CsvValidationException(
          'CSV row $displayRow repeats product ID “$id”.',
        );
      }
      final rawBarcode = _restoreSpreadsheetText(valueAt(row, 'barcode'));
      final parsedBarcode = rawBarcode == null
          ? null
          : Barcode.tryParse(rawBarcode);
      if (rawBarcode != null && parsedBarcode == null) {
        throw _CsvValidationException(
          'CSV row $displayRow has an invalid barcode.',
        );
      }
      final barcode = parsedBarcode?.value;
      if (barcode != null && !barcodes.add(barcode)) {
        throw _CsvValidationException(
          'CSV row $displayRow repeats barcode “$barcode”.',
        );
      }
      final name = _requiredCsvText(
        valueAt(row, 'name'),
        row: displayRow,
        label: 'name',
        maximum: 240,
      );
      final mainPrice = _nonNegativePrice(
        valueAt(row, 'default_price_php'),
        row: displayRow,
        label: 'default price',
      );
      final defaultUnit = _optionalCsvText(
        valueAt(row, 'default_unit_label'),
        maximum: 120,
        row: displayRow,
        label: 'default unit',
      );
      final sellingUnits = _parseSellingUnits(
        valueAt(row, 'selling_units_json'),
        row: displayRow,
        defaultUnitLabel: defaultUnit,
      );
      if (sellingUnits.isNotEmpty && barcode == null) {
        throw _CsvValidationException(
          'CSV row $displayRow needs a main barcode when it has sub-unit prices.',
        );
      }
      totalSellingUnits += sellingUnits.length;
      if (totalSellingUnits > _maximumSellingUnits) {
        throw const _CsvValidationException(
          'The CSV contains too many sub-unit prices.',
        );
      }
      for (final unit in sellingUnits) {
        final unitId = unit.id;
        if (unitId != null && !sellingUnitIds.add(unitId)) {
          throw _CsvValidationException(
            'CSV row $displayRow repeats selling-unit ID “$unitId”.',
          );
        }
      }
      final source = _optionalCsvText(
        valueAt(row, 'source'),
        maximum: 64,
        row: displayRow,
        label: 'source',
      );
      final sourceProductId = _optionalCsvText(
        valueAt(row, 'source_product_id'),
        maximum: 160,
        row: displayRow,
        label: 'source product ID',
      );
      if ((source == null) != (sourceProductId == null)) {
        throw _CsvValidationException(
          'CSV row $displayRow must include both source and source product ID.',
        );
      }
      if (source != null && !sourceIdentities.add((source, sourceProductId!))) {
        throw _CsvValidationException(
          'CSV row $displayRow repeats a shared catalog product.',
        );
      }
      products.add(
        _CsvProduct(
          sourceRow: displayRow,
          id: id,
          barcode: barcode,
          name: name,
          brand: _optionalCsvText(
            valueAt(row, 'brand'),
            maximum: 240,
            row: displayRow,
            label: 'brand',
          ),
          category: _optionalCsvText(
            valueAt(row, 'category'),
            maximum: 240,
            row: displayRow,
            label: 'category',
          ),
          unitLabel: defaultUnit,
          priceCentavos: mainPrice,
          sellingUnits: sellingUnits,
          remoteImageUrl: _optionalCsvText(
            valueAt(row, 'remote_image_url'),
            maximum: 2048,
            row: displayRow,
            label: 'remote image URL',
          ),
          source: source,
          sourceProductId: sourceProductId,
        ),
      );
      if (products.length > _maximumProducts) {
        throw const _CsvValidationException(
          'The CSV contains too many products.',
        );
      }
    }
    return products;
  }

  List<_CsvSellingUnit> _parseSellingUnits(
    String raw, {
    required int row,
    required String? defaultUnitLabel,
  }) {
    if (raw.trim().isEmpty) return const [];
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      throw _CsvValidationException(
        'CSV row $row has invalid selling_units_json.',
      );
    }
    if (decoded is! List) {
      throw _CsvValidationException(
        'CSV row $row selling_units_json must be a JSON list.',
      );
    }
    if (decoded.length > _maximumSellingUnitsPerProduct) {
      throw _CsvValidationException(
        'CSV row $row contains too many sub-unit prices.',
      );
    }
    final units = <_CsvSellingUnit>[];
    final labels = <String>{};
    final mainLabel = (defaultUnitLabel ?? 'Main item').toLowerCase();
    for (var index = 0; index < decoded.length; index++) {
      final value = decoded[index];
      if (value is! Map) {
        throw _CsvValidationException(
          'CSV row $row contains an invalid selling unit.',
        );
      }
      final map = value.cast<String, Object?>();
      final label = (map['label'] as String?)?.trim() ?? '';
      if (label.isEmpty || label.length > 80) {
        throw _CsvValidationException(
          'CSV row $row has a selling unit without a valid label.',
        );
      }
      final normalizedLabel = label.toLowerCase();
      if (!labels.add(normalizedLabel) || normalizedLabel == mainLabel) {
        throw _CsvValidationException(
          'CSV row $row repeats selling-unit label “$label”.',
        );
      }
      final priceValue = map['pricePhp'];
      if (priceValue is! String) {
        throw _CsvValidationException(
          'CSV row $row selling unit “$label” needs pricePhp text.',
        );
      }
      final idValue = map['id'];
      if (idValue != null && idValue is! String) {
        throw _CsvValidationException(
          'CSV row $row selling unit “$label” has an invalid ID.',
        );
      }
      units.add(
        _CsvSellingUnit(
          id: _restoreSpreadsheetText(idValue as String? ?? ''),
          label: label,
          priceCentavos: _nonNegativePrice(
            priceValue,
            row: row,
            label: 'price for $label',
          ),
          position: index,
        ),
      );
    }
    return units;
  }

  Future<_ImportSummary> _merge(List<_CsvProduct> products) async {
    final now = _now().toUtc();
    var unitCount = 0;
    await _database.transaction(() async {
      final existingProducts = await _database
          .select(_database.storeProducts)
          .get();
      final byId = {
        for (final product in existingProducts) product.id: product,
      };
      final byBarcode = {
        for (final product in existingProducts)
          if (product.barcode != null) product.barcode!: product,
      };
      final bySourceIdentity = {
        for (final product in existingProducts)
          if (product.source != null && product.sourceProductId != null)
            (product.source!, product.sourceProductId!): product,
      };
      final existingUnits = await _database
          .select(_database.productSellingUnits)
          .get();
      final unitsById = {for (final unit in existingUnits) unit.id: unit};
      final claimedTargetIds = <String>{};

      for (final product in products) {
        final idMatch = product.id == null ? null : byId[product.id];
        final barcodeMatch = product.barcode == null
            ? null
            : byBarcode[product.barcode];
        final sourceMatch = product.source == null
            ? null
            : bySourceIdentity[(product.source!, product.sourceProductId!)];
        final matchedIds = {
          if (idMatch != null) idMatch.id,
          if (barcodeMatch != null) barcodeMatch.id,
          if (sourceMatch != null) sourceMatch.id,
        };
        if (matchedIds.length > 1) {
          throw _CsvValidationException(
            'CSV row ${product.sourceRow} identifies two different existing products.',
          );
        }
        final existing = idMatch ?? barcodeMatch ?? sourceMatch;
        final targetId = existing?.id ?? product.id ?? _uuid.v4();
        if (!claimedTargetIds.add(targetId)) {
          throw _CsvValidationException(
            'CSV row ${product.sourceRow} resolves to a product already used by another row.',
          );
        }
        for (final unit in product.sellingUnits) {
          final existingUnit = unit.id == null ? null : unitsById[unit.id];
          if (existingUnit != null && existingUnit.productId != targetId) {
            throw _CsvValidationException(
              'CSV row ${product.sourceRow} uses a selling-unit ID owned by another product.',
            );
          }
        }

        final companion = database.StoreProductsCompanion.insert(
          id: targetId,
          barcode: Value(product.barcode),
          source: Value(product.source ?? existing?.source),
          sourceProductId: Value(
            product.sourceProductId ?? existing?.sourceProductId,
          ),
          name: product.name,
          brand: Value(product.brand),
          unitLabel: Value(product.unitLabel),
          category: Value(product.category),
          remoteImageUrl: Value(
            product.remoteImageUrl ?? existing?.remoteImageUrl,
          ),
          localImagePath: Value(existing?.localImagePath),
          // Catalog-pack state is intentionally absent from the spreadsheet
          // format. A price/name edit must never detach the offline image or
          // roll back the source revision that supplied it.
          catalogImagePath: Value(existing?.catalogImagePath),
          sourceUpdatedAt: Value(existing?.sourceUpdatedAt),
          priceCentavos: product.priceCentavos,
          createdAt: Value(existing?.createdAt ?? now),
          updatedAt: Value(now),
        );
        await _database
            .into(_database.storeProducts)
            .insertOnConflictUpdate(companion);
        await (_database.delete(
          _database.productSellingUnits,
        )..where((table) => table.productId.equals(targetId))).go();
        for (final unit in product.sellingUnits) {
          final id = unit.id ?? _uuid.v4();
          final oldUnit = unitsById[id];
          await _database
              .into(_database.productSellingUnits)
              .insert(
                database.ProductSellingUnitsCompanion.insert(
                  id: id,
                  productId: targetId,
                  label: unit.label,
                  priceCentavos: unit.priceCentavos,
                  position: unit.position,
                  createdAt: Value(oldUnit?.createdAt ?? now),
                  updatedAt: Value(now),
                ),
              );
          unitCount++;
        }
      }
    });
    return _ImportSummary(
      productCount: products.length,
      sellingUnitCount: unitCount,
    );
  }

  String? _spreadsheetSafe(String? value, {bool alwaysText = false}) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return null;
    if (text.startsWith("'")) return "'$text";
    final firstVisible = text.trimLeft();
    final dangerous =
        firstVisible.startsWith('=') ||
        firstVisible.startsWith('+') ||
        firstVisible.startsWith('-') ||
        firstVisible.startsWith('@');
    final numericText = alwaysText && RegExp(r'^\d+$').hasMatch(text);
    return dangerous || numericText ? "'$text" : text;
  }

  String? _restoreSpreadsheetText(String value) {
    final text = value.trim();
    if (text.isEmpty) return null;
    if (text.startsWith("''")) return text.substring(1);
    if (text.startsWith("'") && text.length > 1) {
      final rest = text.substring(1);
      if (RegExp(r'^[=+\-@0-9]').hasMatch(rest)) return rest;
    }
    return text;
  }

  String _requiredCsvText(
    String raw, {
    required int row,
    required String label,
    required int maximum,
  }) {
    final text = _restoreSpreadsheetText(raw);
    if (text == null || text.length > maximum) {
      throw _CsvValidationException('CSV row $row needs a valid $label.');
    }
    return text;
  }

  String? _optionalCsvText(
    String raw, {
    required int maximum,
    required int row,
    required String label,
  }) {
    final text = _restoreSpreadsheetText(raw);
    if (text != null && text.length > maximum) {
      throw _CsvValidationException(
        'CSV row $row has a $label that is too long.',
      );
    }
    return text;
  }

  int _nonNegativePrice(String raw, {required int row, required String label}) {
    final value = tryParsePesoCentavos(raw);
    if (value == null || value < 0) {
      throw _CsvValidationException(
        'CSV row $row needs a valid $label of zero or more.',
      );
    }
    return value;
  }

  String _formatPrice(int centavos) =>
      '${centavos ~/ 100}.${(centavos % 100).toString().padLeft(2, '0')}';
}

final class _CsvProduct {
  const _CsvProduct({
    required this.sourceRow,
    required this.id,
    required this.barcode,
    required this.name,
    required this.brand,
    required this.category,
    required this.unitLabel,
    required this.priceCentavos,
    required this.sellingUnits,
    required this.remoteImageUrl,
    required this.source,
    required this.sourceProductId,
  });

  final int sourceRow;
  final String? id;
  final String? barcode;
  final String name;
  final String? brand;
  final String? category;
  final String? unitLabel;
  final int priceCentavos;
  final List<_CsvSellingUnit> sellingUnits;
  final String? remoteImageUrl;
  final String? source;
  final String? sourceProductId;
}

final class _CsvSellingUnit {
  const _CsvSellingUnit({
    required this.id,
    required this.label,
    required this.priceCentavos,
    required this.position,
  });

  final String? id;
  final String label;
  final int priceCentavos;
  final int position;
}

final class _ImportSummary {
  const _ImportSummary({
    required this.productCount,
    required this.sellingUnitCount,
  });

  final int productCount;
  final int sellingUnitCount;
}

final class _CsvValidationException implements Exception {
  const _CsvValidationException(this.message);

  final String message;
}

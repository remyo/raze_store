import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/barcode/barcode.dart';
import '../../../core/database/app_database.dart' as database;
import '../../../core/database/tables.dart' as tables;
import '../../../core/money/money.dart';
import '../domain/catalog_product.dart';
import '../domain/catalog_repository.dart';

final class LocalCatalogRepository implements CatalogRepository {
  LocalCatalogRepository(
    this._database, {
    Uuid uuid = const Uuid(),
    DateTime Function()? now,
  }) : _uuid = uuid,
       _now = now ?? DateTime.now;

  final database.AppDatabase _database;
  final Uuid _uuid;
  final DateTime Function() _now;

  @override
  Stream<List<StoreProduct>> watchProducts({String query = ''}) {
    final statement = _productQuery(query);
    return statement.watch().map(_mapRows);
  }

  @override
  Future<List<StoreProduct>> searchProducts(String query) async {
    return _mapRows(await _productQuery(query).get());
  }

  @override
  Stream<StoreProduct?> watchProduct(String id) {
    final normalizedId = _requiredId(id);
    final statement = _database.select(_database.storeProducts)
      ..where((table) => table.id.equals(normalizedId));
    return statement.watchSingleOrNull().map(
      (row) => row == null ? null : _mapRow(row),
    );
  }

  @override
  Future<StoreProduct?> getProduct(String id) async {
    final normalizedId = _requiredId(id);
    final row = await (_database.select(
      _database.storeProducts,
    )..where((table) => table.id.equals(normalizedId))).getSingleOrNull();
    return row == null ? null : _mapRow(row);
  }

  @override
  Future<StoreProduct?> findByBarcode(String rawBarcode) async {
    final parsed = Barcode.tryParse(rawBarcode);
    if (parsed == null) return null;
    final barcode = parsed.value;
    final row = await (_database.select(
      _database.storeProducts,
    )..where((table) => table.barcode.equals(barcode))).getSingleOrNull();
    return row == null ? null : _mapRow(row);
  }

  @override
  Future<StoreProduct> createProduct(ProductDraft draft) async {
    final id = _draftId(draft.id);
    await _ensureBarcodeAvailable(draft.barcode);
    final now = _now().toUtc();
    final companion = _companion(
      id: id,
      draft: draft,
      createdAt: now,
      updatedAt: now,
    );
    await _database.into(_database.storeProducts).insert(companion);
    return (await getProduct(id))!;
  }

  @override
  Future<StoreProduct> updateProduct(String id, ProductDraft draft) async {
    final normalizedId = _requiredId(id);
    final existing = await getProduct(normalizedId);
    if (existing == null) throw ProductNotFoundException(normalizedId);
    await _ensureBarcodeAvailable(draft.barcode, excludingId: normalizedId);

    final companion = _companion(
      id: normalizedId,
      draft: draft,
      createdAt: existing.createdAt,
      updatedAt: _now().toUtc(),
    );
    await (_database.update(
      _database.storeProducts,
    )..where((table) => table.id.equals(normalizedId))).write(companion);
    return (await getProduct(normalizedId))!;
  }

  @override
  Future<void> deleteProduct(String id) async {
    final normalizedId = _requiredId(id);
    await (_database.delete(
      _database.storeProducts,
    )..where((table) => table.id.equals(normalizedId))).go();
  }

  SimpleSelectStatement<tables.StoreProducts, database.StoreProduct>
  _productQuery(String rawQuery) {
    final query = rawQuery.trim().toLowerCase();
    final statement = _database.select(_database.storeProducts);
    if (query.isNotEmpty) {
      statement.where(
        (table) =>
            table.name.lower().contains(query) |
            table.barcode.contains(query) |
            table.brand.lower().contains(query) |
            table.unitLabel.lower().contains(query) |
            table.category.lower().contains(query),
      );
    }
    statement.orderBy([
      (table) => OrderingTerm.asc(table.name),
      (table) => OrderingTerm.asc(table.id),
    ]);
    return statement;
  }

  List<StoreProduct> _mapRows(List<database.StoreProduct> rows) =>
      rows.map(_mapRow).toList(growable: false);

  StoreProduct _mapRow(database.StoreProduct row) => StoreProduct(
    id: row.id,
    metadata: CatalogMetadata(
      barcode: row.barcode,
      name: row.name,
      brand: row.brand,
      unitLabel: row.unitLabel,
      category: row.category,
      remoteImageUrl: row.remoteImageUrl,
      source: row.source,
      sourceProductId: row.sourceProductId,
    ),
    price: Money.fromCentavos(row.priceCentavos),
    localImagePath: row.localImagePath,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );

  database.StoreProductsCompanion _companion({
    required String id,
    required ProductDraft draft,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) => database.StoreProductsCompanion.insert(
    id: id,
    barcode: Value(draft.barcode),
    source: Value(draft.source),
    sourceProductId: Value(draft.sourceProductId),
    name: draft.name,
    brand: Value(draft.brand),
    unitLabel: Value(draft.unitLabel),
    category: Value(draft.category),
    remoteImageUrl: Value(draft.remoteImageUrl),
    localImagePath: Value(draft.localImagePath),
    priceCentavos: draft.priceCentavos,
    createdAt: Value(createdAt),
    updatedAt: Value(updatedAt),
  );

  Future<void> _ensureBarcodeAvailable(
    String? barcode, {
    String? excludingId,
  }) async {
    if (barcode == null) return;
    final existing = await (_database.select(
      _database.storeProducts,
    )..where((table) => table.barcode.equals(barcode))).getSingleOrNull();
    if (existing != null && existing.id != excludingId) {
      throw DuplicateBarcodeException(barcode);
    }
  }

  String _draftId(String? requestedId) {
    final normalized = requestedId?.trim();
    return normalized == null || normalized.isEmpty ? _uuid.v4() : normalized;
  }

  String _requiredId(String id) {
    final normalized = id.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(id, 'id', 'Must not be blank.');
    }
    return normalized;
  }
}

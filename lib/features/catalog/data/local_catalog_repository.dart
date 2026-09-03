import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/barcode/barcode.dart';
import '../../../core/database/app_database.dart' as database;
import '../../../core/database/tables.dart' as tables;
import '../../../core/money/money.dart';
import '../../../core/storage/local_product_image_store.dart';
import '../domain/catalog_product.dart';
import '../domain/catalog_repository.dart';

final class LocalCatalogRepository implements CatalogRepository {
  LocalCatalogRepository(
    this._database, {
    Uuid uuid = const Uuid(),
    DateTime Function()? now,
    LocalProductImageStore? imageStore,
  }) : _uuid = uuid,
       _now = now ?? DateTime.now,
       _imageStore = imageStore;

  final database.AppDatabase _database;
  final Uuid _uuid;
  final DateTime Function() _now;
  final LocalProductImageStore? _imageStore;

  @override
  Stream<List<StoreProduct>> watchProducts({String query = ''}) {
    final statement = _productQuery(query);
    return statement.watch().asyncMap(_mapRows);
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
    return statement.watchSingleOrNull().asyncMap((row) async {
      if (row == null) return null;
      return _mapRow(row, await _unitsFor(row.id));
    });
  }

  @override
  Future<StoreProduct?> getProduct(String id) async {
    final normalizedId = _requiredId(id);
    final row = await (_database.select(
      _database.storeProducts,
    )..where((table) => table.id.equals(normalizedId))).getSingleOrNull();
    if (row == null) return null;
    return _mapRow(row, await _unitsFor(row.id));
  }

  @override
  Future<StoreProduct?> findByBarcode(String rawBarcode) async {
    final parsed = Barcode.tryParse(rawBarcode);
    if (parsed == null) return null;
    final barcode = parsed.value;
    final row = await (_database.select(
      _database.storeProducts,
    )..where((table) => table.barcode.equals(barcode))).getSingleOrNull();
    if (row == null) return null;
    return _mapRow(row, await _unitsFor(row.id));
  }

  @override
  Future<StoreProduct?> findBySource(
    String source,
    String sourceProductId,
  ) async {
    final normalizedSource = _requiredId(source);
    final normalizedSourceProductId = _requiredId(sourceProductId);
    final row =
        await (_database.select(_database.storeProducts)
              ..where(
                (table) =>
                    table.source.equals(normalizedSource) &
                    table.sourceProductId.equals(normalizedSourceProductId),
              )
              ..limit(1))
            .getSingleOrNull();
    if (row == null) return null;
    return _mapRow(row, await _unitsFor(row.id));
  }

  @override
  Future<StoreProduct> createProduct(ProductDraft draft) async {
    final id = _draftId(draft.id);
    final now = _now().toUtc();
    final companion = _companion(
      id: id,
      draft: draft,
      createdAt: now,
      updatedAt: now,
    );
    await _database.transaction(() async {
      await _ensureBarcodeAvailable(draft.barcode);
      await _ensureSourceAvailable(draft.source, draft.sourceProductId);
      await _database.into(_database.storeProducts).insert(companion);
      await _replaceSellingUnits(id, draft.sellingUnits, now);
    });
    return (await getProduct(id))!;
  }

  @override
  Future<StoreProduct> updateProduct(String id, ProductDraft draft) async {
    final normalizedId = _requiredId(id);
    final existing = await getProduct(normalizedId);
    if (existing == null) throw ProductNotFoundException(normalizedId);

    final companion = _companion(
      id: normalizedId,
      draft: draft,
      createdAt: existing.createdAt,
      updatedAt: _now().toUtc(),
    );
    await _database.transaction(() async {
      await _ensureBarcodeAvailable(draft.barcode, excludingId: normalizedId);
      await _ensureSourceAvailable(
        draft.source,
        draft.sourceProductId,
        excludingId: normalizedId,
      );
      await (_database.update(
        _database.storeProducts,
      )..where((table) => table.id.equals(normalizedId))).write(companion);
      await _replaceSellingUnits(
        normalizedId,
        draft.sellingUnits,
        _now().toUtc(),
      );
    });
    return (await getProduct(normalizedId))!;
  }

  @override
  Future<void> deleteProduct(String id) async {
    final normalizedId = _requiredId(id);
    await _database.transaction(() async {
      await (_database.delete(
        _database.productSellingUnits,
      )..where((table) => table.productId.equals(normalizedId))).go();
      await (_database.delete(
        _database.storeProducts,
      )..where((table) => table.id.equals(normalizedId))).go();
    });
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

  Future<List<StoreProduct>> _mapRows(List<database.StoreProduct> rows) async {
    if (rows.isEmpty) return const [];
    final ids = rows.map((row) => row.id).toList(growable: false);
    final unitRows =
        await (_database.select(_database.productSellingUnits)
              ..where((table) => table.productId.isIn(ids))
              ..orderBy([
                (table) => OrderingTerm.asc(table.productId),
                (table) => OrderingTerm.asc(table.position),
                (table) => OrderingTerm.asc(table.id),
              ]))
            .get();
    final unitsByProduct = <String, List<SellingUnit>>{};
    for (final row in unitRows) {
      (unitsByProduct[row.productId] ??= []).add(_mapUnit(row));
    }
    return Future.wait([
      for (final row in rows) _mapRow(row, unitsByProduct[row.id] ?? const []),
    ]);
  }

  Future<StoreProduct> _mapRow(
    database.StoreProduct row,
    List<SellingUnit> sellingUnits,
  ) async {
    final imagePath = await _repairRelocatedImagePath(row);
    return StoreProduct(
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
      localImagePath: imagePath,
      sellingUnits: List<SellingUnit>.unmodifiable(sellingUnits),
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  Future<String?> _repairRelocatedImagePath(database.StoreProduct row) async {
    final stored = row.localImagePath?.trim();
    final imageStore = _imageStore;
    if (stored == null || stored.isEmpty || imageStore == null) return stored;
    final resolved = await imageStore.resolveManagedPath(stored);
    if (resolved == null || resolved == stored) return stored;
    await (_database.update(_database.storeProducts)..where(
          (table) =>
              table.id.equals(row.id) & table.localImagePath.equals(stored),
        ))
        .write(
          database.StoreProductsCompanion(localImagePath: Value(resolved)),
        );
    return resolved;
  }

  SellingUnit _mapUnit(database.ProductSellingUnit row) => SellingUnit(
    id: row.id,
    label: row.label,
    price: Money.fromCentavos(row.priceCentavos),
  );

  Future<List<SellingUnit>> _unitsFor(String productId) async {
    final rows =
        await (_database.select(_database.productSellingUnits)
              ..where((table) => table.productId.equals(productId))
              ..orderBy([
                (table) => OrderingTerm.asc(table.position),
                (table) => OrderingTerm.asc(table.id),
              ]))
            .get();
    return rows.map(_mapUnit).toList(growable: false);
  }

  Future<void> _replaceSellingUnits(
    String productId,
    List<SellingUnitDraft> units,
    DateTime now,
  ) async {
    await (_database.delete(
      _database.productSellingUnits,
    )..where((table) => table.productId.equals(productId))).go();
    for (var position = 0; position < units.length; position++) {
      final unit = units[position];
      final requestedId = unit.id?.trim();
      final id = requestedId == null || requestedId.isEmpty
          ? _uuid.v4()
          : requestedId;
      await _database
          .into(_database.productSellingUnits)
          .insert(
            database.ProductSellingUnitsCompanion.insert(
              id: id,
              productId: productId,
              label: unit.label,
              priceCentavos: unit.priceCentavos,
              position: position,
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
    }
  }

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

  Future<void> _ensureSourceAvailable(
    String? source,
    String? sourceProductId, {
    String? excludingId,
  }) async {
    if (source == null || sourceProductId == null) return;
    final existing =
        await (_database.select(_database.storeProducts)
              ..where(
                (table) =>
                    table.source.equals(source) &
                    table.sourceProductId.equals(sourceProductId),
              )
              ..limit(1))
            .getSingleOrNull();
    if (existing != null && existing.id != excludingId) {
      throw DuplicateCatalogProductException(source, sourceProductId);
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

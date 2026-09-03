import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart' as database;
import '../../../core/database/cart_line_id.dart';
import '../../../core/database/tables.dart' as tables;
import '../../../core/money/money.dart';
import '../../../core/storage/local_product_image_store.dart';
import '../../catalog/domain/catalog_product.dart';
import '../domain/cart.dart';
import '../domain/cart_repository.dart';

final class LocalCartRepository implements CartRepository {
  LocalCartRepository(
    this._database, {
    DateTime Function()? now,
    LocalProductImageStore? imageStore,
  }) : _now = now ?? DateTime.now,
       _imageStore = imageStore;

  final database.AppDatabase _database;
  final DateTime Function() _now;
  final LocalProductImageStore? _imageStore;

  @override
  Stream<CartDraft> watchDraft() => _orderedQuery().watch().asyncMap(_mapRows);

  @override
  Future<CartDraft> getDraft() async => _mapRows(await _orderedQuery().get());

  @override
  Future<void> addProduct(
    StoreProduct product, {
    ProductSaleOption? saleOption,
    int quantity = 1,
  }) async {
    if (quantity <= 0 || quantity > maximumCartQuantity) {
      throw RangeError.range(quantity, 1, maximumCartQuantity, 'quantity');
    }
    final productId = _requiredProductId(product.id);
    final option = saleOption ?? product.saleOptions.first;
    _validateOption(product, option);
    final lineId = buildCartLineId(productId, option.sellingUnitId);
    final now = _now().toUtc();

    await _database.transaction(() async {
      final existing = await (_database.select(
        _database.draftCartItems,
      )..where((table) => table.lineId.equals(lineId))).getSingleOrNull();

      if (existing == null) {
        await _database
            .into(_database.draftCartItems)
            .insert(
              database.DraftCartItemsCompanion.insert(
                lineId: lineId,
                productId: productId,
                sellingUnitId: Value(option.sellingUnitId),
                barcode: Value(product.barcode),
                nameSnapshot: product.name,
                brandSnapshot: Value(product.brand),
                unitLabelSnapshot: Value(
                  option.isDefault
                      ? product.unitLabel ??
                            (product.sellingUnits.isEmpty ? null : option.label)
                      : option.label,
                ),
                imagePathSnapshot: Value(
                  product.localImagePath ??
                      product.catalogImagePath ??
                      product.remoteImageUrl,
                ),
                unitPriceCentavos: option.priceCentavos,
                quantity: quantity,
                addedAt: Value(now),
                updatedAt: Value(now),
              ),
            );
        return;
      }

      final updatedQuantity = existing.quantity + quantity;
      if (updatedQuantity > maximumCartQuantity) {
        throw RangeError.range(
          updatedQuantity,
          1,
          maximumCartQuantity,
          'quantity',
        );
      }
      await (_database.update(
        _database.draftCartItems,
      )..where((table) => table.lineId.equals(lineId))).write(
        database.DraftCartItemsCompanion(
          quantity: Value(updatedQuantity),
          updatedAt: Value(now),
        ),
      );
    });
  }

  @override
  Future<void> updateQuantity(String lineId, int quantity) async {
    if (quantity < 0 || quantity > maximumCartQuantity) {
      throw RangeError.range(quantity, 0, maximumCartQuantity, 'quantity');
    }
    final normalizedId = _requiredLineId(lineId);
    if (quantity == 0) {
      await removeProduct(normalizedId);
      return;
    }

    final changed =
        await (_database.update(
          _database.draftCartItems,
        )..where((table) => table.lineId.equals(normalizedId))).write(
          database.DraftCartItemsCompanion(
            quantity: Value(quantity),
            updatedAt: Value(_now().toUtc()),
          ),
        );
    if (changed == 0) throw CartProductNotFoundException(normalizedId);
  }

  @override
  Future<void> removeProduct(String lineId) async {
    final normalizedId = _requiredLineId(lineId);
    await (_database.delete(
      _database.draftCartItems,
    )..where((table) => table.lineId.equals(normalizedId))).go();
  }

  @override
  Future<void> clear() => _database.delete(_database.draftCartItems).go();

  SimpleSelectStatement<tables.DraftCartItems, database.DraftCartItem>
  _orderedQuery() {
    return _database.select(_database.draftCartItems)..orderBy([
      (table) => OrderingTerm.asc(table.addedAt),
      (table) => OrderingTerm.asc(table.lineId),
    ]);
  }

  Future<CartDraft> _mapRows(List<database.DraftCartItem> rows) async {
    final items = await Future.wait([for (final row in rows) _mapRow(row)]);
    return CartDraft(items);
  }

  Future<CartItem> _mapRow(database.DraftCartItem row) async {
    final imagePath = await _repairRelocatedImagePath(row);
    return CartItem(
      lineId: row.lineId,
      productId: row.productId,
      sellingUnitId: row.sellingUnitId,
      barcode: row.barcode,
      nameSnapshot: row.nameSnapshot,
      brandSnapshot: row.brandSnapshot,
      unitLabelSnapshot: row.unitLabelSnapshot,
      imagePathSnapshot: imagePath,
      unitPrice: Money.fromCentavos(row.unitPriceCentavos),
      quantity: row.quantity,
      addedAt: row.addedAt,
      updatedAt: row.updatedAt,
    );
  }

  Future<String?> _repairRelocatedImagePath(database.DraftCartItem row) async {
    final stored = row.imagePathSnapshot?.trim();
    final imageStore = _imageStore;
    if (stored == null || stored.isEmpty || imageStore == null) return stored;
    final uri = Uri.tryParse(stored);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return stored;
    }
    final resolved = await imageStore.resolveManagedPath(stored);
    if (resolved == null || resolved == stored) return stored;
    await (_database.update(_database.draftCartItems)..where(
          (table) =>
              table.lineId.equals(row.lineId) &
              table.imagePathSnapshot.equals(stored),
        ))
        .write(
          database.DraftCartItemsCompanion(imagePathSnapshot: Value(resolved)),
        );
    return resolved;
  }

  String _requiredProductId(String productId) {
    final normalized = productId.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(productId, 'productId', 'Must not be blank.');
    }
    return normalized;
  }

  String _requiredLineId(String lineId) {
    final normalized = lineId.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(lineId, 'lineId', 'Must not be blank.');
    }
    return normalized;
  }

  void _validateOption(StoreProduct product, ProductSaleOption option) {
    final unitId = option.sellingUnitId;
    if (unitId == null) {
      if (!option.isDefault ||
          option.label != product.defaultSellingUnitLabel ||
          option.price != product.price) {
        throw ArgumentError.value(
          option,
          'saleOption',
          'The default option does not belong to this product.',
        );
      }
      return;
    }
    final matches = product.sellingUnits.any(
      (unit) =>
          unit.id == unitId &&
          unit.label == option.label &&
          unit.price == option.price,
    );
    if (!matches) {
      throw ArgumentError.value(
        option,
        'saleOption',
        'The selling unit does not belong to this product.',
      );
    }
  }
}

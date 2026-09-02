import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart' as database;
import '../../../core/database/tables.dart' as tables;
import '../../../core/money/money.dart';
import '../../catalog/domain/catalog_product.dart';
import '../domain/cart.dart';
import '../domain/cart_repository.dart';

final class LocalCartRepository implements CartRepository {
  LocalCartRepository(this._database, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final database.AppDatabase _database;
  final DateTime Function() _now;

  @override
  Stream<CartDraft> watchDraft() => _orderedQuery().watch().map(_mapRows);

  @override
  Future<CartDraft> getDraft() async => _mapRows(await _orderedQuery().get());

  @override
  Future<void> addProduct(StoreProduct product, {int quantity = 1}) async {
    if (quantity <= 0 || quantity > maximumCartQuantity) {
      throw RangeError.range(quantity, 1, maximumCartQuantity, 'quantity');
    }
    final productId = _requiredProductId(product.id);
    final now = _now().toUtc();

    await _database.transaction(() async {
      final existing = await (_database.select(
        _database.draftCartItems,
      )..where((table) => table.productId.equals(productId))).getSingleOrNull();

      if (existing == null) {
        await _database
            .into(_database.draftCartItems)
            .insert(
              database.DraftCartItemsCompanion.insert(
                productId: productId,
                barcode: Value(product.barcode),
                nameSnapshot: product.name,
                brandSnapshot: Value(product.brand),
                unitLabelSnapshot: Value(product.unitLabel),
                imagePathSnapshot: Value(
                  product.localImagePath ?? product.remoteImageUrl,
                ),
                unitPriceCentavos: product.priceCentavos,
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
      )..where((table) => table.productId.equals(productId))).write(
        database.DraftCartItemsCompanion(
          quantity: Value(updatedQuantity),
          updatedAt: Value(now),
        ),
      );
    });
  }

  @override
  Future<void> updateQuantity(String productId, int quantity) async {
    if (quantity < 0 || quantity > maximumCartQuantity) {
      throw RangeError.range(quantity, 0, maximumCartQuantity, 'quantity');
    }
    final normalizedId = _requiredProductId(productId);
    if (quantity == 0) {
      await removeProduct(normalizedId);
      return;
    }

    final changed =
        await (_database.update(
          _database.draftCartItems,
        )..where((table) => table.productId.equals(normalizedId))).write(
          database.DraftCartItemsCompanion(
            quantity: Value(quantity),
            updatedAt: Value(_now().toUtc()),
          ),
        );
    if (changed == 0) throw CartProductNotFoundException(normalizedId);
  }

  @override
  Future<void> removeProduct(String productId) async {
    final normalizedId = _requiredProductId(productId);
    await (_database.delete(
      _database.draftCartItems,
    )..where((table) => table.productId.equals(normalizedId))).go();
  }

  @override
  Future<void> clear() => _database.delete(_database.draftCartItems).go();

  SimpleSelectStatement<tables.DraftCartItems, database.DraftCartItem>
  _orderedQuery() {
    return _database.select(_database.draftCartItems)..orderBy([
      (table) => OrderingTerm.asc(table.addedAt),
      (table) => OrderingTerm.asc(table.productId),
    ]);
  }

  CartDraft _mapRows(List<database.DraftCartItem> rows) => CartDraft(
    rows.map(
      (row) => CartItem(
        productId: row.productId,
        barcode: row.barcode,
        nameSnapshot: row.nameSnapshot,
        brandSnapshot: row.brandSnapshot,
        unitLabelSnapshot: row.unitLabelSnapshot,
        imagePathSnapshot: row.imagePathSnapshot,
        unitPrice: Money.fromCentavos(row.unitPriceCentavos),
        quantity: row.quantity,
        addedAt: row.addedAt,
        updatedAt: row.updatedAt,
      ),
    ),
  );

  String _requiredProductId(String productId) {
    final normalized = productId.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(productId, 'productId', 'Must not be blank.');
    }
    return normalized;
  }
}

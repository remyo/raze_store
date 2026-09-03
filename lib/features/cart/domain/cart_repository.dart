import '../../catalog/domain/catalog_product.dart';
import 'cart.dart';

abstract interface class CartRepository {
  Stream<CartDraft> watchDraft();

  Future<CartDraft> getDraft();

  /// Adds a new snapshot or increments the same product + unit selection.
  ///
  /// Omitting [saleOption] preserves the original behavior and adds the
  /// product's barcode/default selling unit.
  Future<void> addProduct(
    StoreProduct product, {
    ProductSaleOption? saleOption,
    int quantity = 1,
  });

  /// A quantity of zero removes the row. Negative quantities are rejected.
  Future<void> updateQuantity(String lineId, int quantity);

  Future<void> removeProduct(String lineId);

  Future<void> clear();
}

final class CartProductNotFoundException implements Exception {
  const CartProductNotFoundException(this.lineId);

  final String lineId;

  @override
  String toString() => 'Cart line $lineId was not found.';
}

import '../../catalog/domain/catalog_product.dart';
import 'cart.dart';

abstract interface class CartRepository {
  Stream<CartDraft> watchDraft();

  Future<CartDraft> getDraft();

  /// Adds a new snapshot or increments the existing product's quantity.
  Future<void> addProduct(StoreProduct product, {int quantity = 1});

  /// A quantity of zero removes the row. Negative quantities are rejected.
  Future<void> updateQuantity(String productId, int quantity);

  Future<void> removeProduct(String productId);

  Future<void> clear();
}

final class CartProductNotFoundException implements Exception {
  const CartProductNotFoundException(this.productId);

  final String productId;

  @override
  String toString() => 'Cart product $productId was not found.';
}

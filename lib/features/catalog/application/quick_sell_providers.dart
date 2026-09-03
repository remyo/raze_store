import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/catalog_product.dart';
import 'catalog_providers.dart';

/// Saved products that have at least one alternate selling unit.
///
/// Keeping this as a separate stream lets the quick-unit page stay focused on
/// products sold by piece, stick, sachet, tray, and similar sari-sari units.
final quickSellProductsProvider = StreamProvider<List<StoreProduct>>((ref) {
  return ref
      .watch(catalogRepositoryProvider)
      .watchProducts()
      .map(
        (products) => List<StoreProduct>.unmodifiable(
          products.where((product) => product.sellingUnits.isNotEmpty),
        ),
      );
});

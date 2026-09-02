import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../data/local_catalog_repository.dart';
import '../domain/catalog_product.dart';
import '../domain/catalog_repository.dart';

final catalogRepositoryProvider = Provider<CatalogRepository>((ref) {
  return LocalCatalogRepository(ref.watch(appDatabaseProvider));
});

final catalogSearchQueryProvider = NotifierProvider<CatalogSearchQuery, String>(
  CatalogSearchQuery.new,
);

final class CatalogSearchQuery extends Notifier<String> {
  @override
  String build() => '';

  void update(String value) => state = value;

  void clear() => state = '';
}

final catalogProductsProvider = StreamProvider<List<StoreProduct>>((ref) {
  final query = ref.watch(catalogSearchQueryProvider);
  return ref.watch(catalogRepositoryProvider).watchProducts(query: query);
});

final catalogProductProvider = StreamProvider.family<StoreProduct?, String>((
  ref,
  id,
) {
  return ref.watch(catalogRepositoryProvider).watchProduct(id);
});

final catalogProductByBarcodeProvider =
    FutureProvider.family<StoreProduct?, String>((ref, barcode) {
      return ref.watch(catalogRepositoryProvider).findByBarcode(barcode);
    });

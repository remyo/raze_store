import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../../../core/storage/product_photo_services.dart';
import '../data/local_catalog_repository.dart';
import '../domain/catalog_categories.dart';
import '../domain/catalog_product.dart';
import '../domain/catalog_repository.dart';
import 'catalog_api_providers.dart';

final catalogRepositoryProvider = Provider<CatalogRepository>((ref) {
  return LocalCatalogRepository(
    ref.watch(appDatabaseProvider),
    imageStore: ref.watch(localProductImageStoreProvider),
  );
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

final catalogStoredCategoriesProvider = StreamProvider<List<String>>((ref) {
  return ref
      .watch(catalogRepositoryProvider)
      .watchProducts()
      .map(
        (products) => distinctCatalogCategories(
          products.map((product) => product.category),
        ),
      );
});

final catalogApiCategoriesProvider = FutureProvider<List<String>>((ref) async {
  final repository = ref.watch(remoteCatalogRepositoryProvider);
  if (!repository.isConfigured) return const [];
  try {
    return await repository.fetchCategories();
  } on Object {
    // Category suggestions are optional. Keep the product form fully usable
    // with its built-in and locally stored categories while offline.
    return const [];
  }
});

final catalogCategorySuggestionsProvider = Provider<List<String>>((ref) {
  final storedCategories = ref
      .watch(catalogStoredCategoriesProvider)
      .when(
        data: (categories) => categories,
        error: (_, _) => const <String>[],
        loading: () => const <String>[],
      );
  return mergeCatalogCategories(
    storedCategories: storedCategories,
    apiCategories: ref
        .watch(catalogApiCategoriesProvider)
        .when(
          data: (categories) => categories,
          error: (_, _) => const <String>[],
          loading: () => const <String>[],
        ),
  );
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

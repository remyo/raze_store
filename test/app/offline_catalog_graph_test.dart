import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:raze_store/app/router.dart';
import 'package:raze_store/features/catalog/application/catalog_lookup_providers.dart';
import 'package:raze_store/features/catalog/application/catalog_lookup_service.dart';
import 'package:raze_store/features/catalog/application/catalog_providers.dart';
import 'package:raze_store/features/catalog/domain/catalog_product.dart';
import 'package:raze_store/features/catalog/domain/catalog_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  test('production barcode lookup uses only the local catalog', () async {
    final local = _LocalMissCatalogRepository();
    final container = ProviderContainer(
      overrides: [catalogRepositoryProvider.overrideWithValue(local)],
    );
    addTearDown(container.dispose);

    final lookup = container.read(catalogLookupServiceProvider);

    expect(lookup.remote, isNull);
    expect(
      (await lookup.findByBarcode('4807770270055')).kind,
      CatalogLookupKind.notFound,
    );
    expect(local.barcodeLookups, 1);
  });

  test('production router has no connected catalog screen', () {
    final paths = _routePaths(appRouter.configuration.routes).toList();

    expect(paths, isNot(contains('/catalog')));
    expect(paths, contains('/profile'));
    expect(paths, contains('/cart'));
    expect(paths, contains('/quick-sell'));
    expect(paths, contains('/sales'));
    expect(paths, contains(':id'));
    expect(paths, contains('/settings/storage'));
    expect(paths, contains('/settings/products/delete'));
  });
}

Iterable<String> _routePaths(Iterable<RouteBase> routes) sync* {
  for (final route in routes) {
    if (route is GoRoute) yield route.path;
    yield* _routePaths(route.routes);
  }
}

final class _LocalMissCatalogRepository implements CatalogRepository {
  int barcodeLookups = 0;

  @override
  Future<StoreProduct?> findByBarcode(String barcode) async {
    barcodeLookups++;
    return null;
  }

  @override
  Future<StoreProduct?> findBySource(
    String source,
    String sourceProductId,
  ) async => null;

  @override
  Future<StoreProduct?> getProduct(String id) async => null;

  @override
  Future<List<StoreProduct>> searchProducts(String query) async => const [];

  @override
  Stream<StoreProduct?> watchProduct(String id) => const Stream.empty();

  @override
  Stream<List<StoreProduct>> watchProducts({String query = ''}) =>
      Stream.value(const []);

  @override
  Future<StoreProduct> createProduct(ProductDraft draft) =>
      throw UnimplementedError();

  @override
  Future<StoreProduct> updateProduct(String id, ProductDraft draft) =>
      throw UnimplementedError();

  @override
  Future<void> deleteProduct(String id) => throw UnimplementedError();
}

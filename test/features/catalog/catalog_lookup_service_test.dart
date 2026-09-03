import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/core/money/money.dart';
import 'package:raze_store/features/catalog/application/catalog_lookup_service.dart';
import 'package:raze_store/features/catalog/domain/catalog_product.dart';
import 'package:raze_store/features/catalog/domain/catalog_repository.dart';
import 'package:raze_store/features/catalog/domain/remote_catalog_product.dart';
import 'package:raze_store/features/catalog/domain/remote_catalog_repository.dart';

void main() {
  group('CatalogLookupService', () {
    test(
      'returns not found after a local miss when running offline-only',
      () async {
        final local = _FakeLocalRepository();
        final service = CatalogLookupService(local: local);

        final result = await service.findByBarcode('4800012345678');

        expect(result.kind, CatalogLookupKind.notFound);
      },
    );

    test('returns a local priced product without calling the API', () async {
      final local = _FakeLocalRepository(product: _storeProduct());
      final remote = _FakeRemoteRepository(product: _remoteProduct());
      final service = CatalogLookupService(local: local, remote: remote);

      final result = await service.findByBarcode('4800012345678');

      expect(result.kind, CatalogLookupKind.local);
      expect(result.localProduct?.priceCentavos, 1500);
      expect(remote.lookupCalls, 0);
    });

    test(
      'uses remote metadata after a local miss without inventing a price',
      () async {
        final remote = _FakeRemoteRepository(product: _remoteProduct());
        final service = CatalogLookupService(
          local: _FakeLocalRepository(),
          remote: remote,
        );

        final result = await service.findByBarcode('4800012345678');

        expect(result.kind, CatalogLookupKind.remote);
        expect(result.remoteProduct?.name, 'API product');
        expect(result.remoteProduct?.metadata.source, 'raze_store_api');
        expect(remote.lookupCalls, 1);
      },
    );

    test('keeps the scanned API alias for future offline lookup', () async {
      final service = CatalogLookupService(
        local: _FakeLocalRepository(),
        remote: _FakeRemoteRepository(
          product: _remoteProduct(barcode: '0888888888888'),
        ),
      );

      final result = await service.findByBarcode('ALIAS+BLUE');

      expect(result.remoteProduct?.barcode, 'ALIAS+BLUE');
      expect(result.remoteProduct?.catalogProductId, 'remote-id');
    });

    test(
      'returns an existing API product saved under another barcode alias',
      () async {
        final existing = _storeProduct();
        final service = CatalogLookupService(
          local: _FakeLocalRepository(sourceProduct: existing),
          remote: _FakeRemoteRepository(
            product: _remoteProduct(barcode: '0888888888888'),
          ),
        );

        final result = await service.findByBarcode('ALIAS+BLUE');

        expect(result.kind, CatalogLookupKind.local);
        expect(result.localProduct, same(existing));
      },
    );

    test('distinguishes an API outage from a genuine miss', () async {
      final remote = _FakeRemoteRepository(error: StateError('offline'));
      final service = CatalogLookupService(
        local: _FakeLocalRepository(),
        remote: remote,
      );

      final result = await service.findByBarcode('4800012345678');

      expect(result.kind, CatalogLookupKind.unavailable);
      expect(result.error, isA<StateError>());
    });

    test('does not call an unconfigured API', () async {
      final remote = _FakeRemoteRepository(configured: false);
      final service = CatalogLookupService(
        local: _FakeLocalRepository(),
        remote: remote,
      );

      final result = await service.findByBarcode('4800012345678');

      expect(result.kind, CatalogLookupKind.notFound);
      expect(remote.lookupCalls, 0);
    });
  });
}

StoreProduct _storeProduct() => StoreProduct(
  id: 'local-id',
  metadata: CatalogMetadata(barcode: '4800012345678', name: 'Local product'),
  price: Money.fromCentavos(1500),
  createdAt: DateTime.utc(2026, 9, 3),
  updatedAt: DateTime.utc(2026, 9, 3),
);

RemoteCatalogProduct _remoteProduct({String barcode = '4800012345678'}) =>
    RemoteCatalogProduct(
      catalogProductId: 'remote-id',
      metadata: CatalogMetadata(
        barcode: barcode,
        name: 'API product',
        source: 'raze_store_api',
        sourceProductId: 'remote-id',
      ),
      updatedAt: DateTime.utc(2026, 9, 3),
    );

final class _FakeLocalRepository implements CatalogRepository {
  _FakeLocalRepository({this.product, this.sourceProduct});

  final StoreProduct? product;
  final StoreProduct? sourceProduct;

  @override
  Future<StoreProduct?> findByBarcode(String rawBarcode) async => product;

  @override
  Future<StoreProduct?> findBySource(
    String source,
    String sourceProductId,
  ) async => sourceProduct;

  @override
  Future<StoreProduct> createProduct(ProductDraft draft) =>
      throw UnimplementedError();

  @override
  Future<void> deleteProduct(String id) => throw UnimplementedError();

  @override
  Future<StoreProduct?> getProduct(String id) => throw UnimplementedError();

  @override
  Future<List<StoreProduct>> searchProducts(String query) =>
      throw UnimplementedError();

  @override
  Future<StoreProduct> updateProduct(String id, ProductDraft draft) =>
      throw UnimplementedError();

  @override
  Stream<StoreProduct?> watchProduct(String id) => const Stream.empty();

  @override
  Stream<List<StoreProduct>> watchProducts({String query = ''}) =>
      const Stream.empty();
}

final class _FakeRemoteRepository implements RemoteCatalogRepository {
  _FakeRemoteRepository({this.product, this.error, this.configured = true});

  final RemoteCatalogProduct? product;
  final Object? error;
  final bool configured;
  int lookupCalls = 0;

  @override
  Uri? get baseUri => configured ? Uri.parse('https://catalog.example/') : null;

  @override
  String? get configurationError => null;

  @override
  bool get isConfigured => configured;

  @override
  Future<RemoteCatalogProduct?> findByBarcode(String barcode) async {
    lookupCalls++;
    if (error case final value?) throw value;
    return product;
  }

  @override
  Future<CatalogApiHealth> checkHealth() => throw UnimplementedError();

  @override
  Future<List<String>> fetchCategories() => throw UnimplementedError();

  @override
  Future<RemoteCatalogPage> searchProducts({String query = '', int page = 1}) =>
      throw UnimplementedError();
}

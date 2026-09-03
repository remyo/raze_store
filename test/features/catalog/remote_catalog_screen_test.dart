import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/features/catalog/application/catalog_api_providers.dart';
import 'package:raze_store/features/catalog/application/catalog_providers.dart';
import 'package:raze_store/features/catalog/domain/catalog_product.dart';
import 'package:raze_store/features/catalog/domain/catalog_repository.dart';
import 'package:raze_store/features/catalog/domain/remote_catalog_product.dart';
import 'package:raze_store/features/catalog/domain/remote_catalog_repository.dart';
import 'package:raze_store/features/catalog/presentation/remote_catalog_screen.dart';

void main() {
  testWidgets('searches and pages through the shared product catalog', (
    tester,
  ) async {
    final repository = _FakeRemoteCatalogRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          remoteCatalogRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const RemoteCatalogScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('API product 1'), findsOneWidget);
    expect(find.text('Select'), findsOneWidget);
    expect(repository.requests, [('', 1)]);

    await tester.tap(find.byKey(const ValueKey('remote-catalog-load-more')));
    await tester.pumpAndSettle();

    expect(find.text('API product 2'), findsOneWidget);
    expect(repository.requests, [('', 1), ('', 2)]);

    await tester.enterText(find.byType(TextField), 'coffee');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(repository.requests.last, ('coffee', 1));
  });

  testWidgets('locks all selections and reports a local lookup failure', (
    tester,
  ) async {
    final repository = _FakeRemoteCatalogRepository(includeSecondProduct: true);
    final lookup = Completer<StoreProduct?>();
    final local = _BlockingCatalogRepository(lookup.future);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          remoteCatalogRepositoryProvider.overrideWithValue(repository),
          catalogRepositoryProvider.overrideWithValue(local),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const RemoteCatalogScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('remote-product-select--1')));
    await tester.pump();

    expect(local.lookupCalls, 1);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('remote-product-select--1-second')),
          )
          .onPressed,
      isNull,
    );

    lookup.completeError(StateError('database unavailable'));
    await tester.pumpAndSettle();

    expect(local.lookupCalls, 1);
    expect(
      find.text('This product could not be opened. Please try again.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

final class _FakeRemoteCatalogRepository implements RemoteCatalogRepository {
  _FakeRemoteCatalogRepository({this.includeSecondProduct = false});

  final bool includeSecondProduct;
  final requests = <(String, int)>[];

  @override
  Uri get baseUri => Uri.parse('https://catalog.example/api/v1/');

  @override
  String? get configurationError => null;

  @override
  bool get isConfigured => true;

  @override
  Future<RemoteCatalogPage> searchProducts({
    String query = '',
    int page = 1,
  }) async {
    requests.add((query, page));
    return RemoteCatalogPage(
      products: [
        RemoteCatalogProduct(
          catalogProductId: '$query-$page',
          metadata: CatalogMetadata(
            barcode: '480000000000$page',
            name: query.isEmpty ? 'API product $page' : '$query result',
            source: 'raze_store_api',
            sourceProductId: '$query-$page',
          ),
          updatedAt: DateTime.utc(2026, 9, 3),
        ),
        if (includeSecondProduct)
          RemoteCatalogProduct(
            catalogProductId: '$query-$page-second',
            metadata: CatalogMetadata(
              barcode: '490000000000$page',
              name: 'Second API product',
              source: 'raze_store_api',
              sourceProductId: '$query-$page-second',
            ),
            updatedAt: DateTime.utc(2026, 9, 3),
          ),
      ],
      totalCount: 2,
      page: page,
      hasNextPage: query.isEmpty && page == 1,
    );
  }

  @override
  Future<CatalogApiHealth> checkHealth() => throw UnimplementedError();

  @override
  Future<List<String>> fetchCategories() => throw UnimplementedError();

  @override
  Future<RemoteCatalogProduct?> findByBarcode(String barcode) =>
      throw UnimplementedError();
}

final class _BlockingCatalogRepository implements CatalogRepository {
  _BlockingCatalogRepository(this.lookup);

  final Future<StoreProduct?> lookup;
  int lookupCalls = 0;

  @override
  Future<StoreProduct?> findByBarcode(String rawBarcode) {
    lookupCalls++;
    return lookup;
  }

  @override
  Future<StoreProduct?> findBySource(String source, String sourceProductId) =>
      throw UnimplementedError();

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

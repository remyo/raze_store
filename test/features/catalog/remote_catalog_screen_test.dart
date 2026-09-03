import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/features/catalog/application/catalog_api_providers.dart';
import 'package:raze_store/features/catalog/domain/catalog_product.dart';
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
}

final class _FakeRemoteCatalogRepository implements RemoteCatalogRepository {
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

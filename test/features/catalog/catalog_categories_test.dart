import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/features/catalog/application/catalog_api_providers.dart';
import 'package:raze_store/features/catalog/application/catalog_providers.dart';
import 'package:raze_store/features/catalog/domain/catalog_categories.dart';
import 'package:raze_store/features/catalog/domain/remote_catalog_product.dart';
import 'package:raze_store/features/catalog/domain/remote_catalog_repository.dart';

void main() {
  test('merges starter, stored, and API categories without duplicates', () {
    final categories = mergeCatalogCategories(
      storedCategories: const [' Coffee & Beverages ', 'beverages', ''],
      apiCategories: const ['Fresh Produce', 'coffee & beverages'],
    );

    expect(categories, containsAll(starterCatalogCategories));
    expect(categories, contains('Coffee & Beverages'));
    expect(categories, contains('Fresh Produce'));
    expect(
      categories.where((category) => category.toLowerCase() == 'beverages'),
      ['Beverages'],
    );
    expect(
      categories.where(
        (category) => category.toLowerCase() == 'coffee & beverages',
      ),
      ['Coffee & Beverages'],
    );
    expect(
      categories,
      orderedEquals(
        [...categories]
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())),
      ),
    );
  });

  test('matches custom categories without case or surrounding spaces', () {
    final categories = mergeCatalogCategories(
      storedCategories: const ['Mobile Load'],
    );

    expect(matchingCatalogCategories('  mobile ', categories: categories), [
      'Mobile Load',
    ]);
  });

  test(
    'adds live API categories to offline and locally stored values',
    () async {
      final container = ProviderContainer(
        overrides: [
          remoteCatalogRepositoryProvider.overrideWithValue(
            _CategoryRemoteRepository(),
          ),
          catalogStoredCategoriesProvider.overrideWithValue(
            const AsyncValue.data(['Mobile Load']),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(catalogApiCategoriesProvider.future);

      final suggestions = container.read(catalogCategorySuggestionsProvider);
      expect(suggestions, contains('Mobile Load'));
      expect(suggestions, contains('Fresh Produce'));
      expect(suggestions, containsAll(starterCatalogCategories));
    },
  );
}

final class _CategoryRemoteRepository implements RemoteCatalogRepository {
  @override
  Uri get baseUri => Uri.parse('https://catalog.example/api/v1/');

  @override
  String? get configurationError => null;

  @override
  bool get isConfigured => true;

  @override
  Future<List<String>> fetchCategories() async => const ['Fresh Produce'];

  @override
  Future<CatalogApiHealth> checkHealth() => throw UnimplementedError();

  @override
  Future<RemoteCatalogProduct?> findByBarcode(String barcode) =>
      throw UnimplementedError();

  @override
  Future<RemoteCatalogPage> searchProducts({String query = '', int page = 1}) =>
      throw UnimplementedError();
}

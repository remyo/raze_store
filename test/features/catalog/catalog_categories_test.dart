import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/features/catalog/application/catalog_providers.dart';
import 'package:raze_store/features/catalog/domain/catalog_categories.dart';

void main() {
  test('merges starter, stored, and API categories without duplicates', () {
    final categories = mergeCatalogCategories(
      storedCategories: const [' Coffee & Beverages ', 'beverages', ''],
      apiCategories: const ['Fresh Produce', 'coffee & beverages'],
    );

    expect(categories, containsAll(starterCatalogCategories));
    expect(
      categories,
      containsAll(const ['Canned Goods', 'Snacks', 'Biscuits', 'Bread']),
    );
    expect(categories, isNot(contains('Biscuits & Snacks')));
    expect(categories, isNot(contains('Bread & Bakery')));
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

  test('starter catalog pack uses only broad shelf categories', () async {
    final source =
        jsonDecode(
              await File(
                'catalog_packs/filipino-sari-sari-starter-v1/source.json',
              ).readAsString(),
            )
            as Map<String, Object?>;
    final products = source['products']! as List<Object?>;
    final categories = products
        .cast<Map<String, Object?>>()
        .map((product) => product['category']! as String)
        .toSet();

    expect(categories, everyElement(isIn(starterCatalogCategories)));
    expect(
      categories,
      containsAll(const ['Canned Goods', 'Snacks', 'Biscuits', 'Beverages']),
    );
  });

  test(
    'adds locally stored categories to the offline starter values',
    () async {
      final container = ProviderContainer(
        overrides: [
          catalogStoredCategoriesProvider.overrideWithValue(
            const AsyncValue.data(['Mobile Load']),
          ),
        ],
      );
      addTearDown(container.dispose);

      final suggestions = container.read(catalogCategorySuggestionsProvider);
      expect(suggestions, contains('Mobile Load'));
      expect(suggestions, containsAll(starterCatalogCategories));
    },
  );
}

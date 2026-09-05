import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/features/catalog/application/catalog_providers.dart';
import 'package:raze_store/features/catalog/domain/catalog_categories.dart';
import 'package:raze_store/features/catalog/domain/catalog_taxonomy.dart';

void main() {
  test('general taxonomy preserves all parent-scoped entries', () {
    expect(generalCatalogCategoryGroups, hasLength(20));
    expect(generalCatalogSubcategories, hasLength(283));
    expect(
      generalCatalogCategoryNames,
      orderedEquals(const [
        'Food & Beverages',
        'Personal Care & Beauty',
        'Health & Wellness',
        'Household & Cleaning',
        'Baby & Kids',
        'Clothing & Fashion',
        'Shoes & Accessories',
        'Electronics & Gadgets',
        'Home & Furniture',
        'Appliances',
        'Sports & Fitness',
        'Automotive',
        'Tools & Hardware',
        'Pet Supplies',
        'Office & School Supplies',
        'Toys & Hobbies',
        'Books & Media',
        'Jewelry & Watches',
        'Grocery & Daily Essentials',
        'Agriculture & Garden',
      ]),
    );
  });

  test('same-named subcategories retain each parent membership', () {
    final parentsBySubcategory = <String, List<String>>{};
    for (final group in generalCatalogCategoryGroups) {
      for (final subcategory in group.subcategories) {
        parentsBySubcategory.putIfAbsent(subcategory, () => []).add(group.name);
      }
    }

    expect(
      parentsBySubcategory.entries
          .where((entry) => entry.value.length > 1)
          .map((entry) => entry.key)
          .toSet(),
      {
        'Baby Clothing',
        'Coffee & Tea',
        'Computer Accessories',
        'Office Furniture',
        'Pest Control',
      },
    );
    expect(parentsBySubcategory['Baby Clothing'], [
      'Baby & Kids',
      'Clothing & Fashion',
    ]);
    expect(parentsBySubcategory['Coffee & Tea'], [
      'Food & Beverages',
      'Grocery & Daily Essentials',
    ]);
    expect(parentsBySubcategory['Computer Accessories'], [
      'Electronics & Gadgets',
      'Office & School Supplies',
    ]);
    expect(parentsBySubcategory['Office Furniture'], [
      'Home & Furniture',
      'Office & School Supplies',
    ]);
    expect(parentsBySubcategory['Pest Control'], [
      'Household & Cleaning',
      'Agriculture & Garden',
    ]);
  });

  test(
    'flat built-in suggestions include starters, general groups, and leaves',
    () {
      expect(builtInCatalogCategories, hasLength(312));
      expect(builtInCatalogCategories, containsAll(starterCatalogCategories));
      expect(
        builtInCatalogCategories,
        containsAll(generalCatalogCategoryNames),
      );
      expect(
        builtInCatalogCategories,
        containsAll(generalCatalogSubcategories.toSet()),
      );
      expect(
        builtInCatalogCategories
            .map((category) => category.toLowerCase())
            .toSet(),
        hasLength(builtInCatalogCategories.length),
      );
      expect(isBuiltInCatalogCategory(' remote-controlled toys '), isTrue);
      expect(matchingCatalogCategories('remote-controlled'), [
        'Remote-Controlled Toys',
      ]);
    },
  );

  test('merges starter, stored, and API categories without duplicates', () {
    final categories = mergeCatalogCategories(
      storedCategories: const [' Coffee & Beverages ', 'beverages', ''],
      apiCategories: const ['Fresh Produce', 'coffee & beverages'],
    );

    expect(categories, containsAll(starterCatalogCategories));
    expect(categories, containsAll(generalCatalogSubcategories.toSet()));
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

    expect(
      matchingCatalogCategories('  mobile ', categories: categories),
      containsAll(const ['Mobile Accessories', 'Mobile Load']),
    );
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
      expect(suggestions, containsAll(builtInCatalogCategories));
    },
  );
}

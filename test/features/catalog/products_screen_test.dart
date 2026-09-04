import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/core/money/money.dart';
import 'package:raze_store/features/cart/application/cart_providers.dart';
import 'package:raze_store/features/cart/domain/cart.dart';
import 'package:raze_store/features/catalog/application/catalog_providers.dart';
import 'package:raze_store/features/catalog/domain/catalog_product.dart';
import 'package:raze_store/features/catalog/presentation/product_image.dart';
import 'package:raze_store/features/catalog/presentation/products_screen.dart';

void main() {
  testWidgets('debounces search and keeps keyboard focused while reloading', (
    tester,
  ) async {
    final filteredResults = StreamController<List<StoreProduct>>.broadcast();
    addTearDown(filteredResults.close);
    final observedQueries = <String>[];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          _emptyCartOverride,
          catalogProductsProvider.overrideWith((ref) {
            final query = ref.watch(catalogSearchQueryProvider);
            observedQueries.add(query);
            if (query.isEmpty) return Stream.value([_coffee]);
            return filteredResults.stream;
          }),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const ProductsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    expect(find.byTooltip('Add product'), findsOneWidget);
    expect(find.byKey(const ValueKey('open-cart')), findsOneWidget);
    expect(find.byTooltip('Quick add by unit'), findsNothing);
    expect(find.byTooltip('Store settings'), findsNothing);

    final searchField = find.byType(TextField);
    await tester.tap(searchField);
    await tester.enterText(searchField, 'c');
    await tester.pump(const Duration(milliseconds: 125));
    await tester.enterText(searchField, 'co');
    await tester.pump(const Duration(milliseconds: 249));

    expect(observedQueries, isNot(contains('c')));
    expect(observedQueries, isNot(contains('co')));
    expect(searchField, findsOneWidget);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isTrue,
    );
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.pump(const Duration(milliseconds: 1));

    expect(observedQueries, isNot(contains('c')));
    expect(observedQueries, contains('co'));
    expect(find.byKey(const ValueKey('product-search-progress')), findsOne);
    expect(searchField, findsOneWidget);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isTrue,
    );

    filteredResults.add([_coffee]);
    await tester.pumpAndSettle();

    expect(find.text('Coffee Original'), findsOneWidget);
    expect(find.byKey(const ValueKey('product-search-progress')), findsNothing);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isTrue,
    );
    expect(tester.testTextInput.isVisible, isTrue);
  });

  testWidgets('builds product slivers in pages and resets pagination', (
    tester,
  ) async {
    final products = List.generate(
      75,
      (index) => _product(index, category: index.isEven ? 'Coffee' : 'Snacks'),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          _emptyCartOverride,
          catalogProductsProvider.overrideWith((ref) => Stream.value(products)),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const ProductsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // The sliver delegate contains the first 30 products and one lazy loader.
    expect(_gridItemCount(tester), 31);
    final productScroll = find
        .descendant(
          of: find.byKey(const ValueKey('products-grid')),
          matching: find.byType(Scrollable),
        )
        .first;
    final scrollableState = tester.state<ScrollableState>(productScroll);

    // The pagination sentinel removes itself as soon as its post-frame
    // callback appends the next page, so it is intentionally too transient
    // to use as scrollUntilVisible's final target. Scroll the list itself and
    // assert the observable result instead.
    await tester.drag(productScroll, const Offset(0, -10000));
    await tester.pumpAndSettle();

    expect(_gridItemCount(tester), 61);

    scrollableState.position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'product');
    await tester.pump(const Duration(milliseconds: 250));

    expect(_gridItemCount(tester), 31);

    await tester.drag(productScroll, const Offset(0, -10000));
    await tester.pumpAndSettle();
    expect(_gridItemCount(tester), 61);

    scrollableState.position.jumpTo(0);
    await tester.pump();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Snacks'));
    await tester.pump();

    expect(_gridItemCount(tester), 31);
  });

  testWidgets('defaults to a two-column image grid and toggles to list', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(390, 900);
    addTearDown(tester.view.reset);
    final products = [
      for (var index = 0; index < 2; index++)
        _product(index, category: 'Coffee'),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          _emptyCartOverride,
          catalogProductsProvider.overrideWith((ref) => Stream.value(products)),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const ProductsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('products-grid')), findsOneWidget);
    final grid = tester.widget<SliverGrid>(
      find.byKey(const ValueKey('product-results-grid')),
    );
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 2);
    expect(grid.delegate.estimatedChildCount, products.length);

    for (final product in products) {
      final tile = find.byKey(ValueKey('product-grid-item-${product.id}'));
      expect(tile, findsOneWidget);
      expect(
        find.descendant(of: tile, matching: find.byType(ProductImage)),
        findsOneWidget,
      );
    }

    await tester.tap(find.byKey(const ValueKey('product-layout-list')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('products-list')), findsOneWidget);
    expect(find.byKey(const ValueKey('product-results-grid')), findsNothing);
    final list = tester.widget<SliverList>(
      find.byKey(const ValueKey('product-results-list')),
    );
    expect(list.delegate.estimatedChildCount, products.length);
  });

  testWidgets('product grid does not overflow a 320 by 667 viewport', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(320, 667);
    addTearDown(tester.view.reset);
    final products = [
      for (var index = 0; index < 6; index++)
        _product(index, category: 'Coffee'),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          _emptyCartOverride,
          catalogProductsProvider.overrideWith((ref) => Stream.value(products)),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const ProductsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('products-grid')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.drag(
      find.byKey(const ValueKey('products-grid')),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('categories share one horizontal two-row scroll position', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(390, 900);
    addTearDown(tester.view.reset);
    final products = [
      for (var index = 0; index < 12; index++)
        _product(index, category: 'Category $index'),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          _emptyCartOverride,
          catalogProductsProvider.overrideWith((ref) => Stream.value(products)),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const ProductsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final browser = find.byKey(const ValueKey('product-category-browser'));
    final gridFinder = find.byKey(const ValueKey('product-category-grid'));
    final grid = tester.widget<GridView>(gridFinder);
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(grid.scrollDirection, Axis.horizontal);
    expect(delegate.crossAxisCount, 2);
    expect(delegate.mainAxisSpacing, AppSpacing.xs);
    expect(delegate.crossAxisSpacing, delegate.mainAxisSpacing);
    expect(
      find.descendant(of: browser, matching: find.byType(Scrollable)),
      findsOneWidget,
    );

    final allLabel = tester.widget<FittedBox>(
      find.byKey(const ValueKey('product-category-label-All')),
    );
    expect(allLabel.fit, BoxFit.scaleDown);
    expect(allLabel.alignment, Alignment.centerLeft);
    final labelPadding = allLabel.child! as Padding;
    expect(
      labelPadding.padding,
      const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
    );

    final all = find.byKey(const ValueKey('product-category-all'));
    final firstCategory = find.byKey(
      const ValueKey('product-category-Category 0'),
    );
    final allBefore = tester.getTopLeft(all);
    final firstBefore = tester.getTopLeft(firstCategory);
    expect(allBefore.dx, closeTo(firstBefore.dx, 0.1));
    expect(allBefore.dy, isNot(closeTo(firstBefore.dy, 0.1)));

    await tester.drag(gridFinder, const Offset(-60, 0));
    await tester.pump();

    final allDelta = tester.getTopLeft(all).dx - allBefore.dx;
    final firstDelta = tester.getTopLeft(firstCategory).dx - firstBefore.dx;
    expect(allDelta, lessThan(-1));
    expect(allDelta, closeTo(firstDelta, 0.1));
  });

  testWidgets('category rows grow for three-times accessibility text', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(390, 900);
    addTearDown(tester.view.reset);
    final products = [
      _product(0, category: 'Household cleaning and laundry supplies'),
      _product(1, category: 'Snacks'),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          _emptyCartOverride,
          catalogProductsProvider.overrideWith((ref) => Stream.value(products)),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(3)),
            child: child!,
          ),
          home: const ProductsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final browser = tester.getRect(
      find.byKey(const ValueKey('product-category-browser')),
    );
    final all = tester.getRect(
      find.byKey(const ValueKey('product-category-all')),
    );
    final longCategory = tester.getRect(
      find.byKey(
        const ValueKey(
          'product-category-Household cleaning and laundry supplies',
        ),
      ),
    );
    expect(browser.height, greaterThan(140));
    expect(all.height, greaterThan(54));
    expect(all.bottom, lessThan(longCategory.top));
    expect(browser.contains(all.topLeft), isTrue);
    expect(browser.contains(longCategory.bottomRight), isTrue);
    expect(tester.takeException(), isNull);
  });
}

final _emptyCartOverride = cartDraftProvider.overrideWith(
  (ref) => Stream.value(CartDraft([])),
);

int? _gridItemCount(WidgetTester tester) {
  final grid = tester.widget<SliverGrid>(
    find.byKey(const ValueKey('product-results-grid')),
  );
  return grid.delegate.estimatedChildCount;
}

StoreProduct _product(int index, {required String category}) {
  return StoreProduct(
    id: 'product-$index',
    metadata: CatalogMetadata(
      barcode: '480${index.toString().padLeft(10, '0')}',
      name: 'Product $index',
      category: category,
    ),
    price: const Money.fromCentavos(1000),
    createdAt: DateTime.utc(2026, 9, 3),
    updatedAt: DateTime.utc(2026, 9, 3),
  );
}

final _coffee = StoreProduct(
  id: 'coffee-original',
  metadata: CatalogMetadata(
    barcode: '4800000000001',
    name: 'Coffee Original',
    category: 'Coffee',
  ),
  price: const Money.fromCentavos(900),
  createdAt: DateTime.utc(2026, 9, 3),
  updatedAt: DateTime.utc(2026, 9, 3),
);

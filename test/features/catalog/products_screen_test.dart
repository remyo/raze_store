import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/core/money/money.dart';
import 'package:raze_store/features/cart/application/cart_providers.dart';
import 'package:raze_store/features/cart/domain/cart.dart';
import 'package:raze_store/features/catalog/application/catalog_providers.dart';
import 'package:raze_store/features/catalog/domain/catalog_product.dart';
import 'package:raze_store/features/catalog/presentation/product_image.dart';
import 'package:raze_store/features/catalog/presentation/products_screen.dart';
import 'package:raze_store/features/settings/application/settings_providers.dart';
import 'package:raze_store/features/settings/domain/app_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

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
    expect(find.byKey(const ValueKey('home-quick-units')), findsOneWidget);
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

  testWidgets('the filled Quick units row opens its dedicated page', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/products',
      routes: [
        GoRoute(path: '/products', builder: (_, _) => const ProductsScreen()),
        GoRoute(
          path: '/quick-sell',
          builder: (_, _) => const Scaffold(
            body: Center(child: Text('Quick units destination')),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          _emptyCartOverride,
          catalogProductsProvider.overrideWith(
            (ref) => Stream.value([_coffee]),
          ),
        ],
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    final shortcut = find.byKey(const ValueKey('home-quick-units'));
    expect(tester.widget(shortcut), isA<FilledButton>());
    expect(
      find.descendant(
        of: shortcut,
        matching: find.text('Pieces, sticks, sachets & packs'),
      ),
      findsOneWidget,
    );
    final surface = tester.widget<Material>(
      find.descendant(of: shortcut, matching: find.byType(Material)),
    );
    expect(surface.color, AppTheme.light.colorScheme.primary);
    expect(
      tester.getSize(shortcut).width,
      tester.getSize(find.byType(TextField)).width,
    );

    for (final alignment in [Alignment.centerLeft, Alignment.centerRight]) {
      final bounds = tester.getRect(shortcut).deflate(8);
      await tester.tapAt(alignment.withinRect(bounds));
      await tester.pumpAndSettle();

      expect(find.text('Quick units destination'), findsOneWidget);

      router.pop();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('Quick units fits a narrow screen with large text', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(320, 900);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          _emptyCartOverride,
          catalogProductsProvider.overrideWith(
            (ref) => Stream.value([_coffee]),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: const ProductsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final shortcut = find.byKey(const ValueKey('home-quick-units'));
    await tester.ensureVisible(shortcut);
    await tester.pumpAndSettle();

    final bounds = tester.getRect(shortcut);
    final titleBounds = tester.getRect(find.text('Quick units'));
    final subtitle = find.text('Pieces, sticks, sachets & packs');
    final subtitleBounds = tester.getRect(subtitle);
    final unitIconBounds = tester.getRect(
      find.descendant(
        of: shortcut,
        matching: find.byIcon(Icons.format_list_numbered_rounded),
      ),
    );
    final arrowBounds = tester.getRect(
      find.descendant(
        of: shortcut,
        matching: find.byIcon(Icons.arrow_forward_rounded),
      ),
    );
    expect(bounds.width, lessThanOrEqualTo(320));
    expect(bounds.height, greaterThanOrEqualTo(48));
    expect(titleBounds.left, greaterThan(bounds.left));
    expect(titleBounds.right, lessThan(bounds.right));
    expect(titleBounds.top, greaterThanOrEqualTo(bounds.top));
    expect(subtitleBounds.top, greaterThanOrEqualTo(titleBounds.bottom));
    expect(subtitleBounds.left, closeTo(titleBounds.left, 0.1));
    expect(subtitleBounds.right, lessThan(bounds.right));
    expect(subtitleBounds.bottom, lessThanOrEqualTo(bounds.bottom));
    expect(unitIconBounds.left, greaterThan(bounds.left));
    expect(unitIconBounds.right, lessThan(titleBounds.left));
    expect(arrowBounds.left, greaterThan(subtitleBounds.right));
    expect(arrowBounds.right, lessThan(bounds.right));
    expect(
      tester
          .renderObject<RenderParagraph>(
            find.descendant(of: subtitle, matching: find.byType(RichText)),
          )
          .didExceedMaxLines,
      isFalse,
    );
    expect(tester.takeException(), isNull);
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
    await tester.pumpAndSettle();
    await _chooseProductBrowseOption(tester, 'product-sort-price-high-low');

    expect(_gridItemCount(tester), 31);

    await tester.drag(productScroll, const Offset(0, -10000));
    await tester.pumpAndSettle();
    expect(_gridItemCount(tester), 61);

    scrollableState.position.jumpTo(0);
    await tester.pumpAndSettle();
    await _chooseProductBrowseOption(tester, 'product-filter-reset');

    expect(_gridItemCount(tester), 31);
    expect(
      find.byKey(const ValueKey('product-filter-active-count')),
      findsNothing,
    );

    await tester.drag(productScroll, const Offset(0, -10000));
    await tester.pumpAndSettle();
    expect(_gridItemCount(tester), 61);

    scrollableState.position.jumpTo(0);
    await tester.pump();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Snacks'));
    await tester.pump();

    expect(_gridItemCount(tester), 31);
  });

  testWidgets('sorts and filters products from the compact browse menu', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(390, 1200);
    addTearDown(tester.view.reset);
    final products = [
      _product(
        0,
        category: 'Snacks',
        name: 'Banana Chips',
        priceCentavos: 2500,
        createdAt: DateTime.utc(2026, 1, 1),
      ),
      _product(
        1,
        category: 'Snacks',
        name: 'Apple Juice',
        priceCentavos: 5000,
        localImagePath: '/products/apple.png',
        createdAt: DateTime.utc(2026, 4, 1),
      ),
      _product(
        2,
        category: 'Snacks',
        name: 'Candy',
        priceCentavos: 0,
        remoteImageUrl: 'https://example.com/candy.png',
        sellingUnits: const [
          SellingUnit(
            id: 'candy-piece',
            label: 'Piece',
            price: Money.fromCentavos(100),
          ),
        ],
        createdAt: DateTime.utc(2026, 5, 1),
      ),
      _product(
        3,
        category: 'Snacks',
        name: 'Donut',
        priceCentavos: 2500,
        catalogImagePath: '/catalog/donut.png',
        createdAt: DateTime.utc(2026, 3, 1),
      ),
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

    final menu = find.byKey(const ValueKey('product-sort-filter-menu'));
    expect(menu, findsOneWidget);
    expect(
      tester.getCenter(menu).dy,
      closeTo(
        tester.getCenter(find.byKey(const ValueKey('product-layout-grid'))).dy,
        1,
      ),
    );

    await tester.tap(menu);
    await tester.pumpAndSettle();
    for (final label in [
      'Default order',
      'Price: highest first',
      'Price: lowest first',
      'Name: A–Z',
      'Name: Z–A',
      'Newest added',
      'All products',
      'With photo',
      'Without photo',
      'With additional units',
      'With a price',
      'Price missing',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.tap(find.byKey(const ValueKey('product-sort-price-high-low')));
    await tester.pumpAndSettle();

    expect(_verticalProductOrder(tester, products), [
      'product-1',
      'product-0',
      'product-3',
      'product-2',
    ]);
    expect(
      _activeFilterCount(tester),
      '1',
      reason: 'A non-default sort is shown as active.',
    );
    _expectCircularFilterBadge(tester, '1');

    await _chooseProductBrowseOption(tester, 'product-sort-name-a-z');
    expect(_verticalProductOrder(tester, products), [
      'product-1',
      'product-0',
      'product-2',
      'product-3',
    ]);

    await _chooseProductBrowseOption(tester, 'product-filter-with-photo');
    expect(_visibleProductIds(tester, products), {
      'product-1',
      'product-2',
      'product-3',
    });
    expect(_activeFilterCount(tester), '2');
    _expectCircularFilterBadge(tester, '2');

    await _chooseProductBrowseOption(tester, 'product-filter-without-photo');
    expect(_visibleProductIds(tester, products), {'product-0'});

    await _chooseProductBrowseOption(tester, 'product-filter-additional-units');
    expect(_visibleProductIds(tester, products), {'product-2'});

    await _chooseProductBrowseOption(tester, 'product-filter-priced');
    expect(_visibleProductIds(tester, products), {
      'product-0',
      'product-1',
      'product-3',
    });

    await _chooseProductBrowseOption(tester, 'product-filter-missing-price');
    expect(_visibleProductIds(tester, products), {'product-2'});

    await _chooseProductBrowseOption(tester, 'product-filter-all');
    await _chooseProductBrowseOption(tester, 'product-sort-newest');
    expect(_verticalProductOrder(tester, products), [
      'product-2',
      'product-1',
      'product-3',
      'product-0',
    ]);

    await _chooseProductBrowseOption(tester, 'product-filter-missing-price');
    expect(_activeFilterCount(tester), '2');
    await _chooseProductBrowseOption(tester, 'product-filter-reset');
    expect(
      find.byKey(const ValueKey('product-filter-active-count')),
      findsNothing,
    );
    expect(_visibleProductIds(tester, products), {
      'product-0',
      'product-1',
      'product-2',
      'product-3',
    });
    expect(_verticalProductOrder(tester, products), [
      'product-0',
      'product-1',
      'product-2',
      'product-3',
    ]);
  });

  testWidgets('applies sorting and filters before the 30 product page slice', (
    tester,
  ) async {
    final products = List.generate(
      75,
      (index) => _product(
        index,
        category: 'General',
        priceCentavos: index * 100,
        localImagePath: index >= 60 ? '/products/$index.png' : null,
      ),
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

    expect(_gridItemCount(tester), 31);
    expect(
      find.byKey(const ValueKey('product-grid-item-product-74')),
      findsNothing,
    );

    await _chooseProductBrowseOption(tester, 'product-sort-price-high-low');
    expect(_gridItemCount(tester), 31);
    expect(
      find.byKey(const ValueKey('product-grid-item-product-74')),
      findsOneWidget,
    );

    await _chooseProductBrowseOption(tester, 'product-filter-with-photo');
    expect(_gridItemCount(tester), 15);
    expect(
      find.byKey(const ValueKey('product-grid-item-product-74')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('product-grid-item-product-59')),
      findsNothing,
    );
  });

  testWidgets('product grid toggles and restores saved list layout', (
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
      final imageFinder = find.descendant(
        of: tile,
        matching: find.byType(ProductImage),
      );
      expect(imageFinder, findsOneWidget);
      expect(tester.widget<ProductImage>(imageFinder).fit, BoxFit.cover);
    }

    await tester.tap(find.byKey(const ValueKey('product-layout-list')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('products-list')), findsOneWidget);
    expect(find.byKey(const ValueKey('product-results-grid')), findsNothing);
    final list = tester.widget<SliverList>(
      find.byKey(const ValueKey('product-results-list')),
    );
    expect(list.delegate.estimatedChildCount, products.length);

    final stored = await SharedPreferences.getInstance();
    expect(
      stored.getString(productsViewLayoutPreferenceKey),
      CatalogViewLayout.list.name,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
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

    expect(find.byKey(const ValueKey('products-list')), findsOneWidget);
    expect(find.byKey(const ValueKey('product-results-list')), findsOneWidget);
    expect(find.byKey(const ValueKey('product-results-grid')), findsNothing);
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

  testWidgets(
    'sort and filter control stays usable on a narrow large-text UI',
    (tester) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(320, 900);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            _emptyCartOverride,
            catalogProductsProvider.overrideWith(
              (ref) => Stream.value([_product(0, category: 'General')]),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: const ProductsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final menu = find.byKey(const ValueKey('product-sort-filter-menu'));
      await tester.ensureVisible(menu);
      await tester.pumpAndSettle();
      expect(menu, findsOneWidget);
      expect(tester.getSize(menu).width, lessThan(120));
      expect(tester.takeException(), isNull);

      await tester.tap(menu);
      await tester.pumpAndSettle();
      final priceSort = find.byKey(
        const ValueKey('product-sort-price-high-low'),
      );
      await tester.ensureVisible(priceSort);
      await tester.pumpAndSettle();
      await tester.tap(priceSort);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('product-filter-active-count')),
        findsOneWidget,
      );
      _expectCircularFilterBadge(tester, '1');
      expect(tester.takeException(), isNull);
    },
  );

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
    final scrollFinder = find.byKey(const ValueKey('product-category-scroll'));
    final scroll = tester.widget<SingleChildScrollView>(scrollFinder);
    expect(scroll.scrollDirection, Axis.horizontal);
    expect(
      find.descendant(of: browser, matching: find.byType(Scrollable)),
      findsOneWidget,
    );
    expect(
      tester.getSize(browser).height,
      (AppSize.compactChip * 2) + AppSpacing.xs,
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
    final nextFirstRowCategory = find.byKey(
      const ValueKey('product-category-Category 1'),
    );
    final allChip = tester.widget<ChoiceChip>(all);
    expect(allChip.padding, EdgeInsets.zero);
    expect(allChip.labelPadding, EdgeInsets.zero);
    expect(allChip.visualDensity, VisualDensity.compact);
    expect(allChip.materialTapTargetSize, MaterialTapTargetSize.shrinkWrap);

    final allRect = tester.getRect(all);
    final firstCategoryRect = tester.getRect(firstCategory);
    final nextFirstRowRect = tester.getRect(nextFirstRowCategory);
    expect(firstCategoryRect.top - allRect.bottom, closeTo(AppSpacing.xs, 0.1));
    expect(nextFirstRowRect.left - allRect.right, closeTo(AppSpacing.xs, 0.1));
    expect(allRect.width, lessThan(nextFirstRowRect.width));

    final allBefore = tester.getTopLeft(all);
    final firstBefore = tester.getTopLeft(firstCategory);
    expect(allBefore.dx, closeTo(firstBefore.dx, 0.1));
    expect(allBefore.dy, isNot(closeTo(firstBefore.dy, 0.1)));

    await tester.drag(scrollFinder, const Offset(-60, 0));
    await tester.pump();

    final allDelta = tester.getTopLeft(all).dx - allBefore.dx;
    final firstDelta = tester.getTopLeft(firstCategory).dx - firstBefore.dx;
    expect(allDelta, lessThan(-1));
    expect(allDelta, closeTo(firstDelta, 0.1));
  });

  testWidgets('long category labels fit and rows grow with accessible text', (
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
    final longLabelFinder = find.byKey(
      const ValueKey(
        'product-category-label-Household cleaning and laundry supplies',
      ),
    );
    final longLabel = tester.widget<FittedBox>(longLabelFinder);
    final longLabelPadding = longLabel.child! as Padding;
    expect(longLabel.fit, BoxFit.scaleDown);
    expect(longLabel.alignment, Alignment.centerLeft);
    expect(
      longLabelPadding.padding,
      const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
    );
    expect(longCategory.width, lessThanOrEqualTo(152));
    expect(
      tester.getSize(longLabelFinder).width,
      lessThan(tester.getSize(find.byWidget(longLabelPadding)).width),
    );
    expect(
      browser.height,
      greaterThan((AppSize.compactChip * 2) + AppSpacing.xs),
    );
    expect(all.height, greaterThan(AppSize.compactChip));
    expect(longCategory.top - all.bottom, closeTo(AppSpacing.xs, 0.1));
    expect(browser.contains(all.topLeft), isTrue);
    expect(longCategory.right, lessThanOrEqualTo(browser.right));
    expect(longCategory.bottom, closeTo(browser.bottom, 0.1));
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

Future<void> _chooseProductBrowseOption(
  WidgetTester tester,
  String optionKey,
) async {
  await tester.tap(find.byKey(const ValueKey('product-sort-filter-menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey(optionKey)));
  await tester.pumpAndSettle();
}

String _activeFilterCount(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('product-filter-active-count')),
        matching: find.byType(Text),
      ),
    )
    .data!;

void _expectCircularFilterBadge(WidgetTester tester, String count) {
  final badge = find.byKey(const ValueKey('product-filter-active-count'));
  final label = find.descendant(of: badge, matching: find.text(count));
  final container = tester.widget<Container>(badge);
  final decoration = container.decoration! as BoxDecoration;
  final size = tester.getSize(badge);

  expect(size.width, 20);
  expect(size.height, size.width);
  expect(decoration.shape, BoxShape.circle);
  expect(container.alignment, Alignment.center);
  expect(label, findsOneWidget);
  expect(
    (tester.getCenter(label) - tester.getCenter(badge)).distance,
    lessThan(0.1),
  );
}

Set<String> _visibleProductIds(
  WidgetTester tester,
  List<StoreProduct> products,
) => {
  for (final product in products)
    if (find
        .byKey(ValueKey('product-grid-item-${product.id}'))
        .evaluate()
        .isNotEmpty)
      product.id,
};

List<String> _verticalProductOrder(
  WidgetTester tester,
  List<StoreProduct> products,
) {
  final positions = <({String id, Offset offset})>[];
  for (final product in products) {
    final finder = find.byKey(ValueKey('product-grid-item-${product.id}'));
    if (finder.evaluate().isNotEmpty) {
      positions.add((id: product.id, offset: tester.getTopLeft(finder)));
    }
  }
  positions.sort((left, right) {
    final row = left.offset.dy.compareTo(right.offset.dy);
    return row != 0 ? row : left.offset.dx.compareTo(right.offset.dx);
  });
  return positions.map((entry) => entry.id).toList(growable: false);
}

StoreProduct _product(
  int index, {
  required String category,
  String? name,
  int priceCentavos = 1000,
  String? localImagePath,
  String? catalogImagePath,
  String? remoteImageUrl,
  List<SellingUnit> sellingUnits = const [],
  DateTime? createdAt,
}) {
  final savedAt = createdAt ?? DateTime.utc(2026, 9, 3);
  return StoreProduct(
    id: 'product-$index',
    metadata: CatalogMetadata(
      barcode: '480${index.toString().padLeft(10, '0')}',
      name: name ?? 'Product $index',
      category: category,
      remoteImageUrl: remoteImageUrl,
    ),
    price: Money.fromCentavos(priceCentavos),
    localImagePath: localImagePath,
    catalogImagePath: catalogImagePath,
    sellingUnits: sellingUnits,
    createdAt: savedAt,
    updatedAt: savedAt,
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

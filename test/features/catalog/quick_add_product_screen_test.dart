import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/core/money/money.dart';
import 'package:raze_store/features/catalog/application/catalog_providers.dart';
import 'package:raze_store/features/catalog/domain/catalog_product.dart';
import 'package:raze_store/features/catalog/domain/catalog_repository.dart';
import 'package:raze_store/features/catalog/presentation/product_form_screen.dart';
import 'package:raze_store/features/catalog/presentation/quick_add_product_screen.dart';

void main() {
  testWidgets('quick add requires only a name and price', (tester) async {
    final repository = _RecordingCatalogRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [catalogRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const QuickAddProductScreen(),
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('quick-add-name')),
      'Kopiko Brown Coffee',
    );
    await tester.enterText(
      find.byKey(const ValueKey('quick-add-price')),
      '12.50',
    );
    await tester.tap(find.byKey(const ValueKey('quick-add-save')));
    await tester.pumpAndSettle();

    expect(repository.created, hasLength(1));
    expect(repository.created.single.name, 'Kopiko Brown Coffee');
    expect(repository.created.single.barcode, isNull);
    expect(repository.created.single.priceCentavos, 1250);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('prefills a scanned main barcode', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogRepositoryProvider.overrideWithValue(
            _RecordingCatalogRepository(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const QuickAddProductScreen(initialBarcode: '4800012345678'),
        ),
      ),
    );

    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('quick-add-barcode')),
          )
          .controller
          ?.text,
      '4800012345678',
    );
  });

  testWidgets('prefills API metadata but still requires a local price', (
    tester,
  ) async {
    final repository = _RecordingCatalogRepository();
    final metadata = CatalogMetadata(
      barcode: '4807770270055',
      name: 'Lucky Me Pancit Canton',
      brand: 'Lucky Me!',
      unitLabel: '60 g',
      category: 'Instant noodles',
      remoteImageUrl: 'https://catalog.example/product.jpg',
      source: 'raze_store_api',
      sourceProductId: 'api-product-id',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [catalogRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        QuickAddProductScreen(initialMetadata: metadata),
                  ),
                ),
                child: const Text('Open API product'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open API product'));
    await tester.pumpAndSettle();

    expect(find.text('Found in the Raze catalog'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('quick-add-barcode')),
          )
          .controller
          ?.text,
      '4807770270055',
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('quick-add-name')))
          .controller
          ?.text,
      'Lucky Me Pancit Canton',
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('quick-add-price')))
          .controller
          ?.text,
      isEmpty,
    );

    await tester.enterText(
      find.byKey(const ValueKey('quick-add-price')),
      '16.00',
    );
    await tester.tap(find.byKey(const ValueKey('quick-add-save')));
    await tester.pumpAndSettle();

    expect(repository.created, hasLength(1));
    final draft = repository.created.single;
    expect(draft.priceCentavos, 1600);
    expect(draft.brand, 'Lucky Me!');
    expect(draft.unitLabel, '60 g');
    expect(draft.category, 'Instant noodles');
    expect(draft.remoteImageUrl, 'https://catalog.example/product.jpg');
    expect(draft.source, 'raze_store_api');
    expect(draft.sourceProductId, 'api-product-id');
    expect(draft.localImagePath, isNull);
    expect(draft.sellingUnits, isEmpty);
  });

  testWidgets('detailed form handoff preserves entered setup values', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/quick-add',
      routes: [
        GoRoute(
          path: '/quick-add',
          builder: (_, _) => const QuickAddProductScreen(
            initialBarcode: '4800012345678',
            goToProductsAfterSave: true,
          ),
        ),
        GoRoute(
          path: '/products/new',
          builder: (_, state) => Text(
            '${state.uri.queryParameters['barcode']}|'
            '${state.uri.queryParameters['name']}|'
            '${state.uri.queryParameters['price']}|'
            '${state.uri.queryParameters['fromSetup']}',
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    );

    await tester.enterText(
      find.byKey(const ValueKey('quick-add-name')),
      'Kopiko Brown Coffee',
    );
    await tester.enterText(
      find.byKey(const ValueKey('quick-add-price')),
      '12.50',
    );
    final detailedFormButton = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Use the detailed product form'),
    );
    detailedFormButton.onPressed!();
    await tester.pumpAndSettle();

    expect(
      find.text('4800012345678|Kopiko Brown Coffee|12.50|true'),
      findsOneWidget,
    );
  });

  testWidgets('detailed API handoff returns the saved product to its caller', (
    tester,
  ) async {
    final repository = _RecordingCatalogRepository();
    final metadata = CatalogMetadata(
      barcode: '4807770270055',
      name: 'API noodles',
      source: 'raze_store_api',
      sourceProductId: 'f71ea24a-41f2-422f-9aeb-24efa48e7a5d',
    );
    Object? routeResult;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                routeResult = await context.push<Object?>('/quick-add');
              },
              child: const Text('Open API flow'),
            ),
          ),
        ),
        GoRoute(
          path: '/quick-add',
          builder: (_, _) => QuickAddProductScreen(initialMetadata: metadata),
        ),
        GoRoute(
          path: '/products/new',
          builder: (_, state) => ProductFormScreen(
            initialBarcode: state.uri.queryParameters['barcode'],
            initialName: state.uri.queryParameters['name'],
            initialPrice: state.uri.queryParameters['price'],
            initialMetadata: state.extra as CatalogMetadata?,
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogRepositoryProvider.overrideWithValue(repository),
          catalogCategorySuggestionsProvider.overrideWithValue(const []),
        ],
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );

    await tester.tap(find.text('Open API flow'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('quick-add-price')),
      '18.00',
    );
    final detailedButton = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Use the detailed product form'),
    );
    detailedButton.onPressed!();
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('product-barcode-field')),
      'EDITED-CODE',
    );
    final saveButton = find.text('Save product');
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(routeResult, isA<StoreProduct>());
    expect((routeResult! as StoreProduct).barcode, 'EDITED-CODE');
    expect(repository.created, hasLength(1));
    expect(find.text('Open API flow'), findsOneWidget);
  });

  testWidgets('system back from setup quick add opens the product list', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/quick-add',
      routes: [
        GoRoute(
          path: '/quick-add',
          builder: (_, _) =>
              const QuickAddProductScreen(goToProductsAfterSave: true),
        ),
        GoRoute(
          path: '/products',
          builder: (_, _) => const Scaffold(body: Text('Product list')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Product list'), findsOneWidget);
  });
}

final class _RecordingCatalogRepository implements CatalogRepository {
  final List<ProductDraft> created = [];

  @override
  Future<StoreProduct> createProduct(ProductDraft draft) async {
    created.add(draft);
    return StoreProduct(
      id: 'created-product',
      metadata: draft.metadata,
      price: Money.fromCentavos(draft.priceCentavos),
      createdAt: DateTime.utc(2026, 9, 3),
      updatedAt: DateTime.utc(2026, 9, 3),
    );
  }

  @override
  Future<void> deleteProduct(String id) => throw UnimplementedError();

  @override
  Future<StoreProduct?> findByBarcode(String rawBarcode) =>
      throw UnimplementedError();

  @override
  Future<StoreProduct?> findBySource(String source, String sourceProductId) =>
      throw UnimplementedError();

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

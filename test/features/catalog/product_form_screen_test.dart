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

void main() {
  testWidgets('rejects the fallback main label for a sub-unit', (tester) async {
    await _pumpForm(tester);

    await _addSellingUnit(tester, label: ' main ITEM ');
    await tester.tap(find.text('Save product'));
    await tester.pump();

    expect(
      find.text('Use a unique name different from the main unit.'),
      findsOneWidget,
    );
  });

  testWidgets('rejects a sub-unit matching a named main unit', (tester) async {
    await _pumpForm(tester);

    await tester.enterText(
      find.byKey(const ValueKey('product-main-unit-field')),
      'Pack',
    );
    await _addSellingUnit(tester, label: 'PACK');
    await tester.tap(find.text('Save product'));
    await tester.pump();

    expect(
      find.text('Use a unique name different from the main unit.'),
      findsOneWidget,
    );
  });

  testWidgets('offers a stored or API-provided category suggestion', (
    tester,
  ) async {
    await _pumpForm(tester, categorySuggestions: const ['Mobile Load']);

    final categoryField = find.byKey(const ValueKey('product-category-field'));
    await tester.ensureVisible(categoryField);
    await tester.tap(categoryField);
    await tester.enterText(categoryField, 'mobile');
    await tester.pump();

    final suggestion = find.widgetWithText(ListTile, 'Mobile Load');
    expect(suggestion, findsOneWidget);
    await tester.tap(suggestion);
    await tester.pump();

    expect(
      tester.widget<TextFormField>(categoryField).controller?.text,
      'Mobile Load',
    );
  });

  testWidgets('requires a main barcode when a sub-unit is added', (
    tester,
  ) async {
    await _pumpForm(tester);

    await _addSellingUnit(tester, label: 'Piece');
    await tester.tap(find.text('Save product'));
    await tester.pump();

    expect(
      find.text('Add a main barcode for sub-unit prices.'),
      findsOneWidget,
    );
  });

  testWidgets('setup handoff saves and navigates to the product list', (
    tester,
  ) async {
    final repository = _RecordingCatalogRepository();
    final router = GoRouter(
      initialLocation: '/products/new',
      routes: [
        GoRoute(
          path: '/products/new',
          builder: (_, _) => const ProductFormScreen(
            initialBarcode: '4800012345678',
            initialName: 'Kopiko Brown Coffee',
            initialPrice: '12.50',
            goToProductsAfterSave: true,
          ),
        ),
        GoRoute(
          path: '/products',
          builder: (_, _) => const Scaffold(body: Text('Product list')),
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
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('product-name-field')),
          )
          .controller
          ?.text,
      'Kopiko Brown Coffee',
    );
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('product-main-price-field')),
          )
          .controller
          ?.text,
      '12.50',
    );
    await tester.tap(find.text('Save product'));
    await tester.pumpAndSettle();

    expect(repository.created, hasLength(1));
    expect(repository.created.single.barcode, '4800012345678');
    expect(repository.created.single.name, 'Kopiko Brown Coffee');
    expect(repository.created.single.priceCentavos, 1250);
    expect(find.text('Product list'), findsOneWidget);
  });

  testWidgets('system back from setup detailed form opens products', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/products/new',
      routes: [
        GoRoute(
          path: '/products/new',
          builder: (_, _) =>
              const ProductFormScreen(goToProductsAfterSave: true),
        ),
        GoRoute(
          path: '/products',
          builder: (_, _) => const Scaffold(body: Text('Product list')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogCategorySuggestionsProvider.overrideWithValue(const []),
        ],
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Product list'), findsOneWidget);
  });
}

Future<void> _addSellingUnit(
  WidgetTester tester, {
  required String label,
}) async {
  final addButton = find.text('Add another selling unit');
  await tester.ensureVisible(addButton);
  await tester.tap(addButton);
  await tester.pump();
  await tester.enterText(
    find.byKey(const ValueKey('selling-unit-label-0')),
    label,
  );
}

Future<void> _pumpForm(
  WidgetTester tester, {
  List<String> categorySuggestions = const [],
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        catalogCategorySuggestionsProvider.overrideWithValue(
          categorySuggestions,
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const ProductFormScreen(),
      ),
    ),
  );
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

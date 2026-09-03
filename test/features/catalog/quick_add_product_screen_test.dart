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

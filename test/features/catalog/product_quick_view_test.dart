import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/core/money/money.dart';
import 'package:raze_store/features/cart/application/cart_providers.dart';
import 'package:raze_store/features/cart/domain/cart.dart';
import 'package:raze_store/features/cart/domain/cart_repository.dart';
import 'package:raze_store/features/catalog/domain/catalog_product.dart';
import 'package:raze_store/features/catalog/presentation/product_quick_view.dart';

void main() {
  testWidgets('chooses a sub-unit before adding a scanned product', (
    tester,
  ) async {
    final cart = _RecordingCartRepository();
    final product = StoreProduct(
      id: 'cigarettes',
      metadata: CatalogMetadata(
        barcode: '4801234567890',
        name: 'Cigarettes',
        unitLabel: 'Pack',
      ),
      price: const Money.fromCentavos(16000),
      sellingUnits: const [
        SellingUnit(
          id: 'stick',
          label: 'Stick',
          price: Money.fromCentavos(1000),
        ),
      ],
      createdAt: DateTime.utc(2026, 9, 3),
      updatedAt: DateTime.utc(2026, 9, 3),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [cartRepositoryProvider.overrideWithValue(cart)],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () => showProductQuickView(
                  context,
                  product: product,
                  allowEdit: false,
                ),
                child: const Text('Open product'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open product'));
    await tester.pumpAndSettle();
    expect(find.text('Choose how it is sold'), findsOneWidget);
    expect(find.text('Main barcode unit'), findsOneWidget);

    await tester.tap(find.text('Stick'));
    await tester.pump();
    expect(find.text('Add 1 Stick'), findsOneWidget);

    await tester.tap(find.text('Add 1 Stick'));
    await tester.pumpAndSettle();
    expect(cart.addedProduct, same(product));
    expect(cart.addedOption?.sellingUnitId, 'stick');
    expect(cart.addedOption?.priceCentavos, 1000);
  });
}

final class _RecordingCartRepository implements CartRepository {
  StoreProduct? addedProduct;
  ProductSaleOption? addedOption;

  @override
  Future<void> addProduct(
    StoreProduct product, {
    ProductSaleOption? saleOption,
    int quantity = 1,
  }) async {
    addedProduct = product;
    addedOption = saleOption;
  }

  @override
  Future<void> clear() async {}

  @override
  Future<CartDraft> getDraft() async => CartDraft(const []);

  @override
  Future<void> removeProduct(String lineId) async {}

  @override
  Future<void> updateQuantity(String lineId, int quantity) async {}

  @override
  Stream<CartDraft> watchDraft() => Stream.value(CartDraft(const []));
}

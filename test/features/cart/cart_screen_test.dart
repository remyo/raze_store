import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/core/money/money.dart';
import 'package:raze_store/features/cart/application/cart_providers.dart';
import 'package:raze_store/features/cart/domain/cart.dart';
import 'package:raze_store/features/cart/domain/cart_repository.dart';
import 'package:raze_store/features/cart/presentation/cart_screen.dart';
import 'package:raze_store/features/catalog/domain/catalog_product.dart';
import 'package:raze_store/features/receipt/domain/receipt_draft.dart';
import 'package:raze_store/features/sales/application/sales_providers.dart';
import 'package:raze_store/features/sales/domain/completed_sale.dart';
import 'package:raze_store/features/sales/domain/sales_date_range.dart';
import 'package:raze_store/features/sales/domain/sales_repository.dart';
import 'package:raze_store/features/settings/application/settings_providers.dart';
import 'package:raze_store/features/settings/domain/settings_repository.dart';
import 'package:raze_store/features/settings/domain/store_profile.dart';

void main() {
  testWidgets('receipt preview reads the saved store identity before opening', (
    tester,
  ) async {
    _useTallView(tester);
    final settings = _FakeSettingsRepository(
      profile: const StoreProfile(storeName: 'Aling Nena Store'),
    );
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cartDraftProvider.overrideWith((ref) => Stream.value(_cart)),
          settingsRepositoryProvider.overrideWithValue(settings),
        ],
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Preview receipt'));
    await tester.pumpAndSettle();

    expect(settings.reads, 1);
    expect(find.text('Receipt for Aling Nena Store'), findsOneWidget);
  });

  testWidgets('receipt preview does not fall back when store details fail', (
    tester,
  ) async {
    _useTallView(tester);
    final settings = _FakeSettingsRepository(error: StateError('unavailable'));
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cartDraftProvider.overrideWith((ref) => Stream.value(_cart)),
          settingsRepositoryProvider.overrideWithValue(settings),
        ],
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Preview receipt'));
    await tester.pumpAndSettle();

    expect(find.text('Cart'), findsWidgets);
    expect(find.text('Receipt for Raze Store'), findsNothing);
    expect(
      find.text('Could not load the store details for this receipt.'),
      findsOneWidget,
    );
  });

  testWidgets('complete sale records the cash and opens its receipt', (
    tester,
  ) async {
    _useTallView(tester);
    final sales = _FakeSalesRepository(_completedSale);
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cartDraftProvider.overrideWith((ref) => Stream.value(_cart)),
          salesRepositoryProvider.overrideWithValue(sales),
        ],
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '20.00');
    await tester.tap(find.byKey(const ValueKey('complete-sale')));
    await tester.pumpAndSettle();

    expect(sales.completedWithCash, 2000);
    expect(find.text('Receipt for Aling Nena Store'), findsOneWidget);
  });

  testWidgets('does not report a saved sale as failed when receipt fails', (
    tester,
  ) async {
    _useTallView(tester);
    final sales = _FakeSalesRepository(_saleWithInvalidReceiptLine);
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cartDraftProvider.overrideWith((ref) => Stream.value(_cart)),
          salesRepositoryProvider.overrideWithValue(sales),
        ],
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('complete-sale')));
    await tester.pumpAndSettle();

    expect(sales.completionCalls, 1);
    expect(
      find.text(
        'Sale saved, but the receipt could not be opened. You can reopen it from Sales.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Could not complete the sale. Please try again.'),
      findsNothing,
    );
  });

  testWidgets('checkout actions wait for an in-flight cart line write', (
    tester,
  ) async {
    _useTallView(tester);
    final updateGate = Completer<void>();
    final cartRepository = _DelayedCartRepository(_cart, updateGate);
    final sales = _FakeSalesRepository(_completedSale);
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cartDraftProvider.overrideWith((ref) => Stream.value(_cart)),
          cartRepositoryProvider.overrideWithValue(cartRepository),
          salesRepositoryProvider.overrideWithValue(sales),
        ],
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Increase quantity'));
    await tester.pump();

    expect(cartRepository.updateCalls, 1);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('complete-sale')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Preview receipt'),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('new-customer')))
          .onPressed,
      isNull,
    );
    expect(sales.completionCalls, 0);

    updateGate.complete();
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('complete-sale')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('cash panel starts open and quick bills calculate change', (
    tester,
  ) async {
    _useTallView(tester);
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cartDraftProvider.overrideWith((ref) => Stream.value(_cart)),
        ],
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('cash-received-field')), findsOneWidget);
    expect(find.text('New customer'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('cash-bill-50')));
    await tester.pump();

    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('cash-received-field')),
    );
    expect(field.controller?.text, '50');
    expect(find.text('Change'), findsOneWidget);
    expect(find.text('₱38.00'), findsOneWidget);

    final previewWidth = tester
        .getSize(find.byKey(const ValueKey('preview-receipt')))
        .width;
    final completeWidth = tester
        .getSize(find.byKey(const ValueKey('complete-sale')))
        .width;
    expect(completeWidth / previewWidth, closeTo(1.5, 0.05));
  });

  testWidgets('keyboard lifts the cash field above its visible edge', (
    tester,
  ) async {
    _useTallView(tester);
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cartDraftProvider.overrideWith((ref) => Stream.value(_cart)),
        ],
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    final cashField = find.byKey(const ValueKey('cash-received-field'));
    await tester.tap(cashField);
    await tester.pump();

    tester.view.viewInsets = const FakeViewPadding(bottom: 500);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    final visibleBottom =
        tester.view.physicalSize.height / tester.view.devicePixelRatio -
        tester.view.viewInsets.bottom / tester.view.devicePixelRatio;
    expect(
      tester.getBottomLeft(cashField).dy,
      lessThanOrEqualTo(visibleBottom),
    );
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('scrolling a long cart collapses the sticky cash panel', (
    tester,
  ) async {
    _useTallView(tester);
    final longCart = _cartWithItems(18);
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cartDraftProvider.overrideWith((ref) => Stream.value(longCart)),
        ],
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('cash-received-field')), findsOneWidget);

    await tester.drag(
      find.byKey(const ValueKey('cart-items-scroll-view')),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('cash-received-field')), findsNothing);
    expect(find.text('Tap or swipe up to open'), findsOneWidget);

    await tester.drag(
      find.byKey(const ValueKey('cash-panel-handle')),
      const Offset(0, -80),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('cash-received-field')), findsOneWidget);
  });

  testWidgets('app bar new-customer action owns the clear-cart dialog', (
    tester,
  ) async {
    _useTallView(tester);
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cartDraftProvider.overrideWith((ref) => Stream.value(_cart)),
        ],
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Start a new customer'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'New customer'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('new-customer')));
    await tester.pumpAndSettle();

    expect(find.text('Start a new customer?'), findsOneWidget);
    expect(find.text('Keep cart'), findsOneWidget);
    expect(find.text('Clear cart'), findsOneWidget);
  });

  testWidgets('swiping a cart line removes that exact line', (tester) async {
    _useTallView(tester);
    final cartRepository = _SwipeCartRepository(_cart);
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cartDraftProvider.overrideWith((ref) => Stream.value(_cart)),
          cartRepositoryProvider.overrideWithValue(cartRepository),
        ],
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const ValueKey('cart-line-main:coffee')),
      const Offset(-600, 0),
    );
    await tester.pumpAndSettle();

    expect(cartRepository.removedLineIds, ['main:coffee']);
  });

  testWidgets('a failed swipe removal restores the cart line', (tester) async {
    _useTallView(tester);
    final cartRepository = _SwipeCartRepository(
      _cart,
      removeError: StateError('write failed'),
    );
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cartDraftProvider.overrideWith((ref) => Stream.value(_cart)),
          cartRepositoryProvider.overrideWithValue(cartRepository),
        ],
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const ValueKey('cart-line-main:coffee')),
      const Offset(-600, 0),
    );
    await tester.pumpAndSettle();

    expect(cartRepository.removedLineIds, ['main:coffee']);
    expect(find.text('Could not remove this product.'), findsOneWidget);
    expect(find.byKey(const ValueKey('cart-line-main:coffee')), findsOneWidget);
  });
}

void _useTallView(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(800, 1400);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

GoRouter _router() => GoRouter(
  initialLocation: '/cart',
  routes: [
    GoRoute(path: '/cart', builder: (_, _) => const CartScreen()),
    GoRoute(
      path: '/receipt',
      builder: (_, state) {
        final draft = state.extra! as ReceiptDraft;
        return Scaffold(body: Text('Receipt for ${draft.storeName}'));
      },
    ),
  ],
);

final _cart = CartDraft([
  CartItem(
    lineId: 'main:coffee',
    productId: 'coffee',
    sellingUnitId: null,
    barcode: '4800012345678',
    nameSnapshot: 'Coffee',
    unitLabelSnapshot: 'Pack',
    unitPrice: Money.fromCentavos(1200),
    quantity: 1,
    addedAt: DateTime.utc(2026, 9, 3),
    updatedAt: DateTime.utc(2026, 9, 3),
  ),
]);

CartDraft _cartWithItems(int count) => CartDraft([
  for (var index = 0; index < count; index++)
    CartItem(
      lineId: 'main:product-$index',
      productId: 'product-$index',
      sellingUnitId: null,
      barcode: '480000000${index.toString().padLeft(3, '0')}',
      nameSnapshot: 'Product ${index + 1}',
      unitLabelSnapshot: 'Piece',
      unitPrice: Money.fromCentavos(100 + index),
      quantity: 1,
      addedAt: DateTime.utc(2026, 9, 3, 0, index),
      updatedAt: DateTime.utc(2026, 9, 3, 0, index),
    ),
]);

final _completedSale = CompletedSale(
  id: 'sale-1',
  completedAt: DateTime.utc(2026, 9, 3, 4, 30),
  storeNameSnapshot: 'Aling Nena Store',
  storeAddressSnapshot: null,
  storeContactSnapshot: null,
  footerMessageSnapshot: 'Salamat po!',
  cashReceivedCentavos: 2000,
  lines: const [
    CompletedSaleLine(
      position: 0,
      productId: 'coffee',
      sellingUnitId: null,
      barcode: '4800012345678',
      nameSnapshot: 'Coffee',
      brandSnapshot: null,
      unitLabelSnapshot: 'Pack',
      imagePathSnapshot: null,
      unitPrice: Money.fromCentavos(1200),
      quantity: 1,
    ),
  ],
);

final _saleWithInvalidReceiptLine = CompletedSale(
  id: 'sale-with-invalid-receipt-line',
  completedAt: DateTime.utc(2026, 9, 3, 4, 31),
  storeNameSnapshot: 'Aling Nena Store',
  storeAddressSnapshot: null,
  storeContactSnapshot: null,
  footerMessageSnapshot: 'Salamat po!',
  cashReceivedCentavos: null,
  lines: const [
    CompletedSaleLine(
      position: 0,
      productId: 'coffee',
      sellingUnitId: null,
      barcode: '4800012345678',
      nameSnapshot: '',
      brandSnapshot: null,
      unitLabelSnapshot: 'Pack',
      imagePathSnapshot: null,
      unitPrice: Money.fromCentavos(1200),
      quantity: 1,
    ),
  ],
);

final class _FakeSettingsRepository implements SettingsRepository {
  _FakeSettingsRepository({this.profile, this.error});

  final StoreProfile? profile;
  final Object? error;
  int reads = 0;

  @override
  Future<StoreProfile> getStoreProfile() async {
    reads++;
    if (error case final error?) throw error;
    return profile!;
  }

  @override
  Future<void> resetStoreProfile() => throw UnimplementedError();

  @override
  Future<void> saveStoreProfile(StoreProfile profile) =>
      throw UnimplementedError();

  @override
  Stream<StoreProfile> watchStoreProfile() => const Stream.empty();
}

final class _DelayedCartRepository implements CartRepository {
  _DelayedCartRepository(this.cart, this.updateGate);

  final CartDraft cart;
  final Completer<void> updateGate;
  int updateCalls = 0;

  @override
  Future<void> addProduct(
    StoreProduct product, {
    ProductSaleOption? saleOption,
    int quantity = 1,
  }) async {}

  @override
  Future<void> clear() async {}

  @override
  Future<CartDraft> getDraft() async => cart;

  @override
  Future<void> removeProduct(String lineId) async {}

  @override
  Future<void> updateQuantity(String lineId, int quantity) async {
    updateCalls += 1;
    await updateGate.future;
  }

  @override
  Stream<CartDraft> watchDraft() => Stream.value(cart);
}

final class _SwipeCartRepository implements CartRepository {
  _SwipeCartRepository(this.cart, {this.removeError});

  final CartDraft cart;
  final Object? removeError;
  final List<String> removedLineIds = [];

  @override
  Future<void> addProduct(
    StoreProduct product, {
    ProductSaleOption? saleOption,
    int quantity = 1,
  }) async {}

  @override
  Future<void> clear() async {}

  @override
  Future<CartDraft> getDraft() async => cart;

  @override
  Future<void> removeProduct(String lineId) async {
    removedLineIds.add(lineId);
    if (removeError case final error?) throw error;
  }

  @override
  Future<void> updateQuantity(String lineId, int quantity) async {}

  @override
  Stream<CartDraft> watchDraft() => Stream.value(cart);
}

final class _FakeSalesRepository implements SalesRepository {
  _FakeSalesRepository(this.sale);

  final CompletedSale sale;
  int? completedWithCash;
  int completionCalls = 0;

  @override
  Future<CompletedSale> completeCurrentCart({int? cashReceivedCentavos}) async {
    completionCalls += 1;
    completedWithCash = cashReceivedCentavos;
    return sale;
  }

  @override
  Future<void> deleteSale(String id) => throw UnimplementedError();

  @override
  Future<void> deleteSales(Iterable<String> ids) => throw UnimplementedError();

  @override
  Future<CompletedSale?> getSale(String id) => throw UnimplementedError();

  @override
  Future<List<CompletedSale>> getSales({SalesDateRange? range}) =>
      throw UnimplementedError();

  @override
  Stream<DateTime?> watchOldestSaleDate() => const Stream.empty();

  @override
  Stream<CompletedSale?> watchSale(String id) => const Stream.empty();

  @override
  Stream<List<CompletedSale>> watchSales({SalesDateRange? range}) =>
      const Stream.empty();
}

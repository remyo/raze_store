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
import 'package:raze_store/features/catalog/application/catalog_providers.dart';
import 'package:raze_store/features/catalog/application/quick_sell_providers.dart';
import 'package:raze_store/features/catalog/domain/catalog_product.dart';
import 'package:raze_store/features/catalog/domain/catalog_repository.dart';
import 'package:raze_store/features/catalog/presentation/quick_sell_screen.dart';

void main() {
  test(
    'quick-sell provider keeps only products with alternate units',
    () async {
      final container = ProviderContainer(
        overrides: [
          catalogRepositoryProvider.overrideWithValue(
            _CatalogRepository([_regularProduct, _unitProduct]),
          ),
        ],
      );
      addTearDown(container.dispose);

      final subscription = container.listen(
        quickSellProductsProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);
      await container.pump();
      final products = container.read(quickSellProductsProvider).requireValue;

      expect(products.map((product) => product.id), ['cigarettes']);
    },
  );

  testWidgets('plus immediately adds the selected selling unit to cart', (
    tester,
  ) async {
    _useTallView(tester);
    final repository = _RecordingCartRepository(CartDraft(const []));
    await _pumpScreen(tester, repository: repository);

    await tester.tap(
      find.byKey(const ValueKey('quick-sell-add-cigarettes-stick')),
    );
    await tester.pump();

    expect(repository.addedProduct, same(_unitProduct));
    expect(repository.addedOption?.sellingUnitId, 'stick');
    expect(repository.addedOption?.label, 'Stick');
    expect(repository.addedQuantity, 1);
  });

  testWidgets('rapid plus taps are shown immediately and written in order', (
    tester,
  ) async {
    _useTallView(tester);
    final gate = Completer<void>();
    final repository = _RecordingCartRepository(
      CartDraft(const []),
      addGate: gate,
    );
    await _pumpScreen(tester, repository: repository);
    final addStick = find.byKey(
      const ValueKey('quick-sell-add-cigarettes-stick'),
    );

    await tester.tap(addStick);
    await tester.pump();
    await tester.tap(addStick);
    await tester.pump();

    expect(repository.addCalls, 1);
    expect(find.text('2'), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
    expect(repository.addCalls, 2);
  });

  testWidgets(
    'cart navigation waits for pending writes and blocks quantity changes',
    (tester) async {
      _useTallView(tester);
      final gate = Completer<void>();
      final repository = _RecordingCartRepository(
        CartDraft([_stickCartItem(quantity: 1)]),
        addGate: gate,
      );
      final router = GoRouter(
        initialLocation: '/quick-sell',
        routes: [
          GoRoute(
            path: '/quick-sell',
            builder: (_, _) => const QuickSellScreen(),
          ),
          GoRoute(
            path: '/cart',
            builder: (_, _) => const Scaffold(body: Text('Cart destination')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            quickSellProductsProvider.overrideWith(
              (ref) => Stream.value([_unitProduct]),
            ),
            cartDraftProvider.overrideWith((ref) => repository.watchDraft()),
            cartRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final openCart = find.byKey(const ValueKey('quick-sell-open-cart'));
      final viewCart = find.byKey(const ValueKey('quick-sell-view-cart'));
      final addStick = find.byKey(
        const ValueKey('quick-sell-add-cigarettes-stick'),
      );
      final staleOpenCartCallback = tester
          .widget<IconButton>(openCart)
          .onPressed!;

      await tester.tap(addStick);
      await tester.pump();

      expect(repository.addCalls, 1);
      expect(tester.widget<IconButton>(openCart).onPressed, isNull);
      expect(tester.widget<FilledButton>(viewCart).onPressed, isNull);

      staleOpenCartCallback();
      await tester.pump();

      expect(find.text('Cart destination'), findsNothing);
      expect(tester.widget<IconButton>(addStick).onPressed, isNull);

      gate.complete();
      await tester.pumpAndSettle();

      expect(find.text('Cart destination'), findsOneWidget);
      expect(repository.addCalls, 1);
    },
  );

  testWidgets('minus reduces the matching product and unit cart line', (
    tester,
  ) async {
    _useTallView(tester);
    final repository = _RecordingCartRepository(
      CartDraft([
        CartItem(
          lineId: 'saved-stick-line',
          productId: _unitProduct.id,
          sellingUnitId: 'stick',
          barcode: _unitProduct.barcode,
          nameSnapshot: _unitProduct.name,
          unitLabelSnapshot: 'Single stick',
          unitPrice: const Money.fromCentavos(900),
          quantity: 2,
          addedAt: DateTime.utc(2026, 9, 3),
          updatedAt: DateTime.utc(2026, 9, 3),
        ),
      ]),
    );
    await _pumpScreen(tester, repository: repository);

    expect(find.text('₱9.00'), findsOneWidget);
    expect(find.text('Using the price already in cart'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('quick-sell-remove-cigarettes-stick')),
    );
    await tester.pump();

    expect(repository.updatedLineId, 'saved-stick-line');
    expect(repository.updatedQuantity, 1);
  });

  testWidgets('empty page explains how to add unit prices', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          quickSellProductsProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
          cartDraftProvider.overrideWith(
            (ref) => Stream.value(CartDraft(const [])),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const QuickSellScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No unit prices yet'), findsOneWidget);
    expect(find.text('Open products'), findsOneWidget);
  });

  testWidgets('edit navigation safely encodes an imported product ID', (
    tester,
  ) async {
    final imported = StoreProduct(
      id: 'api/item ?#1',
      metadata: CatalogMetadata(name: 'Imported eggs', unitLabel: 'Tray'),
      price: const Money.fromCentavos(25000),
      sellingUnits: const [
        SellingUnit(
          id: 'piece',
          label: 'Piece',
          price: Money.fromCentavos(1000),
        ),
      ],
      createdAt: DateTime.utc(2026, 9, 3),
      updatedAt: DateTime.utc(2026, 9, 3),
    );
    final router = GoRouter(
      initialLocation: '/quick-sell',
      routes: [
        GoRoute(
          path: '/quick-sell',
          builder: (_, _) => const QuickSellScreen(),
        ),
        GoRoute(
          path: '/products/:id/edit',
          builder: (_, state) =>
              Scaffold(body: Text('Editing ${state.pathParameters['id']}')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          quickSellProductsProvider.overrideWith(
            (ref) => Stream.value([imported]),
          ),
          cartDraftProvider.overrideWith(
            (ref) => Stream.value(CartDraft(const [])),
          ),
        ],
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Edit Imported eggs'));
    await tester.pumpAndSettle();

    expect(find.text('Editing api/item ?#1'), findsOneWidget);
  });
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required _RecordingCartRepository repository,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        quickSellProductsProvider.overrideWith(
          (ref) => Stream.value([_unitProduct]),
        ),
        cartDraftProvider.overrideWith((ref) => repository.watchDraft()),
        cartRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const QuickSellScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void _useTallView(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(800, 1400);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

final _unitProduct = StoreProduct(
  id: 'cigarettes',
  metadata: CatalogMetadata(
    barcode: '4801234567890',
    name: 'Cigarettes',
    brand: 'Sample',
    unitLabel: 'Pack',
    category: 'Tobacco',
  ),
  price: const Money.fromCentavos(16000),
  sellingUnits: const [
    SellingUnit(id: 'stick', label: 'Stick', price: Money.fromCentavos(1000)),
  ],
  createdAt: DateTime.utc(2026, 9, 3),
  updatedAt: DateTime.utc(2026, 9, 3),
);

final _regularProduct = StoreProduct(
  id: 'soap',
  metadata: CatalogMetadata(name: 'Soap'),
  price: const Money.fromCentavos(2500),
  createdAt: DateTime.utc(2026, 9, 3),
  updatedAt: DateTime.utc(2026, 9, 3),
);

CartItem _stickCartItem({required int quantity}) => CartItem(
  lineId: 'saved-stick-line',
  productId: _unitProduct.id,
  sellingUnitId: 'stick',
  barcode: _unitProduct.barcode,
  nameSnapshot: _unitProduct.name,
  unitLabelSnapshot: 'Stick',
  unitPrice: const Money.fromCentavos(1000),
  quantity: quantity,
  addedAt: DateTime.utc(2026, 9, 3),
  updatedAt: DateTime.utc(2026, 9, 3),
);

final class _RecordingCartRepository implements CartRepository {
  _RecordingCartRepository(this.cart, {this.addGate});

  final CartDraft cart;
  final Completer<void>? addGate;
  StoreProduct? addedProduct;
  ProductSaleOption? addedOption;
  int? addedQuantity;
  int addCalls = 0;
  String? updatedLineId;
  int? updatedQuantity;

  @override
  Future<void> addProduct(
    StoreProduct product, {
    ProductSaleOption? saleOption,
    int quantity = 1,
  }) async {
    addCalls++;
    addedProduct = product;
    addedOption = saleOption;
    addedQuantity = quantity;
    await addGate?.future;
  }

  @override
  Future<void> clear() async {}

  @override
  Future<CartDraft> getDraft() async => cart;

  @override
  Future<void> removeProduct(String lineId) async {}

  @override
  Future<void> updateQuantity(String lineId, int quantity) async {
    updatedLineId = lineId;
    updatedQuantity = quantity;
  }

  @override
  Stream<CartDraft> watchDraft() => Stream.value(cart);
}

final class _CatalogRepository implements CatalogRepository {
  const _CatalogRepository(this.products);

  final List<StoreProduct> products;

  @override
  Stream<List<StoreProduct>> watchProducts({String query = ''}) =>
      Stream.value(products);

  @override
  Future<StoreProduct> createProduct(ProductDraft draft) =>
      throw UnimplementedError();

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
  Stream<StoreProduct?> watchProduct(String id) => throw UnimplementedError();
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/core/money/money.dart';
import 'package:raze_store/features/cart/application/cart_providers.dart';
import 'package:raze_store/features/cart/domain/cart.dart';
import 'package:raze_store/features/cart/domain/cart_repository.dart';
import 'package:raze_store/features/catalog/application/catalog_lookup_providers.dart';
import 'package:raze_store/features/catalog/application/catalog_lookup_service.dart';
import 'package:raze_store/features/catalog/domain/catalog_product.dart';
import 'package:raze_store/features/catalog/domain/catalog_repository.dart';
import 'package:raze_store/features/catalog/domain/remote_catalog_product.dart';
import 'package:raze_store/features/catalog/domain/remote_catalog_repository.dart';
import 'package:raze_store/features/scanner/application/scan_feedback_service.dart';
import 'package:raze_store/features/scanner/presentation/scanner_screen.dart';
import 'package:raze_store/features/settings/application/settings_providers.dart';
import 'package:raze_store/features/settings/domain/app_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MobileScannerPlatform originalPlatform;

  setUp(() {
    originalPlatform = MobileScannerPlatform.instance;
    MobileScannerController.resetPlatformSessionOwner();
  });

  tearDown(() {
    MobileScannerController.resetPlatformSessionOwner();
    MobileScannerPlatform.instance = originalPlatform;
  });

  testWidgets(
    'known single-unit scans add once per scan and reject a camera burst',
    (tester) async {
      final platform = _FakeMobileScannerPlatform();
      MobileScannerPlatform.instance = platform;
      final product = _product();
      final local = _LookupCatalogRepository(product);
      final cart = _RecordingCartRepository();
      final feedback = _RecordingScanFeedbackService();

      await _pumpScanner(tester, local: local, cart: cart, feedback: feedback);

      expect(find.byKey(const ValueKey('open-cart')), findsNothing);
      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.actions, anyOf(isNull, isEmpty));
      expect(
        find.byKey(const ValueKey('scanner-cart-checkout')),
        findsOneWidget,
      );
      expect(find.text('View cart & checkout'), findsOneWidget);
      expect(find.text('0 items'), findsOneWidget);

      final cartButtonTop = tester.getTopLeft(
        find.byKey(const ValueKey('scanner-cart-checkout')),
      );
      final manualSectionTop = tester.getTopLeft(
        find.text('Enter a barcode manually'),
      );
      expect(cartButtonTop.dy, lessThan(manualSectionTop.dy));

      const capture = BarcodeCapture(
        barcodes: [Barcode(rawValue: '4800012345678')],
      );
      platform
        ..addBarcode(capture)
        ..addBarcode(capture);
      await _pumpForScan(tester);

      expect(local.lookupCalls, 1);
      expect(cart.addCalls, 1);
      expect(cart.totalQuantity, 1);
      expect(cart.saleOptions, [null]);
      expect(find.text('Choose how it is sold'), findsNothing);
      expect(find.text('Local product added to cart.'), findsOneWidget);
      expect(find.byKey(const ValueKey('scan-added-feedback')), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      expect(feedback.calls, [(sound: true, vibration: true)]);
      expect(find.text('1 item'), findsOneWidget);

      // Repeated camera frames for the label that is still visible stay
      // guarded and do not start another lookup or cart mutation.
      platform
        ..addBarcode(capture)
        ..addBarcode(capture);
      await tester.pump(const Duration(milliseconds: 100));
      expect(local.lookupCalls, 1);
      expect(cart.totalQuantity, 1);
      expect(feedback.calls, hasLength(1));

      // Once the label has left the frame long enough, scanning the same SKU
      // again is intentional and increments its cart quantity.
      await tester.pump(const Duration(milliseconds: 501));
      platform.addBarcode(capture);
      await _pumpForScan(tester);

      expect(local.lookupCalls, 2);
      expect(cart.addCalls, 2);
      expect(cart.totalQuantity, 2);
      expect(cart.saleOptions, [null, null]);
      expect(feedback.calls, hasLength(2));
      expect(find.text('2 items'), findsOneWidget);
    },
  );

  testWidgets('the scanner cart button opens the checkout cart page', (
    tester,
  ) async {
    final platform = _FakeMobileScannerPlatform();
    MobileScannerPlatform.instance = platform;

    await _pumpScanner(
      tester,
      local: _LookupCatalogRepository(_product()),
      cart: _RecordingCartRepository(initialQuantity: 3),
    );

    expect(find.text('3 items'), findsOneWidget);
    final cartButton = find.byKey(const ValueKey('scanner-cart-checkout'));
    await tester.ensureVisible(cartButton);
    await tester.tap(cartButton);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('scanner-cart-destination')),
      findsOneWidget,
    );
    expect(find.text('Cart page'), findsOneWidget);
  });

  testWidgets('a barcode with sub-unit prices asks which unit to add', (
    tester,
  ) async {
    final platform = _FakeMobileScannerPlatform();
    MobileScannerPlatform.instance = platform;
    final product = _product(
      sellingUnits: const [
        SellingUnit(
          id: 'piece',
          label: 'Piece',
          price: Money.fromCentavos(1000),
        ),
      ],
    );
    final local = _LookupCatalogRepository(product);
    final cart = _RecordingCartRepository();
    final feedback = _RecordingScanFeedbackService();

    await _pumpScanner(
      tester,
      local: local,
      cart: cart,
      preferences: _preferences(autoAddMainUnitOnScan: false),
      feedback: feedback,
    );
    platform.addBarcode(
      const BarcodeCapture(barcodes: [Barcode(rawValue: '4800012345678')]),
    );
    await _pumpForScan(tester);

    expect(local.lookupCalls, 1);
    expect(cart.addCalls, 0);
    expect(find.text('Choose how it is sold'), findsOneWidget);
    expect(find.text('Pack'), findsWidgets);
    expect(find.text('Piece'), findsOneWidget);

    await tester.tap(find.text('Piece'));
    await tester.pump();
    await tester.tap(find.text('Add 1 Piece'));
    await _pumpForScan(tester);

    expect(cart.addCalls, 1);
    expect(cart.totalQuantity, 1);
    expect(cart.saleOptions.single?.sellingUnitId, 'piece');
    expect(find.text('Local product added to cart.'), findsOneWidget);
    expect(feedback.calls, [(sound: true, vibration: true)]);
  });

  testWidgets('auto-main scan bypasses the chooser for products with units', (
    tester,
  ) async {
    final platform = _FakeMobileScannerPlatform();
    MobileScannerPlatform.instance = platform;
    final product = _product(
      sellingUnits: const [
        SellingUnit(
          id: 'piece',
          label: 'Piece',
          price: Money.fromCentavos(1000),
        ),
      ],
    );
    final local = _LookupCatalogRepository(product);
    final cart = _RecordingCartRepository();

    await _pumpScanner(tester, local: local, cart: cart);
    platform.addBarcode(
      const BarcodeCapture(barcodes: [Barcode(rawValue: '4800012345678')]),
    );
    await _pumpForScan(tester);

    expect(find.text('Choose how it is sold'), findsNothing);
    expect(cart.addCalls, 1);
    expect(cart.saleOptions, [null]);
  });

  testWidgets('zero-price main unit falls back to the priced-unit chooser', (
    tester,
  ) async {
    final platform = _FakeMobileScannerPlatform();
    MobileScannerPlatform.instance = platform;
    final product = _product(
      priceCentavos: 0,
      sellingUnits: const [
        SellingUnit(
          id: 'piece',
          label: 'Piece',
          price: Money.fromCentavos(1000),
        ),
      ],
    );
    final local = _LookupCatalogRepository(product);
    final cart = _RecordingCartRepository();

    await _pumpScanner(tester, local: local, cart: cart);
    platform.addBarcode(
      const BarcodeCapture(barcodes: [Barcode(rawValue: '4800012345678')]),
    );
    await _pumpForScan(tester);

    expect(cart.addCalls, 0);
    expect(find.text('Choose how it is sold'), findsOneWidget);
    expect(find.text('Piece'), findsOneWidget);

    await tester.tap(find.text('Piece'));
    await tester.pump();
    await tester.tap(find.text('Add 1 Piece'));
    await _pumpForScan(tester);

    expect(cart.addCalls, 1);
    expect(cart.saleOptions.single?.sellingUnitId, 'piece');
  });

  testWidgets('auto-main scan rejects a product when every unit is unpriced', (
    tester,
  ) async {
    final platform = _FakeMobileScannerPlatform();
    MobileScannerPlatform.instance = platform;
    final product = _product(
      priceCentavos: 0,
      sellingUnits: const [
        SellingUnit(id: 'piece', label: 'Piece', price: Money.fromCentavos(0)),
      ],
    );
    final cart = _RecordingCartRepository();

    await _pumpScanner(
      tester,
      local: _LookupCatalogRepository(product),
      cart: cart,
    );
    platform.addBarcode(
      const BarcodeCapture(barcodes: [Barcode(rawValue: '4800012345678')]),
    );
    await _pumpForScan(tester);

    expect(find.text('Choose how it is sold'), findsNothing);
    expect(find.textContaining('Set a selling price'), findsOneWidget);
    expect(cart.addCalls, 0);
  });

  testWidgets('sound and vibration settings are passed to scan feedback', (
    tester,
  ) async {
    final platform = _FakeMobileScannerPlatform();
    MobileScannerPlatform.instance = platform;
    final feedback = _RecordingScanFeedbackService();

    await _pumpScanner(
      tester,
      local: _LookupCatalogRepository(_product()),
      cart: _RecordingCartRepository(),
      preferences: _preferences(
        scannerSoundEnabled: false,
        scannerVibrationEnabled: true,
      ),
      feedback: feedback,
    );
    platform.addBarcode(
      const BarcodeCapture(barcodes: [Barcode(rawValue: '4800012345678')]),
    );
    await _pumpForScan(tester);

    expect(feedback.calls, [(sound: false, vibration: true)]);
  });

  testWidgets('disabled sound and vibration skip device feedback', (
    tester,
  ) async {
    final platform = _FakeMobileScannerPlatform();
    MobileScannerPlatform.instance = platform;
    final feedback = _RecordingScanFeedbackService();

    await _pumpScanner(
      tester,
      local: _LookupCatalogRepository(_product()),
      cart: _RecordingCartRepository(),
      preferences: _preferences(
        scannerSoundEnabled: false,
        scannerVibrationEnabled: false,
      ),
      feedback: feedback,
    );
    platform.addBarcode(
      const BarcodeCapture(barcodes: [Barcode(rawValue: '4800012345678')]),
    );
    await _pumpForScan(tester);

    expect(feedback.calls, isEmpty);
  });

  testWidgets('a custom repeat cooldown controls deliberate re-scans', (
    tester,
  ) async {
    final platform = _FakeMobileScannerPlatform();
    MobileScannerPlatform.instance = platform;
    final local = _LookupCatalogRepository(_product());
    final cart = _RecordingCartRepository();
    const capture = BarcodeCapture(
      barcodes: [Barcode(rawValue: '4800012345678')],
    );

    await _pumpScanner(
      tester,
      local: local,
      cart: cart,
      preferences: _preferences(scannerRepeatCooldownMs: 1000),
    );
    platform.addBarcode(capture);
    await _pumpForScan(tester);

    // Seeing the same label again refreshes the leave-frame countdown.
    platform.addBarcode(capture);
    await tester.pump(const Duration(milliseconds: 700));
    expect(local.lookupCalls, 1);

    await tester.pump(const Duration(milliseconds: 1001));
    platform.addBarcode(capture);
    await _pumpForScan(tester);

    expect(local.lookupCalls, 2);
    expect(cart.addCalls, 2);
  });

  testWidgets('manual barcode entry never plays scanner feedback', (
    tester,
  ) async {
    final platform = _FakeMobileScannerPlatform();
    MobileScannerPlatform.instance = platform;
    final cart = _RecordingCartRepository();
    final feedback = _RecordingScanFeedbackService();

    await _pumpScanner(
      tester,
      local: _LookupCatalogRepository(_product()),
      cart: cart,
      feedback: feedback,
    );
    await tester.drag(find.byType(ListView), const Offset(0, -420));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('manual-barcode-field')),
      '4800012345678',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await _pumpForScan(tester);

    expect(cart.addCalls, 1);
    expect(feedback.calls, isEmpty);
  });

  testWidgets('a guarded barcode does not starve a different visible label', (
    tester,
  ) async {
    final platform = _FakeMobileScannerPlatform();
    MobileScannerPlatform.instance = platform;
    final local = _LookupCatalogRepository(_product());
    final cart = _RecordingCartRepository();

    await _pumpScanner(tester, local: local, cart: cart);
    platform.addBarcode(
      const BarcodeCapture(barcodes: [Barcode(rawValue: '4800012345678')]),
    );
    await _pumpForScan(tester);

    platform.addBarcode(
      const BarcodeCapture(
        barcodes: [
          Barcode(rawValue: '4800012345678'),
          Barcode(rawValue: '4800012345685'),
        ],
      ),
    );
    await _pumpForScan(tester);

    expect(local.lookedUpBarcodes, ['4800012345678', '4800012345685']);
    expect(cart.addCalls, 2);

    // Accepting the second label must not clear the first label's guard while
    // both products are still inside the camera frame.
    platform.addBarcode(
      const BarcodeCapture(barcodes: [Barcode(rawValue: '4800012345678')]),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(local.lookupCalls, 2);
    expect(cart.addCalls, 2);
  });

  testWidgets('an unknown barcode keeps the add-product workflow', (
    tester,
  ) async {
    final platform = _FakeMobileScannerPlatform();
    MobileScannerPlatform.instance = platform;
    final local = _LookupCatalogRepository(null);
    final cart = _RecordingCartRepository();

    await _pumpScanner(tester, local: local, cart: cart);
    platform.addBarcode(
      const BarcodeCapture(barcodes: [Barcode(rawValue: 'UNKNOWN-123')]),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(cart.addCalls, 0);
    expect(find.text('Product not found'), findsOneWidget);
    expect(find.text('Add this product'), findsOneWidget);

    await tester.tap(find.text('Scan another'));
    await _pumpForScan(tester);

    // The same label is still guarded after dismissing the unknown-product
    // prompt, so it cannot immediately reopen the sheet.
    platform.addBarcode(
      const BarcodeCapture(barcodes: [Barcode(rawValue: 'UNKNOWN-123')]),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(local.lookupCalls, 1);
    expect(find.text('Product not found'), findsNothing);
  });

  testWidgets('a known zero-price product is not added as a free cart line', (
    tester,
  ) async {
    final platform = _FakeMobileScannerPlatform();
    MobileScannerPlatform.instance = platform;
    final local = _LookupCatalogRepository(_product(priceCentavos: 0));
    final cart = _RecordingCartRepository();

    await _pumpScanner(tester, local: local, cart: cart);
    platform.addBarcode(
      const BarcodeCapture(barcodes: [Barcode(rawValue: '4800012345678')]),
    );
    await _pumpForScan(tester);

    expect(cart.addCalls, 0);
    expect(find.textContaining('Set a selling price'), findsOneWidget);
    expect(find.text('Set price'), findsOneWidget);
  });

  testWidgets('a failed cart write has no success feedback and is guarded', (
    tester,
  ) async {
    final platform = _FakeMobileScannerPlatform();
    MobileScannerPlatform.instance = platform;
    final local = _LookupCatalogRepository(_product());
    final cart = _RecordingCartRepository(addError: StateError('write failed'));
    final feedback = _RecordingScanFeedbackService();
    const capture = BarcodeCapture(
      barcodes: [Barcode(rawValue: '4800012345678')],
    );

    await _pumpScanner(tester, local: local, cart: cart, feedback: feedback);
    platform.addBarcode(capture);
    await _pumpForScan(tester);

    expect(
      find.text('Could not add this product to the cart.'),
      findsOneWidget,
    );
    expect(feedback.calls, isEmpty);

    platform.addBarcode(capture);
    await tester.pump(const Duration(milliseconds: 100));
    expect(local.lookupCalls, 1);
    expect(feedback.calls, isEmpty);
  });
}

Future<void> _pumpScanner(
  WidgetTester tester, {
  required CatalogRepository local,
  required CartRepository cart,
  AppPreferences? preferences,
  ScanFeedbackService? feedback,
}) async {
  final resolvedPreferences = preferences ?? _preferences();
  final router = GoRouter(
    initialLocation: '/scanner',
    routes: [
      GoRoute(
        path: '/scanner',
        builder: (context, state) => const ScannerScreen(),
      ),
      GoRoute(
        path: '/cart',
        builder: (context, state) => const Scaffold(
          key: ValueKey('scanner-cart-destination'),
          body: Center(child: Text('Cart page')),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        cartRepositoryProvider.overrideWithValue(cart),
        appPreferencesProvider.overrideWith(
          () => _TestAppPreferencesController(resolvedPreferences),
        ),
        scanFeedbackServiceProvider.overrideWithValue(
          feedback ?? _RecordingScanFeedbackService(),
        ),
        catalogLookupServiceProvider.overrideWithValue(
          CatalogLookupService(
            local: local,
            remote: const _UnconfiguredRemoteCatalogRepository(),
          ),
        ),
      ],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

AppPreferences _preferences({
  bool scannerSoundEnabled = true,
  bool scannerVibrationEnabled = true,
  int scannerRepeatCooldownMs = 500,
  bool autoAddMainUnitOnScan = true,
}) => AppPreferences(
  scannerSoundEnabled: scannerSoundEnabled,
  scannerVibrationEnabled: scannerVibrationEnabled,
  scannerRepeatCooldownMs: scannerRepeatCooldownMs,
  autoAddMainUnitOnScan: autoAddMainUnitOnScan,
  backupReminderFrequency: BackupReminderFrequency.weekly,
  reminderAnchorAtUtc: DateTime.utc(2026, 9, 4),
);

Future<void> _pumpForScan(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

StoreProduct _product({
  int priceCentavos = 12000,
  List<SellingUnit> sellingUnits = const [],
}) => StoreProduct(
  id: 'local-product',
  metadata: CatalogMetadata(
    barcode: '4800012345678',
    name: 'Local product',
    unitLabel: 'Pack',
  ),
  price: Money.fromCentavos(priceCentavos),
  sellingUnits: sellingUnits,
  createdAt: DateTime.utc(2026, 9, 3),
  updatedAt: DateTime.utc(2026, 9, 3),
);

final class _RecordingCartRepository implements CartRepository {
  _RecordingCartRepository({this.addError, int initialQuantity = 0})
    : totalQuantity = initialQuantity;

  final Object? addError;
  int addCalls = 0;
  int totalQuantity;
  final List<ProductSaleOption?> saleOptions = [];
  final StreamController<CartDraft> _drafts =
      StreamController<CartDraft>.broadcast(sync: true);
  StoreProduct? _latestProduct;

  @override
  Future<void> addProduct(
    StoreProduct product, {
    ProductSaleOption? saleOption,
    int quantity = 1,
  }) async {
    addCalls++;
    if (addError case final error?) throw error;
    totalQuantity += quantity;
    saleOptions.add(saleOption);
    _latestProduct = product;
    _drafts.add(_draft);
  }

  @override
  Future<void> clear() async {}

  @override
  Future<CartDraft> getDraft() async => _draft;

  @override
  Future<void> removeProduct(String lineId) async {}

  @override
  Future<void> updateQuantity(String lineId, int quantity) async {}

  @override
  Stream<CartDraft> watchDraft() async* {
    yield _draft;
    yield* _drafts.stream;
  }

  CartDraft get _draft {
    if (totalQuantity == 0) return CartDraft(const []);
    final product = _latestProduct ?? _product();
    final saleOption = saleOptions.lastOrNull;
    return CartDraft([
      CartItem(
        lineId: 'scanner-test-line',
        productId: product.id,
        sellingUnitId: saleOption?.sellingUnitId,
        barcode: product.barcode,
        nameSnapshot: product.name,
        unitPrice: saleOption?.price ?? product.price,
        quantity: totalQuantity,
        addedAt: DateTime.utc(2026, 9, 4),
        updatedAt: DateTime.utc(2026, 9, 4),
      ),
    ]);
  }
}

final class _LookupCatalogRepository implements CatalogRepository {
  _LookupCatalogRepository(this.product);

  final StoreProduct? product;
  int lookupCalls = 0;
  final List<String> lookedUpBarcodes = [];

  @override
  Future<StoreProduct?> findByBarcode(String rawBarcode) async {
    lookupCalls++;
    lookedUpBarcodes.add(rawBarcode);
    return product;
  }

  @override
  Future<StoreProduct?> findBySource(
    String source,
    String sourceProductId,
  ) async => null;

  @override
  Future<StoreProduct> createProduct(ProductDraft draft) =>
      throw UnimplementedError();

  @override
  Future<void> deleteProduct(String id) => throw UnimplementedError();

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

final class _TestAppPreferencesController extends AppPreferencesController {
  _TestAppPreferencesController(this.preferences);

  final AppPreferences preferences;

  @override
  Future<AppPreferences> build() async => preferences;
}

final class _RecordingScanFeedbackService implements ScanFeedbackService {
  final List<({bool sound, bool vibration})> calls = [];

  @override
  Future<void> confirmProductAdded({
    required bool soundEnabled,
    required bool vibrationEnabled,
  }) async {
    calls.add((sound: soundEnabled, vibration: vibrationEnabled));
  }
}

final class _UnconfiguredRemoteCatalogRepository
    implements RemoteCatalogRepository {
  const _UnconfiguredRemoteCatalogRepository();

  @override
  Uri? get baseUri => null;

  @override
  String? get configurationError => 'Not configured';

  @override
  bool get isConfigured => false;

  @override
  Future<CatalogApiHealth> checkHealth() => throw UnimplementedError();

  @override
  Future<List<String>> fetchCategories() => throw UnimplementedError();

  @override
  Future<RemoteCatalogProduct?> findByBarcode(String barcode) =>
      throw UnimplementedError();

  @override
  Future<RemoteCatalogPage> searchProducts({String query = '', int page = 1}) =>
      throw UnimplementedError();
}

final class _FakeMobileScannerPlatform extends MobileScannerPlatform {
  final _barcodeController = StreamController<BarcodeCapture?>.broadcast();

  @override
  Stream<BarcodeCapture?> get barcodesStream => _barcodeController.stream;

  @override
  Stream<TorchState> get torchStateStream =>
      Stream.value(TorchState.unavailable);

  @override
  Stream<double> get zoomScaleStateStream => Stream.value(1);

  @override
  Widget buildCameraView() => const SizedBox.square(dimension: 100);

  @override
  Future<MobileScannerViewAttributes> start(StartOptions startOptions) async {
    return const MobileScannerViewAttributes(
      cameraDirection: CameraFacing.back,
      currentTorchMode: TorchState.unavailable,
      size: Size(200, 200),
      numberOfCameras: 1,
    );
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    await _barcodeController.close();
  }

  void addBarcode(BarcodeCapture capture) => _barcodeController.add(capture);
}

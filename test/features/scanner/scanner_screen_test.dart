import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:raze_store/features/scanner/presentation/scanner_screen.dart';

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
    'known camera scans add the main unit once per scan and reject a burst',
    (tester) async {
      final platform = _FakeMobileScannerPlatform();
      MobileScannerPlatform.instance = platform;
      final product = _product();
      final local = _LookupCatalogRepository(product);
      final cart = _RecordingCartRepository();

      await _pumpScanner(tester, local: local, cart: cart);

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

      // Repeated camera frames for the label that is still visible stay
      // guarded and do not start another lookup or cart mutation.
      platform
        ..addBarcode(capture)
        ..addBarcode(capture);
      await tester.pump(const Duration(milliseconds: 100));
      expect(local.lookupCalls, 1);
      expect(cart.totalQuantity, 1);

      // Once the label has left the frame long enough, scanning the same SKU
      // again is intentional and increments its cart quantity.
      await tester.pump(const Duration(milliseconds: 901));
      platform.addBarcode(capture);
      await _pumpForScan(tester);

      expect(local.lookupCalls, 2);
      expect(cart.addCalls, 2);
      expect(cart.totalQuantity, 2);
      expect(cart.saleOptions, [null, null]);
    },
  );

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
}

Future<void> _pumpScanner(
  WidgetTester tester, {
  required CatalogRepository local,
  required CartRepository cart,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        cartRepositoryProvider.overrideWithValue(cart),
        catalogLookupServiceProvider.overrideWithValue(
          CatalogLookupService(
            local: local,
            remote: const _UnconfiguredRemoteCatalogRepository(),
          ),
        ),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const ScannerScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpForScan(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

StoreProduct _product({int priceCentavos = 12000}) => StoreProduct(
  id: 'local-product',
  metadata: CatalogMetadata(
    barcode: '4800012345678',
    name: 'Local product',
    unitLabel: 'Pack',
  ),
  price: Money.fromCentavos(priceCentavos),
  sellingUnits: const [
    SellingUnit(id: 'piece', label: 'Piece', price: Money.fromCentavos(1000)),
  ],
  createdAt: DateTime.utc(2026, 9, 3),
  updatedAt: DateTime.utc(2026, 9, 3),
);

final class _RecordingCartRepository implements CartRepository {
  int addCalls = 0;
  int totalQuantity = 0;
  final List<ProductSaleOption?> saleOptions = [];

  @override
  Future<void> addProduct(
    StoreProduct product, {
    ProductSaleOption? saleOption,
    int quantity = 1,
  }) async {
    addCalls++;
    totalQuantity += quantity;
    saleOptions.add(saleOption);
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

final class _LookupCatalogRepository implements CatalogRepository {
  _LookupCatalogRepository(this.product);

  final StoreProduct? product;
  int lookupCalls = 0;

  @override
  Future<StoreProduct?> findByBarcode(String rawBarcode) async {
    lookupCalls++;
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

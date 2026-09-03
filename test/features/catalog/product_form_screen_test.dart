import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/core/money/money.dart';
import 'package:raze_store/core/storage/local_product_image_store.dart';
import 'package:raze_store/core/storage/product_photo_services.dart';
import 'package:raze_store/features/catalog/application/catalog_providers.dart';
import 'package:raze_store/features/catalog/domain/catalog_product.dart';
import 'package:raze_store/features/catalog/domain/catalog_repository.dart';
import 'package:raze_store/features/catalog/presentation/product_form_screen.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  testWidgets('uses the API suggested retail price as an editable default', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogCategorySuggestionsProvider.overrideWithValue(const []),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: ProductFormScreen(
            initialMetadata: CatalogMetadata(
              name: 'API product',
              suggestedPriceCentavos: 850,
            ),
          ),
        ),
      ),
    );

    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('product-main-price-field')),
          )
          .controller
          ?.text,
      '8.50',
    );
  });

  testWidgets('offers offline background removal for a chosen photo', (
    tester,
  ) async {
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('raze_store_background_test_'),
    ))!;
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/source.png');
    final processed = File('${directory.path}/background-removed.png');
    await tester.runAsync(() async {
      final bytes = base64Decode(_onePixelPng);
      await source.writeAsBytes(bytes);
      await processed.writeAsBytes(bytes);
    });
    final remover = _FakeBackgroundRemover(XFile(processed.path));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogCategorySuggestionsProvider.overrideWithValue(const []),
          productPhotoPickerProvider.overrideWithValue(
            _FakePhotoPicker(XFile(source.path)),
          ),
          productBackgroundRemoverProvider.overrideWithValue(remover),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const ProductFormScreen(),
        ),
      ),
    );

    await tester.tap(find.text('Add photo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Choose from gallery'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final removeBackground = find.byKey(
      const ValueKey('remove-photo-background'),
    );
    expect(removeBackground, findsOneWidget);
    await tester.tap(removeBackground);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(remover.calls, 1);
    expect(find.text('Background removed'), findsOneWidget);

    final processedPath = remover.lastOutputPath!;
    expect(File(processedPath).existsSync(), isTrue);
    await tester.tap(find.text('Remove'));
    await tester.pump();
    expect(File(processedPath).existsSync(), isFalse);
    expect(remover.deletedPaths, [processedPath]);
  });

  testWidgets('takes and saves a photo while creating a product', (
    tester,
  ) async {
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('raze_store_create_photo_test_'),
    ))!;
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/camera.png');
    await tester.runAsync(
      () => source.writeAsBytes(base64Decode(_onePixelPng)),
    );
    final repository = _RecordingCatalogRepository();
    final picker = _FakePhotoPicker(XFile(source.path));
    final imageStore = _RecordingProductImageStore();
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
          catalogRepositoryProvider.overrideWithValue(repository),
          catalogCategorySuggestionsProvider.overrideWithValue(const []),
          productPhotoPickerProvider.overrideWithValue(picker),
          localProductImageStoreProvider.overrideWithValue(imageStore),
        ],
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add photo'));
    await tester.pumpAndSettle();
    expect(find.text('Take a photo'), findsOneWidget);
    expect(find.text('Choose from gallery'), findsOneWidget);
    await tester.tap(find.text('Take a photo'));
    await tester.pumpAndSettle();

    expect(picker.cameraCalls, 1);
    expect(find.text('Change photo'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('product-name-field')),
      'Test product',
    );
    await tester.enterText(
      find.byKey(const ValueKey('product-main-price-field')),
      '12.50',
    );
    await tester.tap(find.text('Save product'));
    await tester.pumpAndSettle();

    expect(repository.created, hasLength(1));
    expect(imageStore.persistedSourcePaths, [source.path]);
    final storedPath = repository.created.single.localImagePath;
    expect(storedPath, isNotNull);
    expect(File(storedPath!).existsSync(), isTrue);
    expect(find.text('Product list'), findsOneWidget);
  });

  testWidgets('offers camera and gallery while editing a product', (
    tester,
  ) async {
    final product = StoreProduct(
      id: 'existing-product',
      metadata: CatalogMetadata(name: 'Existing product'),
      price: const Money.fromCentavos(1250),
      createdAt: DateTime.utc(2026, 9, 3),
      updatedAt: DateTime.utc(2026, 9, 3),
    );
    final repository = _RecordingCatalogRepository(watchedProduct: product);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogRepositoryProvider.overrideWithValue(repository),
          catalogCategorySuggestionsProvider.overrideWithValue(const []),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: ProductFormScreen(productId: product.id),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Edit product'), findsOneWidget);
    await tester.tap(find.text('Add photo'));
    await tester.pumpAndSettle();

    expect(find.text('Take a photo'), findsOneWidget);
    expect(find.text('Choose from gallery'), findsOneWidget);
  });

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

  testWidgets('opens an explicit category picker while adding a product', (
    tester,
  ) async {
    await _pumpForm(
      tester,
      categorySuggestions: const ['Canned Goods', 'Snacks'],
    );

    final picker = find.byKey(const ValueKey('choose-product-category'));
    await tester.ensureVisible(picker);
    await tester.tap(picker);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('product-category-options')),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(ListTile, 'Canned Goods'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('product-category-field')),
          )
          .controller
          ?.text,
      'Canned Goods',
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

  testWidgets('a duplicate barcode offers the product that already owns it', (
    tester,
  ) async {
    final existing = StoreProduct(
      id: 'existing-coffee',
      metadata: CatalogMetadata(
        barcode: '4800012345678',
        name: 'Existing coffee',
      ),
      price: const Money.fromCentavos(1250),
      createdAt: DateTime.utc(2026, 9, 3),
      updatedAt: DateTime.utc(2026, 9, 3),
    );
    final repository = _RecordingCatalogRepository(
      duplicateBarcodeProduct: existing,
    );
    StoreProduct? routeResult;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: TextButton(
              onPressed: () async {
                routeResult = await context.push<StoreProduct>('/products/new');
              },
              child: const Text('Open add product'),
            ),
          ),
        ),
        GoRoute(
          path: '/products/new',
          builder: (_, _) => const ProductFormScreen(),
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

    await tester.tap(find.text('Open add product'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('product-name-field')),
      'Accidental duplicate',
    );
    await tester.enterText(
      find.byKey(const ValueKey('product-main-price-field')),
      '10.00',
    );
    await tester.enterText(
      find.byKey(const ValueKey('product-barcode-field')),
      '4800012345678',
    );
    await tester.tap(find.text('Save product'));
    await tester.pumpAndSettle();

    expect(find.text('Barcode already saved'), findsOneWidget);
    expect(find.textContaining('belongs to Existing coffee'), findsOneWidget);
    expect(find.textContaining('no duplicate was created'), findsOneWidget);
    expect(repository.created, hasLength(1));

    await tester.tap(
      find.byKey(const ValueKey('use-existing-barcode-product')),
    );
    await tester.pumpAndSettle();

    expect(routeResult?.id, existing.id);
    expect(find.text('Open add product'), findsOneWidget);
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
  _RecordingCatalogRepository({
    this.watchedProduct,
    this.duplicateBarcodeProduct,
  });

  final StoreProduct? watchedProduct;
  final StoreProduct? duplicateBarcodeProduct;
  final List<ProductDraft> created = [];

  @override
  Future<StoreProduct> createProduct(ProductDraft draft) async {
    created.add(draft);
    final duplicate = duplicateBarcodeProduct;
    if (duplicate != null && duplicate.barcode == draft.barcode) {
      throw DuplicateBarcodeException(draft.barcode!);
    }
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
  Future<StoreProduct?> findByBarcode(String rawBarcode) async {
    final duplicate = duplicateBarcodeProduct;
    return duplicate?.barcode == rawBarcode ? duplicate : null;
  }

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
  Stream<StoreProduct?> watchProduct(String id) => watchedProduct == null
      ? const Stream.empty()
      : Stream.value(watchedProduct);

  @override
  Stream<List<StoreProduct>> watchProducts({String query = ''}) =>
      const Stream.empty();
}

final class _RecordingProductImageStore extends LocalProductImageStore {
  _RecordingProductImageStore() : super(root: Directory.systemTemp);

  final List<String> persistedSourcePaths = [];

  @override
  Future<String> persist({required XFile source}) async {
    persistedSourcePaths.add(source.path);
    return source.path;
  }
}

final class _FakePhotoPicker implements ProductPhotoPicker {
  _FakePhotoPicker(this.file);

  final XFile file;
  int cameraCalls = 0;
  int galleryCalls = 0;

  @override
  Future<XFile?> pickFromGallery() async {
    galleryCalls++;
    return file;
  }

  @override
  Future<XFile?> takePhoto() async {
    cameraCalls++;
    return file;
  }
}

final class _FakeBackgroundRemover implements ProductBackgroundRemover {
  _FakeBackgroundRemover(this.output);

  final XFile output;
  int calls = 0;
  String? lastOutputPath;
  final List<String> deletedPaths = [];

  @override
  Future<XFile> removeBackground(XFile source) async {
    calls++;
    lastOutputPath = output.path;
    return output;
  }

  @override
  Future<void> deleteTemporary(XFile output) {
    deletedPaths.add(output.path);
    final file = File(output.path);
    if (file.existsSync()) file.deleteSync();
    return Future<void>.value();
  }
}

const _onePixelPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';

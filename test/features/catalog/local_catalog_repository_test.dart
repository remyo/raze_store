import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/core/database/app_database.dart';
import 'package:raze_store/core/storage/local_product_image_store.dart';
import 'package:raze_store/features/catalog/data/local_catalog_repository.dart';
import 'package:raze_store/features/catalog/domain/catalog_product.dart';
import 'package:raze_store/features/catalog/domain/catalog_repository.dart';

void main() {
  late AppDatabase database;
  late LocalCatalogRepository repository;
  final now = DateTime.utc(2026, 9, 2, 10, 30);

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = LocalCatalogRepository(database, now: () => now);
  });

  tearDown(() => database.close());

  test(
    'creates and finds a scanned product using either UPC representation',
    () async {
      final created = await repository.createProduct(
        ProductDraft(
          id: 'coffee',
          barcode: '012345678905',
          name: 'Kape 3-in-1',
          brand: 'Sample Brand',
          unitLabel: '20 g sachet',
          priceCentavos: 800,
        ),
      );

      expect(created.barcode, '0012345678905');
      expect((await repository.findByBarcode('012345678905'))?.id, 'coffee');
      expect((await repository.findByBarcode('0012345678905'))?.id, 'coffee');
    },
  );

  test('supports loose products with no barcode', () async {
    final created = await repository.createProduct(
      ProductDraft(
        id: 'egg',
        name: 'Itlog',
        category: 'Loose goods',
        priceCentavos: 900,
      ),
    );

    expect(created.barcode, isNull);
    expect((await repository.searchProducts('itlog')).single.id, 'egg');
    expect(await repository.findByBarcode(''), isNull);
  });

  test(
    'creates, orders, and updates sub-selling units under one barcode',
    () async {
      final created = await repository.createProduct(
        ProductDraft(
          id: 'cigarettes',
          barcode: '4801234567890',
          name: 'Cigarettes',
          unitLabel: 'Pack',
          priceCentavos: 16000,
          sellingUnits: [
            SellingUnitDraft(id: 'stick', label: 'Stick', priceCentavos: 1000),
            SellingUnitDraft(
              id: 'half-pack',
              label: 'Half pack',
              priceCentavos: 8500,
            ),
          ],
        ),
      );

      expect(created.saleOptions.map((option) => option.label), [
        'Pack',
        'Stick',
        'Half pack',
      ]);
      expect(created.sellingUnits.first.priceCentavos, 1000);
      expect(
        (await repository.findByBarcode('4801234567890'))!.sellingUnits,
        hasLength(2),
      );

      final updated = await repository.updateProduct(
        created.id,
        ProductDraft.fromProduct(created).copyWithSellingUnits([
          SellingUnitDraft.fromUnit(created.sellingUnits.first),
        ]),
      );

      expect(updated.sellingUnits, hasLength(1));
      expect(updated.sellingUnits.single.id, 'stick');
    },
  );

  test('searches metadata and publishes CRUD changes', () async {
    await repository.createProduct(
      ProductDraft(
        id: 'soda',
        barcode: '4801234567890',
        name: 'Cola',
        brand: 'Pinoy Refreshments',
        priceCentavos: 1500,
      ),
    );

    expect((await repository.searchProducts('refresh')).single.id, 'soda');
    await repository.updateProduct(
      'soda',
      ProductDraft(
        barcode: '4801234567890',
        name: 'Cola Mismo',
        priceCentavos: 1700,
      ),
    );
    expect((await repository.getProduct('soda'))?.priceCentavos, 1700);

    await repository.deleteProduct('soda');
    expect(await repository.getProduct('soda'), isNull);
  });

  test('rejects duplicate canonical barcodes', () async {
    await repository.createProduct(
      ProductDraft(
        id: 'first',
        barcode: '012345678905',
        name: 'First',
        priceCentavos: 100,
      ),
    );

    expect(
      () => repository.createProduct(
        ProductDraft(
          id: 'second',
          barcode: '0012345678905',
          name: 'Second',
          priceCentavos: 200,
        ),
      ),
      throwsA(isA<DuplicateBarcodeException>()),
    );
  });

  test('finds and rejects duplicate shared API identities', () async {
    await repository.createProduct(
      ProductDraft(
        id: 'first',
        barcode: '4800012345678',
        name: 'API product',
        source: 'raze_store_api',
        sourceProductId: 'remote-id',
        priceCentavos: 100,
      ),
    );

    expect(
      (await repository.findBySource('raze_store_api', 'remote-id'))?.id,
      'first',
    );
    expect(
      () => repository.createProduct(
        ProductDraft(
          id: 'second',
          barcode: 'ALIAS+BLUE',
          name: 'Same API product',
          source: 'raze_store_api',
          sourceProductId: 'remote-id',
          priceCentavos: 200,
        ),
      ),
      throwsA(isA<DuplicateCatalogProductException>()),
    );
  });

  test('repairs a relocated managed product photo path on read', () async {
    const fileName = '123e4567-e89b-12d3-a456-426614174000.jpg';
    final root = await Directory.systemTemp.createTemp('raze_store_photos_');
    addTearDown(() => root.delete(recursive: true));
    final managed = Directory('${root.path}/product_images');
    await managed.create(recursive: true);
    final relocatedPath = '${managed.path}/$fileName';
    await File(relocatedPath).writeAsBytes([1, 2, 3]);
    const stalePath = '/old/ios/container/product_images/$fileName';

    await repository.createProduct(
      ProductDraft(
        id: 'with-photo',
        name: 'Photo item',
        localImagePath: stalePath,
        priceCentavos: 100,
      ),
    );
    final repairingRepository = LocalCatalogRepository(
      database,
      imageStore: LocalProductImageStore(root: root),
    );

    expect(
      (await repairingRepository.getProduct('with-photo'))?.localImagePath,
      relocatedPath,
    );
    expect(
      (await LocalCatalogRepository(
        database,
      ).getProduct('with-photo'))?.localImagePath,
      relocatedPath,
    );
  });
}

extension on ProductDraft {
  ProductDraft copyWithSellingUnits(List<SellingUnitDraft> units) =>
      ProductDraft(
        id: id,
        barcode: barcode,
        name: name,
        brand: brand,
        unitLabel: unitLabel,
        category: category,
        remoteImageUrl: remoteImageUrl,
        source: source,
        sourceProductId: sourceProductId,
        localImagePath: localImagePath,
        priceCentavos: priceCentavos,
        sellingUnits: units,
      );
}

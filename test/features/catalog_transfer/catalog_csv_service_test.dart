import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/core/database/app_database.dart';
import 'package:raze_store/features/catalog/data/local_catalog_repository.dart';
import 'package:raze_store/features/catalog/domain/catalog_product.dart';
import 'package:raze_store/features/catalog_transfer/data/catalog_csv_service.dart';
import 'package:raze_store/features/catalog_transfer/data/csv_table_codec.dart';
import 'package:raze_store/features/catalog_transfer/domain/catalog_transfer_result.dart';

void main() {
  late Directory testRoot;
  late AppDatabase sourceDatabase;
  late AppDatabase targetDatabase;

  setUp(() async {
    testRoot = await Directory.systemTemp.createTemp('raze_store_csv_test_');
    sourceDatabase = AppDatabase.forTesting(NativeDatabase.memory());
    targetDatabase = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await sourceDatabase.close();
    await targetDatabase.close();
    if (await testRoot.exists()) await testRoot.delete(recursive: true);
  });

  test(
    'CSV merges by barcode, preserves local photo, units, and other products',
    () async {
      final sourceCatalog = LocalCatalogRepository(sourceDatabase);
      await sourceCatalog.createProduct(
        ProductDraft(
          id: 'source-coffee',
          barcode: '4800012345678',
          name: 'Updated Coffee',
          brand: 'Kape Brand',
          unitLabel: 'Pack',
          category: 'Coffee & Beverages',
          priceCentavos: 7500,
          sellingUnits: [
            SellingUnitDraft(
              id: 'stick-price',
              label: 'Stick',
              priceCentavos: 850,
            ),
          ],
        ),
      );
      final document = await CatalogCsvService(sourceDatabase).buildDocument();
      final csvFile = File('${testRoot.path}/products.csv');
      await csvFile.writeAsString(document.contents);

      final targetCatalog = LocalCatalogRepository(targetDatabase);
      await targetCatalog.createProduct(
        ProductDraft(
          id: 'target-coffee',
          barcode: '4800012345678',
          name: 'Old Coffee',
          localImagePath: '/managed/photo.jpg',
          priceCentavos: 5000,
        ),
      );
      await targetCatalog.createProduct(
        ProductDraft(
          id: 'keep-me',
          name: 'Unrelated Product',
          priceCentavos: 1000,
        ),
      );

      final result = await CatalogCsvService(
        targetDatabase,
      ).importMerging(sourcePath: csvFile.path);

      expect(result, isA<CatalogTransferSuccess>());
      final products = await targetCatalog.searchProducts('');
      expect(products, hasLength(2));
      final coffee = await targetCatalog.findByBarcode('4800012345678');
      expect(coffee, isNotNull);
      expect(coffee!.id, 'target-coffee');
      expect(coffee.name, 'Updated Coffee');
      expect(coffee.localImagePath, '/managed/photo.jpg');
      expect(coffee.priceCentavos, 7500);
      expect(coffee.sellingUnits.single.label, 'Stick');
      expect(coffee.sellingUnits.single.priceCentavos, 850);
      expect(products.any((product) => product.id == 'keep-me'), isTrue);
    },
  );

  test('CSV merges the same API product saved under another barcode', () async {
    const source = 'raze_store_api';
    const sourceProductId = 'f71ea24a-41f2-422f-9aeb-24efa48e7a5d';
    await LocalCatalogRepository(sourceDatabase).createProduct(
      ProductDraft(
        id: 'device-a-id',
        barcode: 'ALIAS+BLUE',
        name: 'Updated API product',
        source: source,
        sourceProductId: sourceProductId,
        priceCentavos: 1400,
      ),
    );
    final document = await CatalogCsvService(sourceDatabase).buildDocument();
    final csvFile = File('${testRoot.path}/api-product.csv');
    await csvFile.writeAsString(document.contents);

    final targetCatalog = LocalCatalogRepository(targetDatabase);
    await targetCatalog.createProduct(
      ProductDraft(
        id: 'device-b-id',
        barcode: '4800012345678',
        name: 'Old API product',
        source: source,
        sourceProductId: sourceProductId,
        priceCentavos: 1200,
      ),
    );

    final result = await CatalogCsvService(
      targetDatabase,
    ).importMerging(sourcePath: csvFile.path);

    expect(result, isA<CatalogTransferSuccess>());
    final products = await targetCatalog.searchProducts('');
    expect(products, hasLength(1));
    expect(products.single.id, 'device-b-id');
    expect(products.single.barcode, 'ALIAS+BLUE');
    expect(products.single.name, 'Updated API product');
  });

  test('invalid CSV changes nothing', () async {
    final catalog = LocalCatalogRepository(targetDatabase);
    await catalog.createProduct(
      ProductDraft(id: 'safe', name: 'Keep This', priceCentavos: 1200),
    );
    const codec = CsvTableCodec();
    final file = File('${testRoot.path}/invalid.csv');
    await file.writeAsString(
      codec.encode([
        CatalogCsvService.headers,
        [
          '1',
          'new-id',
          '',
          'Broken Price',
          '',
          'Snacks',
          'Piece',
          '12.345',
          '[]',
          '',
          '',
          '',
        ],
      ]),
    );

    final result = await CatalogCsvService(
      targetDatabase,
    ).importMerging(sourcePath: file.path);

    expect(result, isA<CatalogTransferFailure>());
    final products = await catalog.searchProducts('');
    expect(products, hasLength(1));
    expect(products.single.name, 'Keep This');
  });

  test(
    'export neutralizes spreadsheet formulas and preserves them on import',
    () async {
      await LocalCatalogRepository(sourceDatabase).createProduct(
        ProductDraft(
          id: 'formula-product',
          barcode: '012345678905',
          name: '=SUM(1,1)',
          priceCentavos: 500,
        ),
      );

      final document = await CatalogCsvService(sourceDatabase).buildDocument();
      expect(document.contents, contains("'=SUM(1,1)"));
      expect(document.contents, contains("'0012345678905"));
      final file = File('${testRoot.path}/safe.csv');
      await file.writeAsString(document.contents);

      final result = await CatalogCsvService(
        targetDatabase,
      ).importMerging(sourcePath: file.path);

      expect(result, isA<CatalogTransferSuccess>());
      final imported = (await LocalCatalogRepository(
        targetDatabase,
      ).searchProducts('')).single;
      expect(imported.name, '=SUM(1,1)');
      expect(imported.barcode, '0012345678905');
    },
  );

  test('zero prices survive CSV export and import', () async {
    await LocalCatalogRepository(sourceDatabase).createProduct(
      ProductDraft(
        id: 'free-item',
        barcode: '4801234567890',
        name: 'Free item',
        priceCentavos: 0,
        sellingUnits: [SellingUnitDraft(label: 'Piece', priceCentavos: 0)],
      ),
    );
    final document = await CatalogCsvService(sourceDatabase).buildDocument();
    final file = File('${testRoot.path}/zero.csv');
    await file.writeAsString(document.contents);

    final result = await CatalogCsvService(
      targetDatabase,
    ).importMerging(sourcePath: file.path);

    expect(result, isA<CatalogTransferSuccess>());
    final product = (await LocalCatalogRepository(
      targetDatabase,
    ).searchProducts('')).single;
    expect(product.priceCentavos, 0);
    expect(product.sellingUnits.single.priceCentavos, 0);
  });

  test('identifier text survives spreadsheet-safe CSV round trips', () async {
    await LocalCatalogRepository(sourceDatabase).createProduct(
      ProductDraft(
        id: '00012345678901234567890',
        barcode: '012345678905',
        name: 'Identifier item',
        source: 'manual-import',
        sourceProductId: "'00098765432109876543210",
        priceCentavos: 100,
      ),
    );

    final document = await CatalogCsvService(sourceDatabase).buildDocument();
    expect(document.contents, contains("'00012345678901234567890"));
    expect(document.contents, contains("''00098765432109876543210"));
    final file = File('${testRoot.path}/identifiers.csv');
    await file.writeAsString(document.contents);

    final result = await CatalogCsvService(
      targetDatabase,
    ).importMerging(sourcePath: file.path);

    expect(result, isA<CatalogTransferSuccess>());
    final imported = (await LocalCatalogRepository(
      targetDatabase,
    ).searchProducts('')).single;
    expect(imported.id, '00012345678901234567890');
    expect(imported.metadata.sourceProductId, "'00098765432109876543210");
  });

  test('rejects more than 100 sub-unit prices in one CSV row', () async {
    const codec = CsvTableCodec();
    final file = File('${testRoot.path}/too-many-units.csv');
    await file.writeAsString(
      codec.encode([
        CatalogCsvService.headers,
        [
          '1',
          'many-units',
          '',
          'Many units',
          '',
          '',
          'Pack',
          '10.00',
          '[${List.generate(101, (index) => '{"label":"Unit $index","pricePhp":"1.00"}').join(',')}]',
          '',
          '',
          '',
        ],
      ]),
    );

    final result = await CatalogCsvService(
      targetDatabase,
    ).importMerging(sourcePath: file.path);

    expect(result, isA<CatalogTransferFailure>());
    expect(
      await LocalCatalogRepository(targetDatabase).searchProducts(''),
      isEmpty,
    );
  });

  test('rejects a sub-unit label matching the fallback main label', () async {
    const codec = CsvTableCodec();
    final file = File('${testRoot.path}/duplicate-main-label.csv');
    await file.writeAsString(
      codec.encode([
        CatalogCsvService.headers,
        [
          '1',
          'duplicate-label',
          '',
          'Duplicate label',
          '',
          '',
          '',
          '10.00',
          '[{"label":"Main item","pricePhp":"1.00"}]',
          '',
          '',
          '',
        ],
      ]),
    );

    final result = await CatalogCsvService(
      targetDatabase,
    ).importMerging(sourcePath: file.path);

    expect(result, isA<CatalogTransferFailure>());
  });
}

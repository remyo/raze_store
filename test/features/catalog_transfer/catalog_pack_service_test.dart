import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/core/database/app_database.dart' show AppDatabase;
import 'package:raze_store/core/storage/local_product_image_store.dart';
import 'package:raze_store/features/cart/data/local_cart_repository.dart';
import 'package:raze_store/features/catalog/data/local_catalog_repository.dart';
import 'package:raze_store/features/catalog/domain/catalog_product.dart';
import 'package:raze_store/features/catalog_transfer/data/catalog_pack_service.dart';
import 'package:raze_store/features/catalog_transfer/domain/catalog_pack_review.dart';
import 'package:raze_store/features/catalog_transfer/domain/catalog_transfer_result.dart';
import 'package:raze_store/features/settings/data/local_settings_repository.dart';
import 'package:raze_store/features/settings/domain/store_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory testRoot;
  late AppDatabase database;
  late LocalProductImageStore imageStore;
  late CatalogPackService service;
  var packNumber = 0;

  setUp(() async {
    testRoot = await Directory.systemTemp.createTemp('raze_store_pack_test_');
    database = AppDatabase.forTesting(NativeDatabase.memory());
    imageStore = LocalProductImageStore(
      root: Directory('${testRoot.path}/managed'),
    );
    service = CatalogPackService(database: database, imageStore: imageStore);
  });

  tearDown(() async {
    await database.close();
    if (await testRoot.exists()) await testRoot.delete(recursive: true);
  });

  test(
    'imports a new product, image, and optional attribution metadata',
    () async {
      final sourceUpdatedAt = DateTime.utc(2026, 9, 3, 4, 5, 6);
      final pack = await _writePack(
        testRoot,
        number: packNumber++,
        products: [
          _product(
            id: 'coffee-001',
            barcode: '4800012345678',
            name: 'Filipino Coffee',
            updatedAt: sourceUpdatedAt,
            priceCentavos: 1299,
            image: 'images/coffee-001.png',
          )..addAll({
            'sourceUrl': 'https://example.test/products/coffee-001',
            'imageSourceUrl': 'https://example.test/images/coffee-001',
            'imageLicense': 'CC-BY-SA-4.0',
          }),
        ],
        images: {'images/coffee-001.png': _pngBytes(1)},
        includeAttribution: true,
      );

      final result = await service.importMerging(pack.path);

      expect(result.success, isTrue);
      expect(result.productCount, 1);
      expect(result.createdCount, 1);
      expect(result.updatedCount, 0);
      expect(result.imageCount, 1);
      final imported = (await LocalCatalogRepository(
        database,
        imageStore: imageStore,
      ).searchProducts('')).single;
      expect(imported.name, 'Filipino Coffee');
      expect(imported.barcode, '4800012345678');
      expect(imported.priceCentavos, 1299);
      expect(imported.metadata.source, 'raze_store_api');
      expect(imported.metadata.sourceProductId, 'coffee-001');
      expect(imported.sourceUpdatedAt, sourceUpdatedAt);
      expect(imported.localImagePath, isNull);
      expect(imported.catalogImagePath, isNotNull);
      expect(
        await File(imported.catalogImagePath!).readAsBytes(),
        _pngBytes(1),
      );
    },
  );

  test('checked-in starter pack imports 208 positive-price products', () async {
    final pack = File('outputs/filipino-sari-sari-starter-v1.razepack');

    final result = await service.importMerging(pack.path);

    expect(result.success, isTrue);
    expect(result.productCount, 208);
    expect(result.createdCount, 208);
    expect(result.updatedCount, 0);
    expect(result.imageCount, 20);
    final imported = await LocalCatalogRepository(
      database,
      imageStore: imageStore,
    ).searchProducts('');
    expect(imported, hasLength(208));
    expect(
      imported,
      everyElement(predicate<StoreProduct>((p) => p.priceCentavos > 0)),
    );
    expect(
      imported.map((product) => product.category).toSet(),
      containsAll(<String?>{
        'Beverages',
        'Bread',
        'Canned Goods',
        'Condiments',
        'Household',
      }),
    );
  });

  test(
    'matched product preserves owner fields, prices, units, photo, cart, and profile',
    () async {
      final localPhotoSource = File('${testRoot.path}/owner.png');
      await localPhotoSource.writeAsBytes(_pngBytes(8));
      final localPhoto = await imageStore.persistFile(localPhotoSource);
      final catalog = LocalCatalogRepository(database, imageStore: imageStore);
      final original = await catalog.createProduct(
        ProductDraft(
          id: 'owner-product',
          barcode: '4800012345678',
          name: 'Owner Name',
          brand: 'Owner Brand',
          category: 'Owner Category',
          unitLabel: 'Owner Pack',
          remoteImageUrl: 'https://owner.test/image.png',
          localImagePath: localPhoto,
          priceCentavos: 4321,
          sellingUnits: [
            SellingUnitDraft(
              id: 'owner-piece',
              label: 'Owner Piece',
              priceCentavos: 321,
            ),
          ],
        ),
      );
      await LocalCartRepository(database).addProduct(original);
      await LocalSettingsRepository(database).saveStoreProfile(
        const StoreProfile(
          storeName: 'Owner Store',
          address: 'Quezon City',
          contact: '09170000000',
          receiptFooter: 'Owner footer',
        ),
      );
      final originalUpdatedAt = original.updatedAt;
      final packUpdatedAt = DateTime.utc(2026, 9, 3);
      final pack = await _writePack(
        testRoot,
        number: packNumber++,
        products: [
          _product(
            id: 'shared-coffee',
            barcode: original.barcode,
            name: 'Pack Name',
            updatedAt: packUpdatedAt,
            priceCentavos: 9999,
            image: 'images/shared-coffee.png',
          )..addAll({
            'brand': 'Pack Brand',
            'category': 'Pack Category',
            'unitLabel': 'Pack Unit',
            'remoteImageUrl': 'https://pack.test/image.png',
          }),
        ],
        images: {'images/shared-coffee.png': _pngBytes(2)},
      );

      final result = await service.importMerging(pack.path);

      expect(result.success, isTrue);
      expect(result.createdCount, 0);
      expect(result.updatedCount, 1);
      final preserved = (await catalog.searchProducts('')).single;
      expect(preserved.id, original.id);
      expect(preserved.name, 'Owner Name');
      expect(preserved.brand, 'Owner Brand');
      expect(preserved.category, 'Owner Category');
      expect(preserved.unitLabel, 'Owner Pack');
      expect(preserved.barcode, '4800012345678');
      expect(preserved.remoteImageUrl, 'https://owner.test/image.png');
      expect(preserved.priceCentavos, 4321);
      expect(preserved.localImagePath, localPhoto);
      expect(preserved.sellingUnits.single.id, 'owner-piece');
      expect(preserved.sellingUnits.single.label, 'Owner Piece');
      expect(preserved.sellingUnits.single.priceCentavos, 321);
      expect(preserved.updatedAt, originalUpdatedAt);
      expect(preserved.metadata.source, 'raze_store_api');
      expect(preserved.metadata.sourceProductId, 'shared-coffee');
      expect(preserved.sourceUpdatedAt, packUpdatedAt);
      expect(
        await File(preserved.catalogImagePath!).readAsBytes(),
        _pngBytes(2),
      );
      final cart = await LocalCartRepository(database).getDraft();
      expect(cart.items.single.name, 'Owner Name');
      expect(cart.items.single.unitPriceCentavos, 4321);
      final profile = await LocalSettingsRepository(database).getStoreProfile();
      expect(profile.storeName, 'Owner Store');
      expect(profile.receiptFooter, 'Owner footer');
    },
  );

  test(
    'overwrite mode updates catalog fields while preserving a confirmed price',
    () async {
      final ownerPhotoSource = File('${testRoot.path}/owner-overwrite.png');
      await ownerPhotoSource.writeAsBytes(_pngBytes(10));
      final ownerPhoto = await imageStore.persistFile(ownerPhotoSource);
      final oldCatalogSource = File('${testRoot.path}/old-catalog.png');
      await oldCatalogSource.writeAsBytes(_pngBytes(11));
      final oldCatalogImage = await imageStore.persistFile(oldCatalogSource);
      final catalog = LocalCatalogRepository(database, imageStore: imageStore);
      final original = await catalog.createProduct(
        ProductDraft(
          id: 'matching-local-id',
          barcode: '111',
          source: 'raze_store_api',
          sourceProductId: 'matching-shared-id',
          sourceUpdatedAt: DateTime.utc(2025),
          name: 'Owner Name',
          brand: 'Owner Brand',
          category: 'Owner Category',
          unitLabel: 'Owner Unit',
          remoteImageUrl: 'https://owner.test/product.png',
          localImagePath: ownerPhoto,
          catalogImagePath: oldCatalogImage,
          priceCentavos: 4321,
          sellingUnits: [
            SellingUnitDraft(
              id: 'owner-piece',
              label: 'Owner Piece',
              priceCentavos: 321,
            ),
          ],
        ),
      );
      await LocalCartRepository(database).addProduct(original);
      await LocalSettingsRepository(
        database,
      ).saveStoreProfile(const StoreProfile(storeName: 'Owner Store'));
      await catalog.createProduct(
        ProductDraft(
          id: 'not-in-pack',
          barcode: '999',
          name: 'Keep Me',
          priceCentavos: 700,
        ),
      );
      final packUpdatedAt = DateTime.utc(2026, 9, 3);
      final pack = await _writePack(
        testRoot,
        number: packNumber++,
        products: [
          _product(
            id: 'matching-shared-id',
            barcode: '222',
            name: 'Updated Pack Name',
            updatedAt: packUpdatedAt,
            priceCentavos: 9999,
            image: 'images/matching.png',
          ),
          _product(
            id: 'new-shared-id',
            barcode: '333',
            name: 'New From Pack',
            updatedAt: packUpdatedAt,
            priceCentavos: 1250,
          ),
        ],
        images: {'images/matching.png': _pngBytes(12)},
      );

      final result = await service.importMerging(
        pack.path,
        mode: CatalogPackImportMode.overwriteMatching,
      );

      expect(result.success, isTrue);
      expect(result.createdCount, 1);
      expect(result.updatedCount, 1);
      expect(result.imageCount, 1);
      expect(result.message, contains('updated 1 existing products'));
      final products = await catalog.searchProducts('');
      expect(products, hasLength(3));
      final updated = products.singleWhere(
        (product) => product.id == original.id,
      );
      expect(updated.barcode, '222');
      expect(updated.name, 'Updated Pack Name');
      expect(updated.brand, 'Pack Brand');
      expect(updated.category, 'Pack Category');
      expect(updated.unitLabel, 'Pack');
      expect(updated.remoteImageUrl, contains('matching-shared-id.png'));
      expect(updated.priceCentavos, 4321);
      expect(updated.sourceUpdatedAt, packUpdatedAt);
      expect(updated.localImagePath, ownerPhoto);
      expect(updated.sellingUnits.single.id, 'owner-piece');
      expect(updated.sellingUnits.single.priceCentavos, 321);
      expect(
        await File(updated.catalogImagePath!).readAsBytes(),
        _pngBytes(12),
      );
      expect(await File(oldCatalogImage).exists(), isFalse);
      expect(
        products.singleWhere((product) => product.id == 'not-in-pack').name,
        'Keep Me',
      );
      expect(
        products.singleWhere((product) => product.barcode == '333').name,
        'New From Pack',
      );
      expect(
        products
            .singleWhere((product) => product.barcode == '333')
            .priceCentavos,
        1250,
      );
      final cart = await LocalCartRepository(database).getDraft();
      expect(cart.items.single.name, 'Owner Name');
      expect(cart.items.single.unitPriceCentavos, 4321);
      expect(
        (await LocalSettingsRepository(database).getStoreProfile()).storeName,
        'Owner Store',
      );
    },
  );

  for (final mode in CatalogPackImportMode.values) {
    test(
      '${mode.name} fills an existing zero price from the pack SRP',
      () async {
        final catalog = LocalCatalogRepository(
          database,
          imageStore: imageStore,
        );
        final original = await catalog.createProduct(
          ProductDraft(
            id: 'zero-price-product',
            barcode: '111',
            source: 'raze_store_api',
            sourceProductId: 'zero-price-shared-id',
            sourceUpdatedAt: DateTime.utc(2025),
            name: 'Local Product',
            priceCentavos: 0,
          ),
        );
        final pack = await _writePack(
          testRoot,
          number: packNumber++,
          products: [
            _product(
              id: 'zero-price-shared-id',
              barcode: '111',
              name: 'Pack Product',
              updatedAt: DateTime.utc(2026),
              priceCentavos: 1599,
            ),
          ],
        );

        final result = await service.importMerging(pack.path, mode: mode);

        expect(result.success, isTrue);
        expect(result.createdCount, 0);
        expect(result.updatedCount, 1);
        final updated = (await catalog.searchProducts('')).single;
        expect(updated.id, original.id);
        expect(updated.priceCentavos, 1599);
        expect(
          updated.name,
          mode == CatalogPackImportMode.keepExisting
              ? 'Local Product'
              : 'Pack Product',
        );
      },
    );
  }

  test(
    'overwrite mode keeps the current price when the pack has no SRP',
    () async {
      final catalog = LocalCatalogRepository(database, imageStore: imageStore);
      await catalog.createProduct(
        ProductDraft(
          id: 'priced-product',
          barcode: '111',
          name: 'Priced Product',
          priceCentavos: 4321,
        ),
      );
      final productWithoutPrice = _product(
        id: 'priced-product-pack',
        barcode: '111',
        name: 'Updated Name',
        updatedAt: DateTime.utc(2026),
        priceCentavos: null,
      )..remove('suggestedPriceCentavos');
      final pack = await _writePack(
        testRoot,
        number: packNumber++,
        products: [productWithoutPrice],
      );

      final result = await service.importMerging(
        pack.path,
        mode: CatalogPackImportMode.overwriteMatching,
      );

      expect(result.success, isTrue);
      final updated = (await catalog.searchProducts('')).single;
      expect(updated.name, 'Updated Name');
      expect(updated.priceCentavos, 4321);
    },
  );

  test(
    'newer pack leaves an existing linked product and image unchanged',
    () async {
      final firstPack = await _writePack(
        testRoot,
        number: packNumber++,
        products: [
          _product(
            id: 'stable-product',
            barcode: '4800012345678',
            name: 'First Name',
            updatedAt: DateTime.utc(2026, 1, 1),
            priceCentavos: 1000,
            image: 'images/stable-product.png',
          ),
        ],
        images: {'images/stable-product.png': _pngBytes(3)},
      );
      expect((await service.importMerging(firstPack.path)).success, isTrue);
      final catalog = LocalCatalogRepository(database, imageStore: imageStore);
      final before = (await catalog.searchProducts('')).single;
      final beforeImage = before.catalogImagePath!;

      final newerPack = await _writePack(
        testRoot,
        number: packNumber++,
        revision: 2,
        products: [
          _product(
            id: 'stable-product',
            barcode: 'DIFFERENT-ALIAS',
            name: 'New Pack Name',
            updatedAt: DateTime.utc(2027, 1, 1),
            priceCentavos: 9000,
            image: 'images/stable-product.png',
          ),
        ],
        images: {'images/stable-product.png': _pngBytes(4)},
      );

      final result = await service.importMerging(newerPack.path);

      expect(result.success, isTrue);
      expect(result.createdCount, 0);
      expect(result.updatedCount, 0);
      expect(result.imageCount, 0);
      final after = (await catalog.searchProducts('')).single;
      expect(after.name, 'First Name');
      expect(after.barcode, '4800012345678');
      expect(after.priceCentavos, 1000);
      expect(after.catalogImagePath, beforeImage);
      expect(after.sourceUpdatedAt, DateTime.utc(2026, 1, 1));
      expect(await File(beforeImage).readAsBytes(), _pngBytes(3));
    },
  );

  test(
    'reimport repairs a missing catalog image without rolling time back',
    () async {
      final firstTimestamp = DateTime.utc(2026, 6, 1);
      final firstPack = await _writePack(
        testRoot,
        number: packNumber++,
        products: [
          _product(
            id: 'repair-product',
            barcode: '4800012345678',
            name: 'Repair Product',
            updatedAt: firstTimestamp,
            priceCentavos: 1000,
            image: 'images/repair-product.png',
          ),
        ],
        images: {'images/repair-product.png': _pngBytes(5)},
      );
      expect((await service.importMerging(firstPack.path)).success, isTrue);
      final catalog = LocalCatalogRepository(database, imageStore: imageStore);
      final before = (await catalog.searchProducts('')).single;
      await File(before.catalogImagePath!).delete();

      final olderPack = await _writePack(
        testRoot,
        number: packNumber++,
        products: [
          _product(
            id: 'repair-product',
            barcode: '4800012345678',
            name: 'Ignored Older Name',
            updatedAt: DateTime.utc(2025, 1, 1),
            priceCentavos: 9999,
            image: 'images/repair-product.png',
          ),
        ],
        images: {'images/repair-product.png': _pngBytes(6)},
      );

      final result = await service.importMerging(olderPack.path);

      expect(result.success, isTrue);
      expect(result.updatedCount, 1);
      expect(result.imageCount, 1);
      final repaired = (await catalog.searchProducts('')).single;
      expect(repaired.name, 'Repair Product');
      expect(repaired.priceCentavos, 1000);
      expect(repaired.sourceUpdatedAt, firstTimestamp);
      expect(
        await File(repaired.catalogImagePath!).readAsBytes(),
        _pngBytes(6),
      );
    },
  );

  test('source and barcode split conflict changes nothing', () async {
    final catalog = LocalCatalogRepository(database);
    await catalog.createProduct(
      ProductDraft(
        id: 'source-owner',
        barcode: '111',
        name: 'Source Owner',
        source: 'raze_store_api',
        sourceProductId: 'conflicted',
        priceCentavos: 100,
      ),
    );
    await catalog.createProduct(
      ProductDraft(
        id: 'barcode-owner',
        barcode: '222',
        name: 'Barcode Owner',
        priceCentavos: 200,
      ),
    );
    final pack = await _writePack(
      testRoot,
      number: packNumber++,
      products: [
        _product(
          id: 'conflicted',
          barcode: '222',
          name: 'Conflict',
          updatedAt: DateTime.utc(2026),
          priceCentavos: 300,
          image: 'images/conflicted.png',
        ),
      ],
      images: {'images/conflicted.png': _pngBytes(7)},
    );

    final result = await service.importMerging(pack.path);

    expect(result.success, isFalse);
    expect(result.failureCode, CatalogImportFailureCode.validationFailed);
    final products = await catalog.searchProducts('');
    expect(products, hasLength(2));
    expect(
      products.singleWhere((item) => item.id == 'source-owner').priceCentavos,
      100,
    );
    expect(
      products
          .singleWhere((item) => item.id == 'barcode-owner')
          .metadata
          .source,
      isNull,
    );
    expect(await (await imageStore.managedDirectory()).list().isEmpty, isTrue);
  });

  test('checksum mismatch is rejected before database changes', () async {
    final pack = await _writePack(
      testRoot,
      number: packNumber++,
      products: [
        _product(
          id: 'bad-checksum',
          barcode: '4800012345678',
          name: 'Bad Checksum',
          updatedAt: DateTime.utc(2026),
          priceCentavos: 100,
        ),
      ],
      catalogChecksumOverride: List.filled(64, '0').join(),
    );

    final result = await service.importMerging(pack.path);

    expect(result.success, isFalse);
    expect(result.failureCode, CatalogImportFailureCode.integrityMismatch);
    expect(await LocalCatalogRepository(database).searchProducts(''), isEmpty);
  });

  test(
    'path traversal entry is rejected without writing outside staging',
    () async {
      final pack = await _writePack(
        testRoot,
        number: packNumber++,
        products: const [],
        unexpectedEntries: {'../escaped.txt': utf8.encode('unsafe')},
      );

      final result = await service.importMerging(pack.path);

      expect(result.success, isFalse);
      expect(result.failureCode, CatalogImportFailureCode.unsafeArchive);
      expect(await File('${testRoot.path}/escaped.txt').exists(), isFalse);
      expect(
        await LocalCatalogRepository(database).searchProducts(''),
        isEmpty,
      );
    },
  );

  test('an undescribed archive entry is rejected', () async {
    final pack = await _writePack(
      testRoot,
      number: packNumber++,
      products: const [],
      unexpectedEntries: {'unexpected.txt': utf8.encode('not described')},
    );

    final result = await service.importMerging(pack.path);

    expect(result.success, isFalse);
    expect(result.failureCode, CatalogImportFailureCode.invalidFile);
    expect(await LocalCatalogRepository(database).searchProducts(''), isEmpty);
  });

  test('case-conflicting archive entry names are rejected', () async {
    final pack = await _writePack(
      testRoot,
      number: packNumber++,
      products: const [],
      unexpectedEntries: {'CATALOG.JSON': utf8.encode('{"products":[]}')},
    );

    final result = await service.importMerging(pack.path);

    expect(result.success, isFalse);
    expect(result.failureCode, CatalogImportFailureCode.invalidFile);
  });

  test('an image whose bytes do not match its extension is rejected', () async {
    final pack = await _writePack(
      testRoot,
      number: packNumber++,
      products: [
        _product(
          id: 'bad-image',
          barcode: '4800012345678',
          name: 'Bad Image',
          updatedAt: DateTime.utc(2026),
          priceCentavos: 100,
          image: 'images/bad-image.png',
        ),
      ],
      images: {'images/bad-image.png': utf8.encode('this is not a PNG image')},
    );

    final result = await service.importMerging(pack.path);

    expect(result.success, isFalse);
    expect(result.failureCode, CatalogImportFailureCode.validationFailed);
    expect(await (await imageStore.managedDirectory()).list().isEmpty, isTrue);
    expect(await LocalCatalogRepository(database).searchProducts(''), isEmpty);
  });

  final oversizedImages = <String, List<int>>{
    'PNG dimension': _pngWithDimensions(width: 5000, height: 1),
    'JPEG pixel count': _jpegWithDimensions(width: 4000, height: 4000),
    'WebP pixel count': _webpWithDimensions(width: 4000, height: 4000),
  };
  for (final fixture in oversizedImages.entries) {
    test('rejects unsafe ${fixture.key}', () async {
      final extension = switch (fixture.key) {
        final value when value.startsWith('PNG') => 'png',
        final value when value.startsWith('JPEG') => 'jpg',
        _ => 'webp',
      };
      final imagePath = 'images/oversized.$extension';
      final pack = await _writePack(
        testRoot,
        number: packNumber++,
        products: [
          _product(
            id: 'oversized-$extension',
            barcode: '4800012345678',
            name: 'Oversized $extension',
            updatedAt: DateTime.utc(2026),
            priceCentavos: 100,
            image: imagePath,
          ),
        ],
        images: {imagePath: fixture.value},
      );

      final result = await service.importMerging(pack.path);

      expect(result.success, isFalse);
      expect(result.failureCode, CatalogImportFailureCode.validationFailed);
      expect(result.message, contains('unsafe dimensions'));
      expect(
        await (await imageStore.managedDirectory()).list().isEmpty,
        isTrue,
      );
      expect(
        await LocalCatalogRepository(database).searchProducts(''),
        isEmpty,
      );
    });
  }

  test('duplicate product barcodes reject the whole pack', () async {
    final pack = await _writePack(
      testRoot,
      number: packNumber++,
      products: [
        _product(
          id: 'duplicate-one',
          barcode: '4800012345678',
          name: 'Duplicate One',
          updatedAt: DateTime.utc(2026),
          priceCentavos: 100,
        ),
        _product(
          id: 'duplicate-two',
          barcode: '4800012345678',
          name: 'Duplicate Two',
          updatedAt: DateTime.utc(2026),
          priceCentavos: 200,
        ),
      ],
    );

    final result = await service.importMerging(pack.path);

    expect(result.success, isFalse);
    expect(result.failureCode, CatalogImportFailureCode.validationFailed);
    expect(await LocalCatalogRepository(database).searchProducts(''), isEmpty);
  });

  test('zero and omitted suggested prices import as zero', () async {
    final omittedPrice = _product(
      id: 'omitted-price',
      barcode: '222',
      name: 'Omitted Price',
      updatedAt: DateTime.utc(2026),
      priceCentavos: null,
    )..remove('suggestedPriceCentavos');
    final pack = await _writePack(
      testRoot,
      number: packNumber++,
      products: [
        _product(
          id: 'zero-price',
          barcode: '111',
          name: 'Zero Price',
          updatedAt: DateTime.utc(2026),
          priceCentavos: 0,
        ),
        omittedPrice,
      ],
    );

    final result = await service.importMerging(pack.path);

    expect(result.success, isTrue);
    expect(result.createdCount, 2);
    final products = await LocalCatalogRepository(database).searchProducts('');
    expect(products, hasLength(2));
    expect(products.every((product) => product.priceCentavos == 0), isTrue);
  });

  test(
    'database failure removes an image persisted before the transaction',
    () async {
      await database.close();
      final failingDatabase = AppDatabase.forTesting(
        NativeDatabase(File('${testRoot.path}/failing.sqlite')),
      );
      addTearDown(() async {
        try {
          await failingDatabase.close();
        } catch (_) {
          // The failure image store intentionally closes it during import.
        }
      });
      final failingRoot = Directory('${testRoot.path}/failing-managed');
      final failingImages = _DatabaseClosingImageStore(
        root: failingRoot,
        database: failingDatabase,
      );
      final failingService = CatalogPackService(
        database: failingDatabase,
        imageStore: failingImages,
      );
      final pack = await _writePack(
        testRoot,
        number: packNumber++,
        products: [
          _product(
            id: 'rollback-image',
            barcode: '4800012345678',
            name: 'Rollback Image',
            updatedAt: DateTime.utc(2026),
            priceCentavos: 100,
            image: 'images/rollback-image.png',
          ),
        ],
        images: {'images/rollback-image.png': _pngBytes(9)},
      );

      final result = await failingService.importMerging(pack.path);

      expect(result.success, isFalse);
      expect(result.failureCode, CatalogImportFailureCode.databaseFailure);
      final managedDirectory = await failingImages.managedDirectory();
      expect(await managedDirectory.list().isEmpty, isTrue);
    },
  );

  test(
    'review classifies products without changing database or images',
    () async {
      final catalog = LocalCatalogRepository(database, imageStore: imageStore);
      await catalog.createProduct(
        ProductDraft(
          id: 'existing-local',
          barcode: '111',
          name: 'Local Product',
          priceCentavos: 500,
        ),
      );
      final pack = await _writePack(
        testRoot,
        number: packNumber++,
        products: [
          _product(
            id: 'existing-shared',
            barcode: '111',
            name: 'Incoming Existing',
            updatedAt: DateTime.utc(2026),
            priceCentavos: 700,
          ),
          _product(
            id: 'new-shared',
            barcode: '222',
            name: 'Incoming New',
            updatedAt: DateTime.utc(2026),
            priceCentavos: 900,
            image: 'images/new.png',
          ),
        ],
        images: {'images/new.png': _pngBytes(31)},
      );

      final prepared = await service.prepareReview(pack.path);

      expect(prepared.success, isTrue);
      expect(prepared.review!.newProducts, hasLength(1));
      expect(prepared.review!.existingProducts, hasLength(1));
      expect(prepared.review!.newProducts.single.incoming.name, 'Incoming New');
      final stagedPreview =
          prepared.review!.newProducts.single.incomingImagePath;
      expect(stagedPreview, isNotNull);
      expect(await File(stagedPreview!).exists(), isTrue);
      expect(
        prepared.review!.existingProducts.single.existing!.name,
        'Local Product',
      );
      expect(await catalog.searchProducts(''), hasLength(1));
      expect(
        await (await imageStore.managedDirectory()).list().isEmpty,
        isTrue,
      );
      expect(await service.getLastImportUndoSummary(), isNull);
      await service.discardReview(prepared.review!.reviewId);
      expect(await File(stagedPreview).exists(), isFalse);
    },
  );

  test('review applies only selected products and selected fields', () async {
    final ownerSource = File('${testRoot.path}/owner-review.png');
    await ownerSource.writeAsBytes(_pngBytes(32));
    final ownerPhoto = await imageStore.persistFile(ownerSource);
    final catalog = LocalCatalogRepository(database, imageStore: imageStore);
    final existing = await catalog.createProduct(
      ProductDraft(
        id: 'existing-local',
        barcode: '111',
        name: 'Owner Name',
        brand: 'Owner Brand',
        category: 'Owner Category',
        unitLabel: 'Owner Pack',
        localImagePath: ownerPhoto,
        priceCentavos: 500,
        sellingUnits: [
          SellingUnitDraft(id: 'piece', label: 'Piece', priceCentavos: 100),
        ],
      ),
    );
    final pack = await _writePack(
      testRoot,
      number: packNumber++,
      products: [
        _product(
          id: 'existing-shared',
          barcode: '111',
          name: 'Troll Name',
          updatedAt: DateTime.utc(2026),
          priceCentavos: 9999,
          image: 'images/existing.png',
        ),
        _product(
          id: 'selected-new',
          barcode: '222',
          name: 'Selected New',
          updatedAt: DateTime.utc(2026),
          priceCentavos: 1200,
        ),
        _product(
          id: 'unchecked-new',
          barcode: '333',
          name: 'Unchecked New',
          updatedAt: DateTime.utc(2026),
          priceCentavos: 1300,
        ),
      ],
      images: {'images/existing.png': _pngBytes(33)},
    );
    final prepared = await service.prepareReview(pack.path);
    final review = prepared.review!;
    final selectedNew = review.newProducts.singleWhere(
      (item) => item.incoming.name == 'Selected New',
    );
    final selectedExisting = review.existingProducts.single;

    final result = await service.applyReview(
      review.reviewId,
      CatalogPackApplySelection(
        selectedProductIds: [selectedNew.targetId, selectedExisting.targetId],
        fields: const {
          CatalogPackImportField.category,
          CatalogPackImportField.suggestedPrice,
          CatalogPackImportField.image,
        },
      ),
    );

    expect(result.success, isTrue);
    final products = await catalog.searchProducts('');
    expect(products, hasLength(2));
    expect(products.where((item) => item.name == 'Unchecked New'), isEmpty);
    final updated = products.singleWhere((item) => item.id == existing.id);
    expect(updated.name, 'Owner Name');
    expect(updated.brand, 'Owner Brand');
    expect(updated.unitLabel, 'Owner Pack');
    expect(updated.category, 'Pack Category');
    expect(updated.priceCentavos, 500);
    expect(updated.localImagePath, ownerPhoto);
    expect(updated.catalogImagePath, isNotNull);
    expect(updated.sellingUnits.single.label, 'Piece');
    final added = products.singleWhere((item) => item.name == 'Selected New');
    expect(added.barcode, isNull);
    expect(added.brand, isNull);
    expect(added.unitLabel, isNull);
    expect(added.category, 'Pack Category');
    expect(added.priceCentavos, 1200);
    expect(await service.getLastImportUndoSummary(), isNotNull);
  });

  test(
    'undo removes imported new rows and exactly restores updated rows',
    () async {
      final catalog = LocalCatalogRepository(database, imageStore: imageStore);
      final existing = await catalog.createProduct(
        ProductDraft(
          id: 'existing-local',
          barcode: '111',
          name: 'Before Import',
          category: 'Before Category',
          priceCentavos: 0,
        ),
      );
      final pack = await _writePack(
        testRoot,
        number: packNumber++,
        products: [
          _product(
            id: 'existing-shared',
            barcode: '111',
            name: 'After Import',
            updatedAt: DateTime.utc(2026),
            priceCentavos: 750,
          ),
          _product(
            id: 'new-shared',
            barcode: '222',
            name: 'Added By Import',
            updatedAt: DateTime.utc(2026),
            priceCentavos: 900,
            image: 'images/new-undo.png',
          ),
        ],
        images: {'images/new-undo.png': _pngBytes(34)},
      );
      final review = (await service.prepareReview(pack.path)).review!;
      final applied = await service.applyReview(
        review.reviewId,
        CatalogPackApplySelection(
          selectedProductIds: review.products.map((item) => item.targetId),
        ),
      );
      expect(applied.success, isTrue);
      expect(await catalog.searchProducts(''), hasLength(2));

      final undone = await service.undoLastImport();

      expect(undone.success, isTrue, reason: undone.message);
      final products = await catalog.searchProducts('');
      expect(products, hasLength(1));
      final restored = products.single;
      expect(restored.id, existing.id);
      expect(restored.name, 'Before Import');
      expect(restored.category, 'Before Category');
      expect(restored.priceCentavos, 0);
      expect(restored.metadata.source, isNull);
      expect(await service.getLastImportUndoSummary(), isNull);
    },
  );

  test('undo refuses to overwrite a product edited after import', () async {
    final catalog = LocalCatalogRepository(database, imageStore: imageStore);
    await catalog.createProduct(
      ProductDraft(
        id: 'existing-local',
        barcode: '111',
        name: 'Before Import',
        priceCentavos: 500,
      ),
    );
    final pack = await _writePack(
      testRoot,
      number: packNumber++,
      products: [
        _product(
          id: 'existing-shared',
          barcode: '111',
          name: 'After Import',
          updatedAt: DateTime.utc(2026),
          priceCentavos: 900,
        ),
      ],
    );
    final review = (await service.prepareReview(pack.path)).review!;
    expect(
      (await service.applyReview(
        review.reviewId,
        CatalogPackApplySelection(
          selectedProductIds: [review.products.single.targetId],
        ),
      )).success,
      isTrue,
    );
    final imported = (await catalog.searchProducts('')).single;
    await catalog.updateProduct(
      imported.id,
      ProductDraft(
        barcode: imported.barcode,
        source: imported.metadata.source,
        sourceProductId: imported.metadata.sourceProductId,
        sourceUpdatedAt: imported.sourceUpdatedAt,
        name: 'Owner Edit After Import',
        brand: imported.brand,
        category: imported.category,
        unitLabel: imported.unitLabel,
        remoteImageUrl: imported.remoteImageUrl,
        localImagePath: imported.localImagePath,
        catalogImagePath: imported.catalogImagePath,
        priceCentavos: imported.priceCentavos,
      ),
    );

    final undo = await service.undoLastImport();

    expect(undo.success, isFalse);
    expect(undo.failureCode, CatalogImportFailureCode.validationFailed);
    expect(
      (await catalog.searchProducts('')).single.name,
      'Owner Edit After Import',
    );
    expect(await service.getLastImportUndoSummary(), isNotNull);
  });

  test(
    'an empty selection changes nothing and discarding expires review',
    () async {
      final pack = await _writePack(
        testRoot,
        number: packNumber++,
        products: [
          _product(
            id: 'new-shared',
            barcode: '111',
            name: 'New Product',
            updatedAt: DateTime.utc(2026),
            priceCentavos: 100,
          ),
        ],
      );
      final review = (await service.prepareReview(pack.path)).review!;

      final empty = await service.applyReview(
        review.reviewId,
        CatalogPackApplySelection(selectedProductIds: const []),
      );
      expect(empty.success, isFalse);
      expect(
        await LocalCatalogRepository(database).searchProducts(''),
        isEmpty,
      );

      await service.discardReview(review.reviewId);
      final expired = await service.applyReview(
        review.reviewId,
        CatalogPackApplySelection(
          selectedProductIds: [review.products.single.targetId],
        ),
      );
      expect(expired.success, isFalse);
      expect(expired.message, contains('expired'));
    },
  );
}

Map<String, Object?> _product({
  required String id,
  required String? barcode,
  required String name,
  required DateTime updatedAt,
  required int? priceCentavos,
  String? image,
}) => <String, Object?>{
  'catalogProductId': id,
  'source': 'raze_store_api',
  'sourceProductId': id,
  'updatedAt': updatedAt.toUtc().toIso8601String(),
  'barcode': barcode,
  'name': name,
  'brand': 'Pack Brand',
  'unitLabel': 'Pack',
  'category': 'Pack Category',
  'remoteImageUrl': 'https://example.test/$id.png',
  'suggestedPriceCentavos': priceCentavos,
  'image': image,
};

Future<File> _writePack(
  Directory root, {
  required int number,
  required List<Map<String, Object?>> products,
  Map<String, List<int>> images = const {},
  int revision = 1,
  bool includeAttribution = false,
  String? catalogChecksumOverride,
  Map<String, List<int>> unexpectedEntries = const {},
}) async {
  final catalogBytes = utf8.encode(jsonEncode({'products': products}));
  final files = <String, List<int>>{'catalog.json': catalogBytes, ...images};
  if (includeAttribution) {
    files['ATTRIBUTION.md'] = utf8.encode(
      '# Attribution\nOpen Food Facts data: ODbL. Images as individually noted.',
    );
  }
  final descriptors = [
    for (final entry in files.entries)
      <String, Object?>{
        'path': entry.key,
        'size': entry.value.length,
        'sha256': entry.key == 'catalog.json' && catalogChecksumOverride != null
            ? catalogChecksumOverride
            : sha256.convert(entry.value).toString(),
      },
  ]..sort((a, b) => (a['path']! as String).compareTo(b['path']! as String));
  final manifestBytes = utf8.encode(
    jsonEncode({
      'format': 'raze-store-catalog-pack',
      'packVersion': 1,
      'packId': 'test-pack',
      'revision': revision,
      'createdAt': DateTime.utc(2026, 9, 3).toIso8601String(),
      'dataFile': 'catalog.json',
      'title': 'Filipino sari-sari starter',
      'description': 'Test catalog pack',
      'dataLicense': 'ODbL-1.0',
      'imageLicense': 'various',
      'attribution': 'See ATTRIBUTION.md',
      'files': descriptors,
      'counts': {'products': products.length, 'images': images.length},
    }),
  );
  final archive = Archive()
    ..add(ArchiveFile.bytes('manifest.json', manifestBytes));
  for (final entry in files.entries) {
    archive.add(ArchiveFile.bytes(entry.key, entry.value));
  }
  for (final entry in unexpectedEntries.entries) {
    archive.add(ArchiveFile.bytes(entry.key, entry.value));
  }
  final file = File('${root.path}/pack-$number.razepack');
  await file.writeAsBytes(ZipEncoder().encode(archive));
  return file;
}

List<int> _pngBytes(int marker) => [
  ..._pngWithDimensions(width: 1, height: 1),
  marker,
];

List<int> _pngWithDimensions({required int width, required int height}) => [
  0x89,
  0x50,
  0x4e,
  0x47,
  0x0d,
  0x0a,
  0x1a,
  0x0a,
  0x00,
  0x00,
  0x00,
  0x0d,
  0x49,
  0x48,
  0x44,
  0x52,
  (width >> 24) & 0xff,
  (width >> 16) & 0xff,
  (width >> 8) & 0xff,
  width & 0xff,
  (height >> 24) & 0xff,
  (height >> 16) & 0xff,
  (height >> 8) & 0xff,
  height & 0xff,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
];

List<int> _jpegWithDimensions({required int width, required int height}) => [
  0xff,
  0xd8,
  0xff,
  0xc0,
  0x00,
  0x11,
  0x08,
  (height >> 8) & 0xff,
  height & 0xff,
  (width >> 8) & 0xff,
  width & 0xff,
  0x03,
  0x01,
  0x11,
  0x00,
  0x02,
  0x11,
  0x00,
  0x03,
  0x11,
  0x00,
  0xff,
  0xd9,
];

List<int> _webpWithDimensions({required int width, required int height}) {
  final widthMinusOne = width - 1;
  final heightMinusOne = height - 1;
  return [
    0x52,
    0x49,
    0x46,
    0x46,
    0x16,
    0x00,
    0x00,
    0x00,
    0x57,
    0x45,
    0x42,
    0x50,
    0x56,
    0x50,
    0x38,
    0x58,
    0x0a,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    widthMinusOne & 0xff,
    (widthMinusOne >> 8) & 0xff,
    (widthMinusOne >> 16) & 0xff,
    heightMinusOne & 0xff,
    (heightMinusOne >> 8) & 0xff,
    (heightMinusOne >> 16) & 0xff,
  ];
}

final class _DatabaseClosingImageStore extends LocalProductImageStore {
  _DatabaseClosingImageStore({required super.root, required this.database});

  final AppDatabase database;
  bool _closed = false;

  @override
  Future<String> persistFile(File source) async {
    final path = await super.persistFile(source);
    if (!_closed) {
      _closed = true;
      await database.close();
    }
    return path;
  }
}

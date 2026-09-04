import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/core/database/app_database.dart';
import 'package:raze_store/core/storage/local_product_image_store.dart';
import 'package:raze_store/features/cart/data/local_cart_repository.dart';
import 'package:raze_store/features/catalog/data/local_bulk_product_deletion_service.dart';
import 'package:raze_store/features/catalog/data/local_catalog_repository.dart';
import 'package:raze_store/features/catalog/domain/catalog_product.dart';

void main() {
  late AppDatabase database;
  late Directory root;
  late LocalProductImageStore imageStore;
  late LocalCatalogRepository catalog;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    root = await Directory.systemTemp.createTemp('raze_bulk_delete_');
    imageStore = LocalProductImageStore(root: root);
    catalog = LocalCatalogRepository(database, imageStore: imageStore);
  });

  tearDown(() async {
    await database.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'atomically removes selected products and cart rows but protects history',
    () async {
      final historicalImage = await _managedImage(
        root,
        imageStore,
        'historical.jpg',
      );
      final unusedImage = await _managedImage(root, imageStore, 'unused.jpg');
      final sharedImage = await _managedImage(root, imageStore, 'shared.jpg');
      final undoOnlyImage = await _managedImage(
        root,
        imageStore,
        'undo-only.jpg',
      );

      final first = await catalog.createProduct(
        ProductDraft(
          id: 'delete-first',
          barcode: '4800000000001',
          name: 'First product',
          localImagePath: historicalImage,
          catalogImagePath: unusedImage,
          priceCentavos: 100,
          sellingUnits: [
            SellingUnitDraft(id: 'piece', label: 'Piece', priceCentavos: 25),
          ],
        ),
      );
      await catalog.createProduct(
        ProductDraft(
          id: 'delete-second',
          name: 'Second product',
          localImagePath: sharedImage,
          priceCentavos: 200,
        ),
      );
      final retained = await catalog.createProduct(
        ProductDraft(
          id: 'keep',
          name: 'Retained product',
          catalogImagePath: sharedImage,
          priceCentavos: 300,
        ),
      );

      final cart = LocalCartRepository(database, imageStore: imageStore);
      await cart.addProduct(first);
      await cart.addProduct(retained);

      await database
          .into(database.sales)
          .insert(
            SalesCompanion.insert(
              id: 'sale-1',
              completedAt: DateTime.utc(2026, 9, 4),
              storeNameSnapshot: 'Test Store',
            ),
          );
      await database
          .into(database.saleLines)
          .insert(
            SaleLinesCompanion.insert(
              saleId: 'sale-1',
              position: 0,
              productIdSnapshot: const Value('delete-first'),
              nameSnapshot: 'First product',
              imagePathSnapshot: Value(historicalImage),
              unitPriceCentavos: 100,
              quantity: 1,
            ),
          );
      await database
          .into(database.catalogImportUndoBatches)
          .insert(
            CatalogImportUndoBatchesCompanion.insert(
              packId: 'starter-pack',
              revision: 2,
              importedAt: DateTime.utc(2026, 9, 4),
              createdCount: 1,
              updatedCount: 1,
            ),
          );
      await database
          .into(database.catalogImportUndoProducts)
          .insert(
            CatalogImportUndoProductsCompanion.insert(
              batchId: 1,
              productId: 'delete-first',
              createdByImport: true,
              beforeJson: Value(
                _undoSnapshot(
                  id: 'delete-first',
                  name: 'Earlier product',
                  catalogImagePath: undoOnlyImage,
                ),
              ),
              afterJson: _undoSnapshot(
                id: 'delete-first',
                name: 'First product',
                localImagePath: historicalImage,
                catalogImagePath: unusedImage,
              ),
            ),
          );

      final result = await LocalBulkProductDeletionService(
        database,
        imageStore,
      ).deleteProducts({'delete-first', 'delete-second', 'missing'});

      expect(result.deletedProductCount, 2);
      expect(result.removedCartRowCount, 1);
      expect(result.cleanedImageCount, 2);
      expect(result.imageCleanupFailureCount, 0);
      expect(await catalog.getProduct('delete-first'), isNull);
      expect(await catalog.getProduct('delete-second'), isNull);
      expect(await catalog.getProduct('keep'), isNotNull);
      expect((await cart.getDraft()).items.single.productId, 'keep');
      expect(
        await database.select(database.productSellingUnits).get(),
        isEmpty,
      );
      expect(await database.select(database.sales).get(), hasLength(1));
      expect(await database.select(database.saleLines).get(), hasLength(1));
      expect(
        await database.select(database.catalogImportUndoBatches).get(),
        isEmpty,
      );
      expect(
        await database.select(database.catalogImportUndoProducts).get(),
        isEmpty,
      );
      expect(await File(historicalImage).exists(), isTrue);
      expect(await File(sharedImage).exists(), isTrue);
      expect(await File(unusedImage).exists(), isFalse);
      expect(await File(undoOnlyImage).exists(), isFalse);
    },
  );

  test(
    'deletes more than one SQLite parameter window in one operation',
    () async {
      const count = 1005;
      final now = DateTime.utc(2026, 9, 4);
      await database.batch((batch) {
        batch.insertAll(database.storeProducts, [
          for (var index = 0; index < count; index++)
            StoreProductsCompanion.insert(
              id: 'product-$index',
              name: 'Product $index',
              priceCentavos: index + 1,
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
        ]);
      });

      final result = await LocalBulkProductDeletionService(database, imageStore)
          .deleteProducts([
            for (var index = 0; index < count; index++) 'product-$index',
          ]);

      expect(result.deletedProductCount, count);
      expect(await database.select(database.storeProducts).get(), isEmpty);
    },
  );

  test('keeps import undo when no requested product exists', () async {
    await database
        .into(database.catalogImportUndoBatches)
        .insert(
          CatalogImportUndoBatchesCompanion.insert(
            packId: 'starter-pack',
            revision: 2,
            importedAt: DateTime.utc(2026, 9, 4),
            createdCount: 1,
            updatedCount: 0,
          ),
        );

    final result = await LocalBulkProductDeletionService(
      database,
      imageStore,
    ).deleteProducts(const ['not-present']);

    expect(result.deletedProductCount, 0);
    expect(
      await database.select(database.catalogImportUndoBatches).get(),
      hasLength(1),
    );
  });
}

Future<String> _managedImage(
  Directory root,
  LocalProductImageStore imageStore,
  String name,
) async {
  final source = File('${root.path}/$name');
  await source.writeAsBytes([1, 2, 3, 4]);
  return imageStore.persistFile(source);
}

String _undoSnapshot({
  required String id,
  required String name,
  String? localImagePath,
  String? catalogImagePath,
}) {
  final timestamp = DateTime.utc(2026, 9, 4).toIso8601String();
  return jsonEncode({
    'version': 1,
    'id': id,
    'barcode': null,
    'source': 'test-pack',
    'sourceProductId': id,
    'name': name,
    'brand': null,
    'unitLabel': null,
    'category': null,
    'remoteImageUrl': null,
    'catalogImagePath': catalogImagePath,
    'sourceUpdatedAt': timestamp,
    'localImagePath': localImagePath,
    'priceCentavos': 100,
    'createdAt': timestamp,
    'updatedAt': timestamp,
  });
}

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'cart_line_id.dart';
import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [StoreProducts, ProductSellingUnits, DraftCartItems, StoreProfiles],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase({String name = 'raze_store'}) : super(driftDatabase(name: name));

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
      await into(storeProfiles).insert(
        StoreProfilesCompanion.insert(),
        mode: InsertMode.insertOrIgnore,
      );
    },
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await migrator.createTable(productSellingUnits);

        // Version 1 keyed a draft row by product only. Version 2 needs one row
        // per selected selling unit, so recreate the table with a line key and
        // carry every unfinished main-unit cart snapshot forward unchanged.
        await customStatement(
          'ALTER TABLE draft_cart_items RENAME TO draft_cart_items_v1',
        );
        await migrator.createTable(draftCartItems);
        await customStatement('''
          INSERT INTO draft_cart_items (
            line_id,
            product_id,
            selling_unit_id,
            barcode,
            name_snapshot,
            brand_snapshot,
            unit_label_snapshot,
            image_path_snapshot,
            unit_price_centavos,
            quantity,
            added_at,
            updated_at
          )
          SELECT
            'main:' || product_id,
            product_id,
            NULL,
            barcode,
            name_snapshot,
            brand_snapshot,
            unit_label_snapshot,
            image_path_snapshot,
            unit_price_centavos,
            quantity,
            added_at,
            updated_at
          FROM draft_cart_items_v1
        ''');
        await customStatement('DROP TABLE draft_cart_items_v1');
      } else if (from < 3) {
        await _upgradeVersion2CartLineIds(migrator);
      }
      if (from < 4) {
        // Source identity was previously advisory. Preserve every product but
        // detach duplicate legacy rows before enforcing one local row per
        // shared-catalog product.
        await customStatement('''
          UPDATE store_products
          SET source = NULL, source_product_id = NULL
          WHERE (source IS NULL AND source_product_id IS NOT NULL)
             OR (source IS NOT NULL AND source_product_id IS NULL)
        ''');
        await customStatement('''
          UPDATE store_products
          SET source = NULL, source_product_id = NULL
          WHERE source IS NOT NULL
            AND source_product_id IS NOT NULL
            AND rowid NOT IN (
              SELECT MIN(rowid)
              FROM store_products
              WHERE source IS NOT NULL AND source_product_id IS NOT NULL
              GROUP BY source, source_product_id
            )
        ''');
        await customStatement('''
          CREATE UNIQUE INDEX IF NOT EXISTS
            store_products_source_identity_unique_idx
          ON store_products (source, source_product_id)
        ''');
      }
    },
  );

  Future<void> _upgradeVersion2CartLineIds(Migrator migrator) async {
    final oldRows = await select(draftCartItems).get();
    await customStatement(
      'ALTER TABLE draft_cart_items RENAME TO draft_cart_items_v2',
    );
    await migrator.createTable(draftCartItems);
    await batch((batch) {
      batch.insertAll(draftCartItems, [
        for (final row in oldRows)
          DraftCartItemsCompanion.insert(
            lineId: buildCartLineId(row.productId, row.sellingUnitId),
            productId: row.productId,
            sellingUnitId: Value(row.sellingUnitId),
            barcode: Value(row.barcode),
            nameSnapshot: row.nameSnapshot,
            brandSnapshot: Value(row.brandSnapshot),
            unitLabelSnapshot: Value(row.unitLabelSnapshot),
            imagePathSnapshot: Value(row.imagePathSnapshot),
            unitPriceCentavos: row.unitPriceCentavos,
            quantity: row.quantity,
            addedAt: Value(row.addedAt),
            updatedAt: Value(row.updatedAt),
          ),
      ]);
    });
    await customStatement('DROP TABLE draft_cart_items_v2');
  }
}

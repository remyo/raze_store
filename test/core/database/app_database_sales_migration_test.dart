import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/core/database/app_database.dart';

void main() {
  test('v5 migration preserves store data and creates sales tables', () async {
    final directory = await Directory.systemTemp.createTemp(
      'raze_store_sales_v5_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/migration.sqlite');
    final database = AppDatabase.forTesting(
      NativeDatabase(
        file,
        setup: (sqlite) {
          sqlite.execute('''
            CREATE TABLE store_products (
              id TEXT NOT NULL PRIMARY KEY,
              barcode TEXT,
              source TEXT,
              source_product_id TEXT,
              name TEXT NOT NULL,
              brand TEXT,
              unit_label TEXT,
              category TEXT,
              remote_image_url TEXT,
              catalog_image_path TEXT,
              source_updated_at INTEGER,
              local_image_path TEXT,
              price_centavos INTEGER NOT NULL,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            );
            CREATE TABLE product_selling_units (
              id TEXT NOT NULL PRIMARY KEY,
              product_id TEXT NOT NULL REFERENCES store_products (id)
                ON DELETE CASCADE,
              label TEXT NOT NULL,
              price_centavos INTEGER NOT NULL,
              position INTEGER NOT NULL,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            );
            CREATE TABLE draft_cart_items (
              line_id TEXT NOT NULL PRIMARY KEY,
              product_id TEXT NOT NULL,
              selling_unit_id TEXT,
              barcode TEXT,
              name_snapshot TEXT NOT NULL,
              brand_snapshot TEXT,
              unit_label_snapshot TEXT,
              image_path_snapshot TEXT,
              unit_price_centavos INTEGER NOT NULL,
              quantity INTEGER NOT NULL,
              added_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            );
            CREATE TABLE store_profiles (
              id INTEGER NOT NULL PRIMARY KEY,
              store_name TEXT NOT NULL,
              address TEXT NOT NULL,
              contact TEXT NOT NULL,
              receipt_footer TEXT NOT NULL,
              updated_at INTEGER NOT NULL
            );
            INSERT INTO store_products VALUES (
              'coffee', '4801234567890', NULL, NULL, 'Instant coffee',
              'Sample Brand', 'Pack', 'Coffee', NULL,
              '/managed/catalog.png', 1788300000, '/managed/owner.png',
              12000, 1788300000, 1788300001
            );
            INSERT INTO product_selling_units VALUES (
              'stick', 'coffee', 'Stick', 800, 0, 1788300000, 1788300001
            );
            INSERT INTO draft_cart_items VALUES (
              'unit:coffee:stick', 'coffee', 'stick', '4801234567890',
              'Instant coffee', 'Sample Brand', 'Stick',
              '/managed/owner.png', 800, 3, 1788300000, 1788300001
            );
            INSERT INTO store_profiles VALUES (
              1, 'Aling Nena Store', 'Quezon City', '09171234567',
              'Salamat po!', 1788300001
            );
            PRAGMA user_version = 5;
          ''');
        },
      ),
    );
    addTearDown(database.close);

    expect(database.schemaVersion, 6);
    final product = await database.select(database.storeProducts).getSingle();
    expect(product.id, 'coffee');
    expect(product.priceCentavos, 12000);
    expect(product.catalogImagePath, '/managed/catalog.png');
    expect(product.localImagePath, '/managed/owner.png');
    final unit = await database
        .select(database.productSellingUnits)
        .getSingle();
    expect(unit.id, 'stick');
    expect(unit.productId, 'coffee');
    expect(unit.priceCentavos, 800);
    final cart = await database.select(database.draftCartItems).getSingle();
    expect(cart.lineId, 'unit:coffee:stick');
    expect(cart.quantity, 3);
    final profile = await database.select(database.storeProfiles).getSingle();
    expect(profile.storeName, 'Aling Nena Store');
    expect(profile.receiptFooter, 'Salamat po!');
    expect(await database.select(database.sales).get(), isEmpty);
    expect(await database.select(database.saleLines).get(), isEmpty);
  });
}

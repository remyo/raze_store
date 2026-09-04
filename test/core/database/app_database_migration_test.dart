import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/core/database/app_database.dart';
import 'package:raze_store/core/database/cart_line_id.dart';
import 'package:raze_store/features/cart/data/local_cart_repository.dart';

void main() {
  test('v1 migration preserves unfinished main-unit cart rows', () async {
    final directory = await Directory.systemTemp.createTemp('raze_store_v1_');
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
              local_image_path TEXT,
              price_centavos INTEGER NOT NULL,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            );
            CREATE TABLE draft_cart_items (
              product_id TEXT NOT NULL PRIMARY KEY,
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
            INSERT INTO draft_cart_items VALUES (
              'coffee', '4801234567890', 'Coffee', 'Sample', 'Pack', NULL,
              12000, 2, 1788343200, 1788343200
            );
            PRAGMA user_version = 1;
          ''');
        },
      ),
    );
    addTearDown(database.close);
    final draft = await LocalCartRepository(database).getDraft();

    expect(database.schemaVersion, 7);
    expect(draft.items, hasLength(1));
    expect(draft.items.single.lineId, 'main:coffee');
    expect(draft.items.single.productId, 'coffee');
    expect(draft.items.single.sellingUnitId, isNull);
    expect(draft.items.single.unitLabelSnapshot, 'Pack');
    expect(draft.items.single.quantity, 2);
  });

  test('v2 migration rewrites main and sub-unit cart line keys', () async {
    final directory = await Directory.systemTemp.createTemp('raze_store_v2_');
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
              local_image_path TEXT,
              price_centavos INTEGER NOT NULL,
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
            INSERT INTO draft_cart_items VALUES (
              'coffee', 'coffee', NULL, NULL, 'Coffee', NULL, 'Pack', NULL,
              12000, 1, 1788343200, 1788343200
            );
            INSERT INTO draft_cart_items VALUES (
              'coffee::selling-unit::stick', 'coffee', 'stick', NULL,
              'Coffee', NULL, 'Stick', NULL, 800, 2,
              1788343200, 1788343200
            );
            PRAGMA user_version = 2;
          ''');
        },
      ),
    );
    addTearDown(database.close);

    final draft = await LocalCartRepository(database).getDraft();

    expect(draft.items, hasLength(2));
    expect(draft.items.map((item) => item.lineId).toSet(), {
      buildCartLineId('coffee', null),
      buildCartLineId('coffee', 'stick'),
    });
  });

  test(
    'v3 migration keeps duplicate products but detaches extra API links',
    () async {
      final directory = await Directory.systemTemp.createTemp('raze_store_v3_');
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
              local_image_path TEXT,
              price_centavos INTEGER NOT NULL,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            );
            INSERT INTO store_products VALUES (
              'first', '111', 'raze_store_api', 'remote-id', 'First',
              NULL, NULL, NULL, NULL, NULL, 100, 1, 1
            );
            INSERT INTO store_products VALUES (
              'second', '222', 'raze_store_api', 'remote-id', 'Second',
              NULL, NULL, NULL, NULL, NULL, 200, 2, 2
            );
            INSERT INTO store_products VALUES (
              'partial', '333', 'raze_store_api', NULL, 'Partial',
              NULL, NULL, NULL, NULL, NULL, 300, 3, 3
            );
            PRAGMA user_version = 3;
          ''');
          },
        ),
      );
      addTearDown(database.close);

      final products = await database.select(database.storeProducts).get();
      final linked = products
          .where((product) => product.sourceProductId == 'remote-id')
          .toList();

      expect(database.schemaVersion, 7);
      expect(products, hasLength(3));
      expect(linked, hasLength(1));
      expect(linked.single.id, 'first');
      expect(
        products.singleWhere((product) => product.id == 'partial').source,
        isNull,
      );
    },
  );

  test(
    'v4 migration adds catalog provenance without changing products',
    () async {
      final directory = await Directory.systemTemp.createTemp('raze_store_v4_');
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
              local_image_path TEXT,
              price_centavos INTEGER NOT NULL,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            );
            CREATE UNIQUE INDEX store_products_barcode_unique_idx
              ON store_products (barcode);
            CREATE INDEX store_products_name_idx ON store_products (name);
            CREATE UNIQUE INDEX store_products_source_identity_unique_idx
              ON store_products (source, source_product_id);
            INSERT INTO store_products VALUES (
              'kept', '4800012345678', 'raze_store_api', 'shared-id',
              'Kept Product', 'Kept Brand', 'Pack', 'Coffee',
              'https://example.test/image.png', '/managed/owner.png',
              4321, 1, 2
            );
            PRAGMA user_version = 4;
          ''');
          },
        ),
      );
      addTearDown(database.close);

      final product = await database.select(database.storeProducts).getSingle();

      expect(database.schemaVersion, 7);
      expect(product.id, 'kept');
      expect(product.name, 'Kept Product');
      expect(product.priceCentavos, 4321);
      expect(product.localImagePath, '/managed/owner.png');
      expect(product.catalogImagePath, isNull);
      expect(product.sourceUpdatedAt, isNull);
    },
  );
}

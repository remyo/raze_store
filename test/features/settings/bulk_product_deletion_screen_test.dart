import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/core/database/app_database.dart';
import 'package:raze_store/core/database/database_provider.dart';
import 'package:raze_store/core/storage/local_product_image_store.dart';
import 'package:raze_store/core/storage/product_photo_services.dart';
import 'package:raze_store/core/widgets/product_image_placeholder.dart';
import 'package:raze_store/features/catalog/presentation/product_image.dart';
import 'package:raze_store/features/settings/presentation/bulk_product_deletion_screen.dart';

void main() {
  late AppDatabase database;
  late Directory root;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    root = await Directory.systemTemp.createTemp('raze_bulk_delete_ui_');
  });

  tearDown(() async {
    await database.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  testWidgets('searches, selects all matching products, and confirms count', (
    tester,
  ) async {
    await _seedProducts(database, 50, needleIndexes: const {48, 49});
    await _pumpScreen(tester, database: database, root: root);

    expect(find.text('Select all 50 matching products'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Needle');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('Select all 2 matching products'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('select-all-matching-products')),
    );
    await tester.pump();
    expect(find.text('Delete 2 selected'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('delete-selected-products')));
    await tester.pumpAndSettle();
    expect(find.text('Delete 2 selected products?'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('Completed sales'),
      ),
      findsOneWidget,
    );
    expect(await database.select(database.storeProducts).get(), hasLength(50));

    await tester.tap(
      find.byKey(const ValueKey('confirm-delete-selected-products')),
    );
    await tester.pumpAndSettle();

    expect(await database.select(database.storeProducts).get(), hasLength(48));
    expect(find.text('No matching products'), findsOneWidget);
    expect(find.textContaining('Deleted 2 products.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _disposeScreen(tester);
  });

  testWidgets('loads another compact page when scrolling near the end', (
    tester,
  ) async {
    await _seedProducts(database, 45);
    await _pumpScreen(tester, database: database, root: root);

    expect(
      find.byKey(const ValueKey('bulk-product-row-product-044')),
      findsNothing,
    );
    await tester.drag(
      find.byKey(const ValueKey('bulk-product-list')),
      const Offset(0, -5000),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('bulk-product-row-product-044')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await _disposeScreen(tester);
  });

  testWidgets(
    'shows image placeholders before product details and trailing checkboxes',
    (tester) async {
      await _seedProducts(database, 2);
      await _pumpScreen(tester, database: database, root: root);

      final photoRow = find.byKey(
        const ValueKey('bulk-product-row-product-000'),
      );
      final emptyPhotoRow = find.byKey(
        const ValueKey('bulk-product-row-product-001'),
      );
      final photo = find.descendant(
        of: photoRow,
        matching: find.byKey(const ValueKey('bulk-product-image-product-000')),
      );
      final checkbox = find.descendant(
        of: photoRow,
        matching: find.byKey(
          const ValueKey('bulk-product-checkbox-product-000'),
        ),
      );

      expect(photo, findsOneWidget);
      expect(
        find.descendant(
          of: photoRow,
          matching: find.byType(ProductImagePlaceholder),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: emptyPhotoRow,
          matching: find.byType(ProductImagePlaceholder),
        ),
        findsOneWidget,
      );
      expect(
        tester.getCenter(photo).dx,
        lessThan(tester.getCenter(checkbox).dx),
      );
      expect(
        find.descendant(of: photoRow, matching: find.byType(ProductImage)),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await _disposeScreen(tester);
    },
  );
}

Future<void> _seedProducts(
  AppDatabase database,
  int count, {
  Set<int> needleIndexes = const {},
}) async {
  final now = DateTime.utc(2026, 9, 4);
  await database.batch((batch) {
    batch.insertAll(database.storeProducts, [
      for (var index = 0; index < count; index++)
        StoreProductsCompanion.insert(
          id: 'product-${index.toString().padLeft(3, '0')}',
          barcode: Value('LOCAL-${index.toString().padLeft(3, '0')}'),
          name: needleIndexes.contains(index)
              ? 'Needle ${index.toString().padLeft(3, '0')}'
              : 'Product ${index.toString().padLeft(3, '0')}',
          category: const Value('Snacks'),
          priceCentavos: 100 + index,
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
    ]);
  });
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required AppDatabase database,
  required Directory root,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        localProductImageStoreProvider.overrideWithValue(
          LocalProductImageStore(root: root),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const BulkProductDeletionScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _disposeScreen(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  // Drift closes watched queries on a zero-delay timer after Riverpod
  // disposes the auto-dispose provider.
  await tester.pump(const Duration(milliseconds: 1));
}

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/core/database/app_database.dart'
    show AppDatabase, SaleLinesCompanion, SalesCompanion;
import 'package:raze_store/core/money/money.dart';
import 'package:raze_store/features/cart/data/local_cart_repository.dart';
import 'package:raze_store/features/catalog/data/local_catalog_repository.dart';
import 'package:raze_store/features/catalog/domain/catalog_product.dart';
import 'package:raze_store/features/sales/data/local_sales_repository.dart';
import 'package:raze_store/features/sales/domain/sales_date_range.dart';
import 'package:raze_store/features/sales/domain/sales_repository.dart';
import 'package:raze_store/features/settings/data/local_settings_repository.dart';
import 'package:raze_store/features/settings/domain/store_profile.dart';

void main() {
  late AppDatabase database;
  late LocalCartRepository cartRepository;
  late StoreProduct product;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    cartRepository = LocalCartRepository(database);
    product = await LocalCatalogRepository(database).createProduct(
      ProductDraft(
        id: 'coffee',
        barcode: '4801234567890',
        name: 'Instant coffee',
        brand: 'Sample Brand',
        unitLabel: 'Pack',
        localImagePath: '/managed/coffee.png',
        priceCentavos: 12000,
        sellingUnits: [
          SellingUnitDraft(id: 'stick', label: 'Stick', priceCentavos: 800),
        ],
      ),
    );
  });

  tearDown(() => database.close());

  test(
    'completion snapshots cart and profile before atomically clearing draft',
    () async {
      await LocalSettingsRepository(database).saveStoreProfile(
        const StoreProfile(
          storeName: 'Aling Nena Store',
          address: 'Quezon City',
          contact: '09171234567',
          receiptFooter: 'Maraming salamat po!',
        ),
      );
      await cartRepository.addProduct(product, quantity: 2);
      await cartRepository.addProduct(
        product,
        saleOption: product.saleOptions.last,
        quantity: 3,
      );
      final completedAt = DateTime(2026, 9, 3, 14, 30);
      final repository = LocalSalesRepository(database, now: () => completedAt);

      final sale = await repository.completeCurrentCart(
        cashReceivedCentavos: 30000,
      );

      expect((await cartRepository.getDraft()).isEmpty, isTrue);
      expect(sale.completedAt, completedAt.toUtc());
      expect(sale.storeNameSnapshot, 'Aling Nena Store');
      expect(sale.storeAddressSnapshot, 'Quezon City');
      expect(sale.storeContactSnapshot, '09171234567');
      expect(sale.footerMessageSnapshot, 'Maraming salamat po!');
      expect(sale.lines, hasLength(2));
      expect(sale.lines.map((line) => line.position), [0, 1]);
      expect(sale.totalQuantity, 5);
      expect(sale.totalCentavos, 26400);
      expect(sale.total, const Money.fromCentavos(26400));
      expect(sale.changeCentavos, 3600);

      final stick = sale.lines.singleWhere(
        (line) => line.sellingUnitId == 'stick',
      );
      expect(stick.productId, 'coffee');
      expect(stick.barcode, '4801234567890');
      expect(stick.nameSnapshot, 'Instant coffee');
      expect(stick.brandSnapshot, 'Sample Brand');
      expect(stick.unitLabelSnapshot, 'Stick');
      expect(stick.imagePathSnapshot, isNull);
      expect(stick.unitPriceCentavos, 800);
      expect(stick.quantity, 3);

      final receipt = sale.toReceiptDraft();
      expect(receipt.storeName, 'Aling Nena Store');
      expect(receipt.createdAt, completedAt.toUtc());
      expect(receipt.lines, hasLength(2));
      expect(receipt.totalCentavos, 26400);
      expect(receipt.cashReceivedCentavos, 30000);
    },
  );

  test(
    'history is independent from later catalog and profile changes',
    () async {
      await cartRepository.addProduct(product);
      final repository = LocalSalesRepository(
        database,
        now: () => DateTime(2026, 9, 3, 9),
      );
      final original = await repository.completeCurrentCart();

      await LocalCatalogRepository(database).deleteProduct(product.id);
      await LocalSettingsRepository(database).saveStoreProfile(
        const StoreProfile(
          storeName: 'Renamed Store',
          address: '',
          contact: '',
          receiptFooter: 'New footer',
        ),
      );

      final saved = await repository.getSale(original.id);
      expect(saved, isNotNull);
      expect(saved!.storeNameSnapshot, 'Raze Store');
      expect(saved.footerMessageSnapshot, 'Salamat po!');
      expect(saved.lines.single.nameSnapshot, 'Instant coffee');
      expect(saved.lines.single.productId, 'coffee');
      expect(saved.lines.single.imagePathSnapshot, isNull);
    },
  );

  test(
    'date ranges query local calendar days with inclusive custom dates',
    () async {
      Future<void> completeAt(DateTime completedAt) async {
        await cartRepository.addProduct(product);
        await LocalSalesRepository(
          database,
          now: () => completedAt,
        ).completeCurrentCart();
      }

      await completeAt(DateTime(2026, 8, 25, 12));
      await completeAt(DateTime(2026, 9, 1, 0));
      await completeAt(DateTime(2026, 9, 2, 23, 59));
      await completeAt(DateTime(2026, 9, 3, 10));
      final repository = LocalSalesRepository(database);
      final now = DateTime(2026, 9, 3, 18);

      expect(
        await repository.getSales(range: SalesDateRange.today(now)),
        hasLength(1),
      );
      expect(
        await repository.getSales(range: SalesDateRange.lastDays(7, now: now)),
        hasLength(3),
      );
      expect(
        await repository.getSales(range: SalesDateRange.thisMonth(now)),
        hasLength(3),
      );
      expect(
        await repository.getSales(
          range: SalesDateRange.custom(
            startDay: DateTime(2026, 9, 1, 22),
            endDay: DateTime(2026, 9, 2, 1),
          ),
        ),
        hasLength(2),
      );
      expect(await repository.getSales(), hasLength(4));
      expect(
        await repository.watchOldestSaleDate().first,
        DateTime(2026, 8, 25, 12).toUtc(),
      );
    },
  );

  test('hydrates wide histories in bounded query chunks', () async {
    const saleCount = 805;
    final start = DateTime.utc(2026, 1, 1);
    await database.batch((batch) {
      batch.insertAll(database.sales, [
        for (var index = 0; index < saleCount; index++)
          SalesCompanion.insert(
            id: 'bulk-$index',
            completedAt: start.add(Duration(minutes: index)),
            storeNameSnapshot: 'Test Store',
          ),
      ]);
      batch.insertAll(database.saleLines, [
        for (var index = 0; index < saleCount; index++)
          SaleLinesCompanion.insert(
            saleId: 'bulk-$index',
            position: 0,
            nameSnapshot: 'Product $index',
            unitPriceCentavos: 100 + index,
            quantity: 1,
          ),
      ]);
    });

    final sales = await LocalSalesRepository(database).getSales();

    expect(sales, hasLength(saleCount));
    expect(sales.first.id, 'bulk-804');
    expect(sales.last.id, 'bulk-0');
    expect(sales.every((sale) => sale.lines.length == 1), isTrue);
  });

  test(
    'deleting sales removes owned lines without affecting other sales',
    () async {
      final repository = LocalSalesRepository(database);
      await cartRepository.addProduct(product);
      final first = await repository.completeCurrentCart();
      await cartRepository.addProduct(product);
      final second = await repository.completeCurrentCart();

      await repository.deleteSale(first.id);

      expect(await repository.getSale(first.id), isNull);
      expect(await repository.getSale(second.id), isNotNull);
      final lineRows = await database.select(database.saleLines).get();
      expect(lineRows, hasLength(1));
      expect(lineRows.single.saleId, second.id);

      await repository.deleteSales([second.id, second.id]);
      expect(await repository.getSales(), isEmpty);
      expect(await database.select(database.saleLines).get(), isEmpty);
    },
  );

  test('empty or invalid completion never changes persisted data', () async {
    final repository = LocalSalesRepository(database);

    await expectLater(
      repository.completeCurrentCart(),
      throwsA(isA<EmptyCartSaleException>()),
    );
    await cartRepository.addProduct(product);
    await expectLater(
      repository.completeCurrentCart(cashReceivedCentavos: -1),
      throwsArgumentError,
    );

    expect((await cartRepository.getDraft()).isNotEmpty, isTrue);
    expect(await repository.getSales(), isEmpty);
  });
}

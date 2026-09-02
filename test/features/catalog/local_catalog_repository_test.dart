import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/core/database/app_database.dart';
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
}

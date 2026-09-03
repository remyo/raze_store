import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/core/database/app_database.dart' show AppDatabase;
import 'package:raze_store/core/money/money.dart';
import 'package:raze_store/core/storage/local_product_image_store.dart';
import 'package:raze_store/features/cart/data/local_cart_repository.dart';
import 'package:raze_store/features/cart/domain/cart.dart';
import 'package:raze_store/features/catalog/domain/catalog_product.dart';

void main() {
  late AppDatabase database;
  late LocalCartRepository repository;
  final now = DateTime.utc(2026, 9, 2, 11);

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = LocalCartRepository(database, now: () => now);
  });

  tearDown(() => database.close());

  test(
    'duplicate add increments quantity and preserves first snapshots',
    () async {
      await repository.addProduct(_product(priceCentavos: 1250));
      await repository.addProduct(
        _product(name: 'Renamed later', priceCentavos: 1500),
        quantity: 2,
      );

      final draft = await repository.getDraft();
      expect(draft.items, hasLength(1));
      expect(draft.items.single.quantity, 3);
      expect(draft.items.single.nameSnapshot, 'Instant noodles');
      expect(draft.items.single.unitPriceCentavos, 1250);
      expect(draft.totalCentavos, 3750);
      expect(draft.totalQuantity, 3);
    },
  );

  test('persists an unfinished draft for a new repository instance', () async {
    await repository.addProduct(_product(barcode: null));

    final reopenedRepository = LocalCartRepository(database);
    final draft = await reopenedRepository.getDraft();

    expect(draft.items.single.productId, 'noodles');
    expect(draft.items.single.barcode, isNull);
  });

  test('keeps main and sub-selling units as distinct cart lines', () async {
    final product = _product(
      priceCentavos: 16000,
      unitLabel: 'Pack',
      sellingUnits: const [
        SellingUnit(
          id: 'stick',
          label: 'Stick',
          price: Money.fromCentavos(1000),
        ),
      ],
    );

    await repository.addProduct(product);
    await repository.addProduct(
      product,
      saleOption: product.saleOptions.last,
      quantity: 3,
    );

    final draft = await repository.getDraft();
    expect(draft.items, hasLength(2));
    expect(draft.distinctProductCount, 1);
    expect(draft.totalQuantity, 4);
    expect(draft.totalCentavos, 19000);
    final main = draft.items.singleWhere((item) => item.sellingUnitId == null);
    final stick = draft.items.singleWhere(
      (item) => item.sellingUnitId == 'stick',
    );
    expect(main.unitLabelSnapshot, 'Pack');
    expect(main.unitPriceCentavos, 16000);
    expect(stick.unitLabelSnapshot, 'Stick');
    expect(stick.unitPriceCentavos, 1000);
    expect(stick.lineId, isNot(main.lineId));

    await repository.updateQuantity(stick.lineId, 5);
    expect(
      (await repository.getDraft()).items
          .singleWhere((item) => item.sellingUnitId == 'stick')
          .quantity,
      5,
    );
  });

  test('updates, removes, and clears quantities', () async {
    await repository.addProduct(_product());
    final lineId = (await repository.getDraft()).items.single.lineId;
    await repository.updateQuantity(lineId, 4);
    expect((await repository.getDraft()).items.single.quantity, 4);

    await repository.updateQuantity(lineId, 0);
    expect((await repository.getDraft()).isEmpty, isTrue);

    await repository.addProduct(_product());
    await repository.clear();
    expect((await repository.getDraft()).isEmpty, isTrue);
  });

  test('rejects a cart quantity above the safe UI limit', () async {
    await repository.addProduct(_product(), quantity: maximumCartQuantity);
    final lineId = (await repository.getDraft()).items.single.lineId;

    expect(() => repository.addProduct(_product()), throwsA(isA<RangeError>()));
    expect(
      () => repository.updateQuantity(lineId, maximumCartQuantity + 1),
      throwsA(isA<RangeError>()),
    );
  });

  test('cart line keys cannot collide when IDs contain separators', () async {
    await repository.addProduct(
      _product(id: 'p::selling-unit::u', name: 'Main product'),
    );
    final productWithUnit = _product(
      id: 'p',
      name: 'Unit product',
      sellingUnits: const [
        SellingUnit(id: 'u', label: 'Stick', price: Money.fromCentavos(200)),
      ],
    );
    await repository.addProduct(
      productWithUnit,
      saleOption: productWithUnit.saleOptions.last,
    );

    final draft = await repository.getDraft();
    expect(draft.items, hasLength(2));
    expect(draft.items.map((item) => item.lineId).toSet(), hasLength(2));
    expect(draft.items.map((item) => item.nameSnapshot), {
      'Main product',
      'Unit product',
    });
  });

  test('repairs a relocated managed cart photo path on read', () async {
    const fileName = '123e4567-e89b-12d3-a456-426614174001.png';
    final root = await Directory.systemTemp.createTemp(
      'raze_store_cart_photo_',
    );
    addTearDown(() => root.delete(recursive: true));
    final managed = Directory('${root.path}/product_images');
    await managed.create(recursive: true);
    final relocatedPath = '${managed.path}/$fileName';
    await File(relocatedPath).writeAsBytes([1, 2, 3]);
    const stalePath = '/old/ios/container/product_images/$fileName';
    final repairingRepository = LocalCartRepository(
      database,
      now: () => now,
      imageStore: LocalProductImageStore(root: root),
    );

    await repairingRepository.addProduct(_product(localImagePath: stalePath));

    expect(
      (await repairingRepository.getDraft()).items.single.imagePathSnapshot,
      relocatedPath,
    );
    expect(
      (await LocalCartRepository(
        database,
      ).getDraft()).items.single.imagePathSnapshot,
      relocatedPath,
    );
  });
}

StoreProduct _product({
  String id = 'noodles',
  String name = 'Instant noodles',
  String? barcode = '4801234567890',
  int priceCentavos = 1250,
  String? unitLabel = '1 pack',
  List<SellingUnit> sellingUnits = const [],
  String? localImagePath = '/local/noodles.jpg',
}) => StoreProduct(
  id: id,
  metadata: CatalogMetadata(barcode: barcode, name: name, unitLabel: unitLabel),
  price: Money.fromCentavos(priceCentavos),
  sellingUnits: sellingUnits,
  localImagePath: localImagePath,
  createdAt: DateTime.utc(2026, 9, 1),
  updatedAt: DateTime.utc(2026, 9, 1),
);

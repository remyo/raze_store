import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/core/database/app_database.dart' show AppDatabase;
import 'package:raze_store/core/money/money.dart';
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

  test('updates, removes, and clears quantities', () async {
    await repository.addProduct(_product());
    await repository.updateQuantity('noodles', 4);
    expect((await repository.getDraft()).items.single.quantity, 4);

    await repository.updateQuantity('noodles', 0);
    expect((await repository.getDraft()).isEmpty, isTrue);

    await repository.addProduct(_product());
    await repository.clear();
    expect((await repository.getDraft()).isEmpty, isTrue);
  });

  test('rejects a cart quantity above the safe UI limit', () async {
    await repository.addProduct(_product(), quantity: maximumCartQuantity);

    expect(() => repository.addProduct(_product()), throwsA(isA<RangeError>()));
    expect(
      () => repository.updateQuantity('noodles', maximumCartQuantity + 1),
      throwsA(isA<RangeError>()),
    );
  });
}

StoreProduct _product({
  String name = 'Instant noodles',
  String? barcode = '4801234567890',
  int priceCentavos = 1250,
}) => StoreProduct(
  id: 'noodles',
  metadata: CatalogMetadata(barcode: barcode, name: name, unitLabel: '1 pack'),
  price: Money.fromCentavos(priceCentavos),
  localImagePath: '/local/noodles.jpg',
  createdAt: DateTime.utc(2026, 9, 1),
  updatedAt: DateTime.utc(2026, 9, 1),
);

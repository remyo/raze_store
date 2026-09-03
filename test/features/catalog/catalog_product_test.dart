import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/features/catalog/domain/catalog_product.dart';

void main() {
  test('requires a complete shared catalog identity', () {
    expect(
      () => ProductDraft(
        name: 'Incomplete API product',
        source: 'raze_store_api',
        priceCentavos: 100,
      ),
      throwsArgumentError,
    );
  });

  group('ProductDraft selling-unit labels', () {
    test('rejects a sub-unit matching the named main unit', () {
      expect(
        () => ProductDraft(
          barcode: '4801234567890',
          name: 'Cigarettes',
          unitLabel: ' Pack ',
          priceCentavos: 16000,
          sellingUnits: [SellingUnitDraft(label: 'pack', priceCentavos: 1000)],
        ),
        throwsArgumentError,
      );
    });

    test('rejects a sub-unit matching the fallback main unit', () {
      expect(
        () => ProductDraft(
          barcode: '4801234567890',
          name: 'Loose item',
          priceCentavos: 1000,
          sellingUnits: [
            SellingUnitDraft(label: 'MAIN ITEM', priceCentavos: 500),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('requires the main product barcode before adding sub-units', () {
      expect(
        () => ProductDraft(
          name: 'Loose item',
          priceCentavos: 1000,
          sellingUnits: [SellingUnitDraft(label: 'Piece', priceCentavos: 500)],
        ),
        throwsArgumentError,
      );
    });
  });
}

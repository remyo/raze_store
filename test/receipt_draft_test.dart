import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/features/receipt/domain/receipt_draft.dart';

void main() {
  group('ReceiptDraft', () {
    test('calculates exact centavo totals, quantity, and change', () {
      final draft = ReceiptDraft(
        storeName: '  Aling Nena Sari-sari Store  ',
        lines: [
          ReceiptLine(
            productName: 'Canned sardines',
            quantity: 2,
            unitPriceCentavos: 2350,
          ),
          ReceiptLine(
            productName: 'Instant noodles',
            quantity: 3,
            unitPriceCentavos: 1250,
          ),
        ],
        createdAt: DateTime.utc(2026, 9, 2, 11, 30),
        cashReceivedCentavos: 10000,
      );

      expect(draft.storeName, 'Aling Nena Sari-sari Store');
      expect(draft.totalQuantity, 5);
      expect(draft.totalCentavos, 8450);
      expect(draft.changeCentavos, 1550);
    });

    test('uses a snapshot of the source lines', () {
      final source = [
        ReceiptLine(
          productName: 'Bottled water',
          quantity: 1,
          unitPriceCentavos: 1500,
        ),
      ];
      final draft = ReceiptDraft(
        storeName: 'Corner Store',
        lines: source,
        createdAt: DateTime(2026),
      );

      source.add(
        ReceiptLine(
          productName: 'Crackers',
          quantity: 1,
          unitPriceCentavos: 800,
        ),
      );

      expect(draft.lines, hasLength(1));
      expect(() => draft.lines.add(source.last), throwsUnsupportedError);
    });

    test('reports a balance due when cash is below the total', () {
      final draft = ReceiptDraft(
        storeName: 'Corner Store',
        lines: [
          ReceiptLine(
            productName: 'Rice',
            quantity: 2,
            unitPriceCentavos: 2000,
          ),
        ],
        createdAt: DateTime(2026),
        cashReceivedCentavos: 3000,
      );

      expect(draft.changeCentavos, -1000);
    });

    test('rejects invalid lines and empty receipts', () {
      expect(
        () =>
            ReceiptLine(productName: ' ', quantity: 1, unitPriceCentavos: 100),
        throwsArgumentError,
      );
      expect(
        () => ReceiptLine(
          productName: 'Coffee',
          quantity: 0,
          unitPriceCentavos: 100,
        ),
        throwsArgumentError,
      );
      expect(
        () => ReceiptDraft(
          storeName: 'Corner Store',
          lines: const [],
          createdAt: DateTime(2026),
        ),
        throwsArgumentError,
      );
    });
  });
}

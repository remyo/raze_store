import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/core/money/money.dart';

void main() {
  group('Money', () {
    test('uses exact integer-centavo arithmetic', () {
      const unitPrice = Money.fromCentavos(1250);

      expect(unitPrice.times(3), const Money.fromCentavos(3750));
      expect(
        unitPrice + const Money.fromCentavos(25),
        const Money.fromCentavos(1275),
      );
    });

    test('parses common peso form values', () {
      expect(tryParsePesoCentavos('12'), 1200);
      expect(tryParsePesoCentavos('12.5'), 1250);
      expect(tryParsePesoCentavos('₱1,234.50'), 123450);
      expect(tryParsePesoCentavos('10.999'), isNull);
      expect(tryParsePesoCentavos('-1'), isNull);
    });

    test('formats Philippine pesos', () {
      expect(const Money.fromCentavos(123450).format(), '₱1,234.50');
    });

    test('formats editable peso input without rounding', () {
      expect(formatPesoInput(850), '8.50');
      expect(formatPesoInput(123450), '1234.50');
    });
  });
}

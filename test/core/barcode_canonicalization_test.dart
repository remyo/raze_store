import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/core/barcode/barcode.dart';

void main() {
  group('Barcode', () {
    test('canonicalizes UPC-A to its EAN-13 representation', () {
      expect(canonicalizeBarcode('012345678905'), '0012345678905');
      expect(Barcode('012345678905'), Barcode('0012345678905'));
    });

    test('preserves case-sensitive non-numeric formats', () {
      expect(Barcode('  AbC-123  ').value, 'AbC-123');
    });

    test('rejects blank values without affecting optional products', () {
      expect(Barcode.tryParse('   '), isNull);
      expect(() => Barcode(''), throwsArgumentError);
    });
  });
}

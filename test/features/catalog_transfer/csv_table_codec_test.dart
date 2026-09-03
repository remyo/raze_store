import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/features/catalog_transfer/data/csv_table_codec.dart';

void main() {
  const codec = CsvTableCodec();

  test('round trips commas, quotes, line breaks, and Unicode text', () {
    final rows = <List<Object?>>[
      ['name', 'price', 'note'],
      ['Kape, 3-in-1', '8.00', 'Sabi niya: "masarap"'],
      ['Itlog', '9.00', 'Per piece\nFresh'],
      ['Asukal', null, ' ₱ value '],
    ];

    final decoded = codec.decode(codec.encode(rows));

    expect(
      decoded,
      rows
          .map((row) => row.map((value) => value?.toString() ?? '').toList())
          .toList(),
    );
  });

  test('accepts UTF-8 BOM and CRLF rows', () {
    expect(codec.decode('\uFEFFa,b\r\n1,2\r\n'), [
      ['a', 'b'],
      ['1', '2'],
    ]);
  });

  test('rejects an unterminated quoted field', () {
    expect(() => codec.decode('name\n"coffee'), throwsFormatException);
  });
}

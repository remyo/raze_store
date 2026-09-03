import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/features/sales/domain/sales_date_range.dart';

void main() {
  test('lastDays includes today and the requested number of calendar days', () {
    final range = SalesDateRange.lastDays(7, now: DateTime(2026, 9, 3, 23, 59));

    expect(range.includes(DateTime(2026, 8, 28)), isTrue);
    expect(range.includes(DateTime(2026, 9, 3, 23, 59, 59)), isTrue);
    expect(range.includes(DateTime(2026, 8, 27, 23, 59, 59)), isFalse);
    expect(range.includes(DateTime(2026, 9, 4)), isFalse);
  });

  test('custom includes both selected days and rejects reversed dates', () {
    final range = SalesDateRange.custom(
      startDay: DateTime(2026, 8, 30, 22),
      endDay: DateTime(2026, 9, 2, 1),
    );

    expect(range.includes(DateTime(2026, 8, 30)), isTrue);
    expect(range.includes(DateTime(2026, 9, 2, 23, 59)), isTrue);
    expect(range.includes(DateTime(2026, 8, 29, 23, 59)), isFalse);
    expect(range.includes(DateTime(2026, 9, 3)), isFalse);
    expect(
      () => SalesDateRange.custom(
        startDay: DateTime(2026, 9, 3),
        endDay: DateTime(2026, 9, 2),
      ),
      throwsArgumentError,
    );
  });
}

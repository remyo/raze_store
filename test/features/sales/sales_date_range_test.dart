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

  test('lastMonths uses complete local calendar month boundaries', () {
    final range = SalesDateRange.lastMonths(
      3,
      now: DateTime(2026, 1, 15, 23, 59),
    );

    expect(range.includes(DateTime(2025, 11, 1)), isTrue);
    expect(range.includes(DateTime(2026, 1, 31, 23, 59, 59)), isTrue);
    expect(range.includes(DateTime(2025, 10, 31, 23, 59, 59)), isFalse);
    expect(range.includes(DateTime(2026, 2, 1)), isFalse);
    expect(
      () => SalesDateRange.lastMonths(0, now: DateTime(2026)),
      throwsArgumentError,
    );
  });

  test('thisYear includes January through December only', () {
    final range = SalesDateRange.thisYear(DateTime(2026, 9, 3));

    expect(range.includes(DateTime(2026)), isTrue);
    expect(range.includes(DateTime(2026, 12, 31, 23, 59, 59)), isTrue);
    expect(range.includes(DateTime(2025, 12, 31, 23, 59, 59)), isFalse);
    expect(range.includes(DateTime(2027)), isFalse);
  });
}

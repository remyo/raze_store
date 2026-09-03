import 'package:flutter/foundation.dart';

/// A half-open instant range used to query completed sales.
///
/// Calendar factories accept local dates and convert their boundaries to UTC,
/// preserving the user's idea of a day even across daylight-saving changes.
@immutable
final class SalesDateRange {
  SalesDateRange({
    required DateTime startInclusive,
    required DateTime endExclusive,
  }) : startInclusive = startInclusive.toUtc(),
       endExclusive = endExclusive.toUtc() {
    if (!this.endExclusive.isAfter(this.startInclusive)) {
      throw ArgumentError.value(
        endExclusive,
        'endExclusive',
        'Must be after startInclusive.',
      );
    }
  }

  factory SalesDateRange.today(DateTime now) {
    final today = _localDay(now);
    return SalesDateRange(
      startInclusive: today,
      endExclusive: _nextLocalDay(today),
    );
  }

  factory SalesDateRange.lastDays(int days, {required DateTime now}) {
    if (days <= 0) {
      throw ArgumentError.value(days, 'days', 'Must be greater than zero.');
    }
    final today = _localDay(now);
    return SalesDateRange(
      startInclusive: DateTime(today.year, today.month, today.day - days + 1),
      endExclusive: _nextLocalDay(today),
    );
  }

  factory SalesDateRange.thisMonth(DateTime now) {
    final local = now.toLocal();
    return SalesDateRange(
      startInclusive: DateTime(local.year, local.month),
      endExclusive: DateTime(local.year, local.month + 1),
    );
  }

  /// Includes the current local calendar month and the preceding months.
  ///
  /// For example, three months on September 3 covers July 1 through the end
  /// of September. Sales cannot normally exist in the future portion of the
  /// current month, while calendar boundaries keep this filter predictable.
  factory SalesDateRange.lastMonths(int months, {required DateTime now}) {
    if (months <= 0) {
      throw ArgumentError.value(months, 'months', 'Must be greater than zero.');
    }
    final local = now.toLocal();
    return SalesDateRange(
      startInclusive: DateTime(local.year, local.month - months + 1),
      endExclusive: DateTime(local.year, local.month + 1),
    );
  }

  factory SalesDateRange.thisYear(DateTime now) {
    final local = now.toLocal();
    return SalesDateRange(
      startInclusive: DateTime(local.year),
      endExclusive: DateTime(local.year + 1),
    );
  }

  /// Creates a range that includes both selected local calendar days.
  factory SalesDateRange.custom({
    required DateTime startDay,
    required DateTime endDay,
  }) {
    final start = _localDay(startDay);
    final end = _localDay(endDay);
    if (end.isBefore(start)) {
      throw ArgumentError.value(
        endDay,
        'endDay',
        'Must be on or after startDay.',
      );
    }
    return SalesDateRange(
      startInclusive: start,
      endExclusive: _nextLocalDay(end),
    );
  }

  final DateTime startInclusive;
  final DateTime endExclusive;

  bool includes(DateTime value) {
    final utc = value.toUtc();
    return !utc.isBefore(startInclusive) && utc.isBefore(endExclusive);
  }

  @override
  bool operator ==(Object other) {
    return other is SalesDateRange &&
        other.startInclusive == startInclusive &&
        other.endExclusive == endExclusive;
  }

  @override
  int get hashCode => Object.hash(startInclusive, endExclusive);
}

List<T> filterSalesByDate<T>(
  Iterable<T> values, {
  required SalesDateRange range,
  required DateTime Function(T value) dateOf,
}) {
  return values
      .where((value) => range.includes(dateOf(value)))
      .toList(growable: false);
}

DateTime _localDay(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

DateTime _nextLocalDay(DateTime day) {
  return DateTime(day.year, day.month, day.day + 1);
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/core/money/money.dart';
import 'package:raze_store/features/sales/application/sales_providers.dart';
import 'package:raze_store/features/sales/domain/completed_sale.dart';
import 'package:raze_store/features/sales/domain/sales_date_range.dart';
import 'package:raze_store/features/sales/domain/sales_repository.dart';
import 'package:raze_store/features/sales/presentation/sales_screen.dart';

void main() {
  testWidgets('period buttons update the summary and daily history together', (
    tester,
  ) async {
    _useView(tester, const Size(430, 900));
    final now = DateTime(2026, 9, 3, 18);
    final repository = _FakeSalesRepository([
      _sale(
        id: 'today',
        name: 'Today coffee',
        completedAt: DateTime(2026, 9, 3, 14),
        unitPriceCentavos: 1250,
        quantity: 2,
      ),
      _sale(
        id: 'month',
        name: 'Month noodles',
        completedAt: DateTime(2026, 9, 1, 9),
        unitPriceCentavos: 1500,
      ),
      _sale(
        id: 'seven-days',
        name: 'August soap',
        completedAt: DateTime(2026, 8, 30, 10),
        unitPriceCentavos: 2000,
      ),
      _sale(
        id: 'older',
        name: 'Older rice',
        completedAt: DateTime(2026, 8, 10, 11),
        unitPriceCentavos: 5000,
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [salesRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          theme: AppTheme.light,
          home: SalesScreen(now: now, onOpenSale: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.unboundedHistoryWatchCount, 0);
    expect(find.text('Today coffee'), findsOneWidget);
    expect(find.text('Month noodles'), findsNothing);
    _expectMetric(
      tester,
      const ValueKey('sales-summary-revenue'),
      'Revenue: ₱25.00',
    );
    _expectMetric(
      tester,
      const ValueKey('sales-summary-transactions'),
      'Transactions: 1',
    );
    _expectMetric(
      tester,
      const ValueKey('sales-summary-items'),
      'Items sold: 2',
    );

    await tester.tap(find.byKey(const ValueKey('sales-period-sevenDays')));
    await tester.pumpAndSettle();

    expect(find.text('Today coffee'), findsOneWidget);
    expect(find.text('Month noodles'), findsOneWidget);
    expect(find.text('August soap'), findsOneWidget);
    expect(find.text('Older rice'), findsNothing);
    _expectMetric(
      tester,
      const ValueKey('sales-summary-revenue'),
      'Revenue: ₱60.00',
    );
    _expectMetric(
      tester,
      const ValueKey('sales-summary-transactions'),
      'Transactions: 3',
    );

    await tester.tap(find.byKey(const ValueKey('sales-period-thisMonth')));
    await tester.pumpAndSettle();

    expect(find.text('Today coffee'), findsOneWidget);
    expect(find.text('Month noodles'), findsOneWidget);
    expect(find.text('August soap'), findsNothing);
    _expectMetric(
      tester,
      const ValueKey('sales-summary-revenue'),
      'Revenue: ₱40.00',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Custom opens a date picker and applies inclusive dates', (
    tester,
  ) async {
    _useView(tester, const Size(800, 1000));
    final repository = _FakeSalesRepository([
      _sale(
        id: 'september-1',
        name: 'September one',
        completedAt: DateTime(2026, 9, 1, 23, 59),
        unitPriceCentavos: 1000,
      ),
      _sale(
        id: 'september-2',
        name: 'September two',
        completedAt: DateTime(2026, 9, 2, 8),
        unitPriceCentavos: 2000,
      ),
      _sale(
        id: 'september-3',
        name: 'September three',
        completedAt: DateTime(2026, 9, 3, 8),
        unitPriceCentavos: 3000,
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [salesRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          theme: AppTheme.light,
          home: SalesScreen(now: DateTime(2026, 9, 3, 12), onOpenSale: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('sales-period-custom')));
    await tester.pumpAndSettle();

    expect(find.text('Choose sales dates'), findsOneWidget);
    await tester.tap(
      find.bySemanticsLabel(RegExp(r'^1, .*September 1, 2026$')),
    );
    await tester.pump();
    await tester.tap(
      find.bySemanticsLabel(RegExp(r'^2, .*September 2, 2026$')),
    );
    await tester.pump();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(find.text('Sep 1 – Sep 2, 2026'), findsWidgets);
    expect(find.text('September one'), findsOneWidget);
    expect(find.text('September two'), findsOneWidget);
    expect(find.text('September three'), findsNothing);
    _expectMetric(
      tester,
      const ValueKey('sales-summary-transactions'),
      'Transactions: 2',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('history is newest-first, day-grouped, and lazily built', (
    tester,
  ) async {
    _useView(tester, const Size(390, 720));
    final now = DateTime(2026, 9, 3, 22);
    final sales = [
      for (var index = 0; index < 60; index++)
        _sale(
          id: 'sale-$index',
          name: 'Sale item $index',
          completedAt: now.subtract(Duration(minutes: index * 10)),
          unitPriceCentavos: 100 + index,
        ),
    ];
    final repository = _FakeSalesRepository(sales);
    CompletedSale? opened;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [salesRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          theme: AppTheme.light,
          home: SalesScreen(now: now, onOpenSale: (sale) => opened = sale),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Today'), findsWidgets);
    expect(find.byKey(const ValueKey('sales-history-sale-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('sales-history-sale-59')), findsNothing);
    expect(find.byKey(const ValueKey('sales-history-sale-10')), findsNothing);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('sales-history-sale-10')),
      280,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('sales-scroll-view')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.byKey(const ValueKey('sales-history-sale-10')));
    expect(opened?.id, 'sale-10');
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty history explains how sales will appear', (tester) async {
    _useView(tester, const Size(390, 720));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          salesRepositoryProvider.overrideWithValue(
            _FakeSalesRepository(const []),
          ),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const SalesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No sales yet'), findsOneWidget);
    expect(
      find.text('Completed checkouts will appear here automatically.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty period does not imply all history is empty', (
    tester,
  ) async {
    _useView(tester, const Size(390, 720));
    final repository = _FakeSalesRepository([
      _sale(
        id: 'older',
        name: 'Earlier sale',
        completedAt: DateTime(2026, 8, 1, 12),
        unitPriceCentavos: 1000,
      ),
    ]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [salesRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          theme: AppTheme.light,
          home: SalesScreen(now: DateTime(2026, 9, 3, 12)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No sales in this period'), findsOneWidget);
    expect(find.text('No sales yet'), findsNothing);
    expect(repository.unboundedHistoryWatchCount, 0);
  });
}

void _expectMetric(WidgetTester tester, Key key, String semanticLabel) {
  expect(find.byKey(key), findsOneWidget);
  expect(tester.getSemantics(find.byKey(key)).label, semanticLabel);
}

void _useView(WidgetTester tester, Size size) {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = size;
  addTearDown(tester.view.reset);
}

CompletedSale _sale({
  required String id,
  required String name,
  required DateTime completedAt,
  required int unitPriceCentavos,
  int quantity = 1,
}) {
  return CompletedSale(
    id: id,
    completedAt: completedAt,
    storeNameSnapshot: 'Aling Nena Store',
    storeAddressSnapshot: null,
    storeContactSnapshot: null,
    footerMessageSnapshot: 'Salamat po!',
    cashReceivedCentavos: null,
    lines: [
      CompletedSaleLine(
        position: 0,
        productId: id,
        sellingUnitId: null,
        barcode: null,
        nameSnapshot: name,
        brandSnapshot: null,
        unitLabelSnapshot: null,
        imagePathSnapshot: null,
        unitPrice: Money.fromCentavos(unitPriceCentavos),
        quantity: quantity,
      ),
    ],
  );
}

final class _FakeSalesRepository implements SalesRepository {
  _FakeSalesRepository(Iterable<CompletedSale> sales)
    : _sales = List<CompletedSale>.of(sales);

  final List<CompletedSale> _sales;
  int unboundedHistoryWatchCount = 0;

  List<CompletedSale> _matching(SalesDateRange? range) {
    final values = range == null
        ? [..._sales]
        : _sales.where((sale) => range.includes(sale.completedAt)).toList();
    values.sort((a, b) => b.completedAt.compareTo(a.completedAt));
    return values;
  }

  @override
  Stream<List<CompletedSale>> watchSales({SalesDateRange? range}) {
    if (range == null) unboundedHistoryWatchCount += 1;
    return Stream.value(_matching(range));
  }

  @override
  Future<List<CompletedSale>> getSales({SalesDateRange? range}) async =>
      _matching(range);

  @override
  Stream<DateTime?> watchOldestSaleDate() {
    if (_sales.isEmpty) return Stream.value(null);
    return Stream.value(
      _sales
          .map((sale) => sale.completedAt)
          .reduce((a, b) => a.isBefore(b) ? a : b),
    );
  }

  @override
  Stream<CompletedSale?> watchSale(String id) =>
      Stream.value(_sales.where((sale) => sale.id == id).firstOrNull);

  @override
  Future<CompletedSale?> getSale(String id) async =>
      _sales.where((sale) => sale.id == id).firstOrNull;

  @override
  Future<CompletedSale> completeCurrentCart({int? cashReceivedCentavos}) =>
      throw UnimplementedError();

  @override
  Future<void> deleteSale(String id) async {
    _sales.removeWhere((sale) => sale.id == id);
  }

  @override
  Future<void> deleteSales(Iterable<String> ids) async {
    final selected = ids.toSet();
    _sales.removeWhere((sale) => selected.contains(sale.id));
  }
}

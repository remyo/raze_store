import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/core/money/money.dart';
import 'package:raze_store/features/receipt/domain/receipt_draft.dart';
import 'package:raze_store/features/sales/application/sales_providers.dart';
import 'package:raze_store/features/sales/domain/completed_sale.dart';
import 'package:raze_store/features/sales/domain/sales_date_range.dart';
import 'package:raze_store/features/sales/domain/sales_repository.dart';
import 'package:raze_store/features/sales/presentation/sale_detail_screen.dart';

void main() {
  testWidgets('shows captured lines, payment, and the saved receipt snapshot', (
    tester,
  ) async {
    _useTallView(tester);
    final sale = _sale();
    final repository = _FakeSalesRepository(sale);
    ReceiptDraft? openedReceipt;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [salesRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          theme: AppTheme.light,
          home: SaleDetailScreen(
            saleId: sale.id,
            initialSale: sale,
            onOpenReceipt: (draft) => openedReceipt = draft,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('₱84.50'), findsWidgets);
    expect(find.text('Canned sardines'), findsOneWidget);
    expect(find.text('Instant noodles'), findsOneWidget);
    expect(find.text('Mega · Sold as Can'), findsOneWidget);
    expect(find.text('₱23.50 × 2'), findsOneWidget);
    expect(find.text('Cash received'), findsOneWidget);
    expect(find.text('₱100.00'), findsOneWidget);
    expect(find.text('Change'), findsOneWidget);
    expect(find.text('₱15.50'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey('sale-detail-view-receipt')),
    );
    await tester.tap(find.byKey(const ValueKey('sale-detail-view-receipt')));

    expect(openedReceipt?.storeName, 'Original Store Name');
    expect(openedReceipt?.storeAddress, 'Original address');
    expect(openedReceipt?.footerMessage, 'Original thanks');
    expect(openedReceipt?.createdAt, sale.completedAt);
    expect(openedReceipt?.totalCentavos, 8450);
    expect(tester.takeException(), isNull);
  });

  testWidgets('requires confirmation and deletes only after approval', (
    tester,
  ) async {
    _useTallView(tester);
    final sale = _sale();
    final repository = _FakeSalesRepository(sale);
    var deletedCallbackCount = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [salesRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          theme: AppTheme.light,
          home: SaleDetailScreen(
            saleId: sale.id,
            initialSale: sale,
            onDeleted: () => deletedCallbackCount++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('sale-detail-delete')));
    await tester.pumpAndSettle();
    expect(find.text('Delete this sale?'), findsOneWidget);
    expect(
      find.textContaining('Products in your catalog will not be deleted'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('sale-delete-cancel')));
    await tester.pumpAndSettle();
    expect(repository.deletedIds, isEmpty);
    expect(deletedCallbackCount, 0);

    await tester.tap(find.byKey(const ValueKey('sale-detail-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sale-delete-confirm')));
    await tester.pumpAndSettle();

    expect(repository.deletedIds, [sale.id]);
    expect(deletedCallbackCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reports a failed delete and keeps the sale visible', (
    tester,
  ) async {
    _useTallView(tester);
    final sale = _sale();
    final repository = _FakeSalesRepository(sale, failDelete: true);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [salesRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          theme: AppTheme.light,
          home: SaleDetailScreen(saleId: sale.id, initialSale: sale),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('sale-detail-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sale-delete-confirm')));
    await tester.pumpAndSettle();

    expect(
      find.text('Could not delete this sale. Please try again.'),
      findsOneWidget,
    );
    expect(find.text('Canned sardines'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('drops the initial snapshot after live null or error resolves', (
    tester,
  ) async {
    _useTallView(tester);
    final sale = _sale();
    final liveSale = StreamController<CompletedSale?>();
    addTearDown(liveSale.close);
    final repository = _FakeSalesRepository(sale, watchedSale: liveSale.stream);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [salesRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          theme: AppTheme.light,
          home: SaleDetailScreen(saleId: sale.id, initialSale: sale),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Canned sardines'), findsOneWidget);

    liveSale.add(null);
    await tester.pumpAndSettle();
    expect(find.text('Sale not found'), findsOneWidget);
    expect(find.text('Canned sardines'), findsNothing);

    liveSale.addError(StateError('database unavailable'));
    await tester.pumpAndSettle();
    expect(find.text('This sale could not be loaded.'), findsOneWidget);
    expect(find.text('Canned sardines'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

void _useTallView(WidgetTester tester) {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = const Size(430, 1000);
  addTearDown(tester.view.reset);
}

CompletedSale _sale() {
  return CompletedSale(
    id: 'sale-2026-09-03',
    completedAt: DateTime(2026, 9, 3, 19, 30),
    storeNameSnapshot: 'Original Store Name',
    storeAddressSnapshot: 'Original address',
    storeContactSnapshot: '0912 345 6789',
    footerMessageSnapshot: 'Original thanks',
    cashReceivedCentavos: 10000,
    lines: [
      const CompletedSaleLine(
        position: 0,
        productId: 'sardines',
        sellingUnitId: null,
        barcode: '4801234567890',
        nameSnapshot: 'Canned sardines',
        brandSnapshot: 'Mega',
        unitLabelSnapshot: 'Can',
        imagePathSnapshot: null,
        unitPrice: Money.fromCentavos(2350),
        quantity: 2,
      ),
      const CompletedSaleLine(
        position: 1,
        productId: 'noodles',
        sellingUnitId: null,
        barcode: null,
        nameSnapshot: 'Instant noodles',
        brandSnapshot: null,
        unitLabelSnapshot: null,
        imagePathSnapshot: null,
        unitPrice: Money.fromCentavos(1250),
        quantity: 3,
      ),
    ],
  );
}

final class _FakeSalesRepository implements SalesRepository {
  _FakeSalesRepository(
    CompletedSale sale, {
    this.failDelete = false,
    this.watchedSale,
  }) : _sale = sale;

  CompletedSale? _sale;
  final bool failDelete;
  final Stream<CompletedSale?>? watchedSale;
  final List<String> deletedIds = [];

  @override
  Stream<CompletedSale?> watchSale(String id) =>
      watchedSale ?? Stream.value(_sale?.id == id ? _sale : null);

  @override
  Future<CompletedSale?> getSale(String id) async =>
      _sale?.id == id ? _sale : null;

  @override
  Stream<List<CompletedSale>> watchSales({SalesDateRange? range}) =>
      Stream.value(_sale == null ? const [] : [_sale!]);

  @override
  Future<List<CompletedSale>> getSales({SalesDateRange? range}) async =>
      _sale == null ? const [] : [_sale!];

  @override
  Stream<DateTime?> watchOldestSaleDate() => Stream.value(_sale?.completedAt);

  @override
  Future<CompletedSale> completeCurrentCart({int? cashReceivedCentavos}) =>
      throw UnimplementedError();

  @override
  Future<void> deleteSale(String id) async {
    if (failDelete) throw StateError('delete failed');
    deletedIds.add(id);
    _sale = null;
  }

  @override
  Future<void> deleteSales(Iterable<String> ids) async {
    for (final id in ids) {
      await deleteSale(id);
    }
  }
}

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart' as database;
import '../../../core/money/money.dart';
import '../domain/completed_sale.dart';
import '../domain/sales_date_range.dart';
import '../domain/sales_repository.dart';

final class LocalSalesRepository implements SalesRepository {
  LocalSalesRepository(
    this._database, {
    Uuid uuid = const Uuid(),
    DateTime Function()? now,
  }) : _uuid = uuid,
       _now = now ?? DateTime.now;

  final database.AppDatabase _database;
  final Uuid _uuid;
  final DateTime Function() _now;
  static const _hydrationChunkSize = 400;

  @override
  Stream<List<CompletedSale>> watchSales({SalesDateRange? range}) {
    return _salesQuery(range).watch().asyncMap(_hydrateSales);
  }

  @override
  Future<List<CompletedSale>> getSales({SalesDateRange? range}) async {
    return _hydrateSales(await _salesQuery(range).get());
  }

  @override
  Stream<DateTime?> watchOldestSaleDate() {
    final query = _database.select(_database.sales)
      ..orderBy([
        (table) => OrderingTerm.asc(table.completedAt),
        (table) => OrderingTerm.asc(table.id),
      ])
      ..limit(1);
    return query.watchSingleOrNull().map((row) => row?.completedAt.toUtc());
  }

  @override
  Stream<CompletedSale?> watchSale(String id) {
    final normalizedId = _requiredId(id);
    final query = _database.select(_database.sales)
      ..where((table) => table.id.equals(normalizedId));
    return query.watchSingleOrNull().asyncMap((row) async {
      if (row == null) return null;
      return _hydrateSale(row);
    });
  }

  @override
  Future<CompletedSale?> getSale(String id) async {
    final normalizedId = _requiredId(id);
    final row = await (_database.select(
      _database.sales,
    )..where((table) => table.id.equals(normalizedId))).getSingleOrNull();
    return row == null ? null : _hydrateSale(row);
  }

  @override
  Future<CompletedSale> completeCurrentCart({int? cashReceivedCentavos}) async {
    if (cashReceivedCentavos != null && cashReceivedCentavos < 0) {
      throw ArgumentError.value(
        cashReceivedCentavos,
        'cashReceivedCentavos',
        'Must not be negative.',
      );
    }

    return _database.transaction(() async {
      final cartRows =
          await (_database.select(_database.draftCartItems)..orderBy([
                (table) => OrderingTerm.asc(table.addedAt),
                (table) => OrderingTerm.asc(table.lineId),
              ]))
              .get();
      if (cartRows.isEmpty) throw const EmptyCartSaleException();

      final profile = await (_database.select(
        _database.storeProfiles,
      )..where((table) => table.id.equals(1))).getSingleOrNull();
      final saleId = _uuid.v4();
      final completedAt = _now().toUtc();
      final storeName = _nonBlankOrDefault(
        profile?.storeName,
        fallback: 'Raze Store',
      );
      final storeAddress = _nullIfBlank(profile?.address);
      final storeContact = _nullIfBlank(profile?.contact);
      final footerMessage = _nullIfBlank(profile?.receiptFooter);

      await _database
          .into(_database.sales)
          .insert(
            database.SalesCompanion.insert(
              id: saleId,
              completedAt: completedAt,
              storeNameSnapshot: storeName,
              storeAddressSnapshot: Value(storeAddress),
              storeContactSnapshot: Value(storeContact),
              footerMessageSnapshot: Value(footerMessage),
              cashReceivedCentavos: Value(cashReceivedCentavos),
            ),
          );

      final lines = <CompletedSaleLine>[];
      for (final entry in cartRows.indexed) {
        final position = entry.$1;
        final row = entry.$2;
        // Catalog images remain catalog-owned. Retaining their file paths here
        // would make history break when a product photo is replaced, while
        // copying a photo for every checkout would grow storage indefinitely.
        // Receipts and sale totals use the immutable text/price snapshots.
        await _database
            .into(_database.saleLines)
            .insert(
              database.SaleLinesCompanion.insert(
                saleId: saleId,
                position: position,
                productIdSnapshot: Value(_nullIfBlank(row.productId)),
                sellingUnitIdSnapshot: Value(_nullIfBlank(row.sellingUnitId)),
                barcodeSnapshot: Value(_nullIfBlank(row.barcode)),
                nameSnapshot: row.nameSnapshot,
                brandSnapshot: Value(_nullIfBlank(row.brandSnapshot)),
                unitLabelSnapshot: Value(_nullIfBlank(row.unitLabelSnapshot)),
                imagePathSnapshot: const Value(null),
                unitPriceCentavos: row.unitPriceCentavos,
                quantity: row.quantity,
              ),
            );
        lines.add(
          CompletedSaleLine(
            position: position,
            productId: _nullIfBlank(row.productId),
            sellingUnitId: _nullIfBlank(row.sellingUnitId),
            barcode: _nullIfBlank(row.barcode),
            nameSnapshot: row.nameSnapshot,
            brandSnapshot: _nullIfBlank(row.brandSnapshot),
            unitLabelSnapshot: _nullIfBlank(row.unitLabelSnapshot),
            imagePathSnapshot: null,
            unitPrice: Money.fromCentavos(row.unitPriceCentavos),
            quantity: row.quantity,
          ),
        );
      }

      await _database.delete(_database.draftCartItems).go();

      return CompletedSale(
        id: saleId,
        completedAt: completedAt,
        storeNameSnapshot: storeName,
        storeAddressSnapshot: storeAddress,
        storeContactSnapshot: storeContact,
        footerMessageSnapshot: footerMessage,
        lines: lines,
        cashReceivedCentavos: cashReceivedCentavos,
      );
    });
  }

  @override
  Future<void> deleteSale(String id) => deleteSales([id]);

  @override
  Future<void> deleteSales(Iterable<String> ids) async {
    final normalizedIds = ids.map(_requiredId).toSet().toList(growable: false);
    if (normalizedIds.isEmpty) return;
    await _database.transaction(() async {
      // Keep each `IN` expression below SQLite parameter limits. Select-all on
      // a wide range can include thousands of transactions.
      for (
        var start = 0;
        start < normalizedIds.length;
        start += _hydrationChunkSize
      ) {
        final end = (start + _hydrationChunkSize).clamp(
          0,
          normalizedIds.length,
        );
        final chunk = normalizedIds.sublist(start, end);
        // Delete children explicitly as well as relying on ON DELETE CASCADE
        // so this remains deterministic for custom test executors.
        await (_database.delete(
          _database.saleLines,
        )..where((table) => table.saleId.isIn(chunk))).go();
        await (_database.delete(
          _database.sales,
        )..where((table) => table.id.isIn(chunk))).go();
      }
    });
  }

  SimpleSelectStatement<database.$SalesTable, database.Sale> _salesQuery(
    SalesDateRange? range,
  ) {
    final query = _database.select(_database.sales);
    if (range != null) {
      query.where(
        (table) =>
            table.completedAt.isBiggerOrEqualValue(range.startInclusive) &
            table.completedAt.isSmallerThanValue(range.endExclusive),
      );
    }
    query.orderBy([
      (table) => OrderingTerm.desc(table.completedAt),
      (table) => OrderingTerm.desc(table.id),
    ]);
    return query;
  }

  Future<List<CompletedSale>> _hydrateSales(List<database.Sale> rows) async {
    if (rows.isEmpty) return const [];
    final saleIds = rows.map((row) => row.id).toList(growable: false);
    final linesBySale = <String, List<database.SaleLine>>{};
    // Keep each `IN` expression comfortably below SQLite parameter limits.
    // This matters for a busy store or a wide custom date range.
    for (var start = 0; start < saleIds.length; start += _hydrationChunkSize) {
      final end = (start + _hydrationChunkSize).clamp(0, saleIds.length);
      final chunk = saleIds.sublist(start, end);
      final lineRows =
          await (_database.select(_database.saleLines)
                ..where((table) => table.saleId.isIn(chunk))
                ..orderBy([
                  (table) => OrderingTerm.asc(table.saleId),
                  (table) => OrderingTerm.asc(table.position),
                ]))
              .get();
      for (final line in lineRows) {
        (linesBySale[line.saleId] ??= []).add(line);
      }
    }
    return [
      for (final row in rows)
        _mapSale(row, linesBySale[row.id] ?? const <database.SaleLine>[]),
    ];
  }

  Future<CompletedSale> _hydrateSale(database.Sale row) async {
    final lines =
        await (_database.select(_database.saleLines)
              ..where((table) => table.saleId.equals(row.id))
              ..orderBy([(table) => OrderingTerm.asc(table.position)]))
            .get();
    return _mapSale(row, lines);
  }

  CompletedSale _mapSale(database.Sale sale, List<database.SaleLine> lines) {
    if (lines.isEmpty) {
      throw StateError('Completed sale ${sale.id} has no line snapshots.');
    }
    return CompletedSale(
      id: sale.id,
      completedAt: sale.completedAt.toUtc(),
      storeNameSnapshot: sale.storeNameSnapshot,
      storeAddressSnapshot: sale.storeAddressSnapshot,
      storeContactSnapshot: sale.storeContactSnapshot,
      footerMessageSnapshot: sale.footerMessageSnapshot,
      cashReceivedCentavos: sale.cashReceivedCentavos,
      lines: [for (final line in lines) _mapLine(line)],
    );
  }

  CompletedSaleLine _mapLine(database.SaleLine line) {
    return CompletedSaleLine(
      position: line.position,
      productId: line.productIdSnapshot,
      sellingUnitId: line.sellingUnitIdSnapshot,
      barcode: line.barcodeSnapshot,
      nameSnapshot: line.nameSnapshot,
      brandSnapshot: line.brandSnapshot,
      unitLabelSnapshot: line.unitLabelSnapshot,
      imagePathSnapshot: line.imagePathSnapshot,
      unitPrice: Money.fromCentavos(line.unitPriceCentavos),
      quantity: line.quantity,
    );
  }

  String _requiredId(String id) {
    final normalized = id.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(id, 'id', 'Must not be blank.');
    }
    return normalized;
  }
}

String? _nullIfBlank(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

String _nonBlankOrDefault(String? value, {required String fallback}) {
  return _nullIfBlank(value) ?? fallback;
}

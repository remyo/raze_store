import 'completed_sale.dart';
import 'sales_date_range.dart';

abstract interface class SalesRepository {
  Stream<List<CompletedSale>> watchSales({SalesDateRange? range});

  Future<List<CompletedSale>> getSales({SalesDateRange? range});

  /// Watches only the oldest completion timestamp, without hydrating lines.
  ///
  /// The sales screen uses this cheap query for its empty state and custom
  /// date-picker boundary instead of loading the store's entire history.
  Stream<DateTime?> watchOldestSaleDate();

  Stream<CompletedSale?> watchSale(String id);

  Future<CompletedSale?> getSale(String id);

  /// Atomically snapshots the current cart and store profile, then clears it.
  Future<CompletedSale> completeCurrentCart({int? cashReceivedCentavos});

  Future<void> deleteSale(String id);

  Future<void> deleteSales(Iterable<String> ids);
}

final class EmptyCartSaleException implements Exception {
  const EmptyCartSaleException();

  @override
  String toString() => 'A sale cannot be completed from an empty cart.';
}

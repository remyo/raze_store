import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../data/local_sales_repository.dart';
import '../domain/completed_sale.dart';
import '../domain/sales_date_range.dart';
import '../domain/sales_repository.dart';

final salesRepositoryProvider = Provider<SalesRepository>((ref) {
  return LocalSalesRepository(ref.watch(appDatabaseProvider));
});

/// Oldest saved transaction date, queried without loading receipt lines.
final oldestSaleDateProvider = StreamProvider.autoDispose<DateTime?>((ref) {
  return ref.watch(salesRepositoryProvider).watchOldestSaleDate();
});

/// A database-filtered history stream for screens with an explicit range.
final salesHistoryForRangeProvider = StreamProvider.family
    .autoDispose<List<CompletedSale>, SalesDateRange>((ref, range) {
      return ref.watch(salesRepositoryProvider).watchSales(range: range);
    });

final completedSaleProvider = StreamProvider.family
    .autoDispose<CompletedSale?, String>((ref, id) {
      return ref.watch(salesRepositoryProvider).watchSale(id);
    });

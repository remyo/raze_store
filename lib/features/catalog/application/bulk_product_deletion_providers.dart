import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../../../core/storage/product_photo_services.dart';
import '../data/local_bulk_product_deletion_service.dart';
import '../domain/bulk_product_deletion.dart';
import '../domain/catalog_product.dart';
import 'catalog_providers.dart';

final bulkProductDeletionServiceProvider = Provider<BulkProductDeletionService>(
  (ref) {
    return LocalBulkProductDeletionService(
      ref.watch(appDatabaseProvider),
      ref.watch(localProductImageStoreProvider),
    );
  },
);

/// An independent query keeps this maintenance page from changing the search
/// text on Home while still letting the database do the filtering.
final bulkDeletionProductsProvider = StreamProvider.autoDispose
    .family<List<StoreProduct>, String>((ref, query) {
      return ref
          .watch(catalogRepositoryProvider)
          .watchProducts(query: query.trim());
    });

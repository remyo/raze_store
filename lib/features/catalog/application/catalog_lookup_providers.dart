import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'catalog_api_providers.dart';
import 'catalog_lookup_service.dart';
import 'catalog_providers.dart';

final catalogLookupServiceProvider = Provider<CatalogLookupService>((ref) {
  return CatalogLookupService(
    local: ref.watch(catalogRepositoryProvider),
    remote: ref.watch(remoteCatalogRepositoryProvider),
  );
});

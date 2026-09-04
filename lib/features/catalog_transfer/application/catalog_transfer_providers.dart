import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:raze_store/app/theme_mode_controller.dart';
import 'package:raze_store/core/database/database_provider.dart';
import 'package:raze_store/core/storage/product_photo_services.dart';
import 'package:raze_store/features/cart/application/cart_providers.dart';
import 'package:raze_store/features/catalog/application/catalog_providers.dart';
import 'package:raze_store/features/catalog/application/custom_catalog_categories_controller.dart';
import 'package:raze_store/features/catalog_transfer/application/catalog_transfer_coordinator.dart';
import 'package:raze_store/features/catalog_transfer/data/catalog_backup_service.dart';
import 'package:raze_store/features/catalog_transfer/data/catalog_csv_service.dart';
import 'package:raze_store/features/catalog_transfer/data/catalog_file_gateway.dart';
import 'package:raze_store/features/catalog_transfer/data/catalog_pack_service.dart';
import 'package:raze_store/features/onboarding/application/onboarding_providers.dart';
import 'package:raze_store/features/settings/application/settings_providers.dart';

final catalogFileGatewayProvider = Provider<CatalogFileGateway>((ref) {
  return const DeviceCatalogFileGateway();
});

final catalogBackupServiceProvider = Provider<CatalogBackupService>((ref) {
  return CatalogBackupService(
    database: ref.watch(appDatabaseProvider),
    imageStore: ref.watch(localProductImageStoreProvider),
    onRestoreCompleted: () async {
      ref.invalidate(catalogProductsProvider);
      ref.invalidate(cartDraftProvider);
      ref.invalidate(storeProfileProvider);
      ref.invalidate(themeModeProvider);
      ref.invalidate(appPreferencesProvider);
      ref.invalidate(customCatalogCategoriesProvider);
      ref.invalidate(onboardingControllerProvider);
      ref.invalidate(catalogPackUndoSummaryProvider);
    },
  );
});

final catalogCsvServiceProvider = Provider<CatalogCsvService>((ref) {
  return CatalogCsvService(ref.watch(appDatabaseProvider));
});

final catalogPackServiceProvider = Provider<CatalogPackService>((ref) {
  return CatalogPackService(
    database: ref.watch(appDatabaseProvider),
    imageStore: ref.watch(localProductImageStoreProvider),
    onImportCompleted: () async {
      ref.invalidate(catalogProductsProvider);
      ref.invalidate(catalogStoredCategoriesProvider);
    },
  );
});

final catalogTransferCoordinatorProvider = Provider<CatalogTransferOperations>(
  (ref) => CatalogTransferCoordinator(
    backupService: ref.watch(catalogBackupServiceProvider),
    packService: ref.watch(catalogPackServiceProvider),
    csvService: ref.watch(catalogCsvServiceProvider),
    fileGateway: ref.watch(catalogFileGatewayProvider),
  ),
);

final catalogPackReviewCoordinatorProvider =
    Provider<CatalogPackReviewOperations>(
      (ref) => CatalogPackReviewCoordinator(
        packService: ref.watch(catalogPackServiceProvider),
        fileGateway: ref.watch(catalogFileGatewayProvider),
      ),
    );

final catalogPackUndoSummaryProvider = FutureProvider((ref) {
  return ref
      .watch(catalogPackReviewCoordinatorProvider)
      .getLastCatalogImportUndo();
});

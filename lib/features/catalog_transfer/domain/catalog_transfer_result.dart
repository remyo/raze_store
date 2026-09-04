enum CatalogTransferAction {
  backupExport,
  backupRestore,
  catalogPackImport,
  catalogPackUndo,
  csvExport,
  csvImport,
}

/// Controls how an offline catalog pack handles products already on the
/// device. Neither mode deletes products that are absent from the pack.
enum CatalogPackImportMode {
  /// Add missing products while preserving confirmed store-owned values on
  /// matches. A suggested price may fill an existing zero main price.
  keepExisting,

  /// Add missing products and replace supported catalog fields on matches.
  /// Confirmed, nonzero store prices remain unchanged.
  overwriteMatching,
}

enum CatalogTransferFailureCode {
  unavailable,
  cancelled,
  sourceMissing,
  sourceOutsideManagedStorage,
  invalidFile,
  unsupportedVersion,
  unsafeArchive,
  integrityMismatch,
  archiveTooLarge,
  validationFailed,
  ioFailure,
  databaseFailure,
}

sealed class CatalogTransferResult {
  const CatalogTransferResult();

  String get message;
}

final class CatalogTransferSuccess extends CatalogTransferResult {
  const CatalogTransferSuccess({
    required this.action,
    required this.message,
    required this.productCount,
    this.sellingUnitCount = 0,
    this.photoCount = 0,
    this.path,
  });

  final CatalogTransferAction action;
  @override
  final String message;
  final int productCount;
  final int sellingUnitCount;
  final int photoCount;
  final String? path;
}

final class CatalogTransferCancelled extends CatalogTransferResult {
  const CatalogTransferCancelled({required this.message});

  @override
  final String message;
}

final class CatalogTransferFailure extends CatalogTransferResult {
  const CatalogTransferFailure({
    required this.code,
    required this.message,
    this.cause,
  });

  final CatalogTransferFailureCode code;
  @override
  final String message;
  final Object? cause;
}

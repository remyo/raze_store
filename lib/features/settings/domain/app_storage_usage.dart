/// A point-in-time measurement of files managed by Raze Store.
///
/// Receipt PNGs and catalog files exported through the system file picker are
/// outside the app's storage and are intentionally not represented here.
/// [temporaryReceiptBytes] covers only app-owned working copies created while
/// opening the file picker or system share sheet.
class AppStorageUsage {
  const AppStorageUsage({
    required this.databaseBytes,
    required this.productImageBytes,
    required this.temporaryReceiptBytes,
    required this.backgroundRemovalBytes,
    required this.cacheBytes,
    required this.measuredAt,
    this.databaseFileCount = 0,
    this.productImageFileCount = 0,
    this.temporaryReceiptFileCount = 0,
    this.backgroundRemovalFileCount = 0,
    this.cacheFileCount = 0,
    this.unreadableEntryCount = 0,
  }) : assert(databaseBytes >= 0),
       assert(productImageBytes >= 0),
       assert(temporaryReceiptBytes >= 0),
       assert(backgroundRemovalBytes >= 0),
       assert(cacheBytes >= 0),
       assert(databaseFileCount >= 0),
       assert(productImageFileCount >= 0),
       assert(temporaryReceiptFileCount >= 0),
       assert(backgroundRemovalFileCount >= 0),
       assert(cacheFileCount >= 0),
       assert(unreadableEntryCount >= 0);

  final int databaseBytes;
  final int productImageBytes;

  /// Receipt PNGs still inside app-owned temporary storage after an export.
  final int temporaryReceiptBytes;

  /// Working PNGs created by the on-device background-removal tool.
  final int backgroundRemovalBytes;

  /// Other files in app cache, including stale app-owned transfer staging.
  final int cacheBytes;
  final DateTime measuredAt;

  final int databaseFileCount;
  final int productImageFileCount;
  final int temporaryReceiptFileCount;
  final int backgroundRemovalFileCount;
  final int cacheFileCount;

  /// Entries that changed or could not be inspected during measurement.
  ///
  /// A non-zero value means the totals are a safe best effort. One directory
  /// resolver that could not be opened also counts as one unreadable entry.
  final int unreadableEntryCount;

  int get temporaryBytes =>
      temporaryReceiptBytes + backgroundRemovalBytes + cacheBytes;

  int get totalManagedBytes =>
      databaseBytes + productImageBytes + temporaryBytes;

  int get temporaryFileCount =>
      temporaryReceiptFileCount + backgroundRemovalFileCount + cacheFileCount;

  int get totalFileCount =>
      databaseFileCount + productImageFileCount + temporaryFileCount;
}

/// The result of deleting rebuildable files from app-owned temporary storage.
class AppStorageCleanupResult {
  const AppStorageCleanupResult({
    required this.clearedBytes,
    required this.clearedFileCount,
    required this.failureCount,
  }) : assert(clearedBytes >= 0),
       assert(clearedFileCount >= 0),
       assert(failureCount >= 0);

  final int clearedBytes;
  final int clearedFileCount;

  /// Entries that could not be measured or removed, or directory resolvers
  /// that were unavailable.
  final int failureCount;

  bool get completedWithoutFailures => failureCount == 0;
}

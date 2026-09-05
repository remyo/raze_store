import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:raze_store/core/storage/local_product_image_store.dart';
import 'package:raze_store/core/storage/product_photo_services.dart';
import 'package:raze_store/features/settings/domain/app_storage_usage.dart';

typedef StorageDirectoryResolver = Future<Directory> Function();
typedef StorageFileLengthReader = Future<int> Function(File file);

/// Measures storage that Raze Store can identify without inspecting user-owned
/// gallery or Files locations.
///
/// Resolvers and the length reader are injectable so tests can exercise the
/// filesystem behavior without platform channels. Every measurement is best
/// effort: an unavailable category does not hide the categories that remain
/// readable.
class AppStorageService {
  AppStorageService({
    StorageDirectoryResolver? documentsDirectoryResolver,
    StorageDirectoryResolver? supportDirectoryResolver,
    StorageDirectoryResolver? cacheDirectoryResolver,
    StorageDirectoryResolver? temporaryDirectoryResolver,
    StorageFileLengthReader? fileLengthReader,
    DateTime Function()? clock,
  }) : _documentsDirectoryResolver =
           documentsDirectoryResolver ?? getApplicationDocumentsDirectory,
       _supportDirectoryResolver =
           supportDirectoryResolver ?? getApplicationSupportDirectory,
       _cacheDirectoryResolver =
           cacheDirectoryResolver ?? getApplicationCacheDirectory,
       _temporaryDirectoryResolver =
           temporaryDirectoryResolver ?? getTemporaryDirectory,
       _fileLengthReader = fileLengthReader ?? _readFileLength,
       _clock = clock ?? DateTime.now;

  final StorageDirectoryResolver _documentsDirectoryResolver;
  final StorageDirectoryResolver _supportDirectoryResolver;
  final StorageDirectoryResolver _cacheDirectoryResolver;
  final StorageDirectoryResolver _temporaryDirectoryResolver;
  final StorageFileLengthReader _fileLengthReader;
  final DateTime Function() _clock;

  static const _databaseBaseNames = <String>['raze_store.sqlite'];
  static const _databaseSuffixes = <String>['', '-wal', '-shm', '-journal'];
  static final _temporaryReceiptFileName = RegExp(
    r'^(?:\d+-)?raze-store-receipt-\d{8}-\d{6}\.png$',
    caseSensitive: false,
  );
  static const _receiptExportTemporaryDirectoryName = 'raze_store_receipts';
  static final _shareTemporaryDirectoryName = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  static const _ownedTemporaryDirectoryPrefixes = <String>[
    'raze_store_gcash_',
    'raze_store_transfer_',
    'raze_store_export_',
    'raze_store_restore_',
    'raze_store_pack_',
  ];

  Future<AppStorageUsage> loadUsage() async {
    final documentsFuture = _resolveDirectory(_documentsDirectoryResolver);
    final supportFuture = _resolveDirectory(_supportDirectoryResolver);
    final cacheFuture = _resolveDirectory(_cacheDirectoryResolver);
    final temporaryFuture = _resolveDirectory(_temporaryDirectoryResolver);

    final documents = await documentsFuture;
    final support = await supportFuture;
    final cache = await cacheFuture;
    final temporary = await temporaryFuture;

    final productImagesFuture = support.directory == null
        ? Future.value(const _MeasuredStorage())
        : _measureDirectory(
            Directory(
              p.join(
                support.directory!.path,
                LocalProductImageStore.directoryName,
              ),
            ),
          );
    final databaseFuture = documents.directory == null
        ? Future.value(const _MeasuredStorage())
        : _measureDatabases(documents.directory!);
    final temporaryStorageFuture = _measureTemporaryStorage(
      cacheDirectory: cache.directory,
      temporaryDirectory: temporary.directory,
    );

    final productImages = await productImagesFuture;
    final databases = await databaseFuture;
    final temporaryStorage = await temporaryStorageFuture;
    final resolverFailures =
        documents.failureCount +
        support.failureCount +
        cache.failureCount +
        temporary.failureCount;

    return AppStorageUsage(
      databaseBytes: databases.bytes,
      productImageBytes: productImages.bytes,
      temporaryReceiptBytes: temporaryStorage.receipts.bytes,
      backgroundRemovalBytes: temporaryStorage.backgroundRemoval.bytes,
      cacheBytes: temporaryStorage.cache.bytes,
      measuredAt: _clock(),
      databaseFileCount: databases.fileCount,
      productImageFileCount: productImages.fileCount,
      temporaryReceiptFileCount: temporaryStorage.receipts.fileCount,
      backgroundRemovalFileCount: temporaryStorage.backgroundRemoval.fileCount,
      cacheFileCount: temporaryStorage.cache.fileCount,
      unreadableEntryCount:
          resolverFailures +
          databases.unreadableEntryCount +
          productImages.unreadableEntryCount +
          temporaryStorage.unreadableEntryCount,
    );
  }

  /// Deletes the app cache and only explicitly app-owned entries elsewhere in
  /// the platform temporary directory.
  ///
  /// On desktop platforms `getTemporaryDirectory()` may return a shared user
  /// directory such as `/tmp`. This method never clears that root wholesale;
  /// it selects only Raze Store background-removal/transfer directories and
  /// exact receipt files created by the export flow. Database files, durable
  /// product images, and user-selected Files exports are never candidates.
  Future<AppStorageCleanupResult> clearTemporaryFiles() async {
    final cacheFuture = _resolveDirectory(_cacheDirectoryResolver);
    final temporaryFuture = _resolveDirectory(_temporaryDirectoryResolver);
    final cache = await cacheFuture;
    final temporary = await temporaryFuture;
    var failureCount = cache.failureCount + temporary.failureCount;

    final protectedPaths = {
      if (cache.directory != null) _normalizedPath(cache.directory!),
      if (temporary.directory != null) _normalizedPath(temporary.directory!),
    };
    final files = <String, File>{};
    final links = <String, Link>{};
    final directories = <String, Directory>{};

    final cacheDirectory = cache.directory;
    if (cacheDirectory != null) {
      failureCount += await _discoverDirectoryContents(
        cacheDirectory,
        files: files,
        links: links,
        directories: directories,
      );
    }

    final temporaryDirectory = temporary.directory;
    if (temporaryDirectory != null &&
        !_directoryCovers(cacheDirectory, temporaryDirectory)) {
      failureCount += await _discoverOwnedTemporaryEntries(
        temporaryDirectory,
        alreadyCoveredBy: cacheDirectory,
        files: files,
        links: links,
        directories: directories,
      );
    }

    var clearedBytes = 0;
    var clearedFileCount = 0;
    for (final file in files.values) {
      var length = 0;
      var entryFailed = false;
      try {
        final measuredLength = await _fileLengthReader(file);
        if (measuredLength >= 0) {
          length = measuredLength;
        } else {
          entryFailed = true;
        }
      } catch (_) {
        entryFailed = true;
      }

      try {
        await file.delete();
        clearedBytes += length;
        clearedFileCount += 1;
      } catch (_) {
        entryFailed = true;
      }
      if (entryFailed) failureCount += 1;
    }

    for (final link in links.values) {
      try {
        await link.delete();
      } catch (_) {
        failureCount += 1;
      }
    }

    final emptyDirectoryCandidates = directories.entries.toList()
      ..sort((a, b) => b.key.length.compareTo(a.key.length));
    for (final entry in emptyDirectoryCandidates) {
      if (protectedPaths.contains(entry.key)) continue;
      try {
        if (await entry.value.list(followLinks: false).isEmpty) {
          await entry.value.delete();
        }
      } catch (_) {
        // A changing or locked directory does not prevent other cleanup.
        failureCount += 1;
      }
    }

    return AppStorageCleanupResult(
      clearedBytes: clearedBytes,
      clearedFileCount: clearedFileCount,
      failureCount: failureCount,
    );
  }

  Future<_ResolvedDirectory> _resolveDirectory(
    StorageDirectoryResolver resolver,
  ) async {
    try {
      return _ResolvedDirectory(directory: await resolver());
    } catch (_) {
      return const _ResolvedDirectory(failureCount: 1);
    }
  }

  Future<_MeasuredStorage> _measureDatabases(Directory directory) async {
    var result = const _MeasuredStorage();
    for (final baseName in _databaseBaseNames) {
      for (final suffix in _databaseSuffixes) {
        result += await _measureFile(
          File(p.join(directory.path, '$baseName$suffix')),
        );
      }
    }
    return result;
  }

  Future<_TemporaryStorageMeasurement> _measureTemporaryStorage({
    required Directory? cacheDirectory,
    required Directory? temporaryDirectory,
  }) async {
    final backgroundRemovalDirectory = temporaryDirectory == null
        ? null
        : Directory(
            p.join(
              temporaryDirectory.path,
              OnDeviceProductBackgroundRemover.directoryName,
            ),
          );
    final cacheFuture = cacheDirectory == null
        ? Future.value(const _TemporaryStorageMeasurement.empty())
        : _measureCacheDirectory(
            cacheDirectory,
            backgroundRemovalDirectory: backgroundRemovalDirectory,
          );
    final ownedTemporaryFuture =
        temporaryDirectory == null ||
            _directoryCovers(cacheDirectory, temporaryDirectory)
        ? Future.value(const _TemporaryStorageMeasurement.empty())
        : _measureOwnedTemporaryEntries(
            temporaryDirectory,
            alreadyCoveredBy: cacheDirectory,
          );

    final cache = await cacheFuture;
    final ownedTemporary = await ownedTemporaryFuture;
    return cache + ownedTemporary;
  }

  Future<_TemporaryStorageMeasurement> _measureCacheDirectory(
    Directory directory, {
    required Directory? backgroundRemovalDirectory,
  }) async {
    var receipts = const _MeasuredStorage();
    var backgroundRemoval = const _MeasuredStorage();
    var cache = const _MeasuredStorage();
    var unreadableEntryCount = 0;

    try {
      if (await directory.exists()) {
        await for (final entity in directory.list(
          recursive: true,
          followLinks: false,
        )) {
          if (entity is! File) continue;
          final path = _normalizedPath(entity);
          final measured = await _measureFile(entity);
          if (backgroundRemovalDirectory != null &&
              _isAtOrWithin(
                _normalizedPath(backgroundRemovalDirectory),
                path,
              )) {
            backgroundRemoval += measured;
          } else if (_temporaryReceiptFileName.hasMatch(p.basename(path))) {
            receipts += measured;
          } else {
            cache += measured;
          }
        }
      }
    } catch (_) {
      unreadableEntryCount += 1;
    }

    return _TemporaryStorageMeasurement(
      receipts: receipts,
      backgroundRemoval: backgroundRemoval,
      cache: cache,
      unreadableEntryCount:
          unreadableEntryCount +
          receipts.unreadableEntryCount +
          backgroundRemoval.unreadableEntryCount +
          cache.unreadableEntryCount,
    );
  }

  Future<_TemporaryStorageMeasurement> _measureOwnedTemporaryEntries(
    Directory temporaryDirectory, {
    required Directory? alreadyCoveredBy,
  }) async {
    var receipts = const _MeasuredStorage();
    var backgroundRemoval = const _MeasuredStorage();
    var cache = const _MeasuredStorage();
    var unreadableEntryCount = 0;

    try {
      if (!await temporaryDirectory.exists()) {
        return const _TemporaryStorageMeasurement.empty();
      }
      await for (final entity in temporaryDirectory.list(followLinks: false)) {
        if (entity is! Directory) continue;
        final entityPath = _normalizedPath(entity);
        if (alreadyCoveredBy != null &&
            _isAtOrWithin(_normalizedPath(alreadyCoveredBy), entityPath)) {
          continue;
        }

        final name = p.basename(entityPath);
        if (name == OnDeviceProductBackgroundRemover.directoryName) {
          backgroundRemoval += await _measureDirectory(entity);
        } else if (_isOwnedTransferDirectoryName(name)) {
          cache += await _measureDirectory(entity);
        } else if (name == _receiptExportTemporaryDirectoryName ||
            _shareTemporaryDirectoryName.hasMatch(name)) {
          receipts += await _measureTemporaryReceiptsIn(entity);
        }
      }
    } catch (_) {
      unreadableEntryCount += 1;
    }

    return _TemporaryStorageMeasurement(
      receipts: receipts,
      backgroundRemoval: backgroundRemoval,
      cache: cache,
      unreadableEntryCount:
          unreadableEntryCount +
          receipts.unreadableEntryCount +
          backgroundRemoval.unreadableEntryCount +
          cache.unreadableEntryCount,
    );
  }

  Future<_MeasuredStorage> _measureTemporaryReceiptsIn(
    Directory shareDirectory,
  ) async {
    var result = const _MeasuredStorage();
    try {
      await for (final entity in shareDirectory.list(followLinks: false)) {
        if (entity is File &&
            _temporaryReceiptFileName.hasMatch(p.basename(entity.path))) {
          result += await _measureFile(entity);
        }
      }
    } catch (_) {
      result += const _MeasuredStorage(unreadableEntryCount: 1);
    }
    return result;
  }

  Future<int> _discoverDirectoryContents(
    Directory root, {
    required Map<String, File> files,
    required Map<String, Link> links,
    required Map<String, Directory> directories,
  }) async {
    try {
      if (!await root.exists()) return 0;
      await for (final entity in root.list(
        recursive: true,
        followLinks: false,
      )) {
        final path = _normalizedPath(entity);
        if (entity is File) {
          files[path] = entity;
        } else if (entity is Link) {
          links[path] = entity;
        } else if (entity is Directory) {
          directories[path] = entity;
        }
      }
      return 0;
    } catch (_) {
      return 1;
    }
  }

  Future<int> _discoverOwnedTemporaryEntries(
    Directory temporaryDirectory, {
    required Directory? alreadyCoveredBy,
    required Map<String, File> files,
    required Map<String, Link> links,
    required Map<String, Directory> directories,
  }) async {
    var failureCount = 0;
    try {
      if (!await temporaryDirectory.exists()) return 0;
      await for (final entity in temporaryDirectory.list(followLinks: false)) {
        if (entity is! Directory) continue;
        final entityPath = _normalizedPath(entity);
        if (alreadyCoveredBy != null &&
            _isAtOrWithin(_normalizedPath(alreadyCoveredBy), entityPath)) {
          continue;
        }

        final name = p.basename(entityPath);
        if (name == OnDeviceProductBackgroundRemover.directoryName ||
            _isOwnedTransferDirectoryName(name)) {
          directories[entityPath] = entity;
          failureCount += await _discoverDirectoryContents(
            entity,
            files: files,
            links: links,
            directories: directories,
          );
        } else if (name == _receiptExportTemporaryDirectoryName ||
            _shareTemporaryDirectoryName.hasMatch(name)) {
          var foundReceipt = false;
          try {
            await for (final candidate in entity.list(followLinks: false)) {
              if (candidate is! File ||
                  !_temporaryReceiptFileName.hasMatch(
                    p.basename(candidate.path),
                  )) {
                continue;
              }
              files[_normalizedPath(candidate)] = candidate;
              foundReceipt = true;
            }
          } catch (_) {
            failureCount += 1;
          }
          if (foundReceipt) directories[entityPath] = entity;
        }
      }
    } catch (_) {
      failureCount += 1;
    }
    return failureCount;
  }

  Future<_MeasuredStorage> _measureDirectory(Directory directory) async {
    try {
      if (!await directory.exists()) return const _MeasuredStorage();
    } catch (_) {
      return const _MeasuredStorage(unreadableEntryCount: 1);
    }

    var result = const _MeasuredStorage();
    try {
      await for (final entity in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) result += await _measureFile(entity);
      }
    } catch (_) {
      result += const _MeasuredStorage(unreadableEntryCount: 1);
    }
    return result;
  }

  Future<_MeasuredStorage> _measureFile(File file) async {
    try {
      final type = await FileSystemEntity.type(file.path, followLinks: false);
      if (type == FileSystemEntityType.notFound) {
        return const _MeasuredStorage();
      }
      if (type != FileSystemEntityType.file) {
        return const _MeasuredStorage();
      }
      final length = await _fileLengthReader(file);
      if (length < 0) {
        return const _MeasuredStorage(unreadableEntryCount: 1);
      }
      return _MeasuredStorage(bytes: length, fileCount: 1);
    } catch (_) {
      return const _MeasuredStorage(unreadableEntryCount: 1);
    }
  }

  static bool _directoryCovers(Directory? root, Directory candidate) =>
      root != null &&
      _isAtOrWithin(_normalizedPath(root), _normalizedPath(candidate));

  static bool _isOwnedTransferDirectoryName(String name) =>
      _ownedTemporaryDirectoryPrefixes.any(name.startsWith);

  static bool _isAtOrWithin(String root, String candidate) =>
      p.equals(root, candidate) || p.isWithin(root, candidate);

  static String _normalizedPath(FileSystemEntity entity) =>
      p.normalize(entity.absolute.path);

  static Future<int> _readFileLength(File file) => file.length();
}

class _ResolvedDirectory {
  const _ResolvedDirectory({this.directory, this.failureCount = 0});

  final Directory? directory;
  final int failureCount;
}

class _MeasuredStorage {
  const _MeasuredStorage({
    this.bytes = 0,
    this.fileCount = 0,
    this.unreadableEntryCount = 0,
  });

  final int bytes;
  final int fileCount;
  final int unreadableEntryCount;

  _MeasuredStorage operator +(_MeasuredStorage other) => _MeasuredStorage(
    bytes: bytes + other.bytes,
    fileCount: fileCount + other.fileCount,
    unreadableEntryCount: unreadableEntryCount + other.unreadableEntryCount,
  );
}

class _TemporaryStorageMeasurement {
  const _TemporaryStorageMeasurement({
    required this.receipts,
    required this.backgroundRemoval,
    required this.cache,
    required this.unreadableEntryCount,
  });

  const _TemporaryStorageMeasurement.empty()
    : receipts = const _MeasuredStorage(),
      backgroundRemoval = const _MeasuredStorage(),
      cache = const _MeasuredStorage(),
      unreadableEntryCount = 0;

  final _MeasuredStorage receipts;
  final _MeasuredStorage backgroundRemoval;
  final _MeasuredStorage cache;
  final int unreadableEntryCount;

  _TemporaryStorageMeasurement operator +(_TemporaryStorageMeasurement other) =>
      _TemporaryStorageMeasurement(
        receipts: receipts + other.receipts,
        backgroundRemoval: backgroundRemoval + other.backgroundRemoval,
        cache: cache + other.cache,
        unreadableEntryCount: unreadableEntryCount + other.unreadableEntryCount,
      );
}

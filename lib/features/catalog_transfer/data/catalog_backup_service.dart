import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:raze_store/core/barcode/barcode.dart';
import 'package:raze_store/core/database/app_database.dart' as database;
import 'package:raze_store/core/storage/local_product_image_store.dart';
import 'package:raze_store/features/catalog_transfer/domain/catalog_transfer_result.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

typedef CatalogRestoreRefresh = Future<void> Function();
typedef BackupTemporaryDirectoryFactory =
    Future<Directory> Function(String prefix);

final RegExp _portablePhotoPattern = RegExp(
  r'^photos/[a-f0-9]{28}\.[a-z0-9]{1,8}$',
);

/// Creates and restores a complete, offline Raze Store catalog archive.
///
/// The archive is a versioned ZIP with a checksummed manifest. Restore fully
/// validates and stages the archive before replacing any database rows.
final class CatalogBackupService {
  CatalogBackupService({
    required database.AppDatabase database,
    required LocalProductImageStore imageStore,
    CatalogRestoreRefresh? onRestoreCompleted,
    BackupTemporaryDirectoryFactory? temporaryDirectoryFactory,
    Future<SharedPreferences> Function()? preferencesFactory,
    Uuid uuid = const Uuid(),
  }) : _database = database,
       _imageStore = imageStore,
       _onRestoreCompleted = onRestoreCompleted,
       _temporaryDirectoryFactory =
           temporaryDirectoryFactory ?? _createTemporaryDirectory,
       _preferencesFactory =
           preferencesFactory ?? SharedPreferences.getInstance,
       _uuid = uuid;

  static const archiveVersion = 1;
  static const archiveFormat = 'raze-store-backup';
  static const archiveExtension = 'razestore';
  static const _oldestSupportedSchemaVersion = 2;
  static const _manifestPath = 'manifest.json';
  static const _dataPath = 'data.json';
  static const _photoPrefix = 'photos/';
  static const _themeModeKey = 'theme_mode';
  static const _onboardingKey = 'raze_store.onboarding.store_setup_complete';
  static const _maximumArchiveBytes = 512 * 1024 * 1024;
  static const _maximumExpandedBytes = 768 * 1024 * 1024;
  static const _maximumEntryBytes = 32 * 1024 * 1024;
  static const _maximumDataBytes = 24 * 1024 * 1024;
  static const _maximumManifestBytes = 1024 * 1024;
  static const _maximumCentralDirectoryBytes = 2 * 1024 * 1024;
  static const _maximumFileCount = 10002;
  static const _maximumProducts = 50000;
  static const _maximumSellingUnits = 100000;
  static const _maximumSellingUnitsPerProduct = 100;

  final database.AppDatabase _database;
  final LocalProductImageStore _imageStore;
  final CatalogRestoreRefresh? _onRestoreCompleted;
  final BackupTemporaryDirectoryFactory _temporaryDirectoryFactory;
  final Future<SharedPreferences> Function() _preferencesFactory;
  final Uuid _uuid;
  bool _operationRunning = false;

  Future<CatalogTransferResult> createArchive({
    required String outputPath,
  }) async {
    if (_operationRunning) return _busyFailure();
    _operationRunning = true;
    Directory? staging;
    try {
      staging = await _temporaryDirectoryFactory('raze_store_export_');
      final snapshot = await _readSnapshot();
      _validateSnapshotForExport(snapshot);
      final stagedFiles = <String, File>{};
      final portablePhotos = await _stagePhotos(
        products: snapshot.products,
        staging: staging,
        stagedFiles: stagedFiles,
      );

      final data = <String, Object?>{
        'products': [
          for (final row in snapshot.products)
            _productToJson(row, portablePhotos[row.id]),
        ],
        'sellingUnits': [
          for (final row in snapshot.sellingUnits) _sellingUnitToJson(row),
        ],
        'storeProfile': _profileToJson(snapshot.profile),
        'preferences': <String, Object?>{
          'themeMode': snapshot.themeMode,
          'storeSetupComplete': snapshot.storeSetupComplete,
        },
      };
      final dataFile = File(p.join(staging.path, _dataPath));
      await dataFile.writeAsString(jsonEncode(data), flush: true);
      stagedFiles[_dataPath] = dataFile;

      final descriptors = <_FileDescriptor>[];
      var expandedBytes = 0;
      for (final entry in stagedFiles.entries) {
        final size = await entry.value.length();
        if (size > _maximumEntryBytes ||
            (entry.key == _dataPath && size > _maximumDataBytes)) {
          throw const _BackupException(
            CatalogTransferFailureCode.archiveTooLarge,
            'A catalog backup file exceeds the safe size limit.',
          );
        }
        expandedBytes += size;
        descriptors.add(
          _FileDescriptor(
            path: entry.key,
            size: size,
            sha256: await _sha256OfFile(entry.value),
          ),
        );
      }
      if (descriptors.length + 1 > _maximumFileCount ||
          expandedBytes > _maximumExpandedBytes) {
        throw const _BackupException(
          CatalogTransferFailureCode.archiveTooLarge,
          'This catalog is too large to back up safely.',
        );
      }
      descriptors.sort((a, b) => a.path.compareTo(b.path));
      final manifestFile = File(p.join(staging.path, _manifestPath));
      await manifestFile.writeAsString(
        jsonEncode(<String, Object?>{
          'format': archiveFormat,
          'archiveVersion': archiveVersion,
          'databaseSchemaVersion': _database.schemaVersion,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
          'dataFile': _dataPath,
          'files': [for (final item in descriptors) item.toJson()],
          'counts': <String, Object?>{
            'products': snapshot.products.length,
            'sellingUnits': snapshot.sellingUnits.length,
            'photos': portablePhotos.length,
          },
        }),
        flush: true,
      );
      final manifestSize = await manifestFile.length();
      if (manifestSize > _maximumManifestBytes ||
          expandedBytes + manifestSize > _maximumExpandedBytes) {
        throw const _BackupException(
          CatalogTransferFailureCode.archiveTooLarge,
          'This catalog has too many files to back up safely.',
        );
      }
      await _encodeArchive(
        outputPath: outputPath,
        manifestFile: manifestFile,
        stagedFiles: stagedFiles,
      );
      return CatalogTransferSuccess(
        action: CatalogTransferAction.backupExport,
        message: 'Backup created successfully.',
        productCount: snapshot.products.length,
        sellingUnitCount: snapshot.sellingUnits.length,
        photoCount: portablePhotos.length,
        path: outputPath,
      );
    } on _BackupException catch (error) {
      return CatalogTransferFailure(
        code: error.code,
        message: error.message,
        cause: error.cause,
      );
    } on FileSystemException catch (error) {
      return CatalogTransferFailure(
        code: CatalogTransferFailureCode.ioFailure,
        message: 'The backup could not be written. Check available storage.',
        cause: error,
      );
    } catch (error) {
      return CatalogTransferFailure(
        code: CatalogTransferFailureCode.databaseFailure,
        message: 'The catalog could not be read for backup.',
        cause: error,
      );
    } finally {
      _operationRunning = false;
      await _deleteDirectoryQuietly(staging);
    }
  }

  Future<CatalogTransferResult> restoreReplacing({
    required String archivePath,
  }) async {
    if (_operationRunning) return _busyFailure();
    _operationRunning = true;
    Directory? staging;
    final newPhotoPaths = <String>[];
    var databaseReplaced = false;
    try {
      final archiveFile = File(archivePath);
      if (!await archiveFile.exists()) {
        throw const _BackupException(
          CatalogTransferFailureCode.sourceMissing,
          'The selected backup file is no longer available.',
        );
      }
      if (await archiveFile.length() > _maximumArchiveBytes) {
        throw const _BackupException(
          CatalogTransferFailureCode.archiveTooLarge,
          'This backup is too large to restore safely.',
        );
      }
      await _preflightZipArchive(archiveFile);

      staging = await _temporaryDirectoryFactory('raze_store_restore_');
      final validated = await _validateAndStageArchive(
        archiveFile: archiveFile,
        staging: staging,
      );
      final oldPhotos = await _existingPhotoPaths();
      final restoredPhotoPaths = <String, String>{};
      for (final product in validated.data.products) {
        final portablePath = product.localPhoto;
        if (portablePath == null) continue;
        final stagedFile = _safeStageFile(staging, portablePath);
        final savedPath = await _imageStore.persistFile(stagedFile);
        restoredPhotoPaths[product.id] = savedPath;
        newPhotoPaths.add(savedPath);
      }

      try {
        await _replaceDatabase(validated.data, restoredPhotoPaths);
        databaseReplaced = true;
      } catch (_) {
        for (final path in newPhotoPaths) {
          await _imageStore.deleteIfManaged(path);
        }
        rethrow;
      }
      final preferencesRestored = await _restorePreferences(
        validated.data.preferences,
      );
      for (final path in oldPhotos) {
        if (!newPhotoPaths.contains(path)) {
          try {
            await _imageStore.deleteIfManaged(path);
          } catch (_) {
            // Stale media cleanup must not turn a committed restore into a
            // reported failure.
          }
        }
      }
      try {
        await _onRestoreCompleted?.call();
      } catch (_) {
        // The restore is committed. Provider refresh is best effort.
      }
      return CatalogTransferSuccess(
        action: CatalogTransferAction.backupRestore,
        message: preferencesRestored
            ? 'Backup restored. Your local catalog was replaced.'
            : 'Catalog, photos, and receipt details were restored, but the app appearance setting could not be restored.',
        productCount: validated.data.products.length,
        sellingUnitCount: validated.data.sellingUnits.length,
        photoCount: restoredPhotoPaths.length,
        path: archivePath,
      );
    } on _BackupException catch (error) {
      return CatalogTransferFailure(
        code: error.code,
        message: error.message,
        cause: error.cause,
      );
    } on FileSystemException catch (error) {
      return CatalogTransferFailure(
        code: CatalogTransferFailureCode.ioFailure,
        message: 'The selected backup could not be read or restored.',
        cause: error,
      );
    } catch (error) {
      return CatalogTransferFailure(
        code: CatalogTransferFailureCode.invalidFile,
        message: 'This is not a valid Raze Store backup.',
        cause: error,
      );
    } finally {
      if (!databaseReplaced) {
        for (final path in newPhotoPaths) {
          try {
            await _imageStore.deleteIfManaged(path);
          } catch (_) {
            // Best-effort rollback cleanup.
          }
        }
      }
      _operationRunning = false;
      await _deleteDirectoryQuietly(staging);
    }
  }

  Future<_DatabaseSnapshot> _readSnapshot() async {
    final databaseRows = await _database.transaction(() async {
      final products = await _database.select(_database.storeProducts).get();
      final units = await _database.select(_database.productSellingUnits).get();
      final profile = await _database
          .select(_database.storeProfiles)
          .getSingleOrNull();
      return (products: products, units: units, profile: profile);
    });
    final preferences = await _preferencesFactory();
    return _DatabaseSnapshot(
      products: databaseRows.products,
      sellingUnits: databaseRows.units,
      profile: databaseRows.profile,
      themeMode: preferences.getString(_themeModeKey),
      storeSetupComplete: preferences.getBool(_onboardingKey) ?? false,
    );
  }

  void _validateSnapshotForExport(_DatabaseSnapshot snapshot) {
    if (snapshot.products.length > _maximumProducts ||
        snapshot.sellingUnits.length > _maximumSellingUnits) {
      throw const _BackupException(
        CatalogTransferFailureCode.archiveTooLarge,
        'This catalog has too many records to back up safely.',
      );
    }
    final mainLabels = <String, String>{
      for (final product in snapshot.products)
        product.id: (product.unitLabel ?? 'Main item').trim().toLowerCase(),
    };
    final barcodes = <String, String?>{
      for (final product in snapshot.products) product.id: product.barcode,
    };
    final unitCounts = <String, int>{};
    final labelsByProduct = <String, Set<String>>{};
    for (final unit in snapshot.sellingUnits) {
      if (!mainLabels.containsKey(unit.productId)) {
        throw const _BackupException(
          CatalogTransferFailureCode.validationFailed,
          'A sub-unit price references a missing product.',
        );
      }
      if (barcodes[unit.productId] == null) {
        throw const _BackupException(
          CatalogTransferFailureCode.validationFailed,
          'A product with sub-unit prices needs a main barcode. Edit it before creating a backup.',
        );
      }
      final count = (unitCounts[unit.productId] ?? 0) + 1;
      if (count > _maximumSellingUnitsPerProduct) {
        throw const _BackupException(
          CatalogTransferFailureCode.archiveTooLarge,
          'A product has too many sub-unit prices to back up safely.',
        );
      }
      unitCounts[unit.productId] = count;
      final normalizedLabel = unit.label.trim().toLowerCase();
      final labels = labelsByProduct.putIfAbsent(unit.productId, () => {});
      if (!labels.add(normalizedLabel) ||
          normalizedLabel == mainLabels[unit.productId]) {
        throw const _BackupException(
          CatalogTransferFailureCode.validationFailed,
          'A product has duplicate main or sub-unit labels. Edit it before creating a backup.',
        );
      }
    }
  }

  Future<Map<String, String>> _stagePhotos({
    required List<database.StoreProduct> products,
    required Directory staging,
    required Map<String, File> stagedFiles,
  }) async {
    final root = await _imageStore.managedDirectory();
    final canonicalRoot = await root.resolveSymbolicLinks();
    final portablePaths = <String, String>{};
    for (final product in products) {
      final localPath = product.localImagePath?.trim();
      if (localPath == null || localPath.isEmpty) continue;
      final resolved = await _imageStore.resolveManagedPath(localPath);
      if (resolved == null) {
        throw _BackupException(
          CatalogTransferFailureCode.sourceOutsideManagedStorage,
          'The photo for ${product.name} is outside Raze Store storage.',
        );
      }
      final source = File(resolved);
      if (!await source.exists()) {
        throw _BackupException(
          CatalogTransferFailureCode.sourceMissing,
          'The photo for ${product.name} is missing. Re-add or remove it before backing up.',
        );
      }
      final canonicalSource = await source.resolveSymbolicLinks();
      if (!p.isWithin(canonicalRoot, canonicalSource)) {
        throw _BackupException(
          CatalogTransferFailureCode.sourceOutsideManagedStorage,
          'The photo for ${product.name} is outside Raze Store storage.',
        );
      }
      final stat = await File(canonicalSource).stat();
      if (stat.type != FileSystemEntityType.file ||
          stat.size > _maximumEntryBytes) {
        throw _BackupException(
          CatalogTransferFailureCode.archiveTooLarge,
          'The photo for ${product.name} is not a supported file size.',
        );
      }
      final portable = _portablePhotoPath(product.id, resolved);
      final destination = _safeStageFile(staging, portable);
      await destination.parent.create(recursive: true);
      await File(canonicalSource).copy(destination.path);
      final normalizedStored = p.normalize(File(localPath).absolute.path);
      if (resolved != normalizedStored) {
        await (_database.update(_database.storeProducts)..where(
              (table) =>
                  table.id.equals(product.id) &
                  table.localImagePath.equals(localPath),
            ))
            .write(
              database.StoreProductsCompanion(localImagePath: Value(resolved)),
            );
      }
      portablePaths[product.id] = portable;
      stagedFiles[portable] = destination;
    }
    return portablePaths;
  }

  Future<void> _encodeArchive({
    required String outputPath,
    required File manifestFile,
    required Map<String, File> stagedFiles,
  }) async {
    final output = File(outputPath);
    await output.parent.create(recursive: true);
    final partial = File('$outputPath.${_uuid.v4()}.part');
    final encoder = ZipFileEncoder();
    try {
      encoder.create(partial.path);
      await encoder.addFile(manifestFile, _manifestPath);
      await _throwIfArchiveTooLarge(partial);
      final entries = stagedFiles.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      for (final entry in entries) {
        await encoder.addFile(entry.value, entry.key);
        await _throwIfArchiveTooLarge(partial);
      }
      await encoder.close();
      await _throwIfArchiveTooLarge(partial);
      if (await output.exists()) await output.delete();
      await partial.rename(output.path);
    } catch (_) {
      try {
        await encoder.close();
      } catch (_) {
        // Cleanup below is sufficient if encoding never fully opened.
      }
      await _deleteFileQuietly(partial);
      rethrow;
    }
  }

  Future<void> _throwIfArchiveTooLarge(File partial) async {
    if (await partial.exists() &&
        await partial.length() > _maximumArchiveBytes) {
      throw const _BackupException(
        CatalogTransferFailureCode.archiveTooLarge,
        'This catalog is too large to back up safely.',
      );
    }
  }

  /// Reads the bounded central directory before `ZipDecoder`. The archive
  /// package materializes Unix symlink targets before its validation callback,
  /// so rejecting symlink attributes here prevents attacker-controlled data
  /// from being decompressed into memory outside our capped output stream.
  Future<void> _preflightZipArchive(File archiveFile) async {
    const eocdSize = 22;
    const maximumCommentBytes = 0xffff;
    const eocdSignature = [0x50, 0x4b, 0x05, 0x06];
    const zip64LocatorSignature = [0x50, 0x4b, 0x06, 0x07];
    const centralHeaderSignature = [0x50, 0x4b, 0x01, 0x02];
    final fileLength = await archiveFile.length();
    if (fileLength < eocdSize) {
      throw const _BackupException(
        CatalogTransferFailureCode.invalidFile,
        'This is not a readable Raze Store backup.',
      );
    }

    final handle = await archiveFile.open();
    try {
      final tailLength = fileLength < eocdSize + maximumCommentBytes
          ? fileLength
          : eocdSize + maximumCommentBytes;
      final tailOffset = fileLength - tailLength;
      await handle.setPosition(tailOffset);
      final tail = await handle.read(tailLength);
      var eocdOffset = -1;
      for (var offset = tail.length - eocdSize; offset >= 0; offset--) {
        if (_bytesMatch(tail, offset, eocdSignature)) {
          eocdOffset = offset;
          break;
        }
      }
      if (eocdOffset < 0) {
        throw const _BackupException(
          CatalogTransferFailureCode.invalidFile,
          'This is not a readable Raze Store backup.',
        );
      }

      final eocd = ByteData.sublistView(tail, eocdOffset);
      final commentLength = eocd.getUint16(20, Endian.little);
      final absoluteEocdOffset = tailOffset + eocdOffset;
      if (absoluteEocdOffset + eocdSize + commentLength != fileLength) {
        throw const _BackupException(
          CatalogTransferFailureCode.invalidFile,
          'The backup has an invalid ZIP directory.',
        );
      }
      if (eocdOffset >= 20 &&
          _bytesMatch(tail, eocdOffset - 20, zip64LocatorSignature)) {
        throw const _BackupException(
          CatalogTransferFailureCode.unsupportedVersion,
          'ZIP64 backups are not supported.',
        );
      }

      final diskNumber = eocd.getUint16(4, Endian.little);
      final directoryDisk = eocd.getUint16(6, Endian.little);
      final entriesOnDisk = eocd.getUint16(8, Endian.little);
      final entryCount = eocd.getUint16(10, Endian.little);
      final directorySize = eocd.getUint32(12, Endian.little);
      final directoryOffset = eocd.getUint32(16, Endian.little);
      if (entryCount == 0xffff ||
          directorySize == 0xffffffff ||
          directoryOffset == 0xffffffff) {
        throw const _BackupException(
          CatalogTransferFailureCode.unsupportedVersion,
          'ZIP64 backups are not supported.',
        );
      }
      if (diskNumber != 0 ||
          directoryDisk != 0 ||
          entriesOnDisk != entryCount ||
          directoryOffset + directorySize != absoluteEocdOffset) {
        throw const _BackupException(
          CatalogTransferFailureCode.invalidFile,
          'The backup has an invalid ZIP directory.',
        );
      }
      if (entryCount > _maximumFileCount ||
          directorySize > _maximumCentralDirectoryBytes) {
        throw const _BackupException(
          CatalogTransferFailureCode.archiveTooLarge,
          'This backup contains too many files.',
        );
      }

      await handle.setPosition(directoryOffset);
      final directoryBytes = await handle.read(directorySize);
      if (directoryBytes.length != directorySize) {
        throw const _BackupException(
          CatalogTransferFailureCode.invalidFile,
          'The backup has an incomplete ZIP directory.',
        );
      }
      final directory = ByteData.sublistView(directoryBytes);
      var position = 0;
      for (var entry = 0; entry < entryCount; entry++) {
        if (position + 46 > directoryBytes.length ||
            !_bytesMatch(directoryBytes, position, centralHeaderSignature)) {
          throw const _BackupException(
            CatalogTransferFailureCode.invalidFile,
            'The backup has an invalid ZIP file entry.',
          );
        }
        final versionMadeBy = directory.getUint16(position + 4, Endian.little);
        final flags = directory.getUint16(position + 8, Endian.little);
        final fileNameLength = directory.getUint16(
          position + 28,
          Endian.little,
        );
        final extraLength = directory.getUint16(position + 30, Endian.little);
        final entryCommentLength = directory.getUint16(
          position + 32,
          Endian.little,
        );
        final diskStart = directory.getUint16(position + 34, Endian.little);
        final externalAttributes = directory.getUint32(
          position + 38,
          Endian.little,
        );
        if ((flags & 0x1) != 0 || diskStart != 0) {
          throw const _BackupException(
            CatalogTransferFailureCode.invalidFile,
            'Encrypted or multi-disk backups are not supported.',
          );
        }
        final unixMode = externalAttributes >> 16;
        final isUnix = versionMadeBy >> 8 == 3;
        if (isUnix && (unixMode & 0xf000) == 0xa000) {
          throw const _BackupException(
            CatalogTransferFailureCode.unsafeArchive,
            'The backup contains an unsupported symbolic link.',
          );
        }
        position += 46 + fileNameLength + extraLength + entryCommentLength;
      }
      if (position != directoryBytes.length) {
        throw const _BackupException(
          CatalogTransferFailureCode.invalidFile,
          'The backup has unexpected ZIP directory data.',
        );
      }
    } finally {
      await handle.close();
    }
  }

  static bool _bytesMatch(List<int> bytes, int offset, List<int> pattern) {
    if (offset < 0 || offset + pattern.length > bytes.length) return false;
    for (var index = 0; index < pattern.length; index++) {
      if (bytes[offset + index] != pattern[index]) return false;
    }
    return true;
  }

  Future<_ValidatedBackup> _validateAndStageArchive({
    required File archiveFile,
    required Directory staging,
  }) async {
    final input = InputFileStream(archiveFile.path);
    Archive? decodedArchive;
    try {
      final names = <String>{};
      final caseFoldedNames = <String>{};
      var expandedBytes = 0;
      final archive = decodedArchive = ZipDecoder().decodeStream(
        input,
        callback: (entry) {
          _validateArchiveEntry(entry);
          if (!names.add(entry.name) ||
              !caseFoldedNames.add(entry.name.toLowerCase())) {
            throw const _BackupException(
              CatalogTransferFailureCode.invalidFile,
              'The backup contains duplicate file names.',
            );
          }
          expandedBytes += entry.size;
          if (names.length > _maximumFileCount ||
              expandedBytes > _maximumExpandedBytes) {
            throw const _BackupException(
              CatalogTransferFailureCode.archiveTooLarge,
              'This backup expands beyond the safe restore limit.',
            );
          }
        },
      );
      final manifestEntry = archive.find(_manifestPath);
      if (manifestEntry == null || manifestEntry.size > _maximumManifestBytes) {
        throw const _BackupException(
          CatalogTransferFailureCode.invalidFile,
          'The backup manifest is missing or invalid.',
        );
      }
      final extractionBudget = _ArchiveExtractionBudget(_maximumExpandedBytes);
      final stagedManifest = _safeStageFile(staging, _manifestPath);
      final actualManifestSize = await _extractEntry(
        manifestEntry,
        stagedManifest,
        maximumBytes: _maximumManifestBytes,
        budget: extractionBudget,
      );
      if (actualManifestSize != manifestEntry.size) {
        throw const _BackupException(
          CatalogTransferFailureCode.integrityMismatch,
          'The backup manifest size is incorrect.',
        );
      }
      final manifestBytes = await stagedManifest.readAsBytes();
      final manifest = _BackupManifest.fromJson(
        _decodeObject(manifestBytes, 'backup manifest'),
      );
      _validateManifest(manifest, archive);

      File? stagedDataFile;
      for (final descriptor in manifest.files) {
        final entry = archive.find(descriptor.path)!;
        final stagedFile = _safeStageFile(staging, descriptor.path);
        await stagedFile.parent.create(recursive: true);
        final stagedSize = await _extractEntry(
          entry,
          stagedFile,
          maximumBytes: descriptor.path == _dataPath
              ? _maximumDataBytes
              : _maximumEntryBytes,
          budget: extractionBudget,
        );
        if (entry.size != descriptor.size || stagedSize != descriptor.size) {
          throw _BackupException(
            CatalogTransferFailureCode.integrityMismatch,
            'Backup file size validation failed for ${descriptor.path}.',
          );
        }
        if (await _sha256OfFile(stagedFile) != descriptor.sha256) {
          throw _BackupException(
            CatalogTransferFailureCode.integrityMismatch,
            'Backup integrity validation failed for ${descriptor.path}.',
          );
        }
        if (descriptor.path == manifest.dataFile) stagedDataFile = stagedFile;
      }
      if (stagedDataFile == null ||
          await stagedDataFile.length() > _maximumDataBytes) {
        throw const _BackupException(
          CatalogTransferFailureCode.invalidFile,
          'The catalog data file is missing or too large.',
        );
      }
      final dataBytes = await stagedDataFile.readAsBytes();
      final data = _BackupData.fromJson(
        _decodeObject(dataBytes, 'catalog data'),
      );
      _validateData(data, manifest);
      return _ValidatedBackup(data: data);
    } on _BackupException {
      rethrow;
    } on ArchiveException catch (error) {
      throw _BackupException(
        CatalogTransferFailureCode.invalidFile,
        'This is not a readable Raze Store backup.',
        error,
      );
    } on FormatException catch (error) {
      throw _BackupException(
        CatalogTransferFailureCode.invalidFile,
        'The backup contains malformed data.',
        error,
      );
    } catch (error) {
      throw _BackupException(
        CatalogTransferFailureCode.invalidFile,
        'This is not a valid Raze Store backup.',
        error,
      );
    } finally {
      for (final entry in decodedArchive?.files ?? const <ArchiveFile>[]) {
        entry.clear();
      }
      await input.close();
    }
  }

  Future<int> _extractEntry(
    ArchiveFile entry,
    File destination, {
    required int maximumBytes,
    required _ArchiveExtractionBudget budget,
  }) async {
    final fileOutput = OutputFileStream(destination.path);
    final output = _CappedOutputStream(
      fileOutput,
      maximumBytes: maximumBytes,
      budget: budget,
    );
    try {
      entry.writeContent(output);
      await output.close();
      return output.length;
    } catch (_) {
      try {
        await output.close();
      } catch (_) {
        // The original extraction error is more useful.
      }
      rethrow;
    } finally {
      // ArchiveFile otherwise caches decompressed bytes for every entry until
      // the complete archive is collected. Release each photo immediately so
      // restore memory is bounded by one entry instead of the whole backup.
      entry.clear();
    }
  }

  void _validateArchiveEntry(ArchiveFile entry) {
    if (!entry.isFile || entry.isSymbolicLink) {
      throw const _BackupException(
        CatalogTransferFailureCode.unsafeArchive,
        'The backup contains an unsupported link or directory entry.',
      );
    }
    _validatePortablePath(entry.name);
    if (entry.size < 0 || entry.size > _maximumEntryBytes) {
      throw const _BackupException(
        CatalogTransferFailureCode.archiveTooLarge,
        'A file in this backup is too large to restore safely.',
      );
    }
  }

  void _validateManifest(_BackupManifest manifest, Archive archive) {
    if (manifest.format != archiveFormat) {
      throw const _BackupException(
        CatalogTransferFailureCode.invalidFile,
        'This file was not created by Raze Store.',
      );
    }
    if (manifest.archiveVersion != archiveVersion) {
      throw const _BackupException(
        CatalogTransferFailureCode.unsupportedVersion,
        'This backup version is not supported by this app version.',
      );
    }
    if (manifest.databaseSchemaVersion < _oldestSupportedSchemaVersion ||
        manifest.databaseSchemaVersion > _database.schemaVersion) {
      throw const _BackupException(
        CatalogTransferFailureCode.unsupportedVersion,
        'This backup requires a different Raze Store app version.',
      );
    }
    if (manifest.dataFile != _dataPath) {
      throw const _BackupException(
        CatalogTransferFailureCode.invalidFile,
        'The backup points to an unexpected data file.',
      );
    }
    if (manifest.productCount < 0 ||
        manifest.sellingUnitCount < 0 ||
        manifest.photoCount < 0) {
      throw const _BackupException(
        CatalogTransferFailureCode.invalidFile,
        'The backup manifest contains invalid record counts.',
      );
    }
    if (manifest.productCount > _maximumProducts ||
        manifest.sellingUnitCount > _maximumSellingUnits ||
        manifest.photoCount > _maximumProducts) {
      throw const _BackupException(
        CatalogTransferFailureCode.archiveTooLarge,
        'This backup contains too many catalog records.',
      );
    }
    final paths = <String>{};
    final caseFoldedPaths = <String>{};
    for (final descriptor in manifest.files) {
      _validatePortablePath(descriptor.path);
      if (!paths.add(descriptor.path) ||
          !caseFoldedPaths.add(descriptor.path.toLowerCase()) ||
          descriptor.path == _manifestPath) {
        throw const _BackupException(
          CatalogTransferFailureCode.invalidFile,
          'The backup manifest contains duplicate file entries.',
        );
      }
      if (descriptor.path != _dataPath &&
          !_portablePhotoPattern.hasMatch(descriptor.path)) {
        throw const _BackupException(
          CatalogTransferFailureCode.validationFailed,
          'The backup contains an invalid product photo file name.',
        );
      }
      final entry = archive.find(descriptor.path);
      if (entry == null || entry.size != descriptor.size) {
        throw _BackupException(
          CatalogTransferFailureCode.integrityMismatch,
          'A backup file is missing or changed: ${descriptor.path}.',
        );
      }
    }
    if (!paths.contains(_dataPath) ||
        archive.files.length != paths.length + 1) {
      throw const _BackupException(
        CatalogTransferFailureCode.invalidFile,
        'The backup contains unexpected or missing files.',
      );
    }
  }

  void _validateData(_BackupData data, _BackupManifest manifest) {
    if (data.products.length > _maximumProducts ||
        data.sellingUnits.length > _maximumSellingUnits) {
      throw const _BackupException(
        CatalogTransferFailureCode.archiveTooLarge,
        'This backup contains too many catalog records.',
      );
    }
    final productIds = _unique(data.products.map((item) => item.id), 'product');
    final mainLabels = <String, String>{
      for (final product in data.products)
        product.id: (product.unitLabel ?? 'Main item').toLowerCase(),
    };
    final productBarcodes = <String, String?>{
      for (final product in data.products) product.id: product.barcode,
    };
    final barcodes = <String>{};
    final referencedPhotos = <String>{};
    for (final product in data.products) {
      if (product.barcode != null && !barcodes.add(product.barcode!)) {
        throw const _BackupException(
          CatalogTransferFailureCode.validationFailed,
          'The backup contains duplicate product barcodes.',
        );
      }
      final photo = product.localPhoto;
      if (photo != null) {
        _validatePortablePath(photo);
        if (!_portablePhotoPattern.hasMatch(photo) ||
            !referencedPhotos.add(photo)) {
          throw const _BackupException(
            CatalogTransferFailureCode.validationFailed,
            'The backup contains an invalid product photo reference.',
          );
        }
      }
    }
    _unique(data.sellingUnits.map((item) => item.id), 'selling-unit');
    final labelsByProduct = <String, Set<String>>{};
    final unitCounts = <String, int>{};
    for (final unit in data.sellingUnits) {
      if (!productIds.contains(unit.productId)) {
        throw const _BackupException(
          CatalogTransferFailureCode.validationFailed,
          'A selling unit references a missing product.',
        );
      }
      if (productBarcodes[unit.productId] == null) {
        throw const _BackupException(
          CatalogTransferFailureCode.validationFailed,
          'A product with sub-unit prices needs a main barcode.',
        );
      }
      final count = (unitCounts[unit.productId] ?? 0) + 1;
      if (count > _maximumSellingUnitsPerProduct) {
        throw const _BackupException(
          CatalogTransferFailureCode.archiveTooLarge,
          'A product in this backup has too many sub-unit prices.',
        );
      }
      unitCounts[unit.productId] = count;
      final labels = labelsByProduct.putIfAbsent(unit.productId, () => {});
      final normalizedLabel = unit.label.toLowerCase();
      if (!labels.add(normalizedLabel) ||
          normalizedLabel == mainLabels[unit.productId]) {
        throw const _BackupException(
          CatalogTransferFailureCode.validationFailed,
          'A product has duplicate main or sub-unit labels.',
        );
      }
    }
    final descriptorPhotos = manifest.files
        .map((item) => item.path)
        .where((path) => path.startsWith(_photoPrefix))
        .toSet();
    if (descriptorPhotos.length != referencedPhotos.length ||
        !descriptorPhotos.containsAll(referencedPhotos)) {
      throw const _BackupException(
        CatalogTransferFailureCode.validationFailed,
        'The backup product-photo list does not match its catalog.',
      );
    }
    if (manifest.productCount != data.products.length ||
        manifest.sellingUnitCount != data.sellingUnits.length ||
        manifest.photoCount != referencedPhotos.length) {
      throw const _BackupException(
        CatalogTransferFailureCode.integrityMismatch,
        'The backup record counts do not match its manifest.',
      );
    }
  }

  Future<void> _replaceDatabase(
    _BackupData data,
    Map<String, String> photoPaths,
  ) async {
    await _database.transaction(() async {
      await _database.delete(_database.draftCartItems).go();
      await _database.delete(_database.productSellingUnits).go();
      await _database.delete(_database.storeProducts).go();
      await _database.delete(_database.storeProfiles).go();

      await _database.batch((batch) {
        batch.insertAll(_database.storeProducts, [
          for (final item in data.products)
            database.StoreProductsCompanion.insert(
              id: item.id,
              barcode: Value(item.barcode),
              source: Value(item.source),
              sourceProductId: Value(item.sourceProductId),
              name: item.name,
              brand: Value(item.brand),
              unitLabel: Value(item.unitLabel),
              category: Value(item.category),
              remoteImageUrl: Value(item.remoteImageUrl),
              localImagePath: Value(photoPaths[item.id]),
              priceCentavos: item.priceCentavos,
              createdAt: Value(item.createdAt),
              updatedAt: Value(item.updatedAt),
            ),
        ]);
        batch.insertAll(_database.productSellingUnits, [
          for (final item in data.sellingUnits)
            database.ProductSellingUnitsCompanion.insert(
              id: item.id,
              productId: item.productId,
              label: item.label,
              priceCentavos: item.priceCentavos,
              position: item.position,
              createdAt: Value(item.createdAt),
              updatedAt: Value(item.updatedAt),
            ),
        ]);
        batch.insert(
          _database.storeProfiles,
          database.StoreProfilesCompanion.insert(
            id: const Value(1),
            storeName: Value(data.profile.storeName),
            address: Value(data.profile.address),
            contact: Value(data.profile.contact),
            receiptFooter: Value(data.profile.receiptFooter),
            updatedAt: Value(data.profile.updatedAt),
          ),
        );
      });
    });
  }

  Future<bool> _restorePreferences(_BackupPreferences preferences) async {
    try {
      final storage = await _preferencesFactory();
      final hadThemeMode = storage.containsKey(_themeModeKey);
      final oldThemeMode = storage.getString(_themeModeKey);
      final hadOnboarding = storage.containsKey(_onboardingKey);
      final oldOnboarding = storage.getBool(_onboardingKey);
      try {
        final themeMode = preferences.themeMode;
        final themeSaved = themeMode == null
            ? (!hadThemeMode || await storage.remove(_themeModeKey))
            : await storage.setString(_themeModeKey, themeMode);
        // A successful restore includes a valid store profile, so startup
        // should never force the user through setup again.
        final onboardingSaved = await storage.setBool(_onboardingKey, true);
        if (!themeSaved || !onboardingSaved) throw StateError('save failed');
        return true;
      } catch (_) {
        try {
          if (hadThemeMode && oldThemeMode != null) {
            await storage.setString(_themeModeKey, oldThemeMode);
          } else {
            await storage.remove(_themeModeKey);
          }
          if (hadOnboarding && oldOnboarding != null) {
            await storage.setBool(_onboardingKey, oldOnboarding);
          } else {
            await storage.remove(_onboardingKey);
          }
        } catch (_) {
          // A warning is returned below even when rollback is unavailable.
        }
        return false;
      }
    } catch (_) {
      return false;
    }
  }

  Future<List<String>> _existingPhotoPaths() async {
    final rows = await _database.select(_database.storeProducts).get();
    return rows
        .map((row) => row.localImagePath?.trim())
        .whereType<String>()
        .where((path) => path.isNotEmpty)
        .toList(growable: false);
  }

  String _portablePhotoPath(String productId, String filePath) {
    final key = sha256
        .convert(utf8.encode('$productId\u0000$filePath'))
        .toString()
        .substring(0, 28);
    var extension = p.extension(filePath).toLowerCase();
    if (!RegExp(r'^\.[a-z0-9]{1,8}$').hasMatch(extension)) extension = '.bin';
    return '$_photoPrefix$key$extension';
  }

  File _safeStageFile(Directory root, String portablePath) {
    _validatePortablePath(portablePath);
    final destination = p.joinAll([root.path, ...p.posix.split(portablePath)]);
    if (!p.isWithin(root.path, destination)) {
      throw const _BackupException(
        CatalogTransferFailureCode.unsafeArchive,
        'The backup contains a path outside its staging area.',
      );
    }
    return File(destination);
  }

  void _validatePortablePath(String value) {
    if (value.isEmpty ||
        value.contains('\\') ||
        value.startsWith('/') ||
        RegExp(r'^[A-Za-z]:').hasMatch(value)) {
      throw const _BackupException(
        CatalogTransferFailureCode.unsafeArchive,
        'The backup contains an unsafe file path.',
      );
    }
    final segments = value.split('/');
    if (segments.any(
      (segment) => segment.isEmpty || segment == '.' || segment == '..',
    )) {
      throw const _BackupException(
        CatalogTransferFailureCode.unsafeArchive,
        'The backup contains an unsafe file path.',
      );
    }
    if (p.posix.normalize(value) != value) {
      throw const _BackupException(
        CatalogTransferFailureCode.unsafeArchive,
        'The backup contains a non-portable file path.',
      );
    }
  }

  Set<String> _unique(Iterable<String> values, String label) {
    final result = <String>{};
    for (final value in values) {
      if (value.isEmpty || !result.add(value)) {
        throw _BackupException(
          CatalogTransferFailureCode.validationFailed,
          'The backup contains an empty or duplicate $label ID.',
        );
      }
    }
    return result;
  }

  Map<String, Object?> _decodeObject(Uint8List bytes, String label) {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) {
      throw FormatException('The $label must be a JSON object.');
    }
    return decoded.cast<String, Object?>();
  }

  Map<String, Object?> _productToJson(
    database.StoreProduct row,
    String? portablePhoto,
  ) => <String, Object?>{
    'id': row.id,
    'barcode': row.barcode,
    'source': row.source,
    'sourceProductId': row.sourceProductId,
    'name': row.name,
    'brand': row.brand,
    'unitLabel': row.unitLabel,
    'category': row.category,
    'remoteImageUrl': row.remoteImageUrl,
    'localPhoto': portablePhoto,
    'priceCentavos': row.priceCentavos,
    'createdAt': row.createdAt.toUtc().toIso8601String(),
    'updatedAt': row.updatedAt.toUtc().toIso8601String(),
  };

  Map<String, Object?> _sellingUnitToJson(database.ProductSellingUnit row) =>
      <String, Object?>{
        'id': row.id,
        'productId': row.productId,
        'label': row.label,
        'priceCentavos': row.priceCentavos,
        'position': row.position,
        'createdAt': row.createdAt.toUtc().toIso8601String(),
        'updatedAt': row.updatedAt.toUtc().toIso8601String(),
      };

  Map<String, Object?> _profileToJson(database.StoreProfile? row) =>
      <String, Object?>{
        'storeName': row?.storeName ?? 'Raze Store',
        'address': row?.address ?? '',
        'contact': row?.contact ?? '',
        'receiptFooter': row?.receiptFooter ?? 'Salamat po!',
        'updatedAt': (row?.updatedAt ?? DateTime.now().toUtc())
            .toUtc()
            .toIso8601String(),
      };

  CatalogTransferFailure _busyFailure() => const CatalogTransferFailure(
    code: CatalogTransferFailureCode.unavailable,
    message: 'Another catalog file operation is already running.',
  );

  static Future<Directory> _createTemporaryDirectory(String prefix) =>
      Directory.systemTemp.createTemp(prefix);

  static Future<String> _sha256OfFile(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();

  static Future<void> _deleteDirectoryQuietly(Directory? directory) async {
    if (directory == null) return;
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
    } on FileSystemException {
      // Temporary cleanup must not hide the operation result.
    }
  }

  static Future<void> _deleteFileQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Temporary cleanup must not hide the operation result.
    }
  }
}

final class _DatabaseSnapshot {
  const _DatabaseSnapshot({
    required this.products,
    required this.sellingUnits,
    required this.profile,
    required this.themeMode,
    required this.storeSetupComplete,
  });

  final List<database.StoreProduct> products;
  final List<database.ProductSellingUnit> sellingUnits;
  final database.StoreProfile? profile;
  final String? themeMode;
  final bool storeSetupComplete;
}

final class _ValidatedBackup {
  const _ValidatedBackup({required this.data});

  final _BackupData data;
}

final class _BackupManifest {
  const _BackupManifest({
    required this.format,
    required this.archiveVersion,
    required this.databaseSchemaVersion,
    required this.dataFile,
    required this.files,
    required this.productCount,
    required this.sellingUnitCount,
    required this.photoCount,
  });

  factory _BackupManifest.fromJson(Map<String, Object?> json) {
    final counts = _asMap(json['counts'], 'manifest counts');
    return _BackupManifest(
      format: _string(json['format'], 'manifest format'),
      archiveVersion: _integer(json['archiveVersion'], 'archive version'),
      databaseSchemaVersion: _integer(
        json['databaseSchemaVersion'],
        'database schema version',
      ),
      dataFile: _string(json['dataFile'], 'data file'),
      files: _asList(json['files'], 'manifest files')
          .map(
            (item) => _FileDescriptor.fromJson(_asMap(item, 'manifest file')),
          )
          .toList(growable: false),
      productCount: _integer(counts['products'], 'product count'),
      sellingUnitCount: _integer(counts['sellingUnits'], 'selling-unit count'),
      photoCount: _integer(counts['photos'], 'photo count'),
    );
  }

  final String format;
  final int archiveVersion;
  final int databaseSchemaVersion;
  final String dataFile;
  final List<_FileDescriptor> files;
  final int productCount;
  final int sellingUnitCount;
  final int photoCount;
}

final class _FileDescriptor {
  const _FileDescriptor({
    required this.path,
    required this.size,
    required this.sha256,
  });

  factory _FileDescriptor.fromJson(Map<String, Object?> json) {
    final digest = _string(json['sha256'], 'file checksum');
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
      throw const FormatException('A backup file checksum is invalid.');
    }
    final size = _integer(json['size'], 'file size');
    if (size < 0) {
      throw const FormatException('A file size cannot be negative.');
    }
    return _FileDescriptor(
      path: _string(json['path'], 'file path'),
      size: size,
      sha256: digest,
    );
  }

  final String path;
  final int size;
  final String sha256;

  Map<String, Object?> toJson() => <String, Object?>{
    'path': path,
    'size': size,
    'sha256': sha256,
  };
}

final class _BackupData {
  const _BackupData({
    required this.products,
    required this.sellingUnits,
    required this.profile,
    required this.preferences,
  });

  factory _BackupData.fromJson(Map<String, Object?> json) {
    final productValues = _asList(json['products'], 'products');
    final sellingUnitValues = _asList(json['sellingUnits'], 'selling units');
    if (productValues.length > CatalogBackupService._maximumProducts ||
        sellingUnitValues.length > CatalogBackupService._maximumSellingUnits) {
      throw const _BackupException(
        CatalogTransferFailureCode.archiveTooLarge,
        'This backup contains too many catalog records.',
      );
    }
    return _BackupData(
      products: productValues
          .map((item) => _BackupProduct.fromJson(_asMap(item, 'product')))
          .toList(growable: false),
      sellingUnits: sellingUnitValues
          .map(
            (item) => _BackupSellingUnit.fromJson(_asMap(item, 'selling unit')),
          )
          .toList(growable: false),
      profile: _BackupProfile.fromJson(
        _asMap(json['storeProfile'], 'store profile'),
      ),
      preferences: _BackupPreferences.fromJson(
        _asMap(json['preferences'], 'preferences'),
      ),
    );
  }

  final List<_BackupProduct> products;
  final List<_BackupSellingUnit> sellingUnits;
  final _BackupProfile profile;
  final _BackupPreferences preferences;
}

final class _BackupProduct {
  const _BackupProduct({
    required this.id,
    required this.barcode,
    required this.source,
    required this.sourceProductId,
    required this.name,
    required this.brand,
    required this.unitLabel,
    required this.category,
    required this.remoteImageUrl,
    required this.localPhoto,
    required this.priceCentavos,
    required this.createdAt,
    required this.updatedAt,
  });

  factory _BackupProduct.fromJson(Map<String, Object?> json) {
    final rawBarcode = _optionalString(json['barcode'], 'product barcode');
    final parsedBarcode = rawBarcode == null
        ? null
        : Barcode.tryParse(rawBarcode);
    if (rawBarcode != null && parsedBarcode == null) {
      throw const FormatException('A product barcode is invalid.');
    }
    final price = _integer(json['priceCentavos'], 'product price');
    if (price < 0) throw const FormatException('A product price is negative.');
    return _BackupProduct(
      id: _nonEmptyString(json['id'], 'product ID'),
      barcode: parsedBarcode?.value,
      source: _optionalString(json['source'], 'product source'),
      sourceProductId: _optionalString(
        json['sourceProductId'],
        'source product ID',
      ),
      name: _nonEmptyString(json['name'], 'product name'),
      brand: _optionalString(json['brand'], 'product brand'),
      unitLabel: _optionalString(json['unitLabel'], 'product unit'),
      category: _optionalString(json['category'], 'product category'),
      remoteImageUrl: _optionalString(
        json['remoteImageUrl'],
        'remote image URL',
      ),
      localPhoto: _optionalString(json['localPhoto'], 'local photo'),
      priceCentavos: price,
      createdAt: _dateTime(json['createdAt'], 'product creation date'),
      updatedAt: _dateTime(json['updatedAt'], 'product update date'),
    );
  }

  final String id;
  final String? barcode;
  final String? source;
  final String? sourceProductId;
  final String name;
  final String? brand;
  final String? unitLabel;
  final String? category;
  final String? remoteImageUrl;
  final String? localPhoto;
  final int priceCentavos;
  final DateTime createdAt;
  final DateTime updatedAt;
}

final class _BackupSellingUnit {
  const _BackupSellingUnit({
    required this.id,
    required this.productId,
    required this.label,
    required this.priceCentavos,
    required this.position,
    required this.createdAt,
    required this.updatedAt,
  });

  factory _BackupSellingUnit.fromJson(Map<String, Object?> json) {
    final price = _integer(json['priceCentavos'], 'selling-unit price');
    final position = _integer(json['position'], 'selling-unit position');
    if (price < 0 || position < 0) {
      throw const FormatException('A selling unit has invalid numeric values.');
    }
    return _BackupSellingUnit(
      id: _nonEmptyString(json['id'], 'selling-unit ID'),
      productId: _nonEmptyString(json['productId'], 'selling-unit product ID'),
      label: _nonEmptyString(json['label'], 'selling-unit label'),
      priceCentavos: price,
      position: position,
      createdAt: _dateTime(json['createdAt'], 'selling-unit creation date'),
      updatedAt: _dateTime(json['updatedAt'], 'selling-unit update date'),
    );
  }

  final String id;
  final String productId;
  final String label;
  final int priceCentavos;
  final int position;
  final DateTime createdAt;
  final DateTime updatedAt;
}

final class _BackupProfile {
  const _BackupProfile({
    required this.storeName,
    required this.address,
    required this.contact,
    required this.receiptFooter,
    required this.updatedAt,
  });

  factory _BackupProfile.fromJson(Map<String, Object?> json) => _BackupProfile(
    storeName: _nonEmptyString(json['storeName'], 'store name'),
    address: _string(json['address'], 'store address'),
    contact: _string(json['contact'], 'store contact'),
    receiptFooter: _string(json['receiptFooter'], 'receipt footer'),
    updatedAt: _dateTime(json['updatedAt'], 'profile update date'),
  );

  final String storeName;
  final String address;
  final String contact;
  final String receiptFooter;
  final DateTime updatedAt;
}

final class _BackupPreferences {
  const _BackupPreferences({
    required this.themeMode,
    required this.storeSetupComplete,
  });

  factory _BackupPreferences.fromJson(Map<String, Object?> json) {
    final theme = _optionalString(json['themeMode'], 'theme mode');
    if (theme != null && !{'system', 'light', 'dark'}.contains(theme)) {
      throw const FormatException('The backup theme setting is invalid.');
    }
    return _BackupPreferences(
      themeMode: theme,
      storeSetupComplete: _boolean(
        json['storeSetupComplete'],
        'setup preference',
      ),
    );
  }

  final String? themeMode;
  final bool storeSetupComplete;
}

/// Counts bytes emitted by every decompressor instead of trusting ZIP header
/// sizes, which an untrusted backup can forge.
final class _ArchiveExtractionBudget {
  _ArchiveExtractionBudget(this.maximumBytes);

  final int maximumBytes;
  int _written = 0;

  void reserve(int bytes) {
    if (bytes < 0 || _written + bytes > maximumBytes) {
      throw const _BackupException(
        CatalogTransferFailureCode.archiveTooLarge,
        'This backup expands beyond the safe restore limit.',
      );
    }
    _written += bytes;
  }
}

/// Delegates decompressed output to disk while enforcing both per-entry and
/// whole-archive byte ceilings during the write itself.
final class _CappedOutputStream extends OutputStream {
  _CappedOutputStream(
    OutputStream delegate, {
    required this.maximumBytes,
    required this.budget,
  }) : _delegate = delegate,
       super(byteOrder: delegate.byteOrder);

  static const _chunkSize = 64 * 1024;

  final OutputStream _delegate;
  final int maximumBytes;
  final _ArchiveExtractionBudget budget;
  int _written = 0;

  @override
  int get length => _written;

  @override
  bool get isOpen => _delegate.isOpen;

  @override
  void open() => _delegate.open();

  @override
  Future<void> close() => _delegate.close();

  @override
  void closeSync() => _delegate.closeSync();

  @override
  void clear() => _delegate.clear();

  @override
  void flush() => _delegate.flush();

  @override
  void writeByte(int value) {
    _reserve(1);
    _delegate.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    final count = length ?? bytes.length;
    _reserve(count);
    _delegate.writeBytes(bytes, length: count);
  }

  @override
  void writeStream(InputStream stream) {
    while (!stream.isEOS) {
      final available = stream.length;
      if (available <= 0) return;
      final count = available > _chunkSize ? _chunkSize : available;
      final bytes = stream.readBytes(count).toUint8List();
      if (bytes.isEmpty) return;
      writeBytes(bytes);
    }
  }

  @override
  Uint8List subset(int start, [int? end]) => _delegate.subset(start, end);

  void _reserve(int bytes) {
    if (bytes < 0 || _written + bytes > maximumBytes) {
      throw const _BackupException(
        CatalogTransferFailureCode.archiveTooLarge,
        'A file in this backup expands beyond the safe restore limit.',
      );
    }
    budget.reserve(bytes);
    _written += bytes;
  }
}

final class _BackupException implements Exception {
  const _BackupException(this.code, this.message, [this.cause]);

  final CatalogTransferFailureCode code;
  final String message;
  final Object? cause;
}

Map<String, Object?> _asMap(Object? value, String label) {
  if (value is! Map) throw FormatException('$label must be an object.');
  return value.cast<String, Object?>();
}

List<Object?> _asList(Object? value, String label) {
  if (value is! List) throw FormatException('$label must be a list.');
  return value.cast<Object?>();
}

String _string(Object? value, String label) {
  if (value is! String) throw FormatException('$label must be text.');
  return value;
}

String _nonEmptyString(Object? value, String label) {
  final text = _string(value, label).trim();
  if (text.isEmpty) throw FormatException('$label must not be empty.');
  return text;
}

String? _optionalString(Object? value, String label) {
  if (value == null) return null;
  final text = _string(value, label).trim();
  return text.isEmpty ? null : text;
}

int _integer(Object? value, String label) {
  if (value is! int) throw FormatException('$label must be an integer.');
  return value;
}

bool _boolean(Object? value, String label) {
  if (value is! bool) throw FormatException('$label must be true or false.');
  return value;
}

DateTime _dateTime(Object? value, String label) {
  final parsed = DateTime.tryParse(_string(value, label));
  if (parsed == null) throw FormatException('$label is invalid.');
  return parsed.toUtc();
}

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
import 'package:uuid/uuid.dart';

typedef CatalogPackImportRefresh = Future<void> Function();
typedef CatalogPackTemporaryDirectoryFactory =
    Future<Directory> Function(String prefix);

enum CatalogImportFailureCode {
  sourceMissing,
  invalidFile,
  unsupportedVersion,
  unsafeArchive,
  archiveTooLarge,
  integrityMismatch,
  validationFailed,
  ioFailure,
  databaseFailure,
  unavailable,
}

final class CatalogImportResult {
  const CatalogImportResult({
    required this.success,
    required this.message,
    this.productCount = 0,
    this.createdCount = 0,
    this.updatedCount = 0,
    this.imageCount = 0,
    this.failureCode,
    this.cause,
  });

  final bool success;
  final String message;
  final int productCount;
  final int createdCount;
  final int updatedCount;
  final int imageCount;
  final CatalogImportFailureCode? failureCode;
  final Object? cause;
}

/// Imports a distributable, offline shared-catalog ZIP.
///
/// The default mode preserves store-owned values. An explicit overwrite can
/// update matching catalog fields and the main selling price, while local
/// photos, sub-unit prices, cart rows, settings, and products missing from the
/// pack always remain untouched.
final class CatalogPackService {
  CatalogPackService({
    required database.AppDatabase database,
    required LocalProductImageStore imageStore,
    CatalogPackImportRefresh? onImportCompleted,
    CatalogPackTemporaryDirectoryFactory? temporaryDirectoryFactory,
    Uuid uuid = const Uuid(),
    DateTime Function()? now,
  }) : _database = database,
       _imageStore = imageStore,
       _onImportCompleted = onImportCompleted,
       _temporaryDirectoryFactory =
           temporaryDirectoryFactory ?? _createTemporaryDirectory,
       _uuid = uuid,
       _now = now ?? DateTime.now;

  static const packVersion = 1;
  static const packFormat = 'raze-store-catalog-pack';
  static const packExtension = 'razepack';
  static const _manifestPath = 'manifest.json';
  static const _catalogPath = 'catalog.json';
  static const _attributionPath = 'ATTRIBUTION.md';
  static const _imagePrefix = 'images/';
  static const _maximumArchiveBytes = 512 * 1024 * 1024;
  static const _maximumExpandedBytes = 768 * 1024 * 1024;
  static const _maximumEntryBytes = 8 * 1024 * 1024;
  static const _maximumImageDimension = 4096;
  static const _maximumImagePixels = 12 * 1024 * 1024;
  static const _maximumCatalogBytes = 24 * 1024 * 1024;
  static const _maximumManifestBytes = 1024 * 1024;
  static const _maximumCentralDirectoryBytes = 2 * 1024 * 1024;
  static const _maximumFileCount = 10002;
  static const _maximumProducts = 50000;
  static const _maximumImages = 10000;
  static final RegExp _portableImagePattern = RegExp(
    r'^images/[A-Za-z0-9][A-Za-z0-9_-]{0,127}\.(?:jpg|jpeg|png|webp)$',
  );

  final database.AppDatabase _database;
  final LocalProductImageStore _imageStore;
  final CatalogPackImportRefresh? _onImportCompleted;
  final CatalogPackTemporaryDirectoryFactory _temporaryDirectoryFactory;
  final Uuid _uuid;
  final DateTime Function() _now;
  bool _operationRunning = false;

  Future<CatalogImportResult> importMerging(
    String sourcePath, {
    CatalogPackImportMode mode = CatalogPackImportMode.keepExisting,
  }) async {
    if (_operationRunning) {
      return const CatalogImportResult(
        success: false,
        message: 'Another catalog file operation is already running.',
        failureCode: CatalogImportFailureCode.unavailable,
      );
    }
    _operationRunning = true;
    Directory? staging;
    final newlyPersistedImages = <String>[];
    var databaseCommitted = false;
    try {
      if (p.extension(sourcePath).toLowerCase() != '.$packExtension') {
        throw const _CatalogPackException(
          CatalogImportFailureCode.invalidFile,
          'Choose a file ending in .razepack.',
        );
      }
      final archiveFile = File(sourcePath);
      if (!await archiveFile.exists()) {
        throw const _CatalogPackException(
          CatalogImportFailureCode.sourceMissing,
          'The selected catalog pack is no longer available.',
        );
      }
      if (await archiveFile.length() > _maximumArchiveBytes) {
        throw const _CatalogPackException(
          CatalogImportFailureCode.archiveTooLarge,
          'This catalog pack is too large to import safely.',
        );
      }

      await _preflightZipArchive(archiveFile);
      staging = await _temporaryDirectoryFactory('raze_store_pack_');
      final validated = await _validateAndStageArchive(
        archiveFile: archiveFile,
        staging: staging,
      );
      final plan = await _buildMergePlan(validated.data, staging, mode);
      final installedImages = <String, String>{};
      for (final item in plan.items) {
        final portableImage = item.imageToInstall;
        if (portableImage == null) continue;
        final savedPath = await _imageStore.persistFile(
          _safeStageFile(staging, portableImage),
        );
        installedImages[item.targetId] = savedPath;
        newlyPersistedImages.add(savedPath);
      }

      final summary = await _applyMerge(plan, installedImages, mode);
      databaseCommitted = true;
      for (final oldPath in summary.supersededCatalogImages) {
        try {
          await _deleteCatalogImageIfUnreferenced(oldPath);
        } catch (_) {
          // The database commit is authoritative; stale media is harmless.
        }
      }
      try {
        await _onImportCompleted?.call();
      } catch (_) {
        // Import is committed. Provider refresh is best effort.
      }
      return CatalogImportResult(
        success: true,
        message: _successMessage(summary, mode),
        productCount: validated.data.products.length,
        createdCount: summary.createdCount,
        updatedCount: summary.updatedCount,
        imageCount: installedImages.length,
      );
    } on _CatalogPackException catch (error) {
      return CatalogImportResult(
        success: false,
        message: '${error.message} No existing products were changed.',
        failureCode: error.code,
        cause: error.cause,
      );
    } on FileSystemException catch (error) {
      return CatalogImportResult(
        success: false,
        message:
            'The selected catalog pack could not be read. No existing products were changed.',
        failureCode: CatalogImportFailureCode.ioFailure,
        cause: error,
      );
    } catch (error) {
      return CatalogImportResult(
        success: false,
        message:
            'The catalog pack could not be imported. No existing products were changed.',
        failureCode: CatalogImportFailureCode.databaseFailure,
        cause: error,
      );
    } finally {
      if (!databaseCommitted) {
        for (final path in newlyPersistedImages) {
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

  static String _successMessage(
    _MergeSummary summary,
    CatalogPackImportMode mode,
  ) {
    final updatedVerb = mode == CatalogPackImportMode.overwriteMatching
        ? 'updated'
        : 'repaired';
    return 'Catalog pack imported ${summary.createdCount} new products'
        '${summary.updatedCount == 0 ? '' : ' and $updatedVerb ${summary.updatedCount} existing products'}.';
  }

  /// Rejects unsupported ZIP features before the archive package has a chance
  /// to materialize attacker-controlled symbolic-link payloads.
  Future<void> _preflightZipArchive(File archiveFile) async {
    const eocdSize = 22;
    const maximumCommentBytes = 0xffff;
    const eocdSignature = [0x50, 0x4b, 0x05, 0x06];
    const zip64LocatorSignature = [0x50, 0x4b, 0x06, 0x07];
    const centralHeaderSignature = [0x50, 0x4b, 0x01, 0x02];
    final fileLength = await archiveFile.length();
    if (fileLength < eocdSize) {
      throw const _CatalogPackException(
        CatalogImportFailureCode.invalidFile,
        'This is not a readable Raze Store catalog pack.',
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
        throw const _CatalogPackException(
          CatalogImportFailureCode.invalidFile,
          'This is not a readable Raze Store catalog pack.',
        );
      }

      final eocd = ByteData.sublistView(tail, eocdOffset);
      final commentLength = eocd.getUint16(20, Endian.little);
      final absoluteEocdOffset = tailOffset + eocdOffset;
      if (absoluteEocdOffset + eocdSize + commentLength != fileLength) {
        throw const _CatalogPackException(
          CatalogImportFailureCode.invalidFile,
          'The catalog pack has an invalid ZIP directory.',
        );
      }
      if (eocdOffset >= 20 &&
          _bytesMatch(tail, eocdOffset - 20, zip64LocatorSignature)) {
        throw const _CatalogPackException(
          CatalogImportFailureCode.unsupportedVersion,
          'ZIP64 catalog packs are not supported.',
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
        throw const _CatalogPackException(
          CatalogImportFailureCode.unsupportedVersion,
          'ZIP64 catalog packs are not supported.',
        );
      }
      if (diskNumber != 0 ||
          directoryDisk != 0 ||
          entriesOnDisk != entryCount ||
          directoryOffset + directorySize != absoluteEocdOffset) {
        throw const _CatalogPackException(
          CatalogImportFailureCode.invalidFile,
          'The catalog pack has an invalid ZIP directory.',
        );
      }
      if (entryCount > _maximumFileCount ||
          directorySize > _maximumCentralDirectoryBytes) {
        throw const _CatalogPackException(
          CatalogImportFailureCode.archiveTooLarge,
          'This catalog pack contains too many files.',
        );
      }

      await handle.setPosition(directoryOffset);
      final directoryBytes = await handle.read(directorySize);
      if (directoryBytes.length != directorySize) {
        throw const _CatalogPackException(
          CatalogImportFailureCode.invalidFile,
          'The catalog pack has an incomplete ZIP directory.',
        );
      }
      final directory = ByteData.sublistView(directoryBytes);
      var position = 0;
      for (var entry = 0; entry < entryCount; entry++) {
        if (position + 46 > directoryBytes.length ||
            !_bytesMatch(directoryBytes, position, centralHeaderSignature)) {
          throw const _CatalogPackException(
            CatalogImportFailureCode.invalidFile,
            'The catalog pack has an invalid ZIP file entry.',
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
          throw const _CatalogPackException(
            CatalogImportFailureCode.invalidFile,
            'Encrypted or multi-disk catalog packs are not supported.',
          );
        }
        final unixMode = externalAttributes >> 16;
        final isUnix = versionMadeBy >> 8 == 3;
        if (isUnix && (unixMode & 0xf000) == 0xa000) {
          throw const _CatalogPackException(
            CatalogImportFailureCode.unsafeArchive,
            'The catalog pack contains an unsupported symbolic link.',
          );
        }
        position += 46 + fileNameLength + extraLength + entryCommentLength;
      }
      if (position != directoryBytes.length) {
        throw const _CatalogPackException(
          CatalogImportFailureCode.invalidFile,
          'The catalog pack has unexpected ZIP directory data.',
        );
      }
    } finally {
      await handle.close();
    }
  }

  Future<_ValidatedCatalogPack> _validateAndStageArchive({
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
            throw const _CatalogPackException(
              CatalogImportFailureCode.invalidFile,
              'The catalog pack contains duplicate file names.',
            );
          }
          expandedBytes += entry.size;
          if (names.length > _maximumFileCount ||
              expandedBytes > _maximumExpandedBytes) {
            throw const _CatalogPackException(
              CatalogImportFailureCode.archiveTooLarge,
              'This catalog pack expands beyond the safe import limit.',
            );
          }
        },
      );
      final manifestEntry = archive.find(_manifestPath);
      if (manifestEntry == null || manifestEntry.size > _maximumManifestBytes) {
        throw const _CatalogPackException(
          CatalogImportFailureCode.invalidFile,
          'The catalog pack manifest is missing or invalid.',
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
        throw const _CatalogPackException(
          CatalogImportFailureCode.integrityMismatch,
          'The catalog pack manifest size is incorrect.',
        );
      }
      final manifest = _CatalogPackManifest.fromJson(
        _decodeObject(await stagedManifest.readAsBytes(), 'pack manifest'),
      );
      _validateManifest(manifest, archive);

      File? stagedCatalog;
      for (final descriptor in manifest.files) {
        final entry = archive.find(descriptor.path)!;
        final stagedFile = _safeStageFile(staging, descriptor.path);
        await stagedFile.parent.create(recursive: true);
        final maximumBytes = descriptor.path == _catalogPath
            ? _maximumCatalogBytes
            : descriptor.path == _attributionPath
            ? _maximumManifestBytes
            : _maximumEntryBytes;
        final stagedSize = await _extractEntry(
          entry,
          stagedFile,
          maximumBytes: maximumBytes,
          budget: extractionBudget,
        );
        if (entry.size != descriptor.size || stagedSize != descriptor.size) {
          throw _CatalogPackException(
            CatalogImportFailureCode.integrityMismatch,
            'Catalog pack file size validation failed for ${descriptor.path}.',
          );
        }
        if (await _sha256OfFile(stagedFile) != descriptor.sha256) {
          throw _CatalogPackException(
            CatalogImportFailureCode.integrityMismatch,
            'Catalog pack integrity validation failed for ${descriptor.path}.',
          );
        }
        if (descriptor.path.startsWith(_imagePrefix)) {
          await _validateImageSignature(stagedFile, descriptor.path);
        }
        if (descriptor.path == manifest.dataFile) stagedCatalog = stagedFile;
      }
      if (stagedCatalog == null ||
          await stagedCatalog.length() > _maximumCatalogBytes) {
        throw const _CatalogPackException(
          CatalogImportFailureCode.invalidFile,
          'The catalog data file is missing or too large.',
        );
      }
      final data = _CatalogPackData.fromJson(
        _decodeObject(await stagedCatalog.readAsBytes(), 'catalog data'),
      );
      _validateData(data, manifest);
      return _ValidatedCatalogPack(manifest: manifest, data: data);
    } on _CatalogPackException {
      rethrow;
    } on ArchiveException catch (error) {
      throw _CatalogPackException(
        CatalogImportFailureCode.invalidFile,
        'This is not a readable Raze Store catalog pack.',
        error,
      );
    } on FormatException catch (error) {
      throw _CatalogPackException(
        CatalogImportFailureCode.invalidFile,
        'The catalog pack contains malformed data.',
        error,
      );
    } catch (error) {
      throw _CatalogPackException(
        CatalogImportFailureCode.invalidFile,
        'This is not a valid Raze Store catalog pack.',
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
      entry.clear();
    }
  }

  void _validateArchiveEntry(ArchiveFile entry) {
    if (!entry.isFile || entry.isSymbolicLink) {
      throw const _CatalogPackException(
        CatalogImportFailureCode.unsafeArchive,
        'The catalog pack contains an unsupported link or directory entry.',
      );
    }
    _validatePortablePath(entry.name);
    final maximumBytes = entry.name == _catalogPath
        ? _maximumCatalogBytes
        : entry.name == _manifestPath || entry.name == _attributionPath
        ? _maximumManifestBytes
        : _maximumEntryBytes;
    if (entry.size < 0 || entry.size > maximumBytes) {
      throw const _CatalogPackException(
        CatalogImportFailureCode.archiveTooLarge,
        'A file in this catalog pack is too large to import safely.',
      );
    }
  }

  void _validateManifest(_CatalogPackManifest manifest, Archive archive) {
    if (manifest.format != packFormat) {
      throw const _CatalogPackException(
        CatalogImportFailureCode.invalidFile,
        'This file is not a Raze Store catalog pack.',
      );
    }
    if (manifest.packVersion != packVersion) {
      throw const _CatalogPackException(
        CatalogImportFailureCode.unsupportedVersion,
        'This catalog pack version is not supported by this app version.',
      );
    }
    if (manifest.dataFile != _catalogPath) {
      throw const _CatalogPackException(
        CatalogImportFailureCode.invalidFile,
        'The catalog pack points to an unexpected data file.',
      );
    }
    if (manifest.revision < 1 ||
        manifest.productCount < 0 ||
        manifest.imageCount < 0) {
      throw const _CatalogPackException(
        CatalogImportFailureCode.invalidFile,
        'The catalog pack manifest contains invalid counts or revision.',
      );
    }
    if (manifest.productCount > _maximumProducts ||
        manifest.imageCount > _maximumImages) {
      throw const _CatalogPackException(
        CatalogImportFailureCode.archiveTooLarge,
        'This catalog pack contains too many records.',
      );
    }
    final paths = <String>{};
    final caseFoldedPaths = <String>{};
    for (final descriptor in manifest.files) {
      _validatePortablePath(descriptor.path);
      if (!paths.add(descriptor.path) ||
          !caseFoldedPaths.add(descriptor.path.toLowerCase()) ||
          descriptor.path == _manifestPath) {
        throw const _CatalogPackException(
          CatalogImportFailureCode.invalidFile,
          'The catalog pack manifest contains duplicate file entries.',
        );
      }
      if (descriptor.path != _catalogPath &&
          descriptor.path != _attributionPath &&
          !_portableImagePattern.hasMatch(descriptor.path)) {
        throw const _CatalogPackException(
          CatalogImportFailureCode.validationFailed,
          'The catalog pack contains an unsupported file name.',
        );
      }
      final entry = archive.find(descriptor.path);
      if (entry == null || entry.size != descriptor.size) {
        throw _CatalogPackException(
          CatalogImportFailureCode.integrityMismatch,
          'A catalog pack file is missing or changed: ${descriptor.path}.',
        );
      }
    }
    if (!paths.contains(_catalogPath) ||
        archive.files.length != paths.length + 1) {
      throw const _CatalogPackException(
        CatalogImportFailureCode.invalidFile,
        'The catalog pack contains unexpected or missing files.',
      );
    }
  }

  void _validateData(_CatalogPackData data, _CatalogPackManifest manifest) {
    if (data.products.length > _maximumProducts) {
      throw const _CatalogPackException(
        CatalogImportFailureCode.archiveTooLarge,
        'This catalog pack contains too many products.',
      );
    }
    final catalogIds = <String>{};
    final sourceIdentities = <(String, String)>{};
    final barcodes = <String>{};
    final referencedImages = <String>{};
    for (final product in data.products) {
      if (!catalogIds.add(product.catalogProductId)) {
        throw const _CatalogPackException(
          CatalogImportFailureCode.validationFailed,
          'The catalog pack repeats a catalog product ID.',
        );
      }
      if (!sourceIdentities.add((product.source, product.sourceProductId))) {
        throw const _CatalogPackException(
          CatalogImportFailureCode.validationFailed,
          'The catalog pack repeats a shared product identity.',
        );
      }
      final barcode = product.barcode;
      if (barcode != null && !barcodes.add(barcode)) {
        throw const _CatalogPackException(
          CatalogImportFailureCode.validationFailed,
          'The catalog pack repeats a product barcode.',
        );
      }
      final image = product.image;
      if (image != null) {
        _validatePortablePath(image);
        if (!_portableImagePattern.hasMatch(image) ||
            !referencedImages.add(image)) {
          throw const _CatalogPackException(
            CatalogImportFailureCode.validationFailed,
            'The catalog pack contains an invalid or repeated image reference.',
          );
        }
      }
    }
    final descriptorImages = manifest.files
        .map((item) => item.path)
        .where((path) => path.startsWith(_imagePrefix))
        .toSet();
    if (descriptorImages.length != referencedImages.length ||
        !descriptorImages.containsAll(referencedImages)) {
      throw const _CatalogPackException(
        CatalogImportFailureCode.validationFailed,
        'The catalog pack image list does not match its products.',
      );
    }
    if (manifest.productCount != data.products.length ||
        manifest.imageCount != referencedImages.length) {
      throw const _CatalogPackException(
        CatalogImportFailureCode.integrityMismatch,
        'The catalog pack record counts do not match its manifest.',
      );
    }
  }

  Future<void> _validateImageSignature(File file, String portablePath) async {
    final handle = await file.open();
    try {
      final extension = p.extension(portablePath).toLowerCase();
      final dimensions = switch (extension) {
        '.jpg' || '.jpeg' => await _readJpegDimensions(handle),
        '.png' => await _readPngDimensions(handle),
        '.webp' => await _readWebpDimensions(handle),
        _ => null,
      };
      if (dimensions == null) {
        throw _CatalogPackException(
          CatalogImportFailureCode.validationFailed,
          'Catalog image $portablePath does not contain readable dimensions for its file type.',
        );
      }
      final pixels = dimensions.width * dimensions.height;
      if (dimensions.width > _maximumImageDimension ||
          dimensions.height > _maximumImageDimension ||
          pixels > _maximumImagePixels) {
        throw _CatalogPackException(
          CatalogImportFailureCode.validationFailed,
          'Catalog image $portablePath has unsafe dimensions. Images must be no larger than 4096 pixels per side or 12 megapixels.',
        );
      }
    } finally {
      await handle.close();
    }
  }

  Future<_ImageDimensions?> _readPngDimensions(RandomAccessFile handle) async {
    await handle.setPosition(0);
    final bytes = await handle.read(24);
    if (bytes.length < 24 ||
        !_bytesMatch(bytes, 0, const [
          0x89,
          0x50,
          0x4e,
          0x47,
          0x0d,
          0x0a,
          0x1a,
          0x0a,
        ]) ||
        !_bytesMatch(bytes, 12, const [0x49, 0x48, 0x44, 0x52])) {
      return null;
    }
    final data = ByteData.sublistView(bytes);
    if (data.getUint32(8, Endian.big) != 13) return null;
    final width = data.getUint32(16, Endian.big);
    final height = data.getUint32(20, Endian.big);
    return width > 0 && height > 0 ? _ImageDimensions(width, height) : null;
  }

  Future<_ImageDimensions?> _readJpegDimensions(RandomAccessFile handle) async {
    final fileLength = await handle.length();
    if (fileLength < 4) return null;
    await handle.setPosition(0);
    final signature = await handle.read(2);
    if (!_bytesMatch(signature, 0, const [0xff, 0xd8])) return null;

    var position = 2;
    while (position < fileLength) {
      await handle.setPosition(position);
      if (await handle.readByte() != 0xff) return null;
      position++;
      int marker;
      do {
        if (position >= fileLength) return null;
        marker = await handle.readByte();
        position++;
      } while (marker == 0xff);
      if (marker == 0x00) return null;
      if (marker == 0xd9 || marker == 0xda) return null;
      if (marker == 0xd8 ||
          marker == 0x01 ||
          (marker >= 0xd0 && marker <= 0xd7)) {
        continue;
      }
      if (position + 2 > fileLength) return null;
      final lengthBytes = await handle.read(2);
      if (lengthBytes.length != 2) return null;
      position += 2;
      final segmentLength = (lengthBytes[0] << 8) | lengthBytes[1];
      if (segmentLength < 2 || position + segmentLength - 2 > fileLength) {
        return null;
      }
      if (_isJpegStartOfFrame(marker)) {
        if (segmentLength < 7) return null;
        final frameHeader = await handle.read(5);
        if (frameHeader.length != 5) return null;
        final height = (frameHeader[1] << 8) | frameHeader[2];
        final width = (frameHeader[3] << 8) | frameHeader[4];
        return width > 0 && height > 0 ? _ImageDimensions(width, height) : null;
      }
      position += segmentLength - 2;
    }
    return null;
  }

  Future<_ImageDimensions?> _readWebpDimensions(RandomAccessFile handle) async {
    final fileLength = await handle.length();
    await handle.setPosition(0);
    final bytes = await handle.read(30);
    if (bytes.length < 21 ||
        !_bytesMatch(bytes, 0, const [0x52, 0x49, 0x46, 0x46]) ||
        !_bytesMatch(bytes, 8, const [0x57, 0x45, 0x42, 0x50])) {
      return null;
    }
    final data = ByteData.sublistView(bytes);
    final riffSize = data.getUint32(4, Endian.little);
    if (riffSize + 8 != fileLength) return null;
    final chunkSize = data.getUint32(16, Endian.little);
    if (chunkSize + 20 > fileLength) return null;

    if (_bytesMatch(bytes, 12, const [0x56, 0x50, 0x38, 0x58])) {
      if (chunkSize < 10 || bytes.length < 30) return null;
      final width = 1 + _uint24LittleEndian(bytes, 24);
      final height = 1 + _uint24LittleEndian(bytes, 27);
      return _ImageDimensions(width, height);
    }
    if (_bytesMatch(bytes, 12, const [0x56, 0x50, 0x38, 0x4c])) {
      if (chunkSize < 5 || bytes.length < 25 || bytes[20] != 0x2f) return null;
      final packed =
          bytes[21] | (bytes[22] << 8) | (bytes[23] << 16) | (bytes[24] << 24);
      return _ImageDimensions(
        1 + (packed & 0x3fff),
        1 + ((packed >> 14) & 0x3fff),
      );
    }
    if (_bytesMatch(bytes, 12, const [0x56, 0x50, 0x38, 0x20])) {
      if (chunkSize < 10 ||
          bytes.length < 30 ||
          !_bytesMatch(bytes, 23, const [0x9d, 0x01, 0x2a])) {
        return null;
      }
      final width = (bytes[26] | (bytes[27] << 8)) & 0x3fff;
      final height = (bytes[28] | (bytes[29] << 8)) & 0x3fff;
      return width > 0 && height > 0 ? _ImageDimensions(width, height) : null;
    }
    return null;
  }

  static bool _isJpegStartOfFrame(int marker) =>
      (marker >= 0xc0 && marker <= 0xc3) ||
      (marker >= 0xc5 && marker <= 0xc7) ||
      (marker >= 0xc9 && marker <= 0xcb) ||
      (marker >= 0xcd && marker <= 0xcf);

  static int _uint24LittleEndian(List<int> bytes, int offset) =>
      bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16);

  Future<_MergePlan> _buildMergePlan(
    _CatalogPackData data,
    Directory staging,
    CatalogPackImportMode mode,
  ) async {
    final existingProducts = await _database
        .select(_database.storeProducts)
        .get();
    final byId = {for (final item in existingProducts) item.id: item};
    final byBarcode = {
      for (final item in existingProducts)
        if (item.barcode != null) item.barcode!: item,
    };
    final bySource = {
      for (final item in existingProducts)
        if (item.source != null && item.sourceProductId != null)
          (item.source!, item.sourceProductId!): item,
    };
    final claimedTargets = <String>{};
    final items = <_MergePlanItem>[];
    for (final product in data.products) {
      final sourceMatch = bySource[(product.source, product.sourceProductId)];
      final barcodeMatch = product.barcode == null
          ? null
          : byBarcode[product.barcode];
      if (sourceMatch != null &&
          barcodeMatch != null &&
          sourceMatch.id != barcodeMatch.id) {
        throw _CatalogPackException(
          CatalogImportFailureCode.validationFailed,
          'Catalog product ${product.catalogProductId} conflicts with two existing products.',
        );
      }
      final existing = sourceMatch ?? barcodeMatch;
      if (existing != null &&
          existing.source != null &&
          (existing.source != product.source ||
              existing.sourceProductId != product.sourceProductId)) {
        throw _CatalogPackException(
          CatalogImportFailureCode.validationFailed,
          'Catalog product ${product.catalogProductId} conflicts with another shared product.',
        );
      }
      final targetId = existing?.id ?? _uuid.v4();
      if ((byId.containsKey(targetId) && existing == null) ||
          !claimedTargets.add(targetId)) {
        throw const _CatalogPackException(
          CatalogImportFailureCode.validationFailed,
          'The catalog pack resolves more than one item to the same product.',
        );
      }

      String? usableCatalogImage;
      final oldCatalogImage = existing?.catalogImagePath?.trim();
      if (oldCatalogImage != null && oldCatalogImage.isNotEmpty) {
        final resolved = await _imageStore.resolveManagedPath(oldCatalogImage);
        if (resolved != null && await File(resolved).exists()) {
          usableCatalogImage = resolved;
        }
      }
      final imageToInstall = switch (mode) {
        CatalogPackImportMode.keepExisting =>
          usableCatalogImage == null ? product.image : null,
        CatalogPackImportMode.overwriteMatching => product.image,
      };
      if (imageToInstall != null) {
        final stagedImage = _safeStageFile(staging, imageToInstall);
        if (!await stagedImage.exists()) {
          throw _CatalogPackException(
            CatalogImportFailureCode.integrityMismatch,
            'The image for ${product.name} is missing.',
          );
        }
      }
      items.add(
        _MergePlanItem(
          product: product,
          targetId: targetId,
          existing: existing,
          imageToInstall: imageToInstall,
          existingUsableCatalogImage: usableCatalogImage,
          oldCatalogImage: oldCatalogImage,
        ),
      );
    }
    return _MergePlan(items);
  }

  Future<_MergeSummary> _applyMerge(
    _MergePlan plan,
    Map<String, String> installedImages,
    CatalogPackImportMode mode,
  ) async {
    var createdCount = 0;
    var updatedCount = 0;
    final supersededImages = <String>{};
    final now = _now().toUtc();
    await _database.transaction(() async {
      final currentProducts = await _database
          .select(_database.storeProducts)
          .get();
      final currentById = {for (final item in currentProducts) item.id: item};
      final currentByBarcode = {
        for (final item in currentProducts)
          if (item.barcode != null) item.barcode!: item,
      };
      final currentBySource = {
        for (final item in currentProducts)
          if (item.source != null && item.sourceProductId != null)
            (item.source!, item.sourceProductId!): item,
      };

      for (final item in plan.items) {
        final product = item.product;
        final sourceMatch =
            currentBySource[(product.source, product.sourceProductId)];
        final barcodeMatch = product.barcode == null
            ? null
            : currentByBarcode[product.barcode];
        final resolved = sourceMatch ?? barcodeMatch;
        if ((item.existing == null && resolved != null) ||
            (item.existing != null && resolved?.id != item.targetId) ||
            (sourceMatch != null &&
                barcodeMatch != null &&
                sourceMatch.id != barcodeMatch.id)) {
          throw const _CatalogPackException(
            CatalogImportFailureCode.validationFailed,
            'The local catalog changed during import. Please try again.',
          );
        }

        final installedImage = installedImages[item.targetId];
        if (item.existing == null) {
          if (currentById.containsKey(item.targetId)) {
            throw const _CatalogPackException(
              CatalogImportFailureCode.validationFailed,
              'A generated product ID is already in use. Please try again.',
            );
          }
          await _database
              .into(_database.storeProducts)
              .insert(
                database.StoreProductsCompanion.insert(
                  id: item.targetId,
                  barcode: Value(product.barcode),
                  source: Value(product.source),
                  sourceProductId: Value(product.sourceProductId),
                  name: product.name,
                  brand: Value(product.brand),
                  unitLabel: Value(product.unitLabel),
                  category: Value(product.category),
                  remoteImageUrl: Value(product.remoteImageUrl),
                  catalogImagePath: Value(installedImage),
                  sourceUpdatedAt: Value(product.updatedAt),
                  localImagePath: const Value(null),
                  priceCentavos: product.suggestedPriceCentavos ?? 0,
                  createdAt: Value(now),
                  updatedAt: Value(now),
                ),
              );
          createdCount++;
          continue;
        }

        final existing = currentById[item.targetId];
        if (existing == null) {
          throw const _CatalogPackException(
            CatalogImportFailureCode.validationFailed,
            'The local catalog changed during import. Please try again.',
          );
        }
        final shouldLinkSource = existing.source == null;
        final repairedPath = installedImage ?? item.existingUsableCatalogImage;
        final shouldRepairImage =
            repairedPath != null && repairedPath != existing.catalogImagePath;
        if (mode == CatalogPackImportMode.overwriteMatching) {
          await (_database.update(
            _database.storeProducts,
          )..where((table) => table.id.equals(item.targetId))).write(
            database.StoreProductsCompanion(
              barcode: Value(product.barcode),
              source: Value(product.source),
              sourceProductId: Value(product.sourceProductId),
              name: Value(product.name),
              brand: Value(product.brand),
              unitLabel: Value(product.unitLabel),
              category: Value(product.category),
              remoteImageUrl: Value(product.remoteImageUrl),
              catalogImagePath: shouldRepairImage
                  ? Value(repairedPath)
                  : const Value.absent(),
              sourceUpdatedAt: Value(product.updatedAt),
              priceCentavos: product.suggestedPriceCentavos == null
                  ? const Value.absent()
                  : Value(product.suggestedPriceCentavos!),
              updatedAt: Value(now),
            ),
          );
          if (installedImage != null &&
              item.oldCatalogImage != null &&
              item.oldCatalogImage != installedImage) {
            supersededImages.add(item.oldCatalogImage!);
          }
          updatedCount++;
          continue;
        }
        if (!shouldLinkSource && !shouldRepairImage) continue;

        await (_database.update(
          _database.storeProducts,
        )..where((table) => table.id.equals(item.targetId))).write(
          database.StoreProductsCompanion(
            source: shouldLinkSource
                ? Value(product.source)
                : const Value.absent(),
            sourceProductId: shouldLinkSource
                ? Value(product.sourceProductId)
                : const Value.absent(),
            sourceUpdatedAt: Value(
              _latestDate(existing.sourceUpdatedAt, product.updatedAt),
            ),
            catalogImagePath: shouldRepairImage
                ? Value(repairedPath)
                : const Value.absent(),
          ),
        );
        if (installedImage != null &&
            item.oldCatalogImage != null &&
            item.oldCatalogImage != installedImage) {
          supersededImages.add(item.oldCatalogImage!);
        }
        updatedCount++;
      }
    });
    return _MergeSummary(
      createdCount: createdCount,
      updatedCount: updatedCount,
      supersededCatalogImages: supersededImages,
    );
  }

  Future<void> _deleteCatalogImageIfUnreferenced(String path) async {
    final rows =
        await (_database.select(_database.storeProducts)..where(
              (table) =>
                  table.catalogImagePath.equals(path) |
                  table.localImagePath.equals(path),
            ))
            .get();
    if (rows.isNotEmpty) return;
    try {
      await _imageStore.deleteIfManaged(path);
    } catch (_) {
      // A committed import must not be reported as failed for stale cleanup.
    }
  }

  File _safeStageFile(Directory root, String portablePath) {
    _validatePortablePath(portablePath);
    final destination = p.joinAll([root.path, ...p.posix.split(portablePath)]);
    if (!p.isWithin(root.path, destination)) {
      throw const _CatalogPackException(
        CatalogImportFailureCode.unsafeArchive,
        'The catalog pack contains a path outside its staging area.',
      );
    }
    return File(destination);
  }

  void _validatePortablePath(String value) {
    if (value.isEmpty ||
        value.contains('\\') ||
        value.startsWith('/') ||
        RegExp(r'^[A-Za-z]:').hasMatch(value)) {
      throw const _CatalogPackException(
        CatalogImportFailureCode.unsafeArchive,
        'The catalog pack contains an unsafe file path.',
      );
    }
    final segments = value.split('/');
    if (segments.any(
      (segment) => segment.isEmpty || segment == '.' || segment == '..',
    )) {
      throw const _CatalogPackException(
        CatalogImportFailureCode.unsafeArchive,
        'The catalog pack contains an unsafe file path.',
      );
    }
    if (p.posix.normalize(value) != value) {
      throw const _CatalogPackException(
        CatalogImportFailureCode.unsafeArchive,
        'The catalog pack contains a non-portable file path.',
      );
    }
  }

  Map<String, Object?> _decodeObject(Uint8List bytes, String label) {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) {
      throw FormatException('The $label must be a JSON object.');
    }
    return decoded.cast<String, Object?>();
  }

  static Future<String> _sha256OfFile(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();

  static bool _bytesMatch(List<int> bytes, int offset, List<int> pattern) {
    if (offset < 0 || offset + pattern.length > bytes.length) return false;
    for (var index = 0; index < pattern.length; index++) {
      if (bytes[offset + index] != pattern[index]) return false;
    }
    return true;
  }

  static DateTime _latestDate(DateTime? existing, DateTime incoming) {
    if (existing == null || incoming.isAfter(existing)) return incoming;
    return existing;
  }

  static Future<Directory> _createTemporaryDirectory(String prefix) =>
      Directory.systemTemp.createTemp(prefix);

  static Future<void> _deleteDirectoryQuietly(Directory? directory) async {
    if (directory == null) return;
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
    } on FileSystemException {
      // Temporary cleanup must not replace the useful import result.
    }
  }
}

final class _ValidatedCatalogPack {
  const _ValidatedCatalogPack({required this.manifest, required this.data});

  final _CatalogPackManifest manifest;
  final _CatalogPackData data;
}

final class _CatalogPackManifest {
  const _CatalogPackManifest({
    required this.format,
    required this.packVersion,
    required this.packId,
    required this.revision,
    required this.createdAt,
    required this.dataFile,
    required this.files,
    required this.productCount,
    required this.imageCount,
  });

  factory _CatalogPackManifest.fromJson(Map<String, Object?> json) {
    final counts = _asMap(json['counts'], 'manifest counts');
    return _CatalogPackManifest(
      format: _boundedRequiredString(
        json['format'],
        'manifest format',
        maximum: 64,
      ),
      packVersion: _integer(json['packVersion'], 'pack version'),
      packId: _boundedRequiredString(json['packId'], 'pack ID', maximum: 160),
      revision: _integer(json['revision'], 'pack revision'),
      createdAt: _dateTime(json['createdAt'], 'pack creation date'),
      dataFile: _boundedRequiredString(
        json['dataFile'],
        'catalog data file',
        maximum: 160,
      ),
      files: _asList(json['files'], 'manifest files')
          .map(
            (item) => _CatalogPackFileDescriptor.fromJson(
              _asMap(item, 'manifest file'),
            ),
          )
          .toList(growable: false),
      productCount: _integer(counts['products'], 'product count'),
      imageCount: _integer(counts['images'], 'image count'),
    );
  }

  final String format;
  final int packVersion;
  final String packId;
  final int revision;
  final DateTime createdAt;
  final String dataFile;
  final List<_CatalogPackFileDescriptor> files;
  final int productCount;
  final int imageCount;
}

final class _CatalogPackFileDescriptor {
  const _CatalogPackFileDescriptor({
    required this.path,
    required this.size,
    required this.sha256,
  });

  factory _CatalogPackFileDescriptor.fromJson(Map<String, Object?> json) {
    final digest = _boundedRequiredString(
      json['sha256'],
      'file checksum',
      maximum: 64,
    );
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
      throw const FormatException('A catalog pack checksum is invalid.');
    }
    final size = _integer(json['size'], 'file size');
    if (size < 0) {
      throw const FormatException('A catalog pack file size is invalid.');
    }
    return _CatalogPackFileDescriptor(
      path: _boundedRequiredString(json['path'], 'file path', maximum: 240),
      size: size,
      sha256: digest,
    );
  }

  final String path;
  final int size;
  final String sha256;
}

final class _CatalogPackData {
  const _CatalogPackData(this.products);

  factory _CatalogPackData.fromJson(Map<String, Object?> json) {
    final products = _asList(json['products'], 'catalog products');
    if (products.length > CatalogPackService._maximumProducts) {
      throw const _CatalogPackException(
        CatalogImportFailureCode.archiveTooLarge,
        'This catalog pack contains too many products.',
      );
    }
    return _CatalogPackData(
      products
          .map(
            (item) =>
                _CatalogPackProduct.fromJson(_asMap(item, 'catalog product')),
          )
          .toList(growable: false),
    );
  }

  final List<_CatalogPackProduct> products;
}

final class _CatalogPackProduct {
  const _CatalogPackProduct({
    required this.catalogProductId,
    required this.source,
    required this.sourceProductId,
    required this.updatedAt,
    required this.barcode,
    required this.name,
    required this.brand,
    required this.unitLabel,
    required this.category,
    required this.remoteImageUrl,
    required this.suggestedPriceCentavos,
    required this.image,
  });

  factory _CatalogPackProduct.fromJson(Map<String, Object?> json) {
    final rawBarcode = _boundedOptionalString(
      json['barcode'],
      'product barcode',
      maximum: 160,
    );
    final parsedBarcode = rawBarcode == null
        ? null
        : Barcode.tryParse(rawBarcode);
    if (rawBarcode != null && parsedBarcode == null) {
      throw const FormatException('A catalog product barcode is invalid.');
    }
    final remoteImageUrl = _boundedOptionalString(
      json['remoteImageUrl'],
      'remote image URL',
      maximum: 2048,
    );
    if (remoteImageUrl != null) {
      final uri = Uri.tryParse(remoteImageUrl);
      if (uri == null ||
          !uri.hasAuthority ||
          uri.userInfo.isNotEmpty ||
          (uri.scheme != 'https' && uri.scheme != 'http')) {
        throw const FormatException('A remote image URL is invalid.');
      }
    }
    final suggestedPrice = json['suggestedPriceCentavos'];
    if (suggestedPrice != null &&
        (suggestedPrice is! int || suggestedPrice < 0)) {
      throw const FormatException(
        'A suggested product price must be a non-negative integer.',
      );
    }
    return _CatalogPackProduct(
      catalogProductId: _boundedRequiredString(
        json['catalogProductId'],
        'catalog product ID',
        maximum: 160,
      ),
      source: _boundedRequiredString(
        json['source'],
        'product source',
        maximum: 64,
      ),
      sourceProductId: _boundedRequiredString(
        json['sourceProductId'],
        'source product ID',
        maximum: 160,
      ),
      updatedAt: _dateTime(json['updatedAt'], 'product update date'),
      barcode: parsedBarcode?.value,
      name: _boundedRequiredString(json['name'], 'product name', maximum: 240),
      brand: _boundedOptionalString(
        json['brand'],
        'product brand',
        maximum: 240,
      ),
      unitLabel: _boundedOptionalString(
        json['unitLabel'],
        'product unit',
        maximum: 120,
      ),
      category: _boundedOptionalString(
        json['category'],
        'product category',
        maximum: 240,
      ),
      remoteImageUrl: remoteImageUrl,
      suggestedPriceCentavos: suggestedPrice as int?,
      image: _boundedOptionalString(
        json['image'],
        'catalog image',
        maximum: 240,
      ),
    );
  }

  final String catalogProductId;
  final String source;
  final String sourceProductId;
  final DateTime updatedAt;
  final String? barcode;
  final String name;
  final String? brand;
  final String? unitLabel;
  final String? category;
  final String? remoteImageUrl;
  final int? suggestedPriceCentavos;
  final String? image;
}

final class _MergePlan {
  const _MergePlan(this.items);

  final List<_MergePlanItem> items;
}

final class _MergePlanItem {
  const _MergePlanItem({
    required this.product,
    required this.targetId,
    required this.existing,
    required this.imageToInstall,
    required this.existingUsableCatalogImage,
    required this.oldCatalogImage,
  });

  final _CatalogPackProduct product;
  final String targetId;
  final database.StoreProduct? existing;
  final String? imageToInstall;
  final String? existingUsableCatalogImage;
  final String? oldCatalogImage;
}

final class _MergeSummary {
  const _MergeSummary({
    required this.createdCount,
    required this.updatedCount,
    required this.supersededCatalogImages,
  });

  final int createdCount;
  final int updatedCount;
  final Set<String> supersededCatalogImages;
}

final class _ImageDimensions {
  const _ImageDimensions(this.width, this.height);

  final int width;
  final int height;
}

final class _ArchiveExtractionBudget {
  _ArchiveExtractionBudget(this.maximumBytes);

  final int maximumBytes;
  int _written = 0;

  void reserve(int bytes) {
    if (bytes < 0 || _written + bytes > maximumBytes) {
      throw const _CatalogPackException(
        CatalogImportFailureCode.archiveTooLarge,
        'This catalog pack expands beyond the safe import limit.',
      );
    }
    _written += bytes;
  }
}

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
      throw const _CatalogPackException(
        CatalogImportFailureCode.archiveTooLarge,
        'A file in this catalog pack expands beyond its safe size limit.',
      );
    }
    budget.reserve(bytes);
    _written += bytes;
  }
}

final class _CatalogPackException implements Exception {
  const _CatalogPackException(this.code, this.message, [this.cause]);

  final CatalogImportFailureCode code;
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

String _boundedRequiredString(
  Object? value,
  String label, {
  required int maximum,
}) {
  if (value is! String) throw FormatException('$label must be text.');
  final text = value.trim();
  if (text.isEmpty || text.length > maximum) {
    throw FormatException('$label is empty or too long.');
  }
  return text;
}

String? _boundedOptionalString(
  Object? value,
  String label, {
  required int maximum,
}) {
  if (value == null) return null;
  if (value is! String) throw FormatException('$label must be text.');
  final text = value.trim();
  if (text.isEmpty) return null;
  if (text.length > maximum) throw FormatException('$label is too long.');
  return text;
}

int _integer(Object? value, String label) {
  if (value is! int) throw FormatException('$label must be an integer.');
  return value;
}

DateTime _dateTime(Object? value, String label) {
  if (value is! String) throw FormatException('$label must be text.');
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw FormatException('$label is invalid.');
  return parsed.toUtc();
}

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:raze_store/features/catalog_transfer/data/catalog_backup_service.dart';
import 'package:raze_store/features/catalog_transfer/data/catalog_csv_service.dart';
import 'package:raze_store/features/catalog_transfer/data/catalog_file_gateway.dart';
import 'package:raze_store/features/catalog_transfer/data/catalog_pack_service.dart';
import 'package:raze_store/features/catalog_transfer/domain/catalog_transfer_result.dart';

abstract interface class CatalogTransferOperations {
  Future<CatalogTransferResult> createBackup();

  Future<CatalogTransferResult> restoreBackupReplacing();

  Future<CatalogTransferResult> importCatalogPackMerging();

  Future<CatalogTransferResult> exportCsv();

  Future<CatalogTransferResult> importCsvMerging();
}

final class CatalogTransferCoordinator implements CatalogTransferOperations {
  CatalogTransferCoordinator({
    required CatalogBackupService backupService,
    required CatalogPackService packService,
    required CatalogCsvService csvService,
    required CatalogFileGateway fileGateway,
    DateTime Function()? clock,
    Future<Directory> Function()? temporaryDirectoryFactory,
  }) : _backupService = backupService,
       _packService = packService,
       _csvService = csvService,
       _fileGateway = fileGateway,
       _clock = clock ?? DateTime.now,
       _temporaryDirectoryFactory =
           temporaryDirectoryFactory ?? _createTemporaryDirectory;

  final CatalogBackupService _backupService;
  final CatalogPackService _packService;
  final CatalogCsvService _csvService;
  final CatalogFileGateway _fileGateway;
  final DateTime Function() _clock;
  final Future<Directory> Function() _temporaryDirectoryFactory;

  @override
  Future<CatalogTransferResult> createBackup() async {
    Directory? temporaryDirectory;
    try {
      temporaryDirectory = await _temporaryDirectoryFactory();
      final fileName = _fileName('raze-store', 'razestore');
      final temporaryPath = p.join(temporaryDirectory.path, fileName);
      final created = await _backupService.createArchive(
        outputPath: temporaryPath,
      );
      if (created is! CatalogTransferSuccess) return created;
      final savedPath = await _fileGateway.saveFile(
        sourcePath: temporaryPath,
        suggestedName: fileName,
        mimeTypes: const ['application/vnd.raze-store.backup'],
      );
      if (savedPath == null) {
        return const CatalogTransferCancelled(
          message: 'Backup save was cancelled.',
        );
      }
      return CatalogTransferSuccess(
        action: CatalogTransferAction.backupExport,
        message:
            'Backup saved with ${created.productCount} products and ${created.photoCount} photos.',
        productCount: created.productCount,
        sellingUnitCount: created.sellingUnitCount,
        photoCount: created.photoCount,
        path: savedPath,
      );
    } catch (error) {
      return _fileFailure(error, 'The backup could not be saved to Files.');
    } finally {
      await _deleteDirectoryQuietly(temporaryDirectory);
    }
  }

  @override
  Future<CatalogTransferResult> restoreBackupReplacing() async {
    try {
      final path = await _fileGateway.pickBackup();
      if (path == null) {
        return const CatalogTransferCancelled(
          message: 'Backup restore was cancelled.',
        );
      }
      if (p.extension(path).toLowerCase() != '.razestore') {
        return const CatalogTransferFailure(
          code: CatalogTransferFailureCode.invalidFile,
          message: 'Choose a file ending in .razestore.',
        );
      }
      return _backupService.restoreReplacing(archivePath: path);
    } catch (error) {
      return _fileFailure(error, 'The backup could not be opened from Files.');
    }
  }

  @override
  Future<CatalogTransferResult> importCatalogPackMerging() async {
    try {
      final path = await _fileGateway.pickCatalogPack();
      if (path == null) {
        return const CatalogTransferCancelled(
          message: 'Catalog pack import was cancelled.',
        );
      }
      if (p.extension(path).toLowerCase() !=
          '.${CatalogPackService.packExtension}') {
        return const CatalogTransferFailure(
          code: CatalogTransferFailureCode.invalidFile,
          message: 'Choose a file ending in .razepack.',
        );
      }

      final imported = await _packService.importMerging(path);
      if (!imported.success) {
        return CatalogTransferFailure(
          code: _packFailureCode(imported.failureCode),
          message: imported.message,
          cause: imported.cause,
        );
      }
      return CatalogTransferSuccess(
        action: CatalogTransferAction.catalogPackImport,
        message: imported.message,
        productCount: imported.productCount,
        photoCount: imported.imageCount,
      );
    } catch (error) {
      return _fileFailure(error, 'The catalog pack could not be opened.');
    }
  }

  @override
  Future<CatalogTransferResult> exportCsv() async {
    Directory? temporaryDirectory;
    try {
      temporaryDirectory = await _temporaryDirectoryFactory();
      final document = await _csvService.buildDocument();
      final fileName = _fileName('raze-store-products', 'csv');
      final temporaryPath = p.join(temporaryDirectory.path, fileName);
      await File(
        temporaryPath,
      ).writeAsString(document.contents, encoding: utf8, flush: true);
      final savedPath = await _fileGateway.saveFile(
        sourcePath: temporaryPath,
        suggestedName: fileName,
        mimeTypes: const ['text/csv'],
      );
      if (savedPath == null) {
        return const CatalogTransferCancelled(
          message: 'CSV export was cancelled.',
        );
      }
      return CatalogTransferSuccess(
        action: CatalogTransferAction.csvExport,
        message:
            'CSV saved with ${document.productCount} products and ${document.sellingUnitCount} sub-unit prices.',
        productCount: document.productCount,
        sellingUnitCount: document.sellingUnitCount,
        path: savedPath,
      );
    } catch (error) {
      return _fileFailure(error, 'The product CSV could not be exported.');
    } finally {
      await _deleteDirectoryQuietly(temporaryDirectory);
    }
  }

  @override
  Future<CatalogTransferResult> importCsvMerging() async {
    try {
      final path = await _fileGateway.pickCsv();
      if (path == null) {
        return const CatalogTransferCancelled(
          message: 'CSV import was cancelled.',
        );
      }
      if (p.extension(path).toLowerCase() != '.csv') {
        return const CatalogTransferFailure(
          code: CatalogTransferFailureCode.invalidFile,
          message: 'Choose a file ending in .csv.',
        );
      }
      return _csvService.importMerging(sourcePath: path);
    } catch (error) {
      return _fileFailure(error, 'The product CSV could not be opened.');
    }
  }

  String _fileName(String stem, String extension) {
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    final date = _clock().toLocal();
    return '$stem-${date.year}-${twoDigits(date.month)}-'
        '${twoDigits(date.day)}-${twoDigits(date.hour)}'
        '${twoDigits(date.minute)}.$extension';
  }

  CatalogTransferFailure _fileFailure(Object error, String message) {
    final unavailable = error is UnimplementedError;
    return CatalogTransferFailure(
      code: unavailable
          ? CatalogTransferFailureCode.unavailable
          : CatalogTransferFailureCode.ioFailure,
      message: unavailable
          ? 'File import and export are not available on this device.'
          : message,
      cause: error,
    );
  }

  CatalogTransferFailureCode _packFailureCode(CatalogImportFailureCode? code) =>
      switch (code) {
        CatalogImportFailureCode.sourceMissing =>
          CatalogTransferFailureCode.sourceMissing,
        CatalogImportFailureCode.invalidFile =>
          CatalogTransferFailureCode.invalidFile,
        CatalogImportFailureCode.unsupportedVersion =>
          CatalogTransferFailureCode.unsupportedVersion,
        CatalogImportFailureCode.unsafeArchive =>
          CatalogTransferFailureCode.unsafeArchive,
        CatalogImportFailureCode.archiveTooLarge =>
          CatalogTransferFailureCode.archiveTooLarge,
        CatalogImportFailureCode.integrityMismatch =>
          CatalogTransferFailureCode.integrityMismatch,
        CatalogImportFailureCode.validationFailed =>
          CatalogTransferFailureCode.validationFailed,
        CatalogImportFailureCode.ioFailure =>
          CatalogTransferFailureCode.ioFailure,
        CatalogImportFailureCode.databaseFailure =>
          CatalogTransferFailureCode.databaseFailure,
        CatalogImportFailureCode.unavailable =>
          CatalogTransferFailureCode.unavailable,
        null => CatalogTransferFailureCode.invalidFile,
      };

  static Future<Directory> _createTemporaryDirectory() =>
      Directory.systemTemp.createTemp('raze_store_transfer_');

  static Future<void> _deleteDirectoryQuietly(Directory? directory) async {
    if (directory == null) return;
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
    } on FileSystemException {
      // Temporary cleanup must not replace a useful operation result.
    }
  }
}

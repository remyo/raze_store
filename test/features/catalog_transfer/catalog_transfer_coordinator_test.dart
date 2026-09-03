import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:raze_store/core/database/app_database.dart';
import 'package:raze_store/core/storage/local_product_image_store.dart';
import 'package:raze_store/features/catalog_transfer/application/catalog_transfer_coordinator.dart';
import 'package:raze_store/features/catalog_transfer/data/catalog_backup_service.dart';
import 'package:raze_store/features/catalog_transfer/data/catalog_csv_service.dart';
import 'package:raze_store/features/catalog_transfer/data/catalog_file_gateway.dart';
import 'package:raze_store/features/catalog_transfer/data/catalog_pack_service.dart';
import 'package:raze_store/features/catalog_transfer/domain/catalog_transfer_result.dart';

void main() {
  late Directory temporaryDirectory;
  late AppDatabase database;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'raze_store_coordinator_test_',
    );
    database = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('cancelled catalog-pack picker returns a cancelled result', () async {
    final coordinator = _coordinator(
      database,
      temporaryDirectory,
      _FakeFileGateway(catalogPackPath: null),
    );

    final result = await coordinator.importCatalogPackMerging();

    expect(result, isA<CatalogTransferCancelled>());
    expect(result.message, 'Catalog pack import was cancelled.');
  });

  test('catalog-pack import rejects a different file extension', () async {
    final coordinator = _coordinator(
      database,
      temporaryDirectory,
      _FakeFileGateway(
        catalogPackPath: p.join(temporaryDirectory.path, 'catalog.zip'),
      ),
    );

    final result = await coordinator.importCatalogPackMerging();

    expect(result, isA<CatalogTransferFailure>());
    expect(
      (result as CatalogTransferFailure).code,
      CatalogTransferFailureCode.invalidFile,
    );
    expect(result.message, 'Choose a file ending in .razepack.');
  });

  test('catalog-pack service failures retain their useful message', () async {
    final coordinator = _coordinator(
      database,
      temporaryDirectory,
      _FakeFileGateway(
        catalogPackPath: p.join(temporaryDirectory.path, 'missing.razepack'),
      ),
    );

    final result = await coordinator.importCatalogPackMerging();

    expect(result, isA<CatalogTransferFailure>());
    expect(
      (result as CatalogTransferFailure).code,
      CatalogTransferFailureCode.sourceMissing,
    );
    expect(result.message, isNotEmpty);
  });
}

CatalogTransferCoordinator _coordinator(
  AppDatabase database,
  Directory temporaryDirectory,
  CatalogFileGateway fileGateway,
) {
  final imageStore = LocalProductImageStore(root: temporaryDirectory);
  return CatalogTransferCoordinator(
    backupService: CatalogBackupService(
      database: database,
      imageStore: imageStore,
    ),
    packService: CatalogPackService(database: database, imageStore: imageStore),
    csvService: CatalogCsvService(database),
    fileGateway: fileGateway,
  );
}

final class _FakeFileGateway implements CatalogFileGateway {
  const _FakeFileGateway({required this.catalogPackPath});

  final String? catalogPackPath;

  @override
  Future<String?> pickCatalogPack() async => catalogPackPath;

  @override
  Future<String?> pickBackup() async => null;

  @override
  Future<String?> pickCsv() async => null;

  @override
  Future<String?> saveFile({
    required String sourcePath,
    required String suggestedName,
    required List<String> mimeTypes,
  }) async => null;
}

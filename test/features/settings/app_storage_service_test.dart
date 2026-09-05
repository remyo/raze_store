import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:raze_store/core/storage/local_product_image_store.dart';
import 'package:raze_store/core/storage/product_photo_services.dart';
import 'package:raze_store/features/settings/data/app_storage_service.dart';

void main() {
  late Directory testRoot;
  late Directory documentsDirectory;
  late Directory supportDirectory;
  late Directory cacheDirectory;
  late Directory temporaryDirectory;

  setUp(() async {
    testRoot = await Directory.systemTemp.createTemp(
      'raze_store_app_storage_service_test_',
    );
    documentsDirectory = Directory(p.join(testRoot.path, 'documents'));
    supportDirectory = Directory(p.join(testRoot.path, 'support'));
    cacheDirectory = Directory(p.join(testRoot.path, 'cache'));
    temporaryDirectory = Directory(p.join(testRoot.path, 'temporary'));
    await Future.wait([
      documentsDirectory.create(recursive: true),
      supportDirectory.create(recursive: true),
      cacheDirectory.create(recursive: true),
      temporaryDirectory.create(recursive: true),
    ]);
  });

  tearDown(() async {
    if (await testRoot.exists()) await testRoot.delete(recursive: true);
  });

  AppStorageService buildService({
    DateTime Function()? clock,
    Directory? temporaryDirectoryOverride,
  }) {
    return AppStorageService(
      documentsDirectoryResolver: () async => documentsDirectory,
      supportDirectoryResolver: () async => supportDirectory,
      cacheDirectoryResolver: () async => cacheDirectory,
      temporaryDirectoryResolver: () async =>
          temporaryDirectoryOverride ?? temporaryDirectory,
      clock: clock,
    );
  }

  test(
    'measures every app-owned category and excludes external copies',
    () async {
      final productImages = Directory(
        p.join(supportDirectory.path, LocalProductImageStore.directoryName),
      );
      await _writeBytes(p.join(productImages.path, 'owner.jpg'), 3);
      await _writeBytes(p.join(productImages.path, 'catalog.png'), 7);
      await _writeBytes(p.join(supportDirectory.path, 'unrelated.bin'), 100);

      await _writeBytes(
        p.join(documentsDirectory.path, 'raze_store.sqlite'),
        10,
      );
      await _writeBytes(
        p.join(documentsDirectory.path, 'raze_store.sqlite-wal'),
        11,
      );
      await _writeBytes(
        p.join(documentsDirectory.path, 'raze_store.sqlite-shm'),
        12,
      );
      await _writeBytes(
        p.join(documentsDirectory.path, 'raze_store.sqlite-journal'),
        13,
      );
      await _writeBytes(
        p.join(documentsDirectory.path, 'unrelated.sqlite'),
        100,
      );

      await _writeBytes(p.join(cacheDirectory.path, 'network', 'cover.jpg'), 4);
      await _writeBytes(
        p.join(
          temporaryDirectory.path,
          OnDeviceProductBackgroundRemover.directoryName,
          'working.png',
        ),
        5,
      );
      await _writeBytes(
        p.join(
          temporaryDirectory.path,
          '11111111-1111-4111-8111-111111111111',
          'raze-store-receipt-20260903-143000.png',
        ),
        9,
      );
      await _writeBytes(
        p.join(
          temporaryDirectory.path,
          'raze_store_receipts',
          '123456-raze-store-receipt-20260903-143001.png',
        ),
        8,
      );
      await _writeBytes(
        p.join(
          temporaryDirectory.path,
          'raze_store_transfer_stale',
          'backup.razestore',
        ),
        6,
      );
      await _writeBytes(
        p.join(temporaryDirectory.path, 'unrelated-temporary-file.bin'),
        103,
      );
      await _writeBytes(
        p.join(
          testRoot.path,
          'gallery',
          'raze-store-receipt-20260903-143000.png',
        ),
        101,
      );

      final measuredAt = DateTime.utc(2026, 9, 3, 5, 30);
      final usage = await buildService(clock: () => measuredAt).loadUsage();

      expect(usage.productImageBytes, 10);
      expect(usage.productImageFileCount, 2);
      expect(usage.databaseBytes, 46);
      expect(usage.databaseFileCount, 4);
      expect(usage.temporaryReceiptBytes, 17);
      expect(usage.temporaryReceiptFileCount, 2);
      expect(usage.backgroundRemovalBytes, 5);
      expect(usage.backgroundRemovalFileCount, 1);
      expect(usage.cacheBytes, 10);
      expect(usage.cacheFileCount, 2);
      expect(usage.temporaryBytes, 32);
      expect(usage.temporaryFileCount, 5);
      expect(usage.totalManagedBytes, 88);
      expect(usage.totalFileCount, 11);
      expect(usage.unreadableEntryCount, 0);
      expect(usage.measuredAt, measuredAt);
    },
  );

  test(
    'does not double-count when cache and temporary roots are equal',
    () async {
      await _writeBytes(p.join(cacheDirectory.path, 'cache.bin'), 8);
      await _writeBytes(
        p.join(
          cacheDirectory.path,
          OnDeviceProductBackgroundRemover.directoryName,
          'working.png',
        ),
        12,
      );
      await _writeBytes(
        p.join(
          cacheDirectory.path,
          'receipt',
          'raze-store-receipt-20260903-143000.png',
        ),
        16,
      );

      final usage = await buildService(
        temporaryDirectoryOverride: cacheDirectory,
      ).loadUsage();

      expect(usage.cacheBytes, 8);
      expect(usage.backgroundRemovalBytes, 12);
      expect(usage.temporaryReceiptBytes, 16);
      expect(usage.temporaryBytes, 36);
      expect(usage.temporaryFileCount, 3);
    },
  );

  test('missing managed locations report zero without creating them', () async {
    final missingRoot = Directory(p.join(testRoot.path, 'missing'));
    final service = AppStorageService(
      documentsDirectoryResolver: () async =>
          Directory(p.join(missingRoot.path, 'documents')),
      supportDirectoryResolver: () async =>
          Directory(p.join(missingRoot.path, 'support')),
      cacheDirectoryResolver: () async =>
          Directory(p.join(missingRoot.path, 'cache')),
      temporaryDirectoryResolver: () async =>
          Directory(p.join(missingRoot.path, 'temporary')),
    );

    final usage = await service.loadUsage();

    expect(usage.totalManagedBytes, 0);
    expect(usage.totalFileCount, 0);
    expect(usage.unreadableEntryCount, 0);
    expect(await missingRoot.exists(), isFalse);
  });

  test(
    'keeps partial totals when a resolver and file are unreadable',
    () async {
      final productImages = Directory(
        p.join(supportDirectory.path, LocalProductImageStore.directoryName),
      );
      await _writeBytes(p.join(productImages.path, 'readable.jpg'), 4);
      await _writeBytes(p.join(productImages.path, 'changing.jpg'), 6);
      await _writeBytes(p.join(cacheDirectory.path, 'cache.bin'), 8);
      await _writeBytes(p.join(cacheDirectory.path, 'changing-cache.bin'), 10);

      final service = AppStorageService(
        documentsDirectoryResolver: () async => throw const FileSystemException(
          'Documents are temporarily unavailable',
        ),
        supportDirectoryResolver: () async => supportDirectory,
        cacheDirectoryResolver: () async => cacheDirectory,
        temporaryDirectoryResolver: () async => temporaryDirectory,
        fileLengthReader: (file) {
          if (p.basename(file.path).startsWith('changing')) {
            throw const FileSystemException('The file disappeared');
          }
          return file.length();
        },
      );

      final usage = await service.loadUsage();

      expect(usage.productImageBytes, 4);
      expect(usage.productImageFileCount, 1);
      expect(usage.databaseBytes, 0);
      expect(usage.cacheBytes, 8);
      expect(usage.totalManagedBytes, 12);
      expect(usage.unreadableEntryCount, 3);
    },
  );

  test('clearTemporaryFiles preserves durable and external files', () async {
    final productImage = await _writeBytes(
      p.join(
        supportDirectory.path,
        LocalProductImageStore.directoryName,
        'product.jpg',
      ),
      17,
    );
    final database = await _writeBytes(
      p.join(documentsDirectory.path, 'raze_store.sqlite'),
      19,
    );
    final externalReceipt = await _writeBytes(
      p.join(
        testRoot.path,
        'files-export',
        'raze-store-receipt-20260903-143000.png',
      ),
      23,
    );
    await _writeBytes(p.join(cacheDirectory.path, 'root-cache.bin'), 5);
    await _writeBytes(p.join(cacheDirectory.path, 'nested', 'cache.bin'), 7);
    await _writeBytes(
      p.join(
        temporaryDirectory.path,
        '11111111-1111-4111-8111-111111111111',
        'raze-store-receipt-20260903-143000.png',
      ),
      11,
    );
    await _writeBytes(
      p.join(
        temporaryDirectory.path,
        'raze_store_receipts',
        '123456-raze-store-receipt-20260903-143001.png',
      ),
      7,
    );
    await _writeBytes(
      p.join(
        temporaryDirectory.path,
        OnDeviceProductBackgroundRemover.directoryName,
        'working.png',
      ),
      13,
    );
    await _writeBytes(
      p.join(
        temporaryDirectory.path,
        'raze_store_export_stale',
        'products.csv',
      ),
      17,
    );
    final unrelatedTemporaryFile = await _writeBytes(
      p.join(temporaryDirectory.path, 'belongs-to-something-else.tmp'),
      31,
    );
    final externalTarget = await _writeBytes(
      p.join(testRoot.path, 'outside', 'keep.bin'),
      29,
    );
    Link? cacheLink;
    if (!Platform.isWindows) {
      cacheLink = Link(p.join(cacheDirectory.path, 'outside-link'));
      await cacheLink.create(externalTarget.path);
    }

    final service = buildService();
    final result = await service.clearTemporaryFiles();

    expect(result.clearedBytes, 60);
    expect(result.clearedFileCount, 6);
    expect(result.failureCount, 0);
    expect(result.completedWithoutFailures, isTrue);
    expect(await cacheDirectory.exists(), isTrue);
    expect(await temporaryDirectory.exists(), isTrue);
    expect(await cacheDirectory.list().toList(), isEmpty);
    expect(
      (await temporaryDirectory.list().toList()).map(
        (entry) => p.basename(entry.path),
      ),
      ['belongs-to-something-else.tmp'],
    );
    expect(await productImage.exists(), isTrue);
    expect(await database.exists(), isTrue);
    expect(await externalReceipt.exists(), isTrue);
    expect(await externalTarget.exists(), isTrue);
    expect(await unrelatedTemporaryFile.exists(), isTrue);
    if (cacheLink != null) expect(await cacheLink.exists(), isFalse);

    final usage = await service.loadUsage();
    expect(usage.productImageBytes, 17);
    expect(usage.databaseBytes, 19);
    expect(usage.temporaryBytes, 0);
  });

  test('clearTemporaryFiles tolerates missing and unavailable roots', () async {
    final missingRoot = Directory(p.join(testRoot.path, 'missing-cache'));
    final service = AppStorageService(
      cacheDirectoryResolver: () async => missingRoot,
      temporaryDirectoryResolver: () async =>
          throw const FileSystemException('Temporary storage is unavailable'),
    );

    final result = await service.clearTemporaryFiles();

    expect(result.clearedBytes, 0);
    expect(result.clearedFileCount, 0);
    expect(result.failureCount, 1);
    expect(result.completedWithoutFailures, isFalse);
    expect(await missingRoot.exists(), isFalse);
  });
}

Future<File> _writeBytes(String path, int length) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  return file.writeAsBytes(List<int>.filled(length, 1), flush: true);
}

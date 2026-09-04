import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/core/database/app_database.dart' show AppDatabase;
import 'package:raze_store/core/storage/local_product_image_store.dart';
import 'package:raze_store/features/cart/data/local_cart_repository.dart';
import 'package:raze_store/features/catalog/data/local_catalog_repository.dart';
import 'package:raze_store/features/catalog/domain/catalog_categories.dart';
import 'package:raze_store/features/catalog/domain/catalog_product.dart';
import 'package:raze_store/features/catalog_transfer/data/catalog_backup_service.dart';
import 'package:raze_store/features/catalog_transfer/domain/catalog_transfer_result.dart';
import 'package:raze_store/features/sales/data/local_sales_repository.dart';
import 'package:raze_store/features/settings/application/settings_providers.dart';
import 'package:raze_store/features/settings/data/local_settings_repository.dart';
import 'package:raze_store/features/settings/domain/app_preferences.dart';
import 'package:raze_store/features/settings/domain/store_profile.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory testRoot;
  late AppDatabase sourceDatabase;
  late AppDatabase targetDatabase;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    testRoot = await Directory.systemTemp.createTemp('raze_store_backup_test_');
    sourceDatabase = AppDatabase.forTesting(NativeDatabase.memory());
    targetDatabase = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await sourceDatabase.close();
    await targetDatabase.close();
    if (await testRoot.exists()) await testRoot.delete(recursive: true);
  });

  test(
    'round trip restores products, units, photos, profile, and theme',
    () async {
      final sourceImages = LocalProductImageStore(
        root: Directory('${testRoot.path}/source'),
      );
      final pickedPhoto = File('${testRoot.path}/coffee.jpg');
      await pickedPhoto.writeAsBytes([1, 2, 3, 4, 5]);
      final savedPhoto = await sourceImages.persistFile(pickedPhoto);
      final catalogPhoto = File('${testRoot.path}/catalog-coffee.webp');
      await catalogPhoto.writeAsBytes([5, 4, 3, 2, 1]);
      final savedCatalogPhoto = await sourceImages.persistFile(catalogPhoto);
      final sourceUpdatedAt = DateTime.utc(2026, 8, 31, 4, 30);
      final sourceCatalog = LocalCatalogRepository(sourceDatabase);
      final product = await sourceCatalog.createProduct(
        ProductDraft(
          id: 'coffee-product',
          barcode: '4800012345678',
          name: '3-in-1 Coffee',
          brand: 'Sample Brand',
          unitLabel: 'Pack',
          category: 'Coffee & Beverages',
          localImagePath: savedPhoto,
          catalogImagePath: savedCatalogPhoto,
          sourceUpdatedAt: sourceUpdatedAt,
          source: 'open_food_facts',
          sourceProductId: '4800012345678',
          priceCentavos: 7200,
          sellingUnits: [
            SellingUnitDraft(
              id: 'coffee-stick',
              label: 'Stick',
              priceCentavos: 800,
            ),
          ],
        ),
      );
      await LocalSettingsRepository(sourceDatabase).saveStoreProfile(
        const StoreProfile(
          storeName: 'Aling Nena Store',
          address: 'Quezon City',
          contact: '09171234567',
          receiptFooter: 'Maraming salamat po!',
        ),
      );
      final sourceCart = LocalCartRepository(sourceDatabase);
      await sourceCart.addProduct(product);
      await sourceCart.addProduct(
        product,
        saleOption: product.saleOptions.last,
      );
      final completedAt = DateTime.utc(2026, 9, 2, 14, 45);
      final sourceSale = await LocalSalesRepository(
        sourceDatabase,
        now: () => completedAt,
      ).completeCurrentCart(cashReceivedCentavos: 10000);
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString('theme_mode', 'dark');
      await preferences.setBool(
        'raze_store.onboarding.store_setup_complete',
        true,
      );
      await preferences.setStringList(customCatalogCategoriesPreferenceKey, [
        'Mobile Load',
        'Frozen Treats',
      ]);
      await preferences.setBool(scannerSoundEnabledPreferenceKey, false);
      await preferences.setBool(scannerVibrationEnabledPreferenceKey, false);
      await preferences.setInt(scannerRepeatCooldownPreferenceKey, 1500);
      await preferences.setBool(autoAddMainUnitOnScanPreferenceKey, false);
      await preferences.setString(
        backupReminderFrequencyPreferenceKey,
        BackupReminderFrequency.monthly.name,
      );
      await preferences.setString(
        backupReminderAnchorPreferenceKey,
        DateTime.utc(2026, 8, 1).toIso8601String(),
      );
      await preferences.setString(
        lastSuccessfulBackupPreferenceKey,
        DateTime.utc(2026, 8, 20).toIso8601String(),
      );
      await preferences.setString(
        backupReminderSnoozedUntilPreferenceKey,
        DateTime.utc(2026, 9, 5).toIso8601String(),
      );

      final archivePath = '${testRoot.path}/store.razestore';
      final exported = await CatalogBackupService(
        database: sourceDatabase,
        imageStore: sourceImages,
      ).createArchive(outputPath: archivePath);

      expect(exported, isA<CatalogTransferSuccess>());
      expect((exported as CatalogTransferSuccess).photoCount, 2);
      expect(await File(archivePath).exists(), isTrue);
      final archive = ZipDecoder().decodeBytes(
        await File(archivePath).readAsBytes(),
      );
      final archiveData =
          (jsonDecode(
                    utf8.decode(
                      archive.files
                          .singleWhere((entry) => entry.name == 'data.json')
                          .readBytes()!,
                    ),
                  )
                  as Map)
              .cast<String, Object?>();
      final archivedPreferences = (archiveData['preferences'] as Map)
          .cast<String, Object?>();
      expect(archivedPreferences['scannerSoundEnabled'], isFalse);
      expect(archivedPreferences['scannerVibrationEnabled'], isFalse);
      expect(archivedPreferences['scannerRepeatCooldownMs'], 1500);
      expect(archivedPreferences['autoAddMainUnitOnScan'], isFalse);
      expect(archivedPreferences['backupReminderFrequency'], 'monthly');
      expect(archivedPreferences, isNot(contains('reminderAnchorAtUtc')));
      expect(archivedPreferences, isNot(contains('lastSuccessfulBackupAtUtc')));
      expect(archivedPreferences, isNot(contains('snoozedUntilUtc')));

      final targetImages = LocalProductImageStore(
        root: Directory('${testRoot.path}/target'),
      );
      final oldPhotoSource = File('${testRoot.path}/old.jpg');
      await oldPhotoSource.writeAsBytes([9, 9, 9]);
      final oldPhoto = await targetImages.persistFile(oldPhotoSource);
      final targetCatalog = LocalCatalogRepository(targetDatabase);
      final oldProduct = await targetCatalog.createProduct(
        ProductDraft(
          id: 'replace-me',
          name: 'Old Product',
          localImagePath: oldPhoto,
          priceCentavos: 100,
        ),
      );
      await LocalCartRepository(targetDatabase).addProduct(oldProduct);
      await preferences.setString('theme_mode', 'light');
      await preferences.setBool(
        'raze_store.onboarding.store_setup_complete',
        false,
      );
      await preferences.setStringList(customCatalogCategoriesPreferenceKey, [
        'Old Category',
      ]);
      await preferences.setBool(scannerSoundEnabledPreferenceKey, true);
      await preferences.setBool(scannerVibrationEnabledPreferenceKey, true);
      await preferences.setInt(scannerRepeatCooldownPreferenceKey, 500);
      await preferences.setBool(autoAddMainUnitOnScanPreferenceKey, true);
      await preferences.setString(
        backupReminderFrequencyPreferenceKey,
        BackupReminderFrequency.off.name,
      );
      final receivingAnchor = DateTime.utc(2026, 9, 1);
      final receivingLastBackup = DateTime.utc(2026, 9, 2);
      final receivingSnooze = DateTime.utc(2026, 9, 6);
      await preferences.setString(
        backupReminderAnchorPreferenceKey,
        receivingAnchor.toIso8601String(),
      );
      await preferences.setString(
        lastSuccessfulBackupPreferenceKey,
        receivingLastBackup.toIso8601String(),
      );
      await preferences.setString(
        backupReminderSnoozedUntilPreferenceKey,
        receivingSnooze.toIso8601String(),
      );

      final restored = await CatalogBackupService(
        database: targetDatabase,
        imageStore: targetImages,
      ).restoreReplacing(archivePath: archivePath);

      expect(restored, isA<CatalogTransferSuccess>());
      final restoredProducts = await targetCatalog.searchProducts('');
      expect(restoredProducts, hasLength(1));
      final restoredProduct = restoredProducts.single;
      expect(restoredProduct.name, '3-in-1 Coffee');
      expect(restoredProduct.priceCentavos, 7200);
      expect(restoredProduct.sellingUnits, hasLength(1));
      expect(restoredProduct.sellingUnits.single.label, 'Stick');
      expect(restoredProduct.sellingUnits.single.priceCentavos, 800);
      expect(restoredProduct.localImagePath, isNot(savedPhoto));
      expect(await File(restoredProduct.localImagePath!).readAsBytes(), [
        1,
        2,
        3,
        4,
        5,
      ]);
      expect(restoredProduct.catalogImagePath, isNot(savedCatalogPhoto));
      expect(await File(restoredProduct.catalogImagePath!).readAsBytes(), [
        5,
        4,
        3,
        2,
        1,
      ]);
      expect(restoredProduct.sourceUpdatedAt?.toUtc(), sourceUpdatedAt);
      expect(await File(oldPhoto).exists(), isFalse);
      expect(
        (await LocalCartRepository(targetDatabase).getDraft()).isEmpty,
        isTrue,
      );
      final restoredSale = await LocalSalesRepository(
        targetDatabase,
      ).getSale(sourceSale.id);
      expect(restoredSale, isNotNull);
      expect(restoredSale!.completedAt, completedAt);
      expect(restoredSale.storeNameSnapshot, 'Aling Nena Store');
      expect(restoredSale.cashReceivedCentavos, 10000);
      expect(restoredSale.lines, hasLength(2));
      expect(restoredSale.totalCentavos, 8000);
      expect(
        restoredSale.lines.every((line) => line.imagePathSnapshot == null),
        isTrue,
      );
      final profile = await LocalSettingsRepository(
        targetDatabase,
      ).getStoreProfile();
      expect(profile.storeName, 'Aling Nena Store');
      expect(profile.receiptFooter, 'Maraming salamat po!');
      expect(preferences.getString('theme_mode'), 'dark');
      expect(
        preferences.getBool('raze_store.onboarding.store_setup_complete'),
        isTrue,
      );
      expect(preferences.getStringList(customCatalogCategoriesPreferenceKey), [
        'Frozen Treats',
        'Mobile Load',
      ]);
      expect(preferences.getBool(scannerSoundEnabledPreferenceKey), isFalse);
      expect(
        preferences.getBool(scannerVibrationEnabledPreferenceKey),
        isFalse,
      );
      expect(preferences.getInt(scannerRepeatCooldownPreferenceKey), 1500);
      expect(preferences.getBool(autoAddMainUnitOnScanPreferenceKey), isFalse);
      expect(
        preferences.getString(backupReminderFrequencyPreferenceKey),
        BackupReminderFrequency.monthly.name,
      );
      expect(
        preferences.getString(backupReminderAnchorPreferenceKey),
        receivingAnchor.toIso8601String(),
      );
      expect(
        preferences.getString(lastSuccessfulBackupPreferenceKey),
        receivingLastBackup.toIso8601String(),
      );
      expect(
        preferences.getString(backupReminderSnoozedUntilPreferenceKey),
        receivingSnooze.toIso8601String(),
      );
    },
  );

  test('restores version 1 backups without pack-owned fields', () async {
    await LocalCatalogRepository(sourceDatabase).createProduct(
      ProductDraft(
        id: 'legacy-product',
        barcode: '4800012345678',
        name: 'Legacy product',
        source: 'open_food_facts',
        sourceProductId: '4800012345678',
        priceCentavos: 1250,
      ),
    );
    final archiveFile = File('${testRoot.path}/legacy-v1.razestore');
    await CatalogBackupService(
      database: sourceDatabase,
      imageStore: LocalProductImageStore(
        root: Directory('${testRoot.path}/legacy-source'),
      ),
    ).createArchive(outputPath: archiveFile.path);
    await _rewriteAsVersion1(archiveFile);

    final result = await CatalogBackupService(
      database: targetDatabase,
      imageStore: LocalProductImageStore(
        root: Directory('${testRoot.path}/legacy-target'),
      ),
    ).restoreReplacing(archivePath: archiveFile.path);

    expect(result, isA<CatalogTransferSuccess>());
    final product = (await LocalCatalogRepository(
      targetDatabase,
    ).searchProducts('')).single;
    expect(product.id, 'legacy-product');
    expect(product.catalogImagePath, isNull);
    expect(product.sourceUpdatedAt, isNull);
  });

  test(
    'version 3 backups without behavior fields preserve device preferences',
    () async {
      await LocalCatalogRepository(sourceDatabase).createProduct(
        ProductDraft(id: 'source-product', name: 'Source', priceCentavos: 500),
      );
      final archiveFile = File('${testRoot.path}/legacy-v3.razestore');
      await CatalogBackupService(
        database: sourceDatabase,
        imageStore: LocalProductImageStore(
          root: Directory('${testRoot.path}/legacy-v3-source'),
        ),
      ).createArchive(outputPath: archiveFile.path);
      await _removeBehaviorPreferences(archiveFile);

      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(scannerSoundEnabledPreferenceKey, false);
      await preferences.setBool(scannerVibrationEnabledPreferenceKey, false);
      await preferences.setInt(scannerRepeatCooldownPreferenceKey, 2000);
      await preferences.setBool(autoAddMainUnitOnScanPreferenceKey, false);
      await preferences.setString(
        backupReminderFrequencyPreferenceKey,
        BackupReminderFrequency.off.name,
      );

      final result = await CatalogBackupService(
        database: targetDatabase,
        imageStore: LocalProductImageStore(
          root: Directory('${testRoot.path}/legacy-v3-target'),
        ),
      ).restoreReplacing(archivePath: archiveFile.path);

      expect(result, isA<CatalogTransferSuccess>());
      expect(preferences.getBool(scannerSoundEnabledPreferenceKey), isFalse);
      expect(
        preferences.getBool(scannerVibrationEnabledPreferenceKey),
        isFalse,
      );
      expect(preferences.getInt(scannerRepeatCooldownPreferenceKey), 2000);
      expect(preferences.getBool(autoAddMainUnitOnScanPreferenceKey), isFalse);
      expect(
        preferences.getString(backupReminderFrequencyPreferenceKey),
        BackupReminderFrequency.off.name,
      );
    },
  );

  test(
    'missing managed photo fails export without creating a backup',
    () async {
      final images = LocalProductImageStore(
        root: Directory('${testRoot.path}/missing-source'),
      );
      final photo = File('${testRoot.path}/temporary.png');
      await photo.writeAsBytes([1]);
      final managedPath = await images.persistFile(photo);
      await LocalCatalogRepository(sourceDatabase).createProduct(
        ProductDraft(
          name: 'Missing photo product',
          localImagePath: managedPath,
          priceCentavos: 500,
        ),
      );
      await File(managedPath).delete();
      final archivePath = '${testRoot.path}/missing.razestore';

      final result = await CatalogBackupService(
        database: sourceDatabase,
        imageStore: images,
      ).createArchive(outputPath: archivePath);

      expect(result, isA<CatalogTransferFailure>());
      expect(
        (result as CatalogTransferFailure).code,
        CatalogTransferFailureCode.sourceMissing,
      );
      expect(await File(archivePath).exists(), isFalse);
    },
  );

  test('rebases an iOS-relocated managed photo and repairs its path', () async {
    final images = LocalProductImageStore(
      root: Directory('${testRoot.path}/new-container'),
    );
    final pickedPhoto = File('${testRoot.path}/relocated.png');
    await pickedPhoto.writeAsBytes([4, 8, 15, 16, 23, 42]);
    final currentPath = await images.persistFile(pickedPhoto);
    final stalePath =
        '/old/app-container/product_images/${currentPath.split('/').last}';
    final catalog = LocalCatalogRepository(sourceDatabase);
    await catalog.createProduct(
      ProductDraft(
        id: 'relocated-photo',
        name: 'Relocated photo',
        localImagePath: stalePath,
        priceCentavos: 100,
      ),
    );
    final archivePath = '${testRoot.path}/relocated.razestore';

    final result = await CatalogBackupService(
      database: sourceDatabase,
      imageStore: images,
    ).createArchive(outputPath: archivePath);

    expect(result, isA<CatalogTransferSuccess>());
    expect(
      (await catalog.getProduct('relocated-photo'))!.localImagePath,
      currentPath,
    );
    expect(await File(archivePath).exists(), isTrue);
  });

  test('reports a warning if appearance preferences cannot restore', () async {
    await LocalCatalogRepository(sourceDatabase).createProduct(
      ProductDraft(id: 'source', name: 'Source', priceCentavos: 500),
    );
    final archivePath = '${testRoot.path}/preferences.razestore';
    await CatalogBackupService(
      database: sourceDatabase,
      imageStore: LocalProductImageStore(
        root: Directory('${testRoot.path}/preferences-source'),
      ),
    ).createArchive(outputPath: archivePath);

    final result = await CatalogBackupService(
      database: targetDatabase,
      imageStore: LocalProductImageStore(
        root: Directory('${testRoot.path}/preferences-target'),
      ),
      preferencesFactory: () async => throw StateError('storage unavailable'),
    ).restoreReplacing(archivePath: archivePath);

    expect(result, isA<CatalogTransferSuccess>());
    expect(result.message, contains('some app settings could not be restored'));
    expect(
      (await LocalCatalogRepository(
        targetDatabase,
      ).searchProducts('')).single.id,
      'source',
    );
  });

  test('rejects archive path traversal before changing current data', () async {
    final currentCatalog = LocalCatalogRepository(targetDatabase);
    await currentCatalog.createProduct(
      ProductDraft(id: 'keep-me', name: 'Keep Me', priceCentavos: 1000),
    );
    final archivePath = '${testRoot.path}/traversal.razestore';
    final archive = Archive()
      ..add(ArchiveFile.bytes('../escaped.txt', utf8.encode('unsafe')));
    await File(archivePath).writeAsBytes(ZipEncoder().encode(archive));

    final result = await CatalogBackupService(
      database: targetDatabase,
      imageStore: LocalProductImageStore(
        root: Directory('${testRoot.path}/target-traversal'),
      ),
      temporaryDirectoryFactory: (prefix) =>
          Directory('${testRoot.path}/staging').create(),
    ).restoreReplacing(archivePath: archivePath);

    expect(result, isA<CatalogTransferFailure>());
    expect(
      (result as CatalogTransferFailure).code,
      CatalogTransferFailureCode.unsafeArchive,
    );
    expect((await currentCatalog.searchProducts('')).single.id, 'keep-me');
    expect(await File('${testRoot.path}/escaped.txt').exists(), isFalse);
  });

  test('rejects case-equivalent archive entry names', () async {
    final archivePath = '${testRoot.path}/case-duplicate.razestore';
    final archive = Archive()
      ..add(ArchiveFile.bytes('data.json', utf8.encode('{}')))
      ..add(ArchiveFile.bytes('DATA.JSON', utf8.encode('{}')));
    await File(archivePath).writeAsBytes(ZipEncoder().encode(archive));

    final result = await CatalogBackupService(
      database: targetDatabase,
      imageStore: LocalProductImageStore(
        root: Directory('${testRoot.path}/case-target'),
      ),
    ).restoreReplacing(archivePath: archivePath);

    expect(result, isA<CatalogTransferFailure>());
    expect(
      (result as CatalogTransferFailure).code,
      CatalogTransferFailureCode.invalidFile,
    );
  });

  test('caps decompressed bytes even when ZIP sizes are forged', () async {
    final archivePath = '${testRoot.path}/forged-size.razestore';
    final archive = Archive()
      ..add(
        ArchiveFile.bytes(
          'manifest.json',
          List<int>.filled(1024 * 1024 + 1, 'a'.codeUnitAt(0)),
        ),
      );
    final encoded = ZipEncoder().encode(archive);
    _writeZipUncompressedSize(encoded, const [0x50, 0x4b, 0x03, 0x04], 22, 16);
    _writeZipUncompressedSize(encoded, const [0x50, 0x4b, 0x01, 0x02], 24, 16);
    await File(archivePath).writeAsBytes(encoded);

    final result = await CatalogBackupService(
      database: targetDatabase,
      imageStore: LocalProductImageStore(
        root: Directory('${testRoot.path}/forged-target'),
      ),
    ).restoreReplacing(archivePath: archivePath);

    expect(result, isA<CatalogTransferFailure>());
    expect(
      (result as CatalogTransferFailure).code,
      CatalogTransferFailureCode.archiveTooLarge,
    );
  });

  test('rejects Unix symlinks before archive decoding', () async {
    final archivePath = '${testRoot.path}/symlink.razestore';
    final archive = Archive()
      ..add(
        ArchiveFile.bytes(
          'manifest.json',
          List<int>.filled(1024 * 1024, 'a'.codeUnitAt(0)),
        ),
      );
    final encoded = ZipEncoder().encode(archive);
    final centralOffset = _indexOfBytes(encoded, const [
      0x50,
      0x4b,
      0x01,
      0x02,
    ]);
    if (centralOffset < 0) throw StateError('ZIP header not found in fixture.');
    _writeLittleEndian(encoded, centralOffset + 4, 2, (3 << 8) | 20);
    _writeLittleEndian(encoded, centralOffset + 38, 4, 0xa1ff << 16);
    await File(archivePath).writeAsBytes(encoded);

    final result = await CatalogBackupService(
      database: targetDatabase,
      imageStore: LocalProductImageStore(
        root: Directory('${testRoot.path}/symlink-target'),
      ),
    ).restoreReplacing(archivePath: archivePath);

    expect(result, isA<CatalogTransferFailure>());
    expect(
      (result as CatalogTransferFailure).code,
      CatalogTransferFailureCode.unsafeArchive,
    );
  });

  test('rejects checksum changes before replacing the catalog', () async {
    await LocalCatalogRepository(sourceDatabase).createProduct(
      ProductDraft(id: 'source', name: 'Source', priceCentavos: 500),
    );
    final sourceImages = LocalProductImageStore(
      root: Directory('${testRoot.path}/checksum-source'),
    );
    final archivePath = '${testRoot.path}/tampered.razestore';
    await CatalogBackupService(
      database: sourceDatabase,
      imageStore: sourceImages,
    ).createArchive(outputPath: archivePath);
    final decoded = ZipDecoder().decodeBytes(
      await File(archivePath).readAsBytes(),
    );
    final rewritten = Archive();
    for (final entry in decoded.files) {
      rewritten.add(
        ArchiveFile.bytes(
          entry.name,
          entry.name == 'data.json' ? utf8.encode('{}') : entry.readBytes()!,
        ),
      );
    }
    await File(archivePath).writeAsBytes(ZipEncoder().encode(rewritten));

    final currentCatalog = LocalCatalogRepository(targetDatabase);
    await currentCatalog.createProduct(
      ProductDraft(id: 'keep-me', name: 'Keep Me', priceCentavos: 1000),
    );
    final result = await CatalogBackupService(
      database: targetDatabase,
      imageStore: LocalProductImageStore(
        root: Directory('${testRoot.path}/checksum-target'),
      ),
    ).restoreReplacing(archivePath: archivePath);

    expect(result, isA<CatalogTransferFailure>());
    expect(
      (result as CatalogTransferFailure).code,
      CatalogTransferFailureCode.integrityMismatch,
    );
    expect((await currentCatalog.searchProducts('')).single.id, 'keep-me');
  });
}

Future<void> _rewriteAsVersion1(File file) async {
  final archive = ZipDecoder().decodeBytes(await file.readAsBytes());
  final entries = <String, List<int>>{
    for (final entry in archive.files) entry.name: entry.readBytes()!,
  };
  final data = (jsonDecode(utf8.decode(entries['data.json']!)) as Map)
      .cast<String, Object?>();
  final preferences = data['preferences'] as Map;
  preferences.remove('customCategories');
  _removeBehaviorPreferenceFields(preferences);
  for (final value in (data['products'] as List).cast<Object?>()) {
    final product = (value as Map).cast<String, Object?>();
    product.remove('catalogImage');
    product.remove('sourceUpdatedAt');
  }
  final dataBytes = utf8.encode(jsonEncode(data));
  entries['data.json'] = dataBytes;

  final manifest = (jsonDecode(utf8.decode(entries['manifest.json']!)) as Map)
      .cast<String, Object?>();
  manifest['archiveVersion'] = 1;
  manifest['databaseSchemaVersion'] = 4;
  for (final value in (manifest['files'] as List).cast<Object?>()) {
    final descriptor = (value as Map).cast<String, Object?>();
    if (descriptor['path'] == 'data.json') {
      descriptor['size'] = dataBytes.length;
      descriptor['sha256'] = sha256.convert(dataBytes).toString();
    }
  }
  entries['manifest.json'] = utf8.encode(jsonEncode(manifest));

  final rewritten = Archive();
  for (final entry in entries.entries) {
    rewritten.add(ArchiveFile.bytes(entry.key, entry.value));
  }
  await file.writeAsBytes(ZipEncoder().encode(rewritten));
}

Future<void> _removeBehaviorPreferences(File file) async {
  final archive = ZipDecoder().decodeBytes(await file.readAsBytes());
  final entries = <String, List<int>>{
    for (final entry in archive.files) entry.name: entry.readBytes()!,
  };
  final data = (jsonDecode(utf8.decode(entries['data.json']!)) as Map)
      .cast<String, Object?>();
  _removeBehaviorPreferenceFields(data['preferences'] as Map);
  final dataBytes = utf8.encode(jsonEncode(data));
  entries['data.json'] = dataBytes;

  final manifest = (jsonDecode(utf8.decode(entries['manifest.json']!)) as Map)
      .cast<String, Object?>();
  for (final value in (manifest['files'] as List).cast<Object?>()) {
    final descriptor = (value as Map).cast<String, Object?>();
    if (descriptor['path'] == 'data.json') {
      descriptor['size'] = dataBytes.length;
      descriptor['sha256'] = sha256.convert(dataBytes).toString();
    }
  }
  entries['manifest.json'] = utf8.encode(jsonEncode(manifest));

  final rewritten = Archive();
  for (final entry in entries.entries) {
    rewritten.add(ArchiveFile.bytes(entry.key, entry.value));
  }
  await file.writeAsBytes(ZipEncoder().encode(rewritten));
}

void _removeBehaviorPreferenceFields(Map preferences) {
  preferences
    ..remove('scannerSoundEnabled')
    ..remove('scannerVibrationEnabled')
    ..remove('scannerRepeatCooldownMs')
    ..remove('autoAddMainUnitOnScan')
    ..remove('backupReminderFrequency');
}

void _writeZipUncompressedSize(
  List<int> bytes,
  List<int> signature,
  int sizeOffset,
  int value,
) {
  final signatureOffset = _indexOfBytes(bytes, signature);
  if (signatureOffset < 0) throw StateError('ZIP header not found in fixture.');
  final offset = signatureOffset + sizeOffset;
  _writeLittleEndian(bytes, offset, 4, value);
}

void _writeLittleEndian(List<int> bytes, int offset, int length, int value) {
  for (var byte = 0; byte < length; byte++) {
    bytes[offset + byte] = (value >> (8 * byte)) & 0xff;
  }
}

int _indexOfBytes(List<int> bytes, List<int> pattern) {
  for (var start = 0; start <= bytes.length - pattern.length; start++) {
    var matches = true;
    for (var index = 0; index < pattern.length; index++) {
      if (bytes[start + index] != pattern[index]) {
        matches = false;
        break;
      }
    }
    if (matches) return start;
  }
  return -1;
}

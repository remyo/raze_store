import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/core/database/app_database.dart';
import 'package:raze_store/core/database/database_provider.dart';
import 'package:raze_store/core/storage/local_product_image_store.dart';
import 'package:raze_store/core/storage/product_photo_services.dart';
import 'package:raze_store/features/catalog/data/local_catalog_repository.dart';
import 'package:raze_store/features/catalog/domain/catalog_product.dart';
import 'package:raze_store/features/catalog_transfer/application/catalog_transfer_providers.dart';
import 'package:raze_store/features/catalog_transfer/data/catalog_backup_service.dart';
import 'package:raze_store/features/catalog_transfer/domain/catalog_transfer_result.dart';
import 'package:raze_store/features/gcash/gcash_fee_settings.dart';
import 'package:raze_store/features/gcash/gcash_record.dart';
import 'package:raze_store/features/gcash/gcash_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory testRoot;
  late AppDatabase sourceDatabase;
  late AppDatabase targetDatabase;
  late SharedPreferences preferences;
  late CatalogBackupService sourceService;
  late CatalogBackupService targetService;
  late File archive;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    testRoot = await Directory.systemTemp.createTemp('gcash_fee_backup_test_');
    sourceDatabase = AppDatabase.forTesting(NativeDatabase.memory());
    targetDatabase = AppDatabase.forTesting(NativeDatabase.memory());
    sourceService = CatalogBackupService(
      database: sourceDatabase,
      imageStore: LocalProductImageStore(
        root: Directory('${testRoot.path}/source'),
      ),
    );
    targetService = CatalogBackupService(
      database: targetDatabase,
      imageStore: LocalProductImageStore(
        root: Directory('${testRoot.path}/target'),
      ),
    );
    archive = File('${testRoot.path}/store.razestore');
  });

  tearDown(() async {
    await sourceDatabase.close();
    await targetDatabase.close();
    await testRoot.delete(recursive: true);
  });

  test('restores shared charges and refreshes loaded fee settings', () async {
    final configured = _configuredFees();
    await preferences.setString(
      gcashFeeSettingsPreferenceKey,
      jsonEncode(configured.toJson()),
    );
    await GcashRepository(sourceDatabase).save(_historicalRecord('source'));
    expect(
      await sourceService.createArchive(outputPath: archive.path),
      isA<CatalogTransferSuccess>(),
    );

    await preferences.setString(
      gcashFeeSettingsPreferenceKey,
      jsonEncode(GcashFeeSettings.defaults().toJson()),
    );
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(targetDatabase),
        localProductImageStoreProvider.overrideWithValue(
          LocalProductImageStore(root: Directory('${testRoot.path}/target')),
        ),
      ],
    );
    addTearDown(container.dispose);
    expect(
      (await container.read(gcashFeeSettingsProvider.future)).toJson(),
      GcashFeeSettings.defaults().toJson(),
    );

    expect(
      await container
          .read(catalogBackupServiceProvider)
          .restoreReplacing(archivePath: archive.path),
      isA<CatalogTransferSuccess>(),
    );
    expect(
      jsonDecode(preferences.getString(gcashFeeSettingsPreferenceKey)!),
      configured.toJson(),
    );
    expect(
      (await container.read(gcashFeeSettingsProvider.future)).toJson(),
      configured.toJson(),
    );
    final historical = (await GcashRepository(
      targetDatabase,
    ).watch().first).single;
    expect(historical.fee, 775);
    expect(configured.feeFor(historical.kind, historical.amount), 1250);
  });

  test(
    'restores legacy Cash In charges for both kinds without changing recorded fees',
    () async {
      await GcashRepository(
        sourceDatabase,
      ).save(_historicalRecord('cash-out', kind: GcashKind.cashOut));
      expect(
        await sourceService.createArchive(outputPath: archive.path),
        isA<CatalogTransferSuccess>(),
      );
      final shared = _configuredFees().shared;
      await _rewritePreferences(archive, (values) {
        values['gcashFeeSettings'] = {
          'version': 1,
          'cashIn': shared.toJson(),
          'cashOut': shared.copyWith(autoFillEnabled: false).toJson(),
        };
      });

      expect(
        await targetService.restoreReplacing(archivePath: archive.path),
        isA<CatalogTransferSuccess>(),
      );
      final restored = GcashFeeSettings.fromJson(
        jsonDecode(preferences.getString(gcashFeeSettingsPreferenceKey)!)
            as Map<String, dynamic>,
      );
      expect(restored.toJson()['version'], 2);
      for (final kind in GcashKind.values) {
        expect(restored.autoFillFor(kind), isTrue);
        expect(restored.feeFor(kind, 50000), 1250);
      }
      final historical = (await GcashRepository(
        targetDatabase,
      ).watch().first).single;
      expect(historical.kind, GcashKind.cashOut);
      expect(historical.fee, 775);
    },
  );

  test('backs up default schedules when no fee preference was saved', () async {
    expect(preferences.containsKey(gcashFeeSettingsPreferenceKey), isFalse);
    expect(
      await sourceService.createArchive(outputPath: archive.path),
      isA<CatalogTransferSuccess>(),
    );
    await preferences.setString(
      gcashFeeSettingsPreferenceKey,
      jsonEncode(_configuredFees().toJson()),
    );

    expect(
      await targetService.restoreReplacing(archivePath: archive.path),
      isA<CatalogTransferSuccess>(),
    );
    expect(
      jsonDecode(preferences.getString(gcashFeeSettingsPreferenceKey)!),
      GcashFeeSettings.defaults().toJson(),
    );
  });

  test(
    'older backups without fee settings retain the device schedules',
    () async {
      expect(
        await sourceService.createArchive(outputPath: archive.path),
        isA<CatalogTransferSuccess>(),
      );
      await _rewritePreferences(archive, (values) {
        values.remove('gcashFeeSettings');
      });
      final existing = jsonEncode(_configuredFees().toJson());
      await preferences.setString(gcashFeeSettingsPreferenceKey, existing);

      expect(
        await targetService.restoreReplacing(archivePath: archive.path),
        isA<CatalogTransferSuccess>(),
      );
      expect(preferences.getString(gcashFeeSettingsPreferenceKey), existing);
    },
  );

  final invalidSettings = <String, Object?>{
    'null settings': null,
    'non-object settings': 'invalid',
    'negative fee': {
      ...GcashFeeSettings.defaults().toJson(),
      'shared': {
        'autoFillEnabled': true,
        'tiers': [
          {'upperLimitCentavos': 50000, 'feeCentavos': -1},
        ],
      },
    },
  };
  for (final invalid in invalidSettings.entries) {
    test('rejects ${invalid.key} before replacing data or settings', () async {
      expect(
        await sourceService.createArchive(outputPath: archive.path),
        isA<CatalogTransferSuccess>(),
      );
      await _rewritePreferences(archive, (values) {
        values['gcashFeeSettings'] = invalid.value;
      });
      final existing = jsonEncode(_configuredFees().toJson());
      await preferences.setString(gcashFeeSettingsPreferenceKey, existing);
      await GcashRepository(targetDatabase).save(_historicalRecord('keep'));
      final catalog = LocalCatalogRepository(targetDatabase);
      await catalog.createProduct(
        ProductDraft(id: 'keep', name: 'Keep Product', priceCentavos: 100),
      );

      final result = await targetService.restoreReplacing(
        archivePath: archive.path,
      );

      expect(result, isA<CatalogTransferFailure>());
      expect(
        (result as CatalogTransferFailure).code,
        CatalogTransferFailureCode.invalidFile,
      );
      expect((await catalog.searchProducts('')).single.id, 'keep');
      expect(
        (await GcashRepository(targetDatabase).watch().first).single.id,
        'keep',
      );
      expect(preferences.getString(gcashFeeSettingsPreferenceKey), existing);
    });
  }

  test('invalid saved fees stop export without creating an archive', () async {
    await preferences.setString(gcashFeeSettingsPreferenceKey, '{broken');

    final result = await sourceService.createArchive(outputPath: archive.path);

    expect(result, isA<CatalogTransferFailure>());
    expect(
      (result as CatalogTransferFailure).code,
      CatalogTransferFailureCode.validationFailed,
    );
    expect(await archive.exists(), isFalse);
  });

  test(
    'failed fee preference write rolls back the previous app settings',
    () async {
      expect(
        await sourceService.createArchive(outputPath: archive.path),
        isA<CatalogTransferSuccess>(),
      );
      final existing = jsonEncode(_configuredFees().toJson());
      await preferences.setString(gcashFeeSettingsPreferenceKey, existing);
      await preferences.setString('theme_mode', 'dark');
      await preferences.setBool(
        'raze_store.onboarding.store_setup_complete',
        false,
      );
      final failingPreferences = _FailFirstFeeSavePreferences(preferences);
      final service = CatalogBackupService(
        database: targetDatabase,
        imageStore: LocalProductImageStore(
          root: Directory('${testRoot.path}/target'),
        ),
        preferencesFactory: () async => failingPreferences,
      );

      final result = await service.restoreReplacing(archivePath: archive.path);

      expect(result, isA<CatalogTransferSuccess>());
      expect(
        result.message,
        contains('some app settings could not be restored'),
      );
      expect(failingPreferences.feeWriteFailed, isTrue);
      expect(preferences.getString(gcashFeeSettingsPreferenceKey), existing);
      expect(preferences.getString('theme_mode'), 'dark');
      expect(
        preferences.getBool('raze_store.onboarding.store_setup_complete'),
        isFalse,
      );
    },
  );
}

GcashFeeSettings _configuredFees() => GcashFeeSettings(
  shared: GcashFeeSchedule(
    autoFillEnabled: true,
    tiers: const [
      GcashFeeTier(upperLimitCentavos: 50000, feeCentavos: 1250),
      GcashFeeTier(upperLimitCentavos: 125000, feeCentavos: 2750),
    ],
  ),
);

GcashRecord _historicalRecord(String id, {GcashKind kind = GcashKind.cashIn}) =>
    GcashRecord(
      id: id,
      kind: kind,
      name: 'Customer',
      number: '09171234567',
      amount: 50000,
      fee: 775,
      reference: '12345678',
      date: DateTime(2026, 9, 5, 12),
    );

Future<void> _rewritePreferences(
  File archiveFile,
  void Function(Map<String, dynamic>) update,
) async {
  final archive = ZipDecoder().decodeBytes(await archiveFile.readAsBytes());
  final entries = <String, List<int>>{
    for (final file in archive.files) file.name: file.readBytes()!,
  };
  final data =
      jsonDecode(utf8.decode(entries['data.json']!)) as Map<String, dynamic>;
  update(data['preferences'] as Map<String, dynamic>);
  final dataBytes = utf8.encode(jsonEncode(data));
  entries['data.json'] = dataBytes;
  final manifest =
      jsonDecode(utf8.decode(entries['manifest.json']!))
          as Map<String, dynamic>;
  for (final descriptor in manifest['files'] as List) {
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
  await archiveFile.writeAsBytes(ZipEncoder().encode(rewritten));
}

class _FailFirstFeeSavePreferences implements SharedPreferences {
  _FailFirstFeeSavePreferences(this.delegate);

  final SharedPreferences delegate;
  bool feeWriteFailed = false;

  @override
  Future<bool> setString(String key, String value) async {
    final saved = await delegate.setString(key, value);
    if (key == gcashFeeSettingsPreferenceKey && !feeWriteFailed) {
      feeWriteFailed = true;
      return false;
    }
    return saved;
  }

  @override
  bool containsKey(String key) => delegate.containsKey(key);

  @override
  Object? get(String key) => delegate.get(key);

  @override
  String? getString(String key) => delegate.getString(key);

  @override
  bool? getBool(String key) => delegate.getBool(key);

  @override
  List<String>? getStringList(String key) => delegate.getStringList(key);

  @override
  Future<bool> setBool(String key, bool value) => delegate.setBool(key, value);

  @override
  Future<bool> setInt(String key, int value) => delegate.setInt(key, value);

  @override
  Future<bool> setStringList(String key, List<String> value) =>
      delegate.setStringList(key, value);

  @override
  Future<bool> remove(String key) => delegate.remove(key);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

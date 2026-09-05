import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/core/database/app_database.dart';
import 'package:raze_store/core/database/database_provider.dart';
import 'package:raze_store/core/storage/local_product_image_store.dart';
import 'package:raze_store/features/catalog_transfer/data/catalog_backup_service.dart';
import 'package:raze_store/features/catalog_transfer/domain/catalog_transfer_result.dart';
import 'package:raze_store/features/gcash/gcash_record.dart';
import 'package:raze_store/features/gcash/gcash_parser.dart';
import 'package:raze_store/features/gcash/gcash_repository.dart';
import 'package:raze_store/features/gcash/gcash_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

GcashRecord record({
  String id = 'one',
  String reference = '123456789',
  GcashKind kind = GcashKind.cashIn,
  DateTime? date,
  Uint8List? receipt,
}) => GcashRecord(
  id: id,
  kind: kind,
  name: 'Sample Customer',
  number: '09171234567',
  amount: 50000,
  fee: 1000,
  reference: reference,
  date: date ?? DateTime(2026, 9, 5, 12, 30),
  receipt: receipt,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reads labeled values without choosing total with service fee', () {
    final result = parseGcashReceipt('''GCash
Sent to
Sample Customer
09171234567
Amount
PHP 500.00
Service fee PHP 10.00
Total PHP 510.00
Ref. No. 1234 5678 9012
Sep 5, 2026 12:30 PM''', GcashKind.cashIn);
    expect(result.name, 'Sample Customer');
    expect(result.number, '09171234567');
    expect(result.amount, 50000);
    expect(result.reference, '123456789012');
    expect(result.date, DateTime(2026, 9, 5, 12, 30));
  });
  test('ambiguous amounts and mobile numbers stay empty; Total is not To', () {
    final result = parseGcashReceipt(
      'Total PHP 510.00\nPHP 500.00\n09171234567\n09179876543',
      GcashKind.cashIn,
    );
    expect(result.name, isNull);
    expect(result.amount, isNull);
    expect(result.number, isNull);
    expect(result.reference, isNull);
    expect(result.date, isNull);
  });
  test('cash out uses sender; masked details are retained', () {
    final result = parseGcashReceipt(
      'From: J*** D**\nMobile number: 09*****1234\nAmount: ₱1,200.50\nTransaction ID: 12345678',
      GcashKind.cashOut,
    );
    expect(result.name, 'J*** D**');
    expect(result.number, '09*****1234');
    expect(result.amount, 120050);
  });
  test('amount parser never rounds excessive decimals', () {
    expect(gcashCentavos('1,234.50'), 123450);
    expect(gcashCentavos('0.1'), 10);
    expect(gcashCentavos('-100'), isNull);
    expect(gcashCentavos('1.001'), isNull);
  });

  late AppDatabase database;
  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
  });
  tearDown(() => database.close());

  test(
    'duplicate normalized references do not overwrite; same id can edit',
    () async {
      final repository = GcashRepository(database);
      await repository.save(record(reference: '1234 5678'));
      await expectLater(
        repository.save(record(id: 'two', reference: '1234-5678')),
        throwsA(isA<DuplicateGcashReference>()),
      );
      expect(await repository.watch().first, hasLength(1));
      await repository.save(
        record(reference: '1234 5678', kind: GcashKind.cashOut),
      );
      expect((await repository.watch().first).single.kind, GcashKind.cashOut);
      expect(await database.select(database.sales).get(), isEmpty);
      await repository.delete('one');
      expect(await repository.watch().first, isEmpty);
    },
  );
  test(
    'date bounds, kind filter and pagination are applied in storage',
    () async {
      final repository = GcashRepository(database);
      await repository.save(
        record(id: 'old', reference: '1111', date: DateTime(2026, 9, 1)),
      );
      await repository.save(
        record(id: 'new', reference: '2222', kind: GcashKind.cashOut),
      );
      await repository.save(
        record(id: 'end', reference: '3333', date: DateTime(2026, 9, 6)),
      );
      final result = await repository
          .watch(
            since: DateTime(2026, 9, 5),
            until: DateTime(2026, 9, 6),
            kind: GcashKind.cashOut,
            limit: 1,
          )
          .first;
      expect(result.map((e) => e.id), ['new']);
      final totals = await repository
          .totals(since: DateTime(2026, 9, 5), until: DateTime(2026, 9, 6))
          .first;
      expect(totals, (cashIn: 0, cashOut: 50000, fees: 1000));
    },
  );
  test('v7 migration adds GCash without modifying existing data', () async {
    final old = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (sqlite) {
          sqlite.execute(
            "CREATE TABLE sentinel (name TEXT); INSERT INTO sentinel VALUES ('existing'); PRAGMA user_version = 7;",
          );
        },
      ),
    );
    addTearDown(old.close);
    await GcashRepository(old).save(record());
    expect(
      (await old.customSelect('SELECT name FROM sentinel').getSingle())
          .read<String>('name'),
      'existing',
    );
    expect(await old.select(old.gcashEntries).get(), hasLength(1));
  });
  test(
    'full backup round trip includes receipt bytes and replaces GCash records',
    () async {
      SharedPreferences.setMockInitialValues({});
      final root = await Directory.systemTemp.createTemp('gcash_backup_test_');
      addTearDown(() => root.delete(recursive: true));
      final target = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(target.close);
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aXuoAAAAASUVORK5CYII=',
      );
      await GcashRepository(database).save(record(receipt: png));
      await GcashRepository(target).save(record(id: 'old', reference: '9999'));
      final path = '${root.path}/backup.razestore';
      final sourceService = CatalogBackupService(
        database: database,
        imageStore: LocalProductImageStore(
          root: Directory('${root.path}/source'),
        ),
      );
      final targetService = CatalogBackupService(
        database: target,
        imageStore: LocalProductImageStore(
          root: Directory('${root.path}/target'),
        ),
      );
      expect(
        await sourceService.createArchive(outputPath: path),
        isA<CatalogTransferSuccess>(),
      );
      expect(
        await targetService.restoreReplacing(archivePath: path),
        isA<CatalogTransferSuccess>(),
      );
      final restored = (await GcashRepository(target).watch().first).single;
      expect(restored.id, 'one');
      expect(restored.receipt, png);
      expect(restored.amount, 50000);
      expect(restored.fee, 1000);
    },
  );
  testWidgets('manual cash in requires details and date before saving', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: const MaterialApp(home: GcashFormScreen(kind: GcashKind.cashIn)),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('gcash-save-record')).hitTestable(),
      findsOneWidget,
    );
    await tester.tap(find.text('Save GCash record'));
    await tester.pumpAndSettle();
    expect(find.text('Required'), findsWidgets);
    expect(await database.select(database.gcashEntries).get(), isEmpty);
  });
}

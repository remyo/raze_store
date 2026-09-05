import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/core/database/app_database.dart';
import 'package:raze_store/features/gcash/gcash_parser.dart';
import 'package:raze_store/features/gcash/gcash_record.dart';
import 'package:raze_store/features/gcash/gcash_repository.dart';

final _receipt = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aXuoAAAAASUVORK5CYII=',
);

GcashRecord _record({
  String id = 'synthetic-record',
  String name = 'JU•• D••',
  String number = '+63 917 000 0000',
  int amount = 100000,
  int fee = 2000,
  String reference = '0040 0000 0000 1',
  DateTime? date,
  Uint8List? receipt,
}) => GcashRecord(
  id: id,
  kind: GcashKind.cashIn,
  name: name,
  number: number,
  amount: amount,
  fee: fee,
  reference: reference,
  date: date ?? DateTime(2026, 7, 4, 13, 47),
  receipt: receipt ?? _receipt,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temporary;
  late File file;
  AppDatabase? database;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp(
      'gcash_persistence_regression_',
    );
    file = File('${temporary.path}/synthetic.sqlite');
    database = AppDatabase.forTesting(NativeDatabase(file));
  });

  tearDown(() async {
    await database?.close();
    await temporary.delete(recursive: true);
  });

  Future<void> reopen() async {
    final previous = database;
    database = null;
    await previous?.close();
    database = AppDatabase.forTesting(NativeDatabase(file));
  }

  test(
    'saved record and receipt survive closing and reopening SQLite',
    () async {
      await GcashRepository(database!).save(_record());
      await reopen();

      final saved = (await GcashRepository(database!).watch().first).single;
      expect(saved.id, 'synthetic-record');
      expect(saved.name, 'JU•• D••');
      expect(saved.number, '+63 917 000 0000');
      expect(saved.amount, 100000);
      expect(saved.fee, 2000);
      expect(saved.reference, '0040000000001');
      expect(saved.date, DateTime(2026, 7, 4, 13, 47));
      expect(saved.receipt, orderedEquals(_receipt));
      expect(await database!.select(database!.sales).get(), isEmpty);
    },
  );

  test(
    'older OCR receipt is persisted but outside a Today history query',
    () async {
      final details = parseGcashReceipt('''
Express Send
JU•• D••
+63 917 000 0000
Sent via GCash
Amount
1,000.00
Total Amount Sent
₱1000.00
Ref No. 0040000000001 Jul 4, 2026 1:47 PM
''', GcashKind.cashIn);
      expect(details.date, DateTime(2026, 7, 4, 13, 47));
      await GcashRepository(database!).save(
        _record(
          name: details.name!,
          number: details.number!,
          amount: details.amount!,
          reference: details.reference!,
          date: details.date,
        ),
      );
      await reopen();

      final repository = GcashRepository(database!);
      expect(
        await repository
            .watch(since: DateTime(2026, 9, 5), until: DateTime(2026, 9, 6))
            .first,
        isEmpty,
        reason: 'History filters the printed transaction date, not save time.',
      );
      expect(
        await repository
            .totals(since: DateTime(2026, 9, 5), until: DateTime(2026, 9, 6))
            .first,
        (cashIn: 0, cashOut: 0, fees: 0),
      );
      expect(
        await repository
            .watch(since: DateTime(2026, 7, 4), until: DateTime(2026, 7, 5))
            .first,
        hasLength(1),
      );
      expect(await repository.totals().first, (
        cashIn: 100000,
        cashOut: 0,
        fees: 2000,
      ));
    },
  );

  test('save notifies an already subscribed history stream', () async {
    final repository = GcashRepository(database!);
    final history = StreamIterator(repository.watch());
    addTearDown(history.cancel);
    expect(await history.moveNext(), isTrue);
    expect(history.current, isEmpty);
    final changed = history.moveNext();

    await repository.save(_record());

    expect(await changed.timeout(const Duration(seconds: 5)), isTrue);
    expect(history.current.single.reference, '0040000000001');
    expect(history.current.single.receipt, orderedEquals(_receipt));
  });

  test(
    'duplicate reference keeps the original record and image intact',
    () async {
      final repository = GcashRepository(database!);
      await repository.save(_record());
      await expectLater(
        repository.save(
          _record(
            id: 'different-record',
            reference: '0040-0000-0000-1',
            name: 'A different customer',
            amount: 900000,
          ),
        ),
        throwsA(isA<DuplicateGcashReference>()),
      );
      await reopen();

      final original = (await GcashRepository(database!).watch().first).single;
      expect(original.id, 'synthetic-record');
      expect(original.name, 'JU•• D••');
      expect(original.amount, 100000);
      expect(original.receipt, orderedEquals(_receipt));
    },
  );

  test('supported field and money limits persist and reopen exactly', () async {
    await GcashRepository(database!).save(
      _record(
        name: 'N' * 150,
        number: '0' * 40,
        amount: 99999999999,
        fee: 99999999999,
        reference: 'R' * 80,
        date: DateTime(2200, 12, 31, 23, 59),
      ),
    );
    await reopen();

    final saved = (await GcashRepository(database!).watch().first).single;
    expect(saved.name.length, 150);
    expect(saved.number.length, 40);
    expect(saved.amount, 99999999999);
    expect(saved.fee, 99999999999);
    expect(saved.reference.length, 80);
    expect(saved.date, DateTime(2200, 12, 31, 23, 59));
  });

  test('invalid values never partly overwrite an existing record', () async {
    final repository = GcashRepository(database!);
    await repository.save(_record());
    final invalidRecords = [
      _record(name: 'N' * 151),
      _record(number: '0' * 41),
      _record(amount: 100000000000),
      _record(fee: 100000000000),
      _record(reference: 'R' * 81),
      _record(date: DateTime(2201)),
      _record(receipt: Uint8List.fromList([1, 2, 3])),
      _record(
        receipt: Uint8List(2000001)..setRange(0, _receipt.length, _receipt),
      ),
    ];
    for (final invalid in invalidRecords) {
      await expectLater(repository.save(invalid), throwsFormatException);
    }
    await reopen();

    final saved = (await GcashRepository(database!).watch().first).single;
    expect(saved.name, 'JU•• D••');
    expect(saved.number, '+63 917 000 0000');
    expect(saved.amount, 100000);
    expect(saved.fee, 2000);
    expect(saved.reference, '0040000000001');
    expect(saved.receipt, orderedEquals(_receipt));
  });

  test(
    'SQLite write failure is surfaced and the next save can recover',
    () async {
      final repository = GcashRepository(database!);
      await database!.customStatement('''
      CREATE TRIGGER gcash_test_reject_insert
      BEFORE INSERT ON gcash_entries
      BEGIN SELECT RAISE(ABORT, 'Synthetic write failure'); END
    ''');
      await expectLater(repository.save(_record()), throwsA(isA<Exception>()));
      expect(await repository.watch().first, isEmpty);

      await database!.customStatement('DROP TRIGGER gcash_test_reject_insert');
      await repository.save(_record());
      await reopen();
      expect(await GcashRepository(database!).watch().first, hasLength(1));
    },
  );
}

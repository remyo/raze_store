import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:raze_store/core/database/app_database.dart';
import 'package:raze_store/features/catalog/application/product_text_recognizer.dart';
import 'package:raze_store/features/catalog/presentation/product_capture_screen.dart';
import 'package:raze_store/features/gcash/gcash_fee_settings.dart';
import 'package:raze_store/features/gcash/gcash_record.dart';
import 'package:raze_store/features/gcash/gcash_repository.dart';
import 'package:raze_store/features/gcash/gcash_screen.dart';
import 'package:raze_store/features/gcash/gcash_transaction_screen.dart';

// This is a synthetic transcription and a generated one-pixel image. No real
// customer's receipt, reference, name, or mobile number belongs in the tests.
const _text = '''Express Send
JU•• D••
+63 917 000 0000
Sent via GCash
Amount
1,000.00
Total Amount Sent
₱1000.00
Ref No. 0040000000001 Jun 27, 2026 6:02 PM''';

class _Fees extends GcashFeeSettingsController {
  @override
  Future<GcashFeeSettings> build() async => GcashFeeSettings.defaults();
}

class _Camera extends Fake implements ProductCaptureLauncher {
  @override
  Future<XFile?> capture(
    BuildContext context, {
    ProductCapturePurpose purpose = ProductCapturePurpose.productPhoto,
  }) async => XFile.fromData(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    ),
    mimeType: 'image/png',
    name: 'synthetic-receipt.png',
  );
}

class _Reader implements ProductTextRecognizer {
  _Reader(this.text);
  final String text;
  bool requested = false;

  @override
  Future<ProductTextRecognitionResult> recognizeImagePath(String path) async {
    requested = true;
    return ProductTextRecognitionResult(
      rawLines: text.split('\n'),
      suggestions: const ProductTextSuggestions(),
    );
  }
}

class _Repository extends GcashRepository {
  _Repository(super.database);
  Completer<void>? gate;
  int attempts = 0;

  @override
  Future<void> save(GcashRecord record) async {
    attempts++;
    await gate?.future;
    await super.save(record);
  }
}

Finder _key(String key) => find.byKey(ValueKey(key));
Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);
String _value(WidgetTester tester, String label) =>
    tester.widget<TextField>(_field(label)).controller!.text;

Future<void> _until(
  WidgetTester tester,
  bool Function() condition, {
  String reason = 'Expected asynchronous operation to finish',
}) async {
  for (var attempt = 0; attempt < 100 && !condition(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(condition(), isTrue, reason: reason);
}

Future<({_Repository repository, _Reader reader})> _open(
  WidgetTester tester, {
  String text = _text,
  GcashKind kind = GcashKind.cashIn,
  Future<void> Function(AppDatabase database)? setup,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final database = AppDatabase.forTesting(NativeDatabase.memory());
  final repository = _Repository(database);
  final reader = _Reader(text);
  await tester.runAsync(() async {
    await database.customSelect('SELECT 1').get();
    await setup?.call(database);
  });
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.runAsync(database.close);
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        gcashRepositoryProvider.overrideWithValue(repository),
        gcashFeeSettingsProvider.overrideWith(_Fees.new),
        productCaptureLauncherProvider.overrideWithValue(_Camera()),
        productTextRecognizerProvider.overrideWithValue(reader),
      ],
      child: MaterialApp(home: GcashScreen(now: () => DateTime(2026, 9, 5))),
    ),
  );
  await _until(
    tester,
    () => find.text('No transactions today').evaluate().isNotEmpty,
  );
  expect(find.text('Today · All transactions'), findsOneWidget);
  await tester.tap(
    _key(
      kind == GcashKind.cashIn
          ? 'gcash-history-cash-in'
          : 'gcash-history-cash-out',
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Scan receipt'));
  await _until(tester, () => reader.requested, reason: 'Receipt reaches OCR');
  await tester.pump(const Duration(milliseconds: 250));
  expect(
    find.text('Receipt attached. Review the details before saving.'),
    findsOneWidget,
  );
  expect(_key('app-toast'), findsOneWidget);
  expect(find.byType(SnackBar), findsNothing);
  expect(_key('gcash-save-record').hitTestable(), findsOneWidget);
  return (repository: repository, reader: reader);
}

Future<List<GcashRecord>> _rows(
  WidgetTester tester,
  _Repository repository,
) async => (await tester.runAsync(() => repository.watch().first))!;

Future<void> _details(WidgetTester tester) async {
  await _until(
    tester,
    () => find.byType(GcashTransactionScreen).evaluate().isNotEmpty,
  );
  await tester.pumpAndSettle();
  expect(find.byType(GcashFormScreen), findsNothing);
  expect(find.text('GCash record saved.'), findsOneWidget);
  expect(find.byType(SnackBar), findsNothing);
}

void main() {
  _test(
    'OCR receipt commits before details and remains visible on its real day',
    (tester) async {
      final fixture = await _open(tester);
      final attached =
          (tester.widget<Image>(_key('gcash-receipt-preview')).image
                  as MemoryImage)
              .bytes;
      fixture.repository.gate = Completer<void>();
      await tester.tap(_key('gcash-save-record'));
      await tester.pump();
      expect(fixture.repository.attempts, 1);
      expect(await _rows(tester, fixture.repository), isEmpty);
      expect(find.byType(GcashTransactionScreen), findsNothing);
      expect(find.text('GCash record saved.'), findsNothing);
      expect(
        tester.widget<FilledButton>(_key('gcash-save-record')).onPressed,
        isNull,
      );
      await tester.tap(_key('gcash-save-record'));
      expect(fixture.repository.attempts, 1);

      fixture.repository.gate!.complete();
      await _details(tester);
      final saved = (await _rows(tester, fixture.repository)).single;
      expect(saved.name, 'JU•• D••');
      expect(saved.reference, '0040000000001');
      expect(saved.amount, 100000);
      expect(saved.fee, 2000);
      expect(saved.date, DateTime(2026, 6, 27, 18, 2));
      expect(saved.receipt, orderedEquals(attached));
      expect(saved.receipt!.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await _until(tester, () => find.text('JU•• D••').evaluate().isNotEmpty);
      final summary = tester
          .widget<Text>(_key('gcash-history-filter-summary'))
          .data!;
      expect(summary, contains('Jun 27'));
      expect(summary, isNot(contains('Today')));
      expect(find.text('JU•• D••'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  _test(
    'Cash Out requires sender identity and verification then saves receipt',
    (tester) async {
      final fixture = await _open(tester, kind: GcashKind.cashOut);
      expect(_value(tester, 'Customer name'), isEmpty);
      expect(_value(tester, 'Mobile number (as shown on receipt)'), isEmpty);
      await tester.ensureVisible(_field('Customer name'));
      await tester.enterText(_field('Customer name'), 'Synthetic Sender');
      await tester.ensureVisible(_field('Mobile number (as shown on receipt)'));
      await tester.enterText(
        _field('Mobile number (as shown on receipt)'),
        '09170000001',
      );
      await tester.tap(_key('gcash-save-record'));
      await tester.pumpAndSettle();
      expect(fixture.repository.attempts, 0);
      expect(
        find.text(
          'Confirm payment in GCash before recording a completed Cash Out.',
        ),
        findsOneWidget,
      );
      expect(find.byType(CheckboxListTile).hitTestable(), findsOneWidget);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(_key('gcash-save-record'));
      await _details(tester);
      final saved = (await _rows(tester, fixture.repository)).single;
      expect(saved.kind, GcashKind.cashOut);
      expect(saved.name, 'Synthetic Sender');
      expect(saved.number, '09170000001');
      expect(saved.receipt, isNotEmpty);
    },
  );

  _test(
    'duplicate save preserves entered data and does not open success details',
    (tester) async {
      final fixture = await _open(
        tester,
        setup: (database) async {
          await GcashRepository(database).save(
            GcashRecord(
              id: 'existing',
              kind: GcashKind.cashIn,
              name: 'Original customer',
              number: '09170000002',
              amount: 50000,
              fee: 1000,
              reference: '0040000000001',
              date: DateTime(2026, 6, 27),
            ),
          );
        },
      );
      await tester.tap(_key('gcash-save-record'));
      await _until(
        tester,
        () => find
            .textContaining('This reference number already exists.')
            .evaluate()
            .isNotEmpty,
      );
      await tester.pumpAndSettle();
      expect(find.byType(GcashFormScreen), findsOneWidget);
      expect(find.byType(GcashTransactionScreen), findsNothing);
      expect(find.text('GCash record saved.'), findsNothing);
      expect(_value(tester, 'Customer name'), 'JU•• D••');
      expect(_value(tester, 'Reference / transaction number'), '0040000000001');
      expect(_key('gcash-receipt-preview'), findsOneWidget);
      expect(
        (await _rows(tester, fixture.repository)).single.name,
        'Original customer',
      );
    },
  );

  _test(
    'failed SQLite write keeps form and receipt and successful retry works',
    (tester) async {
      final fixture = await _open(
        tester,
        setup: (database) async {
          await database.customStatement('''
        CREATE TRIGGER gcash_test_write_error
        BEFORE INSERT ON gcash_entries
        BEGIN SELECT RAISE(ABORT, 'Synthetic failure'); END
      ''');
        },
      );
      await tester.tap(_key('gcash-save-record'));
      await _until(
        tester,
        () => find.textContaining('Record not saved.').evaluate().isNotEmpty,
      );
      expect(await _rows(tester, fixture.repository), isEmpty);
      expect(find.byType(GcashTransactionScreen), findsNothing);
      expect(find.text('GCash record saved.'), findsNothing);
      expect(_value(tester, 'Customer name'), 'JU•• D••');
      expect(_value(tester, 'Amount (₱)'), '1000.00');
      expect(_key('gcash-receipt-preview'), findsOneWidget);

      await tester.runAsync(
        () => fixture.repository.database.customStatement(
          'DROP TRIGGER gcash_test_write_error',
        ),
      );
      await tester.tap(_key('gcash-save-record'));
      await _details(tester);
      expect(await _rows(tester, fixture.repository), hasLength(1));
    },
  );

  _test('receipt above configured brackets asks for a manual fee before save', (
    tester,
  ) async {
    final fixture = await _open(
      tester,
      text: _text
          .replaceAll('1,000.00', '21,300.00')
          .replaceAll('₱1000.00', '₱21300.00'),
    );
    expect(_value(tester, 'Service fee (₱)'), isEmpty);
    await tester.tap(_key('gcash-save-record'));
    await tester.pumpAndSettle();
    expect(fixture.repository.attempts, 0);
    expect(await _rows(tester, fixture.repository), isEmpty);
    expect(find.textContaining('Enter a service fee'), findsWidgets);
    expect(_field('Service fee (₱)').hitTestable(), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    await tester.enterText(_field('Service fee (₱)'), '430');
    await tester.tap(_key('gcash-save-record'));
    await _details(tester);
    expect((await _rows(tester, fixture.repository)).single.fee, 43000);
  });

  _test(
    'overlong OCR name shows field error instead of a failed database save',
    (tester) async {
      final longName = 'A' * 151;
      final fixture = await _open(
        tester,
        text: _text.replaceFirst('JU•• D••', 'Sent to: $longName'),
      );
      expect(_value(tester, 'Customer name'), longName);
      await tester.tap(_key('gcash-save-record'));
      await tester.pumpAndSettle();
      expect(fixture.repository.attempts, 0);
      expect(await _rows(tester, fixture.repository), isEmpty);
      expect(find.textContaining('150'), findsWidgets);
      expect(_field('Customer name').hitTestable(), findsOneWidget);
      expect(find.byType(GcashTransactionScreen), findsNothing);
    },
  );
}

void _test(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (tester) async {
    try {
      await body(tester);
    } finally {
      // Drift cancellation schedules a zero-duration cleanup timer. Dispose
      // and pump it before Flutter checks for pending timers, not in tearDown.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });
}

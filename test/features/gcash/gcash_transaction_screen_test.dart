import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/features/gcash/gcash_record.dart';
import 'package:raze_store/features/gcash/gcash_theme.dart';
import 'package:raze_store/features/gcash/gcash_transaction_screen.dart';

GcashRecord _record({
  GcashKind kind = GcashKind.cashIn,
  String name = 'JU•• D••',
  String number = '+63 917 000 0000',
  int amount = 125075,
  int fee = 2575,
  String reference = '0040000000001',
  Uint8List? receipt,
}) => GcashRecord(
  id: 'local-record',
  kind: kind,
  name: name,
  number: number,
  amount: amount,
  fee: fee,
  reference: reference,
  date: DateTime(2026, 9, 5, 16, 30),
  receipt: receipt,
);

Finder _key(String value) => find.byKey(ValueKey(value));

Future<void> _pump(
  WidgetTester tester,
  GcashRecord record, {
  double width = 390,
  double height = 844,
  double textScale = 1,
  Brightness brightness = Brightness.light,
  List<Widget> actions = const [],
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      GcashTransactionScreen(record: record, actions: actions),
                ),
              ),
              child: const Text('Open transaction'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open transaction'));
  await tester.pumpAndSettle();
}

void main() {
  for (final kind in GcashKind.values) {
    testWidgets('${kind.label} shows recorded values in a read-only summary', (
      tester,
    ) async {
      final record = _record(kind: kind);
      await _pump(tester, record);

      expect(find.text('GCash transaction'), findsOneWidget);
      expect(find.text(kind.label), findsOneWidget);
      expect(find.text('Recorded'), findsOneWidget);
      expect(find.text('Saved in Raze Store'), findsOneWidget);
      expect(_key('gcash-transaction-status'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(find.text('Price'), findsOneWidget);
      expect(find.text('₱1,250.75'), findsOneWidget);
      expect(find.text('₱25.75'), findsOneWidget);
      expect(find.text(record.name), findsOneWidget);
      expect(find.text(record.number), findsOneWidget);
      expect(find.text(record.reference), findsOneWidget);
      expect(find.text('Transaction number'), findsOneWidget);
      expect(find.byType(SelectionArea), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
      expect(find.byType(Form), findsNothing);
      expect(find.byType(Image), findsNothing);
      expect(find.textContaining('Edit'), findsNothing);
      expect(find.textContaining('Save record'), findsNothing);
      expect(find.textContaining('approved'), findsNothing);
      expect(find.textContaining('verified'), findsNothing);
      expect(find.textContaining('Sep'), findsNothing);
      expect(
        tester
            .widget<GcashTransactionScreen>(find.byType(GcashTransactionScreen))
            .record,
        same(record),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('zero profit stays zero and uses the saved charge', (
    tester,
  ) async {
    await _pump(tester, _record(amount: 100000, fee: 0));

    expect(find.text('₱1,000.00'), findsOneWidget);
    expect(find.text('₱0.00'), findsOneWidget);
    expect(find.text('₱20.00'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('receipt bytes are neither decoded nor displayed', (
    tester,
  ) async {
    await _pump(
      tester,
      _record(receipt: Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10])),
    );

    expect(find.byType(Image), findsNothing);
    expect(find.byType(RawImage), findsNothing);
    expect(find.textContaining('receipt'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets('long values scroll and go back at 320px/2x in $brightness', (
      tester,
    ) async {
      final record = _record(
        name: 'N' * 150,
        number: '0' * 40,
        reference: '0' * 80,
        amount: 99999999999,
        fee: 99999999999,
      );
      await _pump(
        tester,
        record,
        width: 320,
        height: 568,
        textScale: 2,
        brightness: brightness,
      );

      final context = tester.element(_key('gcash-transaction-screen'));
      final theme = Theme.of(context);
      expect(theme.brightness, brightness);
      expect(theme.appBarTheme.backgroundColor, isNotNull);
      expect(
        tester.widget<Container>(_key('gcash-transaction-status')).decoration,
        const BoxDecoration(color: GcashTheme.blue, shape: BoxShape.circle),
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(_key('gcash-transaction-reference'));
      await tester.pumpAndSettle();
      expect(find.text(record.reference).hitTestable(), findsOneWidget);
      expect(find.text(record.name), findsOneWidget);
      expect(find.text(record.number), findsOneWidget);
      expect(find.text('₱999,999,999.99'), findsNWidgets(2));
      expect(tester.takeException(), isNull);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Open transaction'), findsOneWidget);
      expect(find.byType(GcashTransactionScreen), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('accepts parent-owned actions in the AppBar', (tester) async {
    var presses = 0;
    await _pump(
      tester,
      _record(),
      actions: [
        IconButton(
          tooltip: 'Record actions',
          onPressed: () => presses++,
          icon: const Icon(Icons.more_vert_rounded),
        ),
      ],
    );

    expect(find.byTooltip('Record actions'), findsOneWidget);
    await tester.tap(find.byTooltip('Record actions'));
    expect(presses, 1);
    expect(tester.takeException(), isNull);
  });
}

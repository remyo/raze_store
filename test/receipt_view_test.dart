import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/features/receipt/domain/receipt_draft.dart';
import 'package:raze_store/features/receipt/presentation/receipt_preview_screen.dart';
import 'package:raze_store/features/receipt/presentation/receipt_view.dart';

void main() {
  late ReceiptDraft draft;

  setUp(() {
    draft = ReceiptDraft(
      storeName: 'Aling Nena Sari-sari Store',
      storeAddress: '123 Mabini Street, Quezon City',
      storeContact: '0912 345 6789',
      footerMessage: 'Maraming salamat po!',
      lines: [
        ReceiptLine(
          productName: 'Canned sardines',
          unitLabel: 'Can',
          barcode: '4801234567890',
          quantity: 2,
          unitPriceCentavos: 2350,
        ),
        ReceiptLine(
          productName: 'Instant noodles',
          quantity: 3,
          unitPriceCentavos: 1250,
        ),
      ],
      createdAt: DateTime(2026, 9, 2, 19, 30),
      cashReceivedCentavos: 10000,
    );
  });

  test('formats Philippine peso amounts from centavos', () {
    expect(formatReceiptMoney(0), '₱0.00');
    expect(formatReceiptMoney(123456), '₱1,234.56');
    expect(formatReceiptMoney(-1250), '-₱12.50');
  });

  testWidgets('renders store profile, products, totals, cash, and change', (
    tester,
  ) async {
    await tester.pumpWidget(_testApp(ReceiptView(draft: draft)));

    expect(find.text('Aling Nena Sari-sari Store'), findsOneWidget);
    expect(find.text('123 Mabini Street, Quezon City'), findsOneWidget);
    expect(find.text('0912 345 6789'), findsOneWidget);
    expect(find.text('Canned sardines'), findsOneWidget);
    expect(find.text('Sold as Can'), findsOneWidget);
    expect(find.text('4801234567890'), findsOneWidget);
    expect(find.text('₱23.50 × 2'), findsOneWidget);
    expect(find.text('₱84.50'), findsOneWidget);
    expect(find.text('5 items'), findsOneWidget);
    expect(find.text('Cash received'), findsOneWidget);
    expect(find.text('Change'), findsOneWidget);
    expect(find.text('₱15.50'), findsOneWidget);
    expect(find.text('Maraming salamat po!'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('preview explains its ephemeral behavior and offers exports', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF006B57)),
        ),
        home: ReceiptPreviewScreen(
          draft: draft,
          onSaveImage: (_, _) async {},
          onShareImage: (_, _, _) async {},
          onClose: () {},
        ),
      ),
    );

    expect(find.text('Receipt preview'), findsOneWidget);
    expect(
      find.text(
        'Saving or sharing this receipt image does not change your cart or sales history.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('receipt-save-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('receipt-share-button')), findsOneWidget);
    expect(find.byType(ReceiptView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _testApp(Widget child) {
  return MaterialApp(
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF006B57)),
    ),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

import 'dart:typed_data';

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
    expect(find.text('Download PNG'), findsOneWidget);
    expect(find.byKey(const ValueKey('receipt-save-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('receipt-share-button')), findsOneWidget);
    expect(find.byType(ReceiptView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('download remains usable with an off-screen long receipt', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1170, 1800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    Uint8List? capturedBytes;
    String? capturedName;
    final longDraft = ReceiptDraft(
      storeName: 'Long Cart Store',
      lines: [
        for (var index = 0; index < 80; index++)
          ReceiptLine(
            productName: 'Product ${index + 1}',
            quantity: 1,
            unitPriceCentavos: 100,
          ),
      ],
      createdAt: DateTime(2026, 9, 5, 14, 6, 7),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ReceiptPreviewScreen(
          draft: longDraft,
          onSaveImage: (bytes, fileName) async {
            capturedBytes = Uint8List.fromList(bytes);
            capturedName = fileName;
          },
          onCaptureImage: () async => _testPngBytes,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('receipt-save-button')));
    await tester.pumpAndSettle();

    expect(capturedBytes, isNotNull);
    expect(
      capturedBytes!.take(8),
      orderedEquals(const [137, 80, 78, 71, 13, 10, 26, 10]),
    );
    expect(capturedName, 'raze-store-receipt-20260905-140607.png');
    expect(find.text('Receipt PNG saved.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('share captures a PNG and supplies an iPad-safe origin', (
    tester,
  ) async {
    Uint8List? sharedBytes;
    Rect? sharedOrigin;
    await tester.pumpWidget(
      MaterialApp(
        home: ReceiptPreviewScreen(
          draft: draft,
          onShareImage: (bytes, _, origin) async {
            sharedBytes = Uint8List.fromList(bytes);
            sharedOrigin = origin;
          },
          onCaptureImage: () async => _testPngBytes,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('receipt-share-button')));
    await tester.pumpAndSettle();

    expect(sharedBytes, isNotNull);
    expect(
      sharedBytes!.take(8),
      orderedEquals(const [137, 80, 78, 71, 13, 10, 26, 10]),
    );
    expect(sharedOrigin, isNotNull);
    expect(sharedOrigin!.isEmpty, isFalse);
    expect(tester.takeException(), isNull);
  });

  test('receipt capture ratio stays within image limits for a long cart', () {
    const logicalSize = Size(420, 100000);

    final ratio = receiptCapturePixelRatio(
      logicalSize: logicalSize,
      devicePixelRatio: 3,
    );

    expect(logicalSize.height * ratio, lessThanOrEqualTo(8192));
    expect(
      logicalSize.width * logicalSize.height * ratio * ratio,
      lessThanOrEqualTo(16000000),
    );
    expect(ratio, greaterThan(0));
  });
}

final _testPngBytes = Uint8List.fromList(const [
  137,
  80,
  78,
  71,
  13,
  10,
  26,
  10,
]);

Widget _testApp(Widget child) {
  return MaterialApp(
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF006B57)),
    ),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

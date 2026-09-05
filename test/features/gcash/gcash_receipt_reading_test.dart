import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:raze_store/features/catalog/application/product_text_recognizer.dart';
import 'package:raze_store/features/catalog/presentation/product_capture_screen.dart';
import 'package:raze_store/features/gcash/gcash_fee_settings.dart';
import 'package:raze_store/features/gcash/gcash_record.dart';
import 'package:raze_store/features/gcash/gcash_screen.dart';

// Synthetic transcription matching the shared Express Send layout. Never store
// real customer phone numbers, reference numbers, names, or screenshots here.
const _expressSend = '''6:02
Express Send
JU•• D••
+63 917 000 0000
Sent via GCash
Amount
1,000.00
Total Amount Sent
₱1000.00
Ref No. 0040000000001 Jun 27, 2026 6:02 PM
279g (gCO2e)
By going digital, you reduce your carbon footprint
Download Share Receipt''';

class _FeeController extends GcashFeeSettingsController {
  @override
  Future<GcashFeeSettings> build() async => GcashFeeSettings.defaults();
}

class _Camera extends Fake implements ProductCaptureLauncher {
  final purposes = <ProductCapturePurpose>[];

  @override
  Future<XFile?> capture(
    BuildContext context, {
    ProductCapturePurpose purpose = ProductCapturePurpose.productPhoto,
  }) async {
    purposes.add(purpose);
    return XFile.fromData(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ),
      mimeType: 'image/png',
      name: 'synthetic-receipt.png',
    );
  }
}

class _Reader implements ProductTextRecognizer {
  _Reader(this.responses);
  final List<Object> responses;
  Completer<void>? requested;

  @override
  Future<ProductTextRecognitionResult> recognizeImagePath(
    String imagePath,
  ) async {
    requested?.complete();
    final response = responses.removeAt(0);
    if (response is! String) throw response;
    return ProductTextRecognitionResult(
      rawLines: response.split('\n'),
      suggestions: const ProductTextSuggestions(),
    );
  }
}

Future<({_Reader reader, _Camera camera})> _open(
  WidgetTester tester,
  List<Object> text, {
  GcashKind kind = GcashKind.cashIn,
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  final reader = _Reader(text);
  final camera = _Camera();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        productCaptureLauncherProvider.overrideWithValue(camera),
        productTextRecognizerProvider.overrideWithValue(reader),
        gcashFeeSettingsProvider.overrideWith(_FeeController.new),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: GcashFormScreen(kind: kind),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (reader: reader, camera: camera);
}

Future<void> _scan(WidgetTester tester, _Reader reader) async {
  await tester.ensureVisible(find.text('Scan receipt'));
  reader.requested = Completer<void>();
  await tester.tap(find.text('Scan receipt'));
  // Image codec/toByteData work needs both real engine time and pumped frames.
  // Waiting on OCR alone would starve the image conversion before it reaches it.
  for (
    var attempt = 0;
    attempt < 100 && !reader.requested!.isCompleted;
    attempt++
  ) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  expect(reader.requested!.isCompleted, isTrue, reason: 'Receipt reaches OCR');
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

String _value(WidgetTester tester, String label) => tester
    .widget<TextField>(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == label,
      ),
    )
    .controller!
    .text;

void main() {
  testWidgets(
    'Express Send fills Cash In recipient and transaction suggestions',
    (tester) async {
      final fakes = await _open(tester, [_expressSend]);
      expect(
        find.byKey(const ValueKey('gcash-receipt-guidance')),
        findsOneWidget,
      );
      expect(
        find.textContaining('Other receipts may be hard to read'),
        findsOneWidget,
      );
      await _scan(tester, fakes.reader);
      expect(fakes.camera.purposes, [ProductCapturePurpose.gcashReceipt]);
      expect(_value(tester, 'Customer name'), 'JU•• D••');
      expect(
        _value(
          tester,
          'Mobile number (as shown on receipt)',
        ).replaceAll(RegExp(r'[\s-]'), ''),
        '+639170000000',
      );
      expect(_value(tester, 'Amount (₱)'), '1000.00');
      expect(_value(tester, 'Service fee (₱)'), '20.00');
      expect(_value(tester, 'Reference / transaction number'), '0040000000001');
      expect(find.text('Jun 27, 2026 · 6:02 PM'), findsOneWidget);
      expect(find.byKey(const ValueKey('gcash-receipt-warning')), findsNothing);
      expect(
        find.byKey(const ValueKey('gcash-save-record')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Express Send does not put the recipient into Cash Out customer fields',
    (tester) async {
      final fakes = await _open(tester, [
        _expressSend,
      ], kind: GcashKind.cashOut);
      await _scan(tester, fakes.reader);
      expect(_value(tester, 'Customer name'), isEmpty);
      expect(_value(tester, 'Mobile number (as shown on receipt)'), isEmpty);
      expect(_value(tester, 'Amount (₱)'), '1000.00');
      expect(_value(tester, 'Reference / transaction number'), '0040000000001');
      expect(
        find.textContaining('shows the recipient, not the sender'),
        findsOneWidget,
      );
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unknown receipt recommends manual entry and replacement clears warning',
    (tester) async {
      final fakes = await _open(tester, [
        'Bank transfer\nAmount: 200.00\nRef No. TEST1234',
        _expressSend,
      ]);
      await _scan(tester, fakes.reader);
      expect(
        find.textContaining('GCash receipt not recognized'),
        findsOneWidget,
      );
      expect(_value(tester, 'Customer name'), isEmpty);
      expect(_value(tester, 'Mobile number (as shown on receipt)'), isEmpty);
      await _scan(tester, fakes.reader);
      expect(find.byKey(const ValueKey('gcash-receipt-warning')), findsNothing);
      expect(_value(tester, 'Customer name'), 'JU•• D••');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Cash Out warning and receipt keep save reachable with a small keyboard viewport',
    (tester) async {
      final fakes = await _open(
        tester,
        [_expressSend],
        kind: GcashKind.cashOut,
        size: const Size(320, 700),
        textScale: 1.5,
      );
      await _scan(tester, fakes.reader);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('gcash-receipt-warning')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('gcash-save-record')).hitTestable(),
        findsOneWidget,
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('gcash-save-bar'))).bottom,
        lessThanOrEqualTo(400),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed replacement OCR does not retain previous receipt details',
    (tester) async {
      final fakes = await _open(tester, [
        _expressSend,
        StateError('OCR unavailable'),
      ]);
      await _scan(tester, fakes.reader);
      expect(_value(tester, 'Customer name'), isNotEmpty);
      await _scan(tester, fakes.reader);
      for (final label in [
        'Customer name',
        'Mobile number (as shown on receipt)',
        'Amount (₱)',
        'Reference / transaction number',
      ]) {
        expect(_value(tester, label), isEmpty);
      }
      expect(find.text('Choose transaction date & time'), findsOneWidget);
      expect(
        find.textContaining('The receipt text could not be read'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('gcash-save-record')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

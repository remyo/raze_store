import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:raze_store/features/catalog/presentation/product_capture_screen.dart';
import 'package:raze_store/features/gcash/gcash_fee_settings.dart';
import 'package:raze_store/features/gcash/gcash_record.dart';
import 'package:raze_store/features/gcash/gcash_screen.dart';

class _FeeController extends GcashFeeSettingsController {
  @override
  Future<GcashFeeSettings> build() async => GcashFeeSettings.defaults();
}

class _PendingCapture implements ProductCaptureLauncher {
  final completion = Completer<XFile?>();

  @override
  Future<XFile?> capture(
    BuildContext context, {
    ProductCapturePurpose purpose = ProductCapturePurpose.productPhoto,
  }) => completion.future;
}

const _homeKey = ValueKey('sheet-test-home');

Future<Completer<void>> _open(
  WidgetTester tester, {
  GcashKind kind = GcashKind.cashIn,
  GcashRecord? record,
  ProductCaptureLauncher? capture,
  bool settle = true,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final closed = Completer<void>();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        gcashFeeSettingsProvider.overrideWith(_FeeController.new),
        if (capture != null)
          productCaptureLauncherProvider.overrideWithValue(capture),
      ],
      child: MaterialApp(
        home: Scaffold(
          key: _homeKey,
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () {
                  showGcashFormSheet(
                    context,
                    kind: kind,
                    record: record,
                  ).then((_) => closed.complete());
                },
                child: const Text('Open form'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open form'));
  await tester.pump();
  if (settle) await tester.pumpAndSettle();
  return closed;
}

GcashFormScreen _form(WidgetTester tester) =>
    tester.widget<GcashFormScreen>(find.byType(GcashFormScreen));

CupertinoSheetRoute<GcashRecord> _route(WidgetTester tester) =>
    ModalRoute.of(tester.element(find.byType(GcashFormScreen)))!
        as CupertinoSheetRoute<GcashRecord>;

Finder get _scrollable => find
    .descendant(
      of: find.byType(GcashFormScreen),
      matching: find.byType(Scrollable),
    )
    .first;

Offset _bodyDragStart(WidgetTester tester) =>
    tester.getTopLeft(_scrollable) + const Offset(20, 120);

void main() {
  testWidgets('slides up, rounds the sheet, and stacks the previous page', (
    tester,
  ) async {
    final closed = await _open(tester, kind: GcashKind.cashOut, settle: false);
    await tester.pump(const Duration(milliseconds: 120));
    final openingTop = tester.getTopLeft(find.byType(GcashFormScreen)).dy;
    await tester.pumpAndSettle();

    final finalTop = tester.getTopLeft(find.byType(GcashFormScreen)).dy;
    expect(openingTop, greaterThan(finalTop));
    expect(finalTop, closeTo(844 * 0.08, 0.1));
    expect(find.byType(CupertinoSheetTransition), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(
      find.descendant(
        of: find.byType(CupertinoSheetTransition),
        matching: find.byType(ClipRSuperellipse),
      ),
      findsOneWidget,
    );
    final home = tester.getRect(find.byKey(_homeKey));
    expect(home.top, greaterThan(0));
    expect(home.width, lessThan(390));
    expect(_form(tester).kind, GcashKind.cashOut);
    expect(_form(tester).asBottomSheet, isTrue);
    expect(_form(tester).scrollController!.hasClients, isTrue);
    expect(closed.isCompleted, isFalse);

    await tester.tap(find.byTooltip('Close form'));
    await tester.pumpAndSettle();
    expect(closed.isCompleted, isTrue);
    expect(
      tester.getRect(find.byKey(_homeKey)),
      const Rect.fromLTWH(0, 0, 390, 844),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('uses the saved transaction kind and details when editing', (
    tester,
  ) async {
    final record = GcashRecord(
      id: 'existing',
      kind: GcashKind.cashOut,
      name: 'Saved customer',
      number: '09171234567',
      amount: 50000,
      fee: 1000,
      reference: '12345678',
      date: DateTime(2026, 9, 5, 12),
    );
    await _open(tester, record: record);
    expect(_form(tester).record, same(record));
    expect(_form(tester).kind, GcashKind.cashOut);
    expect(find.text('Saved customer'), findsOneWidget);
  });

  for (final fromBody in [false, true]) {
    testWidgets('idle swipe dismisses from ${fromBody ? 'form' : 'header'}', (
      tester,
    ) async {
      final closed = await _open(tester);
      await tester.dragFrom(
        fromBody
            ? _bodyDragStart(tester)
            : tester.getCenter(find.text('New Cash In')),
        const Offset(0, 500),
      );
      await tester.pumpAndSettle();

      expect(find.byType(GcashFormScreen), findsNothing);
      expect(closed.isCompleted, isTrue);
      expect(find.text('Open form').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'scrolling the form retains the sheet until content reaches top',
    (tester) async {
      await _open(tester);
      tester.view.physicalSize = const Size(390, 650);
      await tester.pumpAndSettle();
      final top = tester.getTopLeft(find.byType(GcashFormScreen)).dy;
      final controller = _form(tester).scrollController!;
      await tester.dragFrom(_bodyDragStart(tester), const Offset(0, -250));
      await tester.pumpAndSettle();
      final offset = controller.offset;
      expect(offset, greaterThan(0));
      expect(tester.getTopLeft(find.byType(GcashFormScreen)).dy, top);

      await tester.dragFrom(_bodyDragStart(tester), const Offset(0, 70));
      await tester.pumpAndSettle();
      expect(controller.offset, lessThan(offset));
      expect(tester.getTopLeft(find.byType(GcashFormScreen)).dy, top);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'capture blocks header and body dismissal, then re-enables swipe',
    (tester) async {
      final capture = _PendingCapture();
      final closed = await _open(tester, capture: capture);
      await tester.tap(find.text('Scan receipt'));
      await tester.pump();
      expect(_route(tester).enableDrag, isFalse);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is IconButton && widget.tooltip == 'Close form',
              ),
            )
            .onPressed,
        isNull,
      );

      for (final fromBody in [false, true]) {
        await tester.dragFrom(
          fromBody
              ? _bodyDragStart(tester)
              : tester.getCenter(find.text('New Cash In')),
          const Offset(0, 500),
        );
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.byType(GcashFormScreen), findsOneWidget);
        expect(_route(tester).animation!.value, 1);
        expect(closed.isCompleted, isFalse);
      }

      capture.completion.complete(null);
      await tester.pumpAndSettle();
      expect(_route(tester).enableDrag, isTrue);
      await tester.dragFrom(
        tester.getCenter(find.text('New Cash In')),
        const Offset(0, 500),
      );
      await tester.pumpAndSettle();
      expect(closed.isCompleted, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'work beginning during a swipe cancels dismissal and restores sheet',
    (tester) async {
      final closed = await _open(tester);
      final route = _route(tester);
      final onBusyChanged = _form(tester).onBusyChanged!;
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('New Cash In')),
      );
      await gesture.moveBy(const Offset(0, 20));
      await gesture.moveBy(const Offset(0, 500));
      await tester.pump();
      expect(route.animation!.value, lessThan(0.52));

      onBusyChanged(true);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(route.isCurrent, isTrue);
      expect(route.animation!.value, 1);
      expect(route.navigator!.userGestureInProgress, isFalse);
      expect(closed.isCompleted, isFalse);

      onBusyChanged(false);
      await tester.pump();
      await tester.tap(find.byTooltip('Close form'));
      await tester.pumpAndSettle();
      expect(closed.isCompleted, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}

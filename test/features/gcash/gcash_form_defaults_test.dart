import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/features/gcash/gcash_fee_settings.dart';
import 'package:raze_store/features/gcash/gcash_record.dart';
import 'package:raze_store/features/gcash/gcash_repository.dart';
import 'package:raze_store/features/gcash/gcash_screen.dart';
import 'package:raze_store/features/gcash/gcash_theme.dart';

class _FeeController extends GcashFeeSettingsController {
  _FeeController(this.settings);
  final Future<GcashFeeSettings> settings;
  @override
  Future<GcashFeeSettings> build() => settings;
}

class _RecordingRepository extends Fake implements GcashRepository {
  final saved = <GcashRecord>[];
  final pendingSave = Completer<void>();

  @override
  Future<void> save(GcashRecord record) {
    saved.add(record);
    return pendingSave.future;
  }
}

GcashRecord _receiptRecord(GcashKind kind) => GcashRecord(
  id: 'receipt',
  kind: kind,
  name: 'Sample customer',
  number: '09170000000',
  amount: 50000,
  fee: 1000,
  reference: '12345678',
  date: DateTime(2026, 9, 5),
  receipt: base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  ),
);

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

String _fee(WidgetTester tester) =>
    tester.widget<TextField>(_field('Service fee (₱)')).controller!.text;

Future<void> _open(
  WidgetTester tester, {
  GcashKind kind = GcashKind.cashIn,
  GcashRecord? record,
  Future<GcashFeeSettings>? settings,
  bool asSheet = false,
  double textScale = 1,
  GcashRepository? repository,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (repository != null)
          gcashRepositoryProvider.overrideWithValue(repository),
        gcashFeeSettingsProvider.overrideWith(
          () => _FeeController(
            settings ?? Future.value(GcashFeeSettings.defaults()),
          ),
        ),
      ],
      child: MaterialApp(
        theme: ThemeData(colorSchemeSeed: Colors.green),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: asSheet
            ? Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () =>
                        showGcashFormSheet(context, kind: kind, record: record),
                    child: const Text('Open form'),
                  ),
                ),
              )
            : GcashFormScreen(kind: kind, record: record),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (asSheet) {
    await tester.tap(find.text('Open form'));
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets(
    'bottom-sheet form stays usable with a small screen and keyboard',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 700);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            gcashFeeSettingsProvider.overrideWith(
              () => _FeeController(Future.value(GcashFeeSettings.defaults())),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showGcashFormSheet(context),
                  child: const Text('Open form'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open form'));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoSheetTransition), findsOneWidget);
      expect(find.text('New Cash In'), findsOneWidget);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      final formScroll = find
          .descendant(
            of: find.byType(GcashFormScreen),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        _field('Amount (₱)'),
        150,
        scrollable: formScroll,
      );
      await tester.enterText(_field('Amount (₱)'), '500');
      await tester.pumpAndSettle();
      expect(_fee(tester), '10.00');
      expect(
        find.byKey(const ValueKey('gcash-save-record')).hitTestable(),
        findsOneWidget,
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('gcash-save-bar'))).bottom,
        lessThanOrEqualTo(400),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Close form'));
      await tester.pumpAndSettle();
      expect(find.byType(GcashFormScreen), findsNothing);
    },
  );

  for (final kind in GcashKind.values) {
    testWidgets('${kind.label} keeps Save fixed with a receipt and keyboard', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 700);
      addTearDown(tester.view.reset);
      await _open(
        tester,
        kind: kind,
        record: _receiptRecord(kind),
        asSheet: true,
        textScale: 1.4,
      );
      final save = find.byKey(const ValueKey('gcash-save-record'));
      final scroll = find.byKey(const ValueKey('gcash-form-scroll'));
      expect(
        find.byKey(const ValueKey('gcash-receipt-preview')),
        findsOneWidget,
      );
      expect(save.hitTestable(), findsOneWidget);
      final initial = tester.getRect(save);
      await tester.drag(scroll, const Offset(0, -350));
      await tester.pumpAndSettle();
      expect(tester.getRect(save), initial);
      expect(save.hitTestable(), findsOneWidget);

      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      expect(save.hitTestable(), findsOneWidget);
      expect(tester.getRect(save).bottom, lessThanOrEqualTo(420));
      await tester.ensureVisible(_field('Amount (₱)'));
      await tester.enterText(_field('Amount (₱)'), '700');
      await tester.pumpAndSettle();
      expect(save.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('sticky Save validates every field without scrolling first', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 600);
    addTearDown(tester.view.reset);
    final repository = _RecordingRepository();
    await _open(tester, asSheet: true, repository: repository);
    await tester.tap(find.byKey(const ValueKey('gcash-save-record')));
    await tester.pumpAndSettle();
    expect(repository.saved, isEmpty);
    expect(find.text('Required'), findsNWidgets(4));
    expect(
      find.text('Review the highlighted receipt details before saving.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'sticky Save prevents duplicate saves and closes after completion',
    (tester) async {
      final repository = _RecordingRepository();
      await _open(
        tester,
        record: _receiptRecord(GcashKind.cashIn),
        asSheet: true,
        repository: repository,
      );
      final save = find.byKey(const ValueKey('gcash-save-record'));
      await tester.tap(save);
      await tester.pump();
      expect(repository.saved, hasLength(1));
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      await tester.tap(save);
      await tester.pump();
      expect(repository.saved, hasLength(1));
      repository.pendingSave.complete();
      await tester.pumpAndSettle();
      expect(find.byType(GcashFormScreen), findsNothing);
      expect(find.text('Open form'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('sticky Cash Out Save still requires payment verification', (
    tester,
  ) async {
    final repository = _RecordingRepository();
    await _open(
      tester,
      kind: GcashKind.cashOut,
      record: _receiptRecord(GcashKind.cashOut),
      asSheet: true,
      repository: repository,
    );
    final verification = find.text('I checked the payment in GCash');
    await tester.ensureVisible(verification);
    await tester.tap(verification);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('gcash-save-record')));
    await tester.pumpAndSettle();
    expect(repository.saved, isEmpty);
    expect(
      find.text(
        'Confirm payment in GCash before recording a completed Cash Out.',
      ),
      findsOneWidget,
    );
    expect(find.byType(GcashFormScreen), findsOneWidget);
  });
  testWidgets(
    'bracket defaults update, manual override persists, default can be reapplied',
    (tester) async {
      await _open(tester);
      final amount = _field('Amount (₱)');
      await tester.ensureVisible(amount);
      await tester.enterText(amount, '500');
      await tester.pump();
      expect(_fee(tester), '10.00');
      await tester.enterText(amount, '500.01');
      await tester.pump();
      expect(_fee(tester), '20.00');
      await tester.enterText(_field('Service fee (₱)'), '7.00');
      await tester.enterText(amount, '1500');
      await tester.pump();
      expect(_fee(tester), '7.00');
      final reset = find.text('Use default charge · ₱30.00');
      await tester.ensureVisible(reset);
      await tester.tap(reset);
      await tester.pump();
      expect(_fee(tester), '30.00');
      await tester.enterText(amount, '10000.01');
      await tester.pump();
      expect(_fee(tester), isEmpty);
      expect(
        find.textContaining('above your configured brackets'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'existing saved fee is unchanged until default is explicitly selected',
    (tester) async {
      await _open(
        tester,
        record: GcashRecord(
          id: 'old',
          kind: GcashKind.cashIn,
          name: 'Sample',
          number: '09170000000',
          amount: 50000,
          fee: 3700,
          reference: '12345678',
          date: DateTime(2026, 9, 5),
        ),
      );
      expect(_fee(tester), '37.00');
      await tester.ensureVisible(_field('Amount (₱)'));
      await tester.enterText(_field('Amount (₱)'), '1000');
      await tester.pump();
      expect(_fee(tester), '37.00');
    },
  );

  testWidgets(
    'Cash Out uses the shared rates and disabled autofill requires manual fee',
    (tester) async {
      final settings = GcashFeeSettings.defaults();
      await _open(
        tester,
        kind: GcashKind.cashOut,
        settings: Future.value(
          settings.copyWith(
            shared: GcashFeeSchedule(
              autoFillEnabled: true,
              tiers: [
                const GcashFeeTier(
                  upperLimitCentavos: 100000,
                  feeCentavos: 2500,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.ensureVisible(_field('Amount (₱)'));
      await tester.enterText(_field('Amount (₱)'), '500');
      await tester.pump();
      expect(_fee(tester), '25.00');
      await tester.pumpWidget(const SizedBox());
      await _open(
        tester,
        settings: Future.value(
          settings.copyWith(
            shared: settings.shared.copyWith(autoFillEnabled: false),
          ),
        ),
      );
      await tester.ensureVisible(_field('Amount (₱)'));
      await tester.enterText(_field('Amount (₱)'), '500');
      await tester.pump();
      expect(_fee(tester), '0.00');
      expect(find.textContaining('Automatic charges are off'), findsOneWidget);
    },
  );

  testWidgets('late settings do not replace an explicitly entered charge', (
    tester,
  ) async {
    final completion = Completer<GcashFeeSettings>();
    await _open(tester, settings: completion.future);
    await tester.ensureVisible(_field('Amount (₱)'));
    await tester.enterText(_field('Amount (₱)'), '500');
    await tester.enterText(_field('Service fee (₱)'), '15');
    completion.complete(GcashFeeSettings.defaults());
    await tester.pumpAndSettle();
    expect(_fee(tester), '15');
  });

  testWidgets('GCash uses scoped blue theme without changing parent theme', (
    tester,
  ) async {
    await _open(tester);
    final scaffold = tester.element(find.byType(Scaffold));
    expect(Theme.of(scaffold).colorScheme.primary, GcashTheme.blue);
    expect(Theme.of(scaffold).appBarTheme.foregroundColor, Colors.white);
    final parent = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(parent.theme!.colorScheme.primary, isNot(GcashTheme.blue));
  });
}

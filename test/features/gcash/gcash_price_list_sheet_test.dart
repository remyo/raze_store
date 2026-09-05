import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/features/gcash/gcash_fee_settings.dart';
import 'package:raze_store/features/gcash/gcash_price_list_sheet.dart';

class _FeeController extends GcashFeeSettingsController {
  _FeeController(this.load);

  final Future<GcashFeeSettings> Function() load;

  @override
  Future<GcashFeeSettings> build() => load();

  @override
  Future<void> save(GcashFeeSettings settings) {
    fail('The quick price list must never change saved charges.');
  }
}

class _RouteObserver extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
  }
}

GcashFeeSettings _customSettings({bool automatic = true}) => GcashFeeSettings(
  shared: GcashFeeSchedule(
    autoFillEnabled: automatic,
    tiers: const [
      GcashFeeTier(upperLimitCentavos: 50025, feeCentavos: 1234),
      GcashFeeTier(upperLimitCentavos: 100050, feeCentavos: 2345),
    ],
  ),
);

Future<void> _open(
  WidgetTester tester, {
  Future<GcashFeeSettings> Function()? load,
  Size size = const Size(390, 844),
  double textScale = 1,
  bool settle = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        gcashFeeSettingsProvider.overrideWith(
          () => _FeeController(load ?? () async => _customSettings()),
        ),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showGcashPriceListSheet(context),
              child: const Text('Show prices'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Show prices'));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }
}

void main() {
  testWidgets('shows saved shared charges with precise centavo boundaries', (
    tester,
  ) async {
    await _open(tester);

    expect(find.text('GCash price list'), findsOneWidget);
    expect(find.text('Same charges for Cash In & Cash Out.'), findsOneWidget);
    expect(
      find.text('Your store’s charges, not official GCash rates.'),
      findsOneWidget,
    );
    expect(find.text('Amount'), findsOneWidget);
    expect(find.text('Charge'), findsOneWidget);
    expect(find.text('₱0.01 – ₱500.25'), findsOneWidget);
    expect(find.text('₱500.26 – ₱1,000.50'), findsOneWidget);
    expect(find.text('₱12.34'), findsOneWidget);
    expect(find.text('₱23.45'), findsOneWidget);
    expect(
      find.text('Above ₱1,000.50, enter the charge manually.'),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Save'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Close price list'));
    await tester.pumpAndSettle();
    expect(find.text('GCash price list'), findsNothing);
    expect(find.text('Show prices'), findsOneWidget);
  });

  testWidgets('still shows the saved reference table when auto-fill is off', (
    tester,
  ) async {
    await _open(tester, load: () async => _customSettings(automatic: false));

    expect(
      find.text('Automatic charges are off. Use this list as a reference.'),
      findsOneWidget,
    );
    expect(find.text('₱12.34'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('waits for saved charges instead of displaying fallback rates', (
    tester,
  ) async {
    final pending = Completer<GcashFeeSettings>();
    await _open(tester, load: () => pending.future, settle: false);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Amount'), findsNothing);
    expect(find.textContaining('₱'), findsNothing);

    pending.complete(_customSettings());
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('₱12.34'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed load offers retry and then reads the saved prices', (
    tester,
  ) async {
    var loads = 0;
    final retry = Completer<GcashFeeSettings>();
    await _open(
      tester,
      load: () {
        loads++;
        if (loads == 1) return Future.error(StateError('Load failed'));
        return retry.future;
      },
    );

    expect(find.text('Could not load your saved charges.'), findsOneWidget);
    expect(find.textContaining('₱'), findsNothing);
    expect(loads, 1);
    await tester.tap(find.byKey(const ValueKey('gcash-price-list-retry')));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(loads, 2);

    retry.complete(_customSettings());
    await tester.pumpAndSettle();
    expect(find.text('Could not load your saved charges.'), findsNothing);
    expect(find.text('₱12.34'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('all tiers remain accessible at 320 pixels with large text', (
    tester,
  ) async {
    await _open(
      tester,
      load: () async => GcashFeeSettings.defaults(),
      size: const Size(320, 568),
      textScale: 2,
    );

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('gcash-price-list-close')).hitTestable(),
      findsOneWidget,
    );
    // A builder, rather than a fully built table, keeps the long list bounded.
    expect(
      find.byKey(const ValueKey('gcash-price-list-tier-19')),
      findsNothing,
    );
    final scrollable = find.descendant(
      of: find.byKey(const ValueKey('gcash-price-list-scroll')),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('gcash-price-list-tier-19')),
      200,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    expect(find.text('₱9,500.01 – ₱10,000'), findsOneWidget);
    expect(find.text('₱200'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('gcash-price-list-manual-note')),
      200,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Above ₱10,000, enter the charge manually.').hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Close price list'));
    await tester.pumpAndSettle();
    expect(find.text('GCash price list'), findsNothing);
  });

  testWidgets('price list can be dismissed while saved rates are loading', (
    tester,
  ) async {
    final pending = Completer<GcashFeeSettings>();
    await _open(tester, load: () => pending.future, settle: false);
    await tester.tap(find.byTooltip('Close price list'));
    await tester.pumpAndSettle();
    expect(find.text('GCash price list'), findsNothing);
    pending.complete(_customSettings());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens above the Home branch navigator and its tab bar', (
    tester,
  ) async {
    final root = _RouteObserver();
    final branch = _RouteObserver();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gcashFeeSettingsProvider.overrideWith(
            () => _FeeController(() async => _customSettings()),
          ),
        ],
        child: MaterialApp(
          navigatorObservers: [root],
          home: Scaffold(
            bottomNavigationBar: const SizedBox(
              key: ValueKey('host-tab-bar'),
              height: 70,
              child: Center(child: Text('Home tabs')),
            ),
            body: Navigator(
              observers: [branch],
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (context) => Center(
                  child: TextButton(
                    onPressed: () => showGcashPriceListSheet(context),
                    child: const Text('Show prices'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Show prices'));
    await tester.pumpAndSettle();

    expect(root.pushed.whereType<ModalBottomSheetRoute<void>>(), hasLength(1));
    expect(branch.pushed.whereType<ModalBottomSheetRoute<void>>(), isEmpty);
    expect(
      find.byKey(const ValueKey('host-tab-bar')).hitTestable(),
      findsNothing,
    );
    expect(find.text('₱12.34'), findsOneWidget);
    await tester.tap(find.byTooltip('Close price list'));
    await tester.pumpAndSettle();
    expect(find.text('Show prices').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

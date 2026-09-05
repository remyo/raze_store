import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:raze_store/features/gcash/gcash_fee_settings.dart';
import 'package:raze_store/features/gcash/gcash_home_shortcut.dart';
import 'package:raze_store/features/gcash/gcash_theme.dart';

class _SavedCharges extends GcashFeeSettingsController {
  @override
  Future<GcashFeeSettings> build() async => GcashFeeSettings(
    shared: GcashFeeSchedule(
      autoFillEnabled: true,
      tiers: const [GcashFeeTier(upperLimitCentavos: 50000, feeCentavos: 1750)],
    ),
  );
}

void main() {
  testWidgets(
    'home presents one blue GCash entry and the main card area opens services',
    (tester) async {
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: GcashHomeShortcut()),
          ),
          GoRoute(
            path: '/gcash',
            builder: (_, _) => const Scaffold(body: Text('Services page')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      expect(find.text('GCash Services'), findsOneWidget);
      expect(find.text('History'), findsNothing);
      expect(find.text('Cash In'), findsNothing);
      expect(find.text('Cash Out'), findsNothing);
      expect(find.text('Price list'), findsOneWidget);
      expect(tester.widget<Card>(find.byType(Card)).color, GcashTheme.blue);
      await tester.tap(find.text('GCash Services'));
      await tester.pumpAndSettle();
      expect(find.text('Services page'), findsOneWidget);
    },
  );

  testWidgets('price list opens saved charges without opening services', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: GcashHomeShortcut()),
        ),
        GoRoute(
          path: '/gcash',
          builder: (_, _) => const Scaffold(body: Text('Services page')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [gcashFeeSettingsProvider.overrideWith(_SavedCharges.new)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    final priceButton = find.byKey(const ValueKey('home-gcash-price-list'));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('home-gcash-services')),
        matching: priceButton,
      ),
      findsOneWidget,
    );
    await tester.tap(priceButton);
    await tester.pumpAndSettle();
    expect(find.text('GCash price list'), findsOneWidget);
    expect(find.text('₱17.50'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Services page'), findsNothing);
    expect(router.routeInformationProvider.value.uri.path, '/');
    Navigator.of(tester.element(find.text('GCash price list'))).pop();
    await tester.pumpAndSettle();
    expect(priceButton.hitTestable(), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_forward_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Services page'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home entry grows without overflow for large text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 700);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(3)),
          child: child!,
        ),
        home: const Scaffold(body: GcashHomeShortcut()),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}

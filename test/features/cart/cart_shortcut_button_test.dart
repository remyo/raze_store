import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:raze_store/core/money/money.dart';
import 'package:raze_store/features/cart/application/cart_providers.dart';
import 'package:raze_store/features/cart/domain/cart.dart';
import 'package:raze_store/features/cart/presentation/cart_shortcut_button.dart';

void main() {
  testWidgets('shows cart quantity and opens the cart as a pushed page', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(
          path: '/home',
          builder: (context, state) => Scaffold(
            appBar: AppBar(actions: const [CartShortcutButton()]),
            body: const Text('Home page'),
          ),
        ),
        GoRoute(
          path: '/cart',
          builder: (context, state) => const Scaffold(body: Text('Cart page')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cartDraftProvider.overrideWith(
            (ref) => Stream.value(
              CartDraft([
                CartItem(
                  lineId: 'coffee|main',
                  productId: 'coffee',
                  sellingUnitId: null,
                  barcode: '4800012345678',
                  nameSnapshot: 'Coffee',
                  unitPrice: const Money.fromCentavos(1000),
                  quantity: 3,
                  addedAt: DateTime.utc(2026, 9, 4),
                  updatedAt: DateTime.utc(2026, 9, 4),
                ),
              ]),
            ),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('3'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('open-cart')))
          .tooltip,
      'Open cart, 3 items',
    );

    await tester.tap(find.byKey(const ValueKey('open-cart')));
    await tester.pumpAndSettle();
    expect(find.text('Cart page'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Home page'), findsOneWidget);
  });
}

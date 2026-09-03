import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:raze_store/app/shell/app_shell.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/features/cart/application/cart_providers.dart';
import 'package:raze_store/features/cart/domain/cart.dart';

void main() {
  testWidgets('bottom navigation opens the Sales branch', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/products',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) =>
              AppShell(navigationShell: navigationShell),
          branches: [
            _branch('/products', 'Products page'),
            _branch('/scan', 'Scan page'),
            _branch('/cart', 'Cart page'),
            _branch('/sales', 'Sales page'),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cartDraftProvider.overrideWith((ref) => Stream.value(CartDraft([]))),
        ],
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Products page'), findsOneWidget);
    expect(find.text('Sales'), findsOneWidget);

    await tester.tap(find.text('Sales'));
    await tester.pumpAndSettle();

    expect(find.text('Sales page'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

StatefulShellBranch _branch(String path, String label) {
  return StatefulShellBranch(
    routes: [
      GoRoute(
        path: path,
        builder: (context, state) => Scaffold(body: Center(child: Text(label))),
      ),
    ],
  );
}

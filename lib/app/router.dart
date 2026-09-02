import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:raze_store/app/shell/app_shell.dart';
import 'package:raze_store/features/cart/presentation/cart_screen.dart';
import 'package:raze_store/features/catalog/presentation/product_form_screen.dart';
import 'package:raze_store/features/catalog/presentation/products_screen.dart';
import 'package:raze_store/features/scanner/presentation/scanner_screen.dart';
import 'package:raze_store/features/receipt/receipt.dart';
import 'package:raze_store/features/settings/presentation/settings_screen.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/products',
  routes: [
    GoRoute(path: '/', redirect: (_, _) => '/products'),
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return AppShell(navigationShell: navigationShell);
      },
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/products',
              builder: (context, state) => const ProductsScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/scan',
              builder: (context, state) => const ScannerScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/cart',
              builder: (context, state) => const CartScreen(),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/products/new',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => ProductFormScreen(
        initialBarcode: state.uri.queryParameters['barcode'],
      ),
    ),
    GoRoute(
      path: '/products/:id/edit',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) =>
          ProductFormScreen(productId: state.pathParameters['id']),
    ),
    GoRoute(
      path: '/settings',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: '/receipt',
      parentNavigatorKey: rootNavigatorKey,
      redirect: (context, state) =>
          state.extra is ReceiptDraft ? null : '/cart',
      builder: (context, state) =>
          ReceiptPreviewScreen(draft: state.extra! as ReceiptDraft),
    ),
  ],
);

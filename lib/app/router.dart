import 'package:flutter/material.dart';
import 'package:raze_store/features/gcash/gcash_screen.dart';
import 'package:raze_store/features/gcash/gcash_record.dart';
import 'package:go_router/go_router.dart';
import 'package:raze_store/app/shell/app_shell.dart';
import 'package:raze_store/features/cart/presentation/cart_screen.dart';
import 'package:raze_store/features/catalog/presentation/product_form_screen.dart';
import 'package:raze_store/features/catalog/presentation/products_screen.dart';
import 'package:raze_store/features/catalog/presentation/quick_sell_screen.dart';
import 'package:raze_store/features/catalog/domain/catalog_product.dart';
import 'package:raze_store/features/onboarding/presentation/app_startup_gate.dart';
import 'package:raze_store/features/onboarding/presentation/first_launch_setup_screen.dart';
import 'package:raze_store/features/profile/presentation/profile_screen.dart';
import 'package:raze_store/features/scanner/presentation/scanner_screen.dart';
import 'package:raze_store/features/receipt/receipt.dart';
import 'package:raze_store/features/sales/domain/completed_sale.dart';
import 'package:raze_store/features/sales/presentation/sale_detail_screen.dart';
import 'package:raze_store/features/sales/presentation/sales_screen.dart';
import 'package:raze_store/features/settings/presentation/settings_screen.dart';
import 'package:raze_store/features/settings/presentation/catalog_category_settings_screen.dart';
import 'package:raze_store/features/settings/presentation/bulk_product_deletion_screen.dart';
import 'package:raze_store/features/settings/presentation/storage_screen.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/',
  routes: [
    GoRoute(path: '/gcash', builder: (context, state) => const GcashScreen()),
    GoRoute(
      path: '/gcash/new',
      builder: (context, state) => GcashFormScreen(
        kind: state.uri.queryParameters['kind'] == 'cashOut'
            ? GcashKind.cashOut
            : GcashKind.cashIn,
      ),
    ),
    GoRoute(path: '/', builder: (context, state) => const AppStartupGate()),
    GoRoute(
      path: '/setup',
      builder: (context, state) => const FirstLaunchSetupScreen(),
    ),
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
              path: '/profile',
              builder: (context, state) => const ProfileScreen(),
            ),
          ],
        ),
      ],
    ),
    GoRoute(path: '/cart', builder: (context, state) => const CartScreen()),
    GoRoute(
      path: '/sales',
      builder: (context, state) => const SalesScreen(),
      routes: [
        GoRoute(
          path: ':id',
          builder: (context, state) => SaleDetailScreen(
            saleId: state.pathParameters['id']!,
            initialSale: state.extra is CompletedSale
                ? state.extra! as CompletedSale
                : null,
          ),
        ),
      ],
    ),
    GoRoute(
      path: '/products/quick-add',
      parentNavigatorKey: rootNavigatorKey,
      // Keep the old route as a compatibility alias, but use the complete
      // editor so photos are available before the product is first saved.
      builder: (context, state) => ProductFormScreen(
        initialBarcode: state.uri.queryParameters['barcode'],
        initialMetadata: state.extra is CatalogMetadata
            ? state.extra! as CatalogMetadata
            : null,
        goToProductsAfterSave: state.uri.queryParameters['fromSetup'] == 'true',
      ),
    ),
    GoRoute(
      path: '/quick-sell',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => const QuickSellScreen(),
    ),
    GoRoute(
      path: '/products/new',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => ProductFormScreen(
        initialBarcode: state.uri.queryParameters['barcode'],
        initialName: state.uri.queryParameters['name'],
        initialPrice: state.uri.queryParameters['price'],
        initialMetadata: state.extra is CatalogMetadata
            ? state.extra! as CatalogMetadata
            : null,
        goToProductsAfterSave: state.uri.queryParameters['fromSetup'] == 'true',
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
      path: '/settings/categories',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => const CatalogCategorySettingsScreen(),
    ),
    GoRoute(
      path: '/settings/storage',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => const StorageScreen(),
    ),
    GoRoute(
      path: '/settings/products/delete',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => const BulkProductDeletionScreen(),
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

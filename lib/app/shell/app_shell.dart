import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/features/cart/application/cart_providers.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cartQuantity = ref.watch(cartDraftProvider).value?.totalQuantity ?? 0;
    final destinations = <NavigationDestination>[
      const NavigationDestination(
        icon: Icon(Icons.storefront_outlined),
        selectedIcon: Icon(Icons.storefront_rounded),
        label: 'Products',
      ),
      const NavigationDestination(
        icon: Icon(Icons.barcode_reader),
        selectedIcon: Icon(Icons.barcode_reader),
        label: 'Scan',
      ),
      NavigationDestination(
        icon: _CartIcon(quantity: cartQuantity),
        selectedIcon: _CartIcon(quantity: cartQuantity, selected: true),
        label: 'Cart',
      ),
    ];

    return AppShellBranchScope(
      index: navigationShell.currentIndex,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final useRail = constraints.maxWidth >= AppBreakpoints.medium;
          if (!useRail) {
            return Scaffold(
              body: navigationShell,
              bottomNavigationBar: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                ),
                child: NavigationBar(
                  selectedIndex: navigationShell.currentIndex,
                  destinations: destinations,
                  onDestinationSelected: _goToBranch,
                ),
              ),
            );
          }

          return Scaffold(
            body: Row(
              children: [
                SafeArea(
                  right: false,
                  child: NavigationRail(
                    selectedIndex: navigationShell.currentIndex,
                    onDestinationSelected: _goToBranch,
                    extended: constraints.maxWidth >= AppBreakpoints.expanded,
                    minExtendedWidth: 216,
                    leading: const Padding(
                      padding: EdgeInsets.fromLTRB(
                        AppSpacing.sm,
                        AppSpacing.md,
                        AppSpacing.sm,
                        AppSpacing.lg,
                      ),
                      child: _StoreMark(),
                    ),
                    destinations: [
                      const NavigationRailDestination(
                        icon: Icon(Icons.storefront_outlined),
                        selectedIcon: Icon(Icons.storefront_rounded),
                        label: Text('Products'),
                      ),
                      const NavigationRailDestination(
                        icon: Icon(Icons.barcode_reader),
                        selectedIcon: Icon(Icons.barcode_reader),
                        label: Text('Scan'),
                      ),
                      NavigationRailDestination(
                        icon: _CartIcon(quantity: cartQuantity),
                        selectedIcon: _CartIcon(
                          quantity: cartQuantity,
                          selected: true,
                        ),
                        label: Text('Cart'),
                      ),
                    ],
                  ),
                ),
                VerticalDivider(
                  width: 1,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                Expanded(child: navigationShell),
              ],
            ),
          );
        },
      ),
    );
  }

  void _goToBranch(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }
}

/// Exposes which persistent shell branch is actually visible.
///
/// Route-level [TickerMode] also changes while dialogs and root routes are
/// shown, so it cannot distinguish a deliberate scanner workflow from the
/// user switching to Products or Cart.
class AppShellBranchScope extends InheritedWidget {
  const AppShellBranchScope({
    super.key,
    required this.index,
    required super.child,
  });

  final int index;

  static int of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<AppShellBranchScope>()
          ?.index ??
      1;

  @override
  bool updateShouldNotify(AppShellBranchScope oldWidget) =>
      index != oldWidget.index;
}

class _CartIcon extends StatelessWidget {
  const _CartIcon({required this.quantity, this.selected = false});

  final int quantity;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Badge(
      isLabelVisible: quantity > 0,
      label: Text(quantity > 99 ? '99+' : '$quantity'),
      child: Icon(
        selected
            ? Icons.shopping_basket_rounded
            : Icons.shopping_basket_outlined,
      ),
    );
  }
}

class _StoreMark extends StatelessWidget {
  const _StoreMark();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Raze Store',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.primary,
          borderRadius: AppRadius.control,
        ),
        child: SizedBox.square(
          dimension: 42,
          child: Icon(Icons.storefront_rounded, color: scheme.onPrimary),
        ),
      ),
    );
  }
}

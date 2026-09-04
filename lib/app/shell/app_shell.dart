import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/features/settings/application/settings_providers.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(appPreferencesProvider).value;
    final backupDue =
        preferences?.isBackupReminderDue(
          ref.watch(appPreferencesClockProvider)(),
        ) ??
        false;
    final destinations = <NavigationDestination>[
      const NavigationDestination(
        icon: Icon(Icons.storefront_outlined),
        selectedIcon: Icon(Icons.storefront_rounded),
        label: 'Home',
      ),
      const NavigationDestination(
        icon: Icon(Icons.barcode_reader),
        selectedIcon: Icon(Icons.barcode_reader),
        label: 'Scan',
      ),
      NavigationDestination(
        icon: _ProfileIcon(backupDue: backupDue),
        selectedIcon: _ProfileIcon(backupDue: backupDue, selected: true),
        label: 'Profile',
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
                        label: Text('Home'),
                      ),
                      const NavigationRailDestination(
                        icon: Icon(Icons.barcode_reader),
                        selectedIcon: Icon(Icons.barcode_reader),
                        label: Text('Scan'),
                      ),
                      NavigationRailDestination(
                        icon: _ProfileIcon(backupDue: backupDue),
                        selectedIcon: _ProfileIcon(
                          backupDue: backupDue,
                          selected: true,
                        ),
                        label: Text('Profile'),
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

class _ProfileIcon extends StatelessWidget {
  const _ProfileIcon({required this.backupDue, this.selected = false});

  final bool backupDue;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Badge(
      isLabelVisible: backupDue,
      child: Icon(
        selected ? Icons.person_rounded : Icons.person_outline_rounded,
      ),
    );
  }
}

/// Exposes which persistent shell branch is actually visible.
///
/// Route-level [TickerMode] also changes while dialogs and root routes are
/// shown, so it cannot distinguish a deliberate scanner workflow from the
/// user switching to Home or Profile.
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

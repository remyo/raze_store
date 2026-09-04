import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/features/profile/presentation/profile_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows Sales and Settings and invokes their navigation seams', (
    tester,
  ) async {
    var salesOpenCount = 0;
    var settingsOpenCount = 0;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          home: ProfileScreen(
            onOpenSales: () => salesOpenCount += 1,
            onOpenSettings: () => settingsOpenCount += 1,
          ),
        ),
      ),
    );

    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Sales'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('profile-open-sales')));
    await tester.pump();
    expect(salesOpenCount, 1);
    expect(settingsOpenCount, 0);

    await tester.tap(find.byKey(const ValueKey('profile-open-settings')));
    await tester.pump();
    expect(salesOpenCount, 1);
    expect(settingsOpenCount, 1);
  });

  testWidgets('remains usable on a narrow screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: ProfileScreen(onOpenSales: () {}, onOpenSettings: () {}),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('profile-open-sales')), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-open-settings')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('default actions push Sales and Settings and return to Profile', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/profile',
      routes: [
        GoRoute(
          path: '/profile',
          builder: (context, state) => const ProfileScreen(),
        ),
        GoRoute(
          path: '/sales',
          builder: (context, state) => const Scaffold(body: Text('Sales page')),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) =>
              const Scaffold(body: Text('Settings page')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('profile-open-sales')));
    await tester.pumpAndSettle();
    expect(find.text('Sales page'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('profile-open-settings')));
    await tester.pumpAndSettle();
    expect(find.text('Settings page'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Profile'), findsOneWidget);
  });
}

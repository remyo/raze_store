import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/core/money/money.dart';
import 'package:raze_store/features/cart/application/cart_providers.dart';
import 'package:raze_store/features/cart/domain/cart.dart';
import 'package:raze_store/features/cart/presentation/cart_screen.dart';
import 'package:raze_store/features/receipt/domain/receipt_draft.dart';
import 'package:raze_store/features/settings/application/settings_providers.dart';
import 'package:raze_store/features/settings/domain/settings_repository.dart';
import 'package:raze_store/features/settings/domain/store_profile.dart';

void main() {
  testWidgets('receipt preview reads the saved store identity before opening', (
    tester,
  ) async {
    _useTallView(tester);
    final settings = _FakeSettingsRepository(
      profile: const StoreProfile(storeName: 'Aling Nena Store'),
    );
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cartDraftProvider.overrideWith((ref) => Stream.value(_cart)),
          settingsRepositoryProvider.overrideWithValue(settings),
        ],
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Preview receipt'));
    await tester.pumpAndSettle();

    expect(settings.reads, 1);
    expect(find.text('Receipt for Aling Nena Store'), findsOneWidget);
  });

  testWidgets('receipt preview does not fall back when store details fail', (
    tester,
  ) async {
    _useTallView(tester);
    final settings = _FakeSettingsRepository(error: StateError('unavailable'));
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cartDraftProvider.overrideWith((ref) => Stream.value(_cart)),
          settingsRepositoryProvider.overrideWithValue(settings),
        ],
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Preview receipt'));
    await tester.pumpAndSettle();

    expect(find.text('Cart'), findsWidgets);
    expect(find.text('Receipt for Raze Store'), findsNothing);
    expect(
      find.text('Could not load the store details for this receipt.'),
      findsOneWidget,
    );
  });
}

void _useTallView(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(800, 1400);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

GoRouter _router() => GoRouter(
  initialLocation: '/cart',
  routes: [
    GoRoute(path: '/cart', builder: (_, _) => const CartScreen()),
    GoRoute(
      path: '/receipt',
      builder: (_, state) {
        final draft = state.extra! as ReceiptDraft;
        return Scaffold(body: Text('Receipt for ${draft.storeName}'));
      },
    ),
  ],
);

final _cart = CartDraft([
  CartItem(
    lineId: 'main:coffee',
    productId: 'coffee',
    sellingUnitId: null,
    barcode: '4800012345678',
    nameSnapshot: 'Coffee',
    unitLabelSnapshot: 'Pack',
    unitPrice: Money.fromCentavos(1200),
    quantity: 1,
    addedAt: DateTime.utc(2026, 9, 3),
    updatedAt: DateTime.utc(2026, 9, 3),
  ),
]);

final class _FakeSettingsRepository implements SettingsRepository {
  _FakeSettingsRepository({this.profile, this.error});

  final StoreProfile? profile;
  final Object? error;
  int reads = 0;

  @override
  Future<StoreProfile> getStoreProfile() async {
    reads++;
    if (error case final error?) throw error;
    return profile!;
  }

  @override
  Future<void> resetStoreProfile() => throw UnimplementedError();

  @override
  Future<void> saveStoreProfile(StoreProfile profile) =>
      throw UnimplementedError();

  @override
  Stream<StoreProfile> watchStoreProfile() => const Stream.empty();
}

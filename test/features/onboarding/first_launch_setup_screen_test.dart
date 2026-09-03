import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/features/catalog_transfer/application/catalog_transfer_coordinator.dart';
import 'package:raze_store/features/catalog_transfer/application/catalog_transfer_providers.dart';
import 'package:raze_store/features/catalog_transfer/domain/catalog_transfer_result.dart';
import 'package:raze_store/features/onboarding/application/onboarding_providers.dart';
import 'package:raze_store/features/onboarding/domain/onboarding_repository.dart';
import 'package:raze_store/features/onboarding/presentation/first_launch_setup_screen.dart';
import 'package:raze_store/features/settings/application/settings_providers.dart';
import 'package:raze_store/features/settings/domain/settings_repository.dart';
import 'package:raze_store/features/settings/domain/store_profile.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('saves receipt details before showing setup choices', (
    tester,
  ) async {
    final settings = _MemorySettingsRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsRepositoryProvider.overrideWithValue(settings)],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const FirstLaunchSetupScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('setup-store-name')),
      'Aling Nena Store',
    );
    await tester.enterText(
      find.byKey(const ValueKey('setup-address')),
      'Quezon City',
    );
    await tester.tap(find.byKey(const ValueKey('save-store-setup')));
    await tester.pumpAndSettle();

    expect(settings.profile.storeName, 'Aling Nena Store');
    expect(settings.profile.address, 'Quezon City');
    expect(find.text('Aling Nena Store is ready'), findsOneWidget);
    expect(find.text('Quick add first product'), findsOneWidget);
    expect(find.text('Import or restore a catalog'), findsOneWidget);
    expect(find.text('Continue to product list'), findsOneWidget);
  });

  testWidgets('cancelled catalog import keeps onboarding incomplete', (
    tester,
  ) async {
    final settings = _MemorySettingsRepository();
    final onboarding = _MemoryOnboardingRepository();
    final transfers = _FakeCatalogTransferOperations(
      importResult: const CatalogTransferCancelled(
        message: 'CSV import was cancelled.',
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settings),
          onboardingRepositoryProvider.overrideWithValue(onboarding),
          catalogTransferCoordinatorProvider.overrideWithValue(transfers),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const FirstLaunchSetupScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('setup-store-name')),
      'Aling Nena Store',
    );
    await tester.tap(find.byKey(const ValueKey('save-store-setup')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('setup-import-restore')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import product CSV'));
    await tester.pumpAndSettle();

    expect(transfers.importCalls, 1);
    expect(onboarding.complete, isFalse);
    expect(find.text('Aling Nena Store is ready'), findsOneWidget);
    expect(find.text('CSV import was cancelled.'), findsOneWidget);
  });

  testWidgets('successful catalog import completes setup and opens products', (
    tester,
  ) async {
    final settings = _MemorySettingsRepository();
    final onboarding = _MemoryOnboardingRepository();
    final transfers = _FakeCatalogTransferOperations(
      importResult: const CatalogTransferSuccess(
        action: CatalogTransferAction.csvImport,
        message: 'Imported 2 products.',
        productCount: 2,
      ),
    );
    final router = GoRouter(
      initialLocation: '/setup',
      routes: [
        GoRoute(
          path: '/setup',
          builder: (_, _) => const FirstLaunchSetupScreen(),
        ),
        GoRoute(
          path: '/products',
          builder: (_, _) => const Scaffold(body: Text('Product list')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settings),
          onboardingRepositoryProvider.overrideWithValue(onboarding),
          catalogTransferCoordinatorProvider.overrideWithValue(transfers),
        ],
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('setup-store-name')),
      'Aling Nena Store',
    );
    await tester.tap(find.byKey(const ValueKey('save-store-setup')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('setup-import-restore')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import product CSV'));
    await tester.pumpAndSettle();

    expect(transfers.importCalls, 1);
    expect(onboarding.complete, isTrue);
    expect(find.text('Product list'), findsOneWidget);
  });
}

final class _MemorySettingsRepository implements SettingsRepository {
  StoreProfile profile = StoreProfile.defaults;

  @override
  Future<StoreProfile> getStoreProfile() async => profile;

  @override
  Future<void> resetStoreProfile() async {
    profile = StoreProfile.defaults;
  }

  @override
  Future<void> saveStoreProfile(StoreProfile profile) async {
    this.profile = profile;
  }

  @override
  Stream<StoreProfile> watchStoreProfile() => Stream.value(profile);
}

final class _MemoryOnboardingRepository implements OnboardingRepository {
  bool complete = false;

  @override
  Future<bool> isStoreSetupComplete() async => complete;

  @override
  Future<void> markStoreSetupComplete() async {
    complete = true;
  }
}

final class _FakeCatalogTransferOperations
    implements CatalogTransferOperations {
  _FakeCatalogTransferOperations({required this.importResult});

  final CatalogTransferResult importResult;
  int importCalls = 0;

  @override
  Future<CatalogTransferResult> importCsvMerging() async {
    importCalls++;
    return importResult;
  }

  @override
  Future<CatalogTransferResult> createBackup() => throw UnimplementedError();

  @override
  Future<CatalogTransferResult> exportCsv() => throw UnimplementedError();

  @override
  Future<CatalogTransferResult> restoreBackupReplacing() =>
      throw UnimplementedError();
}

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
    expect(find.text('Import offline catalog pack'), findsOneWidget);
    expect(find.text('Add first product'), findsOneWidget);
    expect(find.text('Restore backup or import CSV'), findsOneWidget);
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

  testWidgets('catalog pack import completes setup and opens products', (
    tester,
  ) async {
    final settings = _MemorySettingsRepository();
    final onboarding = _MemoryOnboardingRepository();
    final transfers = _FakeCatalogTransferOperations(
      importResult: const CatalogTransferCancelled(message: 'Not used.'),
      packImportResult: const CatalogTransferSuccess(
        action: CatalogTransferAction.catalogPackImport,
        message: 'Added 250 offline products.',
        productCount: 250,
        photoCount: 240,
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

    await tester.tap(find.byKey(const ValueKey('setup-import-catalog-pack')));
    await tester.pumpAndSettle();

    expect(transfers.packImportCalls, 1);
    expect(onboarding.complete, isTrue);
    expect(find.text('Product list'), findsOneWidget);
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

  testWidgets('restore and CSV choices scroll at large text sizes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final settings = _MemorySettingsRepository();
    final transfers = _FakeCatalogTransferOperations(
      importResult: const CatalogTransferCancelled(
        message: 'CSV import was cancelled.',
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settings),
          catalogTransferCoordinatorProvider.overrideWithValue(transfers),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(3)),
            child: child!,
          ),
          home: const FirstLaunchSetupScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('setup-store-name')),
      'Aling Nena Store',
    );
    final saveSetup = find.byKey(const ValueKey('save-store-setup'));
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    await tester.tap(saveSetup);
    await tester.pumpAndSettle();

    final openChoices = find.byKey(const ValueKey('setup-import-restore'));
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    await tester.tap(openChoices);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('setup-import-restore-sheet-scroll')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    final csvChoice = find.text('Import product CSV');
    await tester.ensureVisible(csvChoice);
    await tester.tap(csvChoice);
    await tester.pumpAndSettle();

    expect(transfers.importCalls, 1);
    expect(tester.takeException(), isNull);
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
  _FakeCatalogTransferOperations({
    required this.importResult,
    this.packImportResult = const CatalogTransferCancelled(
      message: 'Catalog pack import was cancelled.',
    ),
  });

  final CatalogTransferResult importResult;
  final CatalogTransferResult packImportResult;
  int importCalls = 0;
  int packImportCalls = 0;

  @override
  Future<CatalogTransferResult> importCatalogPackMerging({
    CatalogPackImportMode mode = CatalogPackImportMode.keepExisting,
  }) async {
    packImportCalls++;
    return packImportResult;
  }

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

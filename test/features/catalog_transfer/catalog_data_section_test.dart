import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/features/catalog_transfer/application/catalog_transfer_coordinator.dart';
import 'package:raze_store/features/catalog_transfer/application/catalog_transfer_providers.dart';
import 'package:raze_store/features/catalog_transfer/domain/catalog_pack_review.dart';
import 'package:raze_store/features/catalog_transfer/domain/catalog_transfer_result.dart';
import 'package:raze_store/features/catalog_transfer/presentation/catalog_data_section.dart';
import 'package:raze_store/features/settings/application/settings_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('explains safe pack merge, backup, and CSV behavior', (
    tester,
  ) async {
    final operations = _FakeTransferOperations();
    final reviewOperations = _FakeReviewOperations();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogTransferCoordinatorProvider.overrideWithValue(operations),
          catalogPackReviewCoordinatorProvider.overrideWithValue(
            reviewOperations,
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: SingleChildScrollView(child: CatalogDataSection()),
          ),
        ),
      ),
    );

    expect(
      find.text(
        'Backup files are not encrypted. They contain prices, completed transactions and payment amounts, store details, and copies of product photos, so keep them private.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Import adds or updates'), findsOneWidget);

    expect(find.text('Offline catalog pack'), findsOneWidget);
    expect(find.textContaining('Existing non-zero prices'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('import-catalog-pack')));
    await tester.pumpAndSettle();
    expect(find.text('Review catalog pack'), findsOneWidget);
    expect(find.text('New products'), findsOneWidget);
    expect(find.text('Existing products'), findsOneWidget);
    expect(reviewOperations.applyCalls, 0);
    await tester.tap(
      find.byKey(const ValueKey('catalog-review-new-select-shown')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('catalog-review-apply')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('catalog-review-confirm-apply')),
    );
    await tester.pumpAndSettle();
    expect(reviewOperations.applyCalls, 1);
    expect(reviewOperations.lastSelection!.selectedProductIds, {'new-1'});

    await tester.ensureVisible(find.text('Restore backup'));
    await tester.tap(find.text('Restore backup'));
    await tester.pumpAndSettle();
    expect(find.text('Replace local store data?'), findsOneWidget);
    expect(operations.restoreCalls, 0);
    await tester.tap(find.text('Choose backup and replace'));
    await tester.pumpAndSettle();
    expect(operations.restoreCalls, 1);

    ScaffoldMessenger.of(
      tester.element(find.byType(CatalogDataSection)),
    ).hideCurrentSnackBar();
    await tester.pumpAndSettle();
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import CSV'));
    await tester.pumpAndSettle();
    expect(find.text('Import product CSV?'), findsOneWidget);
    expect(operations.importCalls, 0);
    await tester.tap(find.text('Choose CSV and import'));
    await tester.pumpAndSettle();
    expect(operations.importCalls, 1);
  });

  testWidgets('reviews matching pack products separately from new ones', (
    tester,
  ) async {
    final operations = _FakeTransferOperations();
    final reviewOperations = _FakeReviewOperations(
      review: _review(includeExisting: true),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogTransferCoordinatorProvider.overrideWithValue(operations),
          catalogPackReviewCoordinatorProvider.overrideWithValue(
            reviewOperations,
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: SingleChildScrollView(child: CatalogDataSection()),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('import-catalog-pack')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Existing products'));
    await tester.pumpAndSettle();
    expect(
      find.text('0 of 1 existing products selected. Showing 1 of 1.'),
      findsOneWidget,
    );
  });

  testWidgets('records only a successfully saved complete backup', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 9, 4, 9);
    SharedPreferences.setMockInitialValues({});
    final operations = _FakeTransferOperations(
      backupResult: const CatalogTransferSuccess(
        action: CatalogTransferAction.backupExport,
        message: 'Backup saved.',
        productCount: 2,
      ),
    );
    final reviewOperations = _FakeReviewOperations();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appPreferencesClockProvider.overrideWithValue(() => now),
          catalogTransferCoordinatorProvider.overrideWithValue(operations),
          catalogPackReviewCoordinatorProvider.overrideWithValue(
            reviewOperations,
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: SingleChildScrollView(child: CatalogDataSection()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Create backup'));
    await tester.tap(find.text('Create backup'));
    await tester.pumpAndSettle();

    expect(operations.backupCalls, 1);
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString(lastSuccessfulBackupPreferenceKey),
      now.toIso8601String(),
    );
  });

  testWidgets('confirmation dialogs scroll at large text sizes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final reviewOperations = _FakeReviewOperations(
      undoSummary: CatalogPackUndoSummary(
        packId: 'starter',
        revision: 1,
        importedAt: DateTime.utc(2026, 9, 4),
        createdCount: 2,
        updatedCount: 1,
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogTransferCoordinatorProvider.overrideWithValue(
            _FakeTransferOperations(),
          ),
          catalogPackReviewCoordinatorProvider.overrideWithValue(
            reviewOperations,
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: const Scaffold(
            body: SingleChildScrollView(child: CatalogDataSection()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> expectScrollableDialog({
      required Finder trigger,
      required String title,
    }) async {
      await tester.ensureVisible(trigger);
      await tester.pumpAndSettle();
      await tester.tap(trigger);
      await tester.pumpAndSettle();

      expect(find.text(title), findsOneWidget);
      expect(
        tester.widget<AlertDialog>(find.byType(AlertDialog)).scrollable,
        isTrue,
      );
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    }

    await expectScrollableDialog(
      trigger: find.byKey(const ValueKey('undo-catalog-pack-import')),
      title: 'Undo last catalog import?',
    );
    await expectScrollableDialog(
      trigger: find.text('Restore backup'),
      title: 'Replace local store data?',
    );
    await expectScrollableDialog(
      trigger: find.text('Import CSV'),
      title: 'Import product CSV?',
    );
  });
}

final class _FakeTransferOperations implements CatalogTransferOperations {
  _FakeTransferOperations({
    this.backupResult = const CatalogTransferCancelled(message: 'Cancelled.'),
  });

  final CatalogTransferResult backupResult;
  var packImportCalls = 0;
  CatalogPackImportMode? lastPackImportMode;
  var restoreCalls = 0;
  var importCalls = 0;
  var backupCalls = 0;

  @override
  Future<CatalogTransferResult> createBackup() async {
    backupCalls++;
    return backupResult;
  }

  @override
  Future<CatalogTransferResult> exportCsv() async =>
      const CatalogTransferCancelled(message: 'Cancelled.');

  @override
  Future<CatalogTransferResult> importCsvMerging() async {
    importCalls++;
    return const CatalogTransferSuccess(
      action: CatalogTransferAction.csvImport,
      message: 'Imported.',
      productCount: 1,
    );
  }

  @override
  Future<CatalogTransferResult> importCatalogPackMerging({
    CatalogPackImportMode mode = CatalogPackImportMode.keepExisting,
  }) async {
    packImportCalls++;
    lastPackImportMode = mode;
    return const CatalogTransferSuccess(
      action: CatalogTransferAction.catalogPackImport,
      message: 'Catalog pack imported.',
      productCount: 1,
      photoCount: 1,
    );
  }

  @override
  Future<CatalogTransferResult> restoreBackupReplacing() async {
    restoreCalls++;
    return const CatalogTransferSuccess(
      action: CatalogTransferAction.backupRestore,
      message: 'Restored.',
      productCount: 1,
    );
  }
}

final class _FakeReviewOperations implements CatalogPackReviewOperations {
  _FakeReviewOperations({CatalogPackReview? review, this.undoSummary})
    : review = review ?? _review();

  final CatalogPackReview review;
  final CatalogPackUndoSummary? undoSummary;
  var applyCalls = 0;
  var discardCalls = 0;
  var undoCalls = 0;
  CatalogPackApplySelection? lastSelection;

  @override
  Future<CatalogPackReviewChoiceResult> chooseCatalogPackForReview() async =>
      CatalogPackReviewReady(review);

  @override
  Future<CatalogTransferResult> applyCatalogPackReview(
    CatalogPackReview review,
    CatalogPackApplySelection selection,
  ) async {
    applyCalls++;
    lastSelection = selection;
    return CatalogTransferSuccess(
      action: CatalogTransferAction.catalogPackImport,
      message: 'Imported ${selection.selectedProductIds.length} products.',
      productCount: selection.selectedProductIds.length,
    );
  }

  @override
  Future<void> discardCatalogPackReview(CatalogPackReview review) async {
    discardCalls++;
  }

  @override
  Future<CatalogPackUndoSummary?> getLastCatalogImportUndo() async =>
      undoSummary;

  @override
  Future<CatalogTransferResult> undoLastCatalogImport() async {
    undoCalls++;
    return const CatalogTransferSuccess(
      action: CatalogTransferAction.catalogPackUndo,
      message: 'Catalog import undone.',
      productCount: 3,
    );
  }
}

CatalogPackReview _review({bool includeExisting = false}) => CatalogPackReview(
  reviewId: 'review-1',
  packId: 'starter',
  revision: 1,
  createdAt: DateTime.utc(2026, 9, 4),
  products: [
    CatalogPackReviewProduct(
      targetId: 'new-1',
      catalogProductId: 'shared-new-1',
      incoming: _details(name: 'New Coffee'),
      existing: null,
      hasBundledImage: false,
    ),
    if (includeExisting)
      CatalogPackReviewProduct(
        targetId: 'existing-1',
        catalogProductId: 'shared-existing-1',
        incoming: _details(name: 'Updated Crackers'),
        existing: _details(name: 'Local Crackers'),
        hasBundledImage: false,
      ),
  ],
);

CatalogPackProductDetails _details({required String name}) =>
    CatalogPackProductDetails(
      barcode: '4800000000000',
      name: name,
      brand: 'Brand',
      unitLabel: 'Pack',
      category: 'Snacks',
      priceCentavos: 1000,
      hasImage: false,
    );

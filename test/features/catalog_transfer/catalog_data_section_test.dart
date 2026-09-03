import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/features/catalog_transfer/application/catalog_transfer_coordinator.dart';
import 'package:raze_store/features/catalog_transfer/application/catalog_transfer_providers.dart';
import 'package:raze_store/features/catalog_transfer/domain/catalog_transfer_result.dart';
import 'package:raze_store/features/catalog_transfer/presentation/catalog_data_section.dart';

void main() {
  testWidgets(
    'explains backup and CSV behavior and confirms destructive restore',
    (tester) async {
      final operations = _FakeTransferOperations();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            catalogTransferCoordinatorProvider.overrideWithValue(operations),
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
          'Backup files are not encrypted. They contain prices, store details, and copies of product photos, so keep them private.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Import adds or updates'), findsOneWidget);

      await tester.tap(find.text('Restore backup'));
      await tester.pumpAndSettle();
      expect(find.text('Replace this catalog?'), findsOneWidget);
      expect(operations.restoreCalls, 0);
      await tester.tap(find.text('Choose file and replace'));
      await tester.pumpAndSettle();
      expect(operations.restoreCalls, 1);

      await tester.tap(find.text('Import CSV'));
      await tester.pumpAndSettle();
      expect(find.text('Import product CSV?'), findsOneWidget);
      expect(operations.importCalls, 0);
      await tester.tap(find.text('Choose CSV and import'));
      await tester.pumpAndSettle();
      expect(operations.importCalls, 1);
    },
  );
}

final class _FakeTransferOperations implements CatalogTransferOperations {
  var restoreCalls = 0;
  var importCalls = 0;

  @override
  Future<CatalogTransferResult> createBackup() async =>
      const CatalogTransferCancelled(message: 'Cancelled.');

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
  Future<CatalogTransferResult> restoreBackupReplacing() async {
    restoreCalls++;
    return const CatalogTransferSuccess(
      action: CatalogTransferAction.backupRestore,
      message: 'Restored.',
      productCount: 1,
    );
  }
}

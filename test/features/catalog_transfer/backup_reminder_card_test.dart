import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/features/catalog_transfer/application/catalog_transfer_coordinator.dart';
import 'package:raze_store/features/catalog_transfer/application/catalog_transfer_providers.dart';
import 'package:raze_store/features/catalog_transfer/domain/catalog_transfer_result.dart';
import 'package:raze_store/features/catalog_transfer/presentation/backup_reminder_card.dart';
import 'package:raze_store/features/settings/application/settings_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final now = DateTime.utc(2026, 9, 4, 8);

  setUp(() {
    SharedPreferences.setMockInitialValues({
      backupReminderFrequencyPreferenceKey: 'weekly',
      backupReminderAnchorPreferenceKey: now
          .subtract(const Duration(days: 8))
          .toIso8601String(),
    });
  });

  testWidgets('postpones a due reminder for one day', (tester) async {
    await _pumpReminder(tester, now: now, operations: _FakeOperations());

    expect(find.byKey(const ValueKey('backup-reminder-card')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('snooze-backup-reminder')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('backup-reminder-card')), findsNothing);
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString(backupReminderSnoozedUntilPreferenceKey),
      now.add(const Duration(days: 1)).toIso8601String(),
    );
  });

  testWidgets('successful backup records completion and clears reminder', (
    tester,
  ) async {
    final operations = _FakeOperations(
      backupResult: const CatalogTransferSuccess(
        action: CatalogTransferAction.backupExport,
        message: 'Backup saved.',
        productCount: 20,
      ),
    );
    await _pumpReminder(tester, now: now, operations: operations);

    await tester.tap(find.byKey(const ValueKey('create-reminder-backup')));
    await tester.pumpAndSettle();

    expect(operations.backupCalls, 1);
    expect(find.byKey(const ValueKey('backup-reminder-card')), findsNothing);
    expect(find.text('Backup saved.'), findsOneWidget);
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString(lastSuccessfulBackupPreferenceKey),
      now.toIso8601String(),
    );
  });
}

Future<void> _pumpReminder(
  WidgetTester tester, {
  required DateTime now,
  required CatalogTransferOperations operations,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appPreferencesClockProvider.overrideWithValue(() => now),
        catalogTransferCoordinatorProvider.overrideWithValue(operations),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: SingleChildScrollView(child: BackupReminderCard()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final class _FakeOperations implements CatalogTransferOperations {
  _FakeOperations({
    this.backupResult = const CatalogTransferCancelled(message: 'Cancelled.'),
  });

  final CatalogTransferResult backupResult;
  int backupCalls = 0;

  @override
  Future<CatalogTransferResult> createBackup() async {
    backupCalls++;
    return backupResult;
  }

  @override
  Future<CatalogTransferResult> exportCsv() => throw UnimplementedError();

  @override
  Future<CatalogTransferResult> importCatalogPackMerging({
    CatalogPackImportMode mode = CatalogPackImportMode.keepExisting,
  }) => throw UnimplementedError();

  @override
  Future<CatalogTransferResult> importCsvMerging() =>
      throw UnimplementedError();

  @override
  Future<CatalogTransferResult> restoreBackupReplacing() =>
      throw UnimplementedError();
}

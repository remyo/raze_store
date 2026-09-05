import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/features/settings/application/app_storage_providers.dart';
import 'package:raze_store/features/settings/data/app_storage_service.dart';
import 'package:raze_store/features/settings/domain/app_storage_usage.dart';
import 'package:raze_store/features/settings/presentation/storage_screen.dart';

void main() {
  test('formats storage amounts with binary units', () {
    expect(formatStorageBytes(-1), '0 B');
    expect(formatStorageBytes(0), '0 B');
    expect(formatStorageBytes(999), '999 B');
    expect(formatStorageBytes(1024), '1.0 KB');
    expect(formatStorageBytes(3 * 1024 * 1024), '3.0 MB');
    expect(formatStorageBytes(2 * 1024 * 1024 * 1024), '2.0 GB');
  });

  testWidgets('shows the complete managed breakdown and external scope', (
    tester,
  ) async {
    final service = await _pumpStorage(tester);

    final total = find.byKey(const ValueKey('storage-managed-total'));
    expect(total, findsOneWidget);
    expect(tester.widget<Text>(total).data, '1.0 GB');
    expect(find.text('Store database'), findsOneWidget);
    expect(find.text('Managed product images'), findsOneWidget);
    expect(find.text('Temporary receipt copies'), findsOneWidget);
    expect(find.text('Background-removal files'), findsOneWidget);
    expect(find.text('Other temporary cache'), findsOneWidget);

    final externalNotice = find.byKey(
      const ValueKey('storage-external-files-notice'),
    );
    await tester.ensureVisible(externalNotice);
    expect(find.textContaining('Receipt PNGs'), findsOneWidget);
    expect(find.textContaining('backups, and CSV files'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('storage-installed-app-notice')),
      findsOneWidget,
    );
    expect(
      find.textContaining('bundled background-removal model'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('storage-database-reuse-note')),
      findsOneWidget,
    );
    expect(find.textContaining('device free'), findsNothing);
    expect(service.loadCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('clears temporary files after confirmation and refreshes', (
    tester,
  ) async {
    final service = await _pumpStorage(tester);
    final clearButton = find.byKey(const ValueKey('storage-clear-temporary'));
    await tester.ensureVisible(clearButton);
    await tester.tap(clearButton);
    await tester.pumpAndSettle();

    expect(find.text('Clear temporary files?'), findsOneWidget);
    expect(
      find.textContaining(
        'Products, sales, product images, the database, and exported files will stay untouched.',
      ),
      findsOneWidget,
    );
    expect(service.clearCalls, 0);

    await tester.tap(
      find.byKey(const ValueKey('storage-confirm-clear-temporary')),
    );
    await tester.pumpAndSettle();

    expect(service.clearCalls, 1);
    expect(service.loadCalls, 2);
    expect(find.text('Cleared 2.0 MB from temporary storage.'), findsOneWidget);
    final receiptRow = find.byKey(const ValueKey('storage-temporary-receipts'));
    expect(
      find.descendant(of: receiptRow, matching: find.text('0 B')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('stays usable on a narrow screen with large text', (
    tester,
  ) async {
    await _pumpStorage(
      tester,
      size: const Size(320, 720),
      textScaler: const TextScaler.linear(2),
    );

    final clearButton = find.byKey(const ValueKey('storage-clear-temporary'));
    await tester.ensureVisible(clearButton);
    expect(clearButton, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<_FakeStorageService> _pumpStorage(
  WidgetTester tester, {
  Size size = const Size(390, 1200),
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final service = _FakeStorageService();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appStorageServiceProvider.overrideWithValue(service)],
      child: MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
        home: const StorageScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return service;
}

class _FakeStorageService extends AppStorageService {
  int loadCalls = 0;
  int clearCalls = 0;
  var _temporaryReceiptBytes = 512 * 1024;
  var _backgroundRemovalBytes = 512 * 1024;
  var _cacheBytes = 1024 * 1024;

  @override
  Future<AppStorageUsage> loadUsage() async {
    loadCalls += 1;
    return AppStorageUsage(
      databaseBytes: 1024 * 1024 * 1024,
      productImageBytes: 4 * 1024 * 1024,
      temporaryReceiptBytes: _temporaryReceiptBytes,
      backgroundRemovalBytes: _backgroundRemovalBytes,
      cacheBytes: _cacheBytes,
      measuredAt: DateTime(2026, 9, 3),
      databaseFileCount: 2,
      productImageFileCount: 3,
      temporaryReceiptFileCount: _temporaryReceiptBytes == 0 ? 0 : 1,
      backgroundRemovalFileCount: _backgroundRemovalBytes == 0 ? 0 : 1,
      cacheFileCount: _cacheBytes == 0 ? 0 : 2,
    );
  }

  @override
  Future<AppStorageCleanupResult> clearTemporaryFiles() async {
    clearCalls += 1;
    final cleared =
        _temporaryReceiptBytes + _backgroundRemovalBytes + _cacheBytes;
    _temporaryReceiptBytes = 0;
    _backgroundRemovalBytes = 0;
    _cacheBytes = 0;
    return AppStorageCleanupResult(
      clearedBytes: cleared,
      clearedFileCount: 4,
      failureCount: 0,
    );
  }
}

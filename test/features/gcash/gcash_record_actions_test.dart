import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/features/gcash/gcash_record.dart';
import 'package:raze_store/features/gcash/gcash_record_actions.dart';
import 'package:raze_store/features/gcash/gcash_repository.dart';
import 'package:raze_store/features/receipt/application/receipt_export_service.dart';

const _menuKey = ValueKey('gcash-record-actions');
const _progressKey = ValueKey('gcash-record-actions-progress');

class _Repository extends Fake implements GcashRepository {
  final deletedIds = <String>[];
  final savedRecords = <GcashRecord>[];
  Completer<void>? pendingDelete;
  bool failDelete = false;

  @override
  Future<void> delete(String id) async {
    deletedIds.add(id);
    if (pendingDelete != null) await pendingDelete!.future;
    if (failDelete) throw StateError('Synthetic delete failure');
  }

  @override
  Future<void> save(GcashRecord record) async => savedRecords.add(record);
}

class _ExportService extends Fake implements ReceiptExportService {
  final downloads = <({Uint8List bytes, String fileName})>[];
  final shares =
      <({Uint8List bytes, String fileName, String storeName, Rect? origin})>[];
  Completer<ReceiptSaveResult>? pendingDownload;
  Completer<void>? pendingShare;
  ReceiptSaveResult downloadResult = ReceiptSaveResult.saved;
  bool fail = false;

  @override
  Future<ReceiptSaveResult> savePng({
    required Uint8List bytes,
    required String fileName,
  }) async {
    downloads.add((bytes: bytes, fileName: fileName));
    if (fail) throw StateError('Synthetic export failure');
    return pendingDownload == null
        ? downloadResult
        : await pendingDownload!.future;
  }

  @override
  Future<void> sharePng({
    required Uint8List bytes,
    required String fileName,
    required String storeName,
    Rect? sharePositionOrigin,
  }) async {
    shares.add((
      bytes: bytes,
      fileName: fileName,
      storeName: storeName,
      origin: sharePositionOrigin,
    ));
    if (fail) throw StateError('Synthetic share failure');
    if (pendingShare != null) await pendingShare!.future;
  }
}

GcashRecord _record({
  bool withReceipt = true,
  String name = 'Sample customer',
  String reference = '0040000000001',
}) => GcashRecord(
  id: 'saved-record-42',
  kind: GcashKind.cashIn,
  name: name,
  number: '09170000000',
  amount: 50000,
  fee: 1000,
  reference: reference,
  date: DateTime(2026, 9, 5, 12),
  receipt: withReceipt
      ? Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10])
      : null,
);

class _Harness {
  final repository = _Repository();
  final exportService = _ExportService();
  final navigator = GlobalKey<NavigatorState>();
  int onDeletedCalls = 0;
  bool? canPopAtDeletion;
  bool navigateOnDelete = true;
}

Future<_Harness> _open(
  WidgetTester tester, {
  GcashRecord? record,
  _Harness? harness,
  double textScale = 1,
}) async {
  final state = harness ?? _Harness();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [gcashRepositoryProvider.overrideWithValue(state.repository)],
      child: MaterialApp(
        navigatorKey: state.navigator,
        theme: ThemeData(
          appBarTheme: const AppBarThemeData(
            foregroundColor: Colors.white,
            backgroundColor: Color(0xFF005CE5),
          ),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => Scaffold(
                    appBar: AppBar(
                      title: const Text('Transaction record'),
                      actions: [
                        GcashRecordActions(
                          record: record ?? _record(),
                          exportService: state.exportService,
                          onDeleted: () {
                            state.onDeletedCalls++;
                            state.canPopAtDeletion = tester
                                .widget<PopScope>(find.byType(PopScope))
                                .canPop;
                            if (state.navigateOnDelete) {
                              Navigator.of(context).maybePop();
                            }
                          },
                        ),
                      ],
                    ),
                    body: const Text('Saved transaction details'),
                  ),
                ),
              ),
              child: const Text('Open record'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open record'));
  await tester.pumpAndSettle();
  return state;
}

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(_menuKey));
  await tester.pumpAndSettle();
}

Future<VoidCallback> _select(WidgetTester tester, String label) async {
  await _openMenu(tester);
  // Preserve the private enum callback when replaying a rapid selection;
  // casting it to void Function(dynamic) would reject its narrower argument.
  final dynamic menu = tester.widget(find.byKey(_menuKey));
  final item = tester.widget<PopupMenuItem<dynamic>>(
    find.ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate((widget) => widget is PopupMenuItem),
    ),
  );
  await tester.tap(find.text(label));
  // Fixed pumps let pending-operation tests inspect a spinning progress icon.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  return () => menu.onSelected!(item.value);
}

void _expectUnchanged(_Harness harness) {
  expect(harness.repository.deletedIds, isEmpty);
  expect(harness.repository.savedRecords, isEmpty);
  expect(harness.onDeletedCalls, 0);
}

void main() {
  testWidgets('opening and dismissing the menu is read-only, with no edit', (
    tester,
  ) async {
    final harness = await _open(tester);
    await _openMenu(tester);
    expect(find.text('Download receipt'), findsOneWidget);
    expect(find.text('Share receipt'), findsOneWidget);
    expect(find.text('Delete record'), findsOneWidget);
    expect(find.textContaining('Edit'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    await tester.tapAt(const Offset(16, 450));
    await tester.pumpAndSettle();
    _expectUnchanged(harness);
    expect(harness.exportService.downloads, isEmpty);
    expect(harness.exportService.shares, isEmpty);
    expect(find.text('Saved transaction details'), findsOneWidget);
  });

  testWidgets('records without an attachment only offer deletion', (
    tester,
  ) async {
    final harness = await _open(tester, record: _record(withReceipt: false));
    await _openMenu(tester);
    expect(find.text('Download receipt'), findsNothing);
    expect(find.text('Share receipt'), findsNothing);
    expect(find.text('Delete record'), findsOneWidget);
    _expectUnchanged(harness);
  });

  testWidgets('download exports the saved bytes and id without mutation', (
    tester,
  ) async {
    final record = _record();
    final harness = await _open(tester, record: record);
    await _select(tester, 'Download receipt');
    await tester.pumpAndSettle();
    expect(harness.exportService.downloads, hasLength(1));
    expect(harness.exportService.downloads.single.bytes, same(record.receipt));
    expect(
      harness.exportService.downloads.single.fileName,
      'gcash-saved-record-42.png',
    );
    expect(find.text('Receipt saved to Files.'), findsOneWidget);
    expect(find.text('Saved transaction details'), findsOneWidget);
    _expectUnchanged(harness);
  });

  testWidgets('cancelled download does not report a saved receipt', (
    tester,
  ) async {
    final harness = _Harness();
    harness.exportService.downloadResult = ReceiptSaveResult.cancelled;
    await _open(tester, harness: harness);
    await _select(tester, 'Download receipt');
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('Saved transaction details'), findsOneWidget);
    expect(
      tester.widget<PopupMenuButton<dynamic>>(find.byKey(_menuKey)).enabled,
      isTrue,
    );
    _expectUnchanged(harness);
  });

  for (final action in ['Download receipt', 'Share receipt']) {
    testWidgets('$action failure retains the record and enables retry', (
      tester,
    ) async {
      final harness = _Harness();
      harness.exportService.fail = true;
      await _open(tester, harness: harness);
      await _select(tester, action);
      await tester.pumpAndSettle();
      expect(
        find.text('Could not export the receipt. Please try again.'),
        findsOneWidget,
      );
      expect(find.text('Saved transaction details'), findsOneWidget);
      expect(
        tester.widget<PopupMenuButton<dynamic>>(find.byKey(_menuKey)).enabled,
        isTrue,
      );
      _expectUnchanged(harness);
    });
  }

  testWidgets('sharing uses saved bytes and the persistent iPad menu anchor', (
    tester,
  ) async {
    final record = _record();
    final harness = await _open(tester, record: record);
    final expectedOrigin = tester.getRect(find.byKey(_menuKey));
    await _select(tester, 'Share receipt');
    await tester.pumpAndSettle();
    expect(harness.exportService.shares, hasLength(1));
    final call = harness.exportService.shares.single;
    expect(call.bytes, same(record.receipt));
    expect(call.fileName, 'gcash-saved-record-42.png');
    expect(call.storeName, 'GCash receipt');
    expect(call.origin, expectedOrigin);
    expect(call.origin!.width, greaterThan(0));
    expect(call.origin!.height, greaterThan(0));
    _expectUnchanged(harness);
  });

  for (final useBack in [false, true]) {
    testWidgets(
      'delete ${useBack ? 'dismissal' : 'cancellation'} changes nothing',
      (tester) async {
        final harness = await _open(tester);
        final repeatAction = await _select(tester, 'Delete record');
        repeatAction();
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(
          find.textContaining('Sample customer\nTransaction no. 0040000000001'),
          findsOneWidget,
        );
        if (useBack) {
          await harness.navigator.currentState!.maybePop();
        } else {
          await tester.tap(find.text('Cancel'));
        }
        await tester.pumpAndSettle();
        _expectUnchanged(harness);
        expect(find.text('Saved transaction details'), findsOneWidget);
        expect(
          tester.widget<PopupMenuButton<dynamic>>(find.byKey(_menuKey)).enabled,
          isTrue,
        );
      },
    );
  }

  testWidgets(
    'confirmed deletion targets one id and blocks duplicate actions/back',
    (tester) async {
      final harness = _Harness();
      harness.repository.pendingDelete = Completer<void>();
      await _open(tester, harness: harness);
      final repeatAction = await _select(tester, 'Delete record');
      await tester.tap(find.text('Delete'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(harness.repository.deletedIds, ['saved-record-42']);
      expect(find.byKey(_progressKey), findsOneWidget);
      expect(
        tester
            .widget<CircularProgressIndicator>(find.byKey(_progressKey))
            .color,
        Colors.white,
      );
      expect(
        tester.widget<PopupMenuButton<dynamic>>(find.byKey(_menuKey)).enabled,
        isFalse,
      );
      repeatAction();
      await harness.navigator.currentState!.maybePop();
      await tester.pump();
      expect(find.text('Saved transaction details'), findsOneWidget);
      expect(harness.repository.deletedIds, ['saved-record-42']);
      expect(harness.onDeletedCalls, 0);
      harness.repository.pendingDelete!.complete();
      await tester.pumpAndSettle();
      expect(harness.onDeletedCalls, 1);
      expect(harness.canPopAtDeletion, isTrue);
      expect(find.text('Open record'), findsOneWidget);
      expect(find.text('Saved transaction details'), findsNothing);
      expect(harness.repository.savedRecords, isEmpty);
    },
  );

  testWidgets('delete confirmation fits long details on a tiny scaled screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final harness = await _open(
      tester,
      record: _record(name: 'Name ' * 30, reference: '0' * 80),
      textScale: 2,
    );
    await _select(tester, 'Delete record');
    await tester.pumpAndSettle();
    expect(
      tester.widget<AlertDialog>(find.byType(AlertDialog)).scrollable,
      isTrue,
    );
    expect(find.text('Delete').hitTestable(), findsOneWidget);
    expect(find.text('Cancel').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    _expectUnchanged(harness);
  });

  testWidgets(
    'successful deletion only calls back once if caller stays on page',
    (tester) async {
      final harness = _Harness()..navigateOnDelete = false;
      await _open(tester, harness: harness);
      final repeatAction = await _select(tester, 'Delete record');
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      repeatAction();
      await tester.pumpAndSettle();
      expect(harness.repository.deletedIds, ['saved-record-42']);
      expect(harness.onDeletedCalls, 1);
      expect(harness.canPopAtDeletion, isTrue);
      expect(
        tester.widget<PopupMenuButton<dynamic>>(find.byKey(_menuKey)).enabled,
        isFalse,
      );
      expect(find.byKey(_progressKey), findsNothing);
    },
  );

  testWidgets(
    'delete failure does not navigate and permits a confirmed retry',
    (tester) async {
      final harness = _Harness();
      harness.repository.failDelete = true;
      await _open(tester, harness: harness);
      await _select(tester, 'Delete record');
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Could not delete the record.'), findsOneWidget);
      expect(find.text('Saved transaction details'), findsOneWidget);
      expect(harness.onDeletedCalls, 0);
      expect(
        tester.widget<PopupMenuButton<dynamic>>(find.byKey(_menuKey)).enabled,
        isTrue,
      );
      harness.repository.failDelete = false;
      await _select(tester, 'Delete record');
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(harness.repository.deletedIds, [
        'saved-record-42',
        'saved-record-42',
      ]);
      expect(harness.onDeletedCalls, 1);
    },
  );

  for (final share in [false, true]) {
    testWidgets(
      '${share ? 'share' : 'download'} pending disables repeats and back',
      (tester) async {
        final harness = _Harness();
        if (share) {
          harness.exportService.pendingShare = Completer<void>();
        } else {
          harness.exportService.pendingDownload =
              Completer<ReceiptSaveResult>();
        }
        await _open(tester, harness: harness);
        final repeatAction = await _select(
          tester,
          share ? 'Share receipt' : 'Download receipt',
        );
        repeatAction();
        await harness.navigator.currentState!.maybePop();
        await tester.pump();
        expect(find.byKey(_progressKey), findsOneWidget);
        expect(
          tester.widget<PopupMenuButton<dynamic>>(find.byKey(_menuKey)).enabled,
          isFalse,
        );
        expect(find.text('Saved transaction details'), findsOneWidget);
        if (share) {
          expect(harness.exportService.shares, hasLength(1));
          harness.exportService.pendingShare!.complete();
        } else {
          expect(harness.exportService.downloads, hasLength(1));
          harness.exportService.pendingDownload!.complete(
            ReceiptSaveResult.cancelled,
          );
        }
        await tester.pumpAndSettle();
        expect(find.byKey(_progressKey), findsNothing);
        expect(
          tester.widget<PopupMenuButton<dynamic>>(find.byKey(_menuKey)).enabled,
          isTrue,
        );
        _expectUnchanged(harness);
        await harness.navigator.currentState!.maybePop();
        await tester.pumpAndSettle();
        expect(find.text('Saved transaction details'), findsNothing);
      },
    );
  }
}

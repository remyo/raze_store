import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/core/database/app_database.dart';
import 'package:raze_store/features/gcash/gcash_record.dart';
import 'package:raze_store/features/gcash/gcash_repository.dart';
import 'package:raze_store/features/gcash/gcash_screen.dart';
import 'package:raze_store/features/gcash/gcash_transaction_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _today = DateTime(2026, 9, 5);

GcashRecord _record(
  String id, {
  DateTime? date,
  GcashKind kind = GcashKind.cashIn,
}) => GcashRecord(
  id: id,
  kind: kind,
  name: 'Customer $id',
  number: '09171234567',
  amount: 50000,
  fee: 1000,
  reference: '1234$id',
  date: date ?? DateTime(2026, 9, 5, 12),
);

class _RecordRequest {
  _RecordRequest({
    required this.since,
    required this.until,
    required this.kind,
    required this.limit,
    required this.rows,
  });

  final DateTime? since;
  final DateTime? until;
  final GcashKind? kind;
  final int limit;
  final List<GcashRecord> rows;
  final controller = StreamController<List<GcashRecord>>();

  void emit() => controller.add(rows.take(limit).toList());
}

class _HistoryRepository extends GcashRepository {
  _HistoryRepository(this.rows)
    : super(AppDatabase.forTesting(NativeDatabase.memory()));

  final List<GcashRecord> rows;
  final requests = <_RecordRequest>[];
  int totalRequests = 0;
  bool pauseRequests = false;

  List<GcashRecord> _matching(
    DateTime? since,
    DateTime? until,
    GcashKind? kind,
  ) =>
      rows
          .where(
            (record) =>
                (since == null || !record.date.isBefore(since)) &&
                (until == null || record.date.isBefore(until)) &&
                (kind == null || record.kind == kind),
          )
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date));

  @override
  Stream<List<GcashRecord>> watch({
    DateTime? since,
    DateTime? until,
    GcashKind? kind,
    int limit = 40,
  }) {
    final request = _RecordRequest(
      since: since,
      until: until,
      kind: kind,
      limit: limit,
      rows: _matching(since, until, kind),
    );
    requests.add(request);
    if (!pauseRequests) request.emit();
    return request.controller.stream;
  }

  @override
  Stream<({int cashIn, int cashOut, int fees})> totals({
    DateTime? since,
    DateTime? until,
    GcashKind? kind,
  }) {
    totalRequests++;
    final filtered = _matching(since, until, kind);
    return Stream.value((
      cashIn: filtered
          .where((record) => record.kind == GcashKind.cashIn)
          .fold(0, (sum, record) => sum + record.amount),
      cashOut: filtered
          .where((record) => record.kind == GcashKind.cashOut)
          .fold(0, (sum, record) => sum + record.amount),
      fees: filtered.fold(0, (sum, record) => sum + record.fee),
    ));
  }

  Future<void> dispose() async {
    await Future.wait(requests.map((request) => request.controller.close()));
    await database.close();
  }
}

Finder _key(String value) => find.byKey(ValueKey(value));

Finder get _historyScroll => find.descendant(
  of: _key('gcash-history-list'),
  matching: find.byType(Scrollable),
);

Future<_HistoryRepository> _pumpHistory(
  WidgetTester tester, {
  List<GcashRecord> records = const [],
  double width = 390,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  final repository = _HistoryRepository(records);
  addTearDown(repository.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [gcashRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(home: GcashScreen(now: () => _today)),
    ),
  );
  await tester.pumpAndSettle();
  return repository;
}

Future<void> _openFilters(WidgetTester tester) async {
  await tester.tap(_key('gcash-history-filter'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _selectFilter(WidgetTester tester, String key) async {
  await tester.ensureVisible(_key(key));
  await tester.tap(_key(key));
  await tester.pump();
}

void main() {
  testWidgets('starts on Today with a useful empty state and day bounds', (
    tester,
  ) async {
    final repository = await _pumpHistory(
      tester,
      records: [
        _record('yesterday', date: DateTime(2026, 9, 4, 23, 59)),
        _record('tomorrow', date: DateTime(2026, 9, 6)),
      ],
    );

    expect(find.text('GCash Services'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.byTooltip('GCash settings'), findsOneWidget);
    expect(find.text('No transactions today'), findsOneWidget);
    expect(find.text('Today · All transactions'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.text('₱0.00'), findsNWidgets(3));
    expect(repository.requests.single.since, _today);
    expect(repository.requests.single.until, DateTime(2026, 9, 6));
    expect(repository.requests.single.limit, 41);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bottom actions stay visible during scrolling and open sheets', (
    tester,
  ) async {
    await _pumpHistory(
      tester,
      width: 320,
      records: [
        for (var index = 0; index < 60; index++)
          _record(
            '$index',
            date: DateTime(2026, 9, 5, 12).subtract(Duration(minutes: index)),
          ),
      ],
    );
    final cashIn = _key('gcash-history-cash-in');
    final cashOut = _key('gcash-history-cash-out');
    final initialPosition = tester.getRect(cashIn);
    await tester.scrollUntilVisible(
      _key('gcash-history-record-45'),
      500,
      scrollable: _historyScroll,
      maxScrolls: 30,
    );
    await tester.pumpAndSettle();
    expect(tester.getRect(cashIn), initialPosition);
    expect(cashIn.hitTestable(), findsOneWidget);
    expect(cashOut.hitTestable(), findsOneWidget);

    for (final entry in [
      (finder: cashIn, kind: GcashKind.cashIn),
      (finder: cashOut, kind: GcashKind.cashOut),
    ]) {
      await tester.tap(entry.finder);
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoSheetTransition), findsOneWidget);
      final form = tester.widget<GcashFormScreen>(find.byType(GcashFormScreen));
      expect(form.kind, entry.kind);
      expect(form.asBottomSheet, isTrue);
      expect(form.record, isNull);
      await tester.tap(find.byTooltip('Close form'));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoSheetTransition), findsNothing);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a history row opens its read-only transaction page', (
    tester,
  ) async {
    final record = _record('view', kind: GcashKind.cashOut);
    await _pumpHistory(tester, records: [record]);
    expect(find.text('Customer view'), findsOneWidget);
    expect(find.text('Sep 5, 12:00 PM\n09171234567'), findsOneWidget);
    await tester.tap(_key('gcash-history-record-view'));
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoSheetTransition), findsNothing);
    expect(find.byType(GcashFormScreen), findsNothing);
    final page = tester.widget<GcashTransactionScreen>(
      find.byType(GcashTransactionScreen),
    );
    expect(page.record, same(record));
    expect(find.text('GCash transaction'), findsOneWidget);
    expect(find.text('Customer view'), findsOneWidget);
    expect(find.text('09171234567'), findsOneWidget);
    expect(find.text('₱500.00'), findsOneWidget);
    expect(find.text('₱10.00'), findsOneWidget);
    expect(find.text('1234view'), findsOneWidget);
    expect(find.text('Recorded'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(Image), findsNothing);
    expect(find.byKey(const ValueKey('gcash-record-actions')), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(_key('gcash-history-record-view').hitTestable(), findsOneWidget);
    expect(find.text('Today · All transactions'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('deleting from record actions returns to refreshed history', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = GcashRepository(database);
    await tester.runAsync(() => repository.save(_record('delete-record')));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [gcashRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(home: GcashScreen(now: () => _today)),
      ),
    );
    await tester.runAsync(() => repository.watch().first);
    await tester.pumpAndSettle();
    await tester.tap(_key('gcash-history-record-delete-record'));
    await tester.pumpAndSettle();
    expect(find.byType(GcashTransactionScreen), findsOneWidget);
    await tester.tap(find.byTooltip('Record actions'));
    await tester.pumpAndSettle();
    expect(find.text('Edit'), findsNothing);
    await tester.tap(find.text('Delete record'));
    await tester.pumpAndSettle();
    expect(find.text('Delete GCash record?'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    // Let native SQLite work and the dialog/page transitions advance together.
    for (
      var attempt = 0;
      attempt < 100 &&
          find.byType(GcashTransactionScreen).evaluate().isNotEmpty;
      attempt++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
    expect(find.byType(GcashTransactionScreen), findsNothing);
    expect(find.byType(GcashFormScreen), findsNothing);
    expect(find.text('No transactions today'), findsOneWidget);
    expect(find.text('₱0.00'), findsNWidgets(3));
    expect(await tester.runAsync(() => repository.watch().first), isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('filter edits cancel cleanly and apply dates and type together', (
    tester,
  ) async {
    final repository = await _pumpHistory(
      tester,
      records: [
        _record('today'),
        _record(
          'recent-out',
          date: DateTime(2026, 9, 1),
          kind: GcashKind.cashOut,
        ),
        _record('old-out', date: DateTime(2026, 8, 1), kind: GcashKind.cashOut),
      ],
    );
    await _openFilters(tester);
    await _selectFilter(tester, 'gcash-filter-days-7');
    await _selectFilter(tester, 'gcash-filter-kind-cashOut');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repository.requests, hasLength(1));
    expect(find.text('Today · All transactions'), findsOneWidget);
    expect(find.text('Customer today'), findsOneWidget);

    await _openFilters(tester);
    expect(
      tester.widget<ChoiceChip>(_key('gcash-filter-days-1')).selected,
      isTrue,
    );
    expect(
      tester.widget<ChoiceChip>(_key('gcash-filter-kind-all')).selected,
      isTrue,
    );
    await _selectFilter(tester, 'gcash-filter-days-7');
    await _selectFilter(tester, 'gcash-filter-kind-cashOut');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.text('Last 7 days · Cash Out'), findsOneWidget);
    expect(find.text('Customer recent-out'), findsOneWidget);
    expect(find.text('Customer today'), findsNothing);
    expect(find.text('Customer old-out'), findsNothing);
    expect(repository.requests.last.since, DateTime(2026, 8, 30));
    expect(repository.requests.last.until, DateTime(2026, 9, 6));
    expect(repository.requests.last.kind, GcashKind.cashOut);
    expect(repository.requests.last.limit, 41);

    await _openFilters(tester);
    await _selectFilter(tester, 'gcash-filter-days-0');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(repository.requests.last.since, isNull);
    expect(repository.requests.last.until, isNull);
    expect(find.text('Customer old-out'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a new filter clears old rows while its results are pending', (
    tester,
  ) async {
    final repository = await _pumpHistory(tester, records: [_record('today')]);
    final oldRequest = repository.requests.single;
    repository.pauseRequests = true;
    await _openFilters(tester);
    await _selectFilter(tester, 'gcash-filter-kind-cashOut');
    await tester.tap(find.text('Apply'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Customer today'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    oldRequest.emit();
    await tester.pump();
    expect(find.text('Customer today'), findsNothing);
    repository.requests.last.emit();
    await tester.pumpAndSettle();
    expect(find.text('No transactions today'), findsOneWidget);
    expect(find.text('Today · Cash Out'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pagination waits for one page and keeps all-range totals', (
    tester,
  ) async {
    final repository = await _pumpHistory(
      tester,
      records: [
        for (var index = 0; index < 60; index++)
          _record(
            '$index',
            date: DateTime(2026, 9, 5, 12).subtract(Duration(minutes: index)),
          ),
      ],
    );
    expect(find.text('₱30,000.00'), findsOneWidget);
    expect(repository.totalRequests, 1);
    repository.pauseRequests = true;
    for (
      var attempt = 0;
      attempt < 30 && repository.requests.length == 1;
      attempt++
    ) {
      await tester.drag(_key('gcash-history-list'), const Offset(0, -500));
      await tester.pump();
    }
    expect(repository.requests, hasLength(2));
    expect(repository.requests.last.limit, 81);
    expect(repository.totalRequests, 1);
    expect(_key('gcash-history-record-40'), findsNothing);

    await tester.drag(_key('gcash-history-list'), const Offset(0, -300));
    await tester.pump();
    expect(repository.requests, hasLength(2));
    repository.requests.last.emit();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      _key('gcash-history-record-45'),
      500,
      scrollable: _historyScroll,
    );
    expect(_key('gcash-history-record-45'), findsOneWidget);

    repository.pauseRequests = false;
    await _openFilters(tester);
    await _selectFilter(tester, 'gcash-filter-days-30');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(repository.requests.last.limit, 41);
    expect(repository.requests.last.since, DateTime(2026, 8, 7));
    expect(find.text('Customer 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('custom single-day range is a draft until applied', (
    tester,
  ) async {
    final repository = await _pumpHistory(tester);
    await _openFilters(tester);
    await tester.tap(_key('gcash-filter-custom-range'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Switch to input'));
    await tester.pumpAndSettle();
    final inputs = find.byType(TextField);
    expect(inputs, findsNWidgets(2));
    await tester.enterText(inputs.at(0), '09/03/2026');
    await tester.enterText(inputs.at(1), '09/03/2026');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(repository.requests, hasLength(1));
    expect(find.text('Sep 3, 2026'), findsOneWidget);
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(repository.requests.last.since, DateTime(2026, 9, 3));
    expect(repository.requests.last.until, DateTime(2026, 9, 4));
    expect(find.text('No transactions on Sep 3'), findsOneWidget);
    expect(find.text('Sep 3, 2026 · All transactions'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saving Cash In closes the sheet and refreshes Today history', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = GcashRepository(database);
    await tester.runAsync(() => repository.watch().first);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [gcashRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(home: GcashScreen(now: () => _today)),
      ),
    );
    await tester.runAsync(() => repository.watch(since: _today).first);
    await tester.pumpAndSettle();
    await tester.tap(_key('gcash-history-cash-in'));
    await tester.pumpAndSettle();

    Finder field(String label) => find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == label,
    );
    for (final entry in [
      (label: 'Customer name', value: 'New customer'),
      (label: 'Mobile number (as shown on receipt)', value: '09171234567'),
      (label: 'Amount (₱)', value: '500'),
      (label: 'Reference / transaction number', value: '123456789'),
    ]) {
      await tester.ensureVisible(field(entry.label));
      await tester.enterText(field(entry.label), entry.value);
    }
    await tester.ensureVisible(find.text('Choose transaction date & time'));
    await tester.tap(find.text('Choose transaction date & time'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Switch to input'));
    await tester.pumpAndSettle();
    final dateField = find.descendant(
      of: find.byType(DatePickerDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(dateField, '09/05/2026');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save GCash record'));
    await tester.runAsync(() async {
      await tester.tap(find.text('Save GCash record'));
      return repository.watch().first;
    });
    await tester.pumpAndSettle();
    final saved = await tester.runAsync(() => repository.watch().first);
    await tester.pumpAndSettle();

    expect(saved!.single.name, 'New customer');
    expect(saved.single.amount, 50000);
    expect(saved.single.fee, 1000);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('New customer'), findsOneWidget);
    expect(find.text('No transactions today'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:raze_store/core/widgets/app_toast.dart';

import 'gcash_record.dart';
import 'gcash_record_actions.dart';
import 'gcash_repository.dart';
import 'gcash_screen.dart' show showGcashFormSheet;
import 'gcash_settings_screen.dart';
import 'gcash_theme.dart';
import 'gcash_transaction_screen.dart';

typedef _GcashTotals = ({int cashIn, int cashOut, int fees});

String _money(int value) =>
    NumberFormat.currency(locale: 'en_PH', symbol: '₱').format(value / 100);

class GcashScreen extends ConsumerStatefulWidget {
  const GcashScreen({super.key, this.now});

  final DateTime Function()? now;

  @override
  ConsumerState<GcashScreen> createState() => _GcashScreenState();
}

class _GcashScreenState extends ConsumerState<GcashScreen> {
  static const _pageSize = 40;
  final _scroll = ScrollController();
  _HistoryFilter _filter = const _HistoryFilter();
  StreamSubscription<List<GcashRecord>>? _recordSubscription;
  StreamSubscription<_GcashTotals>? _totalSubscription;
  List<GcashRecord>? _records;
  _GcashTotals? _totals;
  Object? _recordError;
  bool _totalError = false;
  bool _loadingRecords = false;
  bool _hasMore = false;
  int _limit = _pageSize;
  int _recordRequest = 0;
  int _filterRevision = 0;
  DateTime? _since;
  DateTime? _until;

  DateTime get _today =>
      DateUtils.dateOnly(widget.now?.call() ?? DateTime.now());

  @override
  void initState() {
    super.initState();
    _reloadFilter();
  }

  void _reloadFilter() {
    final today = _today;
    final range = _filter.range;
    _since =
        range?.start ??
        (_filter.days == 0
            ? null
            : DateTime(today.year, today.month, today.day - _filter.days + 1));
    final end = range?.end ?? today;
    _until = range == null && _filter.days == 0
        ? null
        : DateTime(end.year, end.month, end.day + 1);
    _limit = _pageSize;
    _records = null;
    _totals = null;
    _hasMore = false;
    _totalError = false;
    final revision = ++_filterRevision;
    unawaited(_totalSubscription?.cancel());
    _totalSubscription = ref
        .read(gcashRepositoryProvider)
        .totals(since: _since, until: _until, kind: _filter.kind)
        .listen(
          (totals) {
            if (!mounted || revision != _filterRevision) return;
            setState(() {
              _totals = totals;
              _totalError = false;
            });
          },
          onError: (Object error) {
            if (!mounted || revision != _filterRevision) return;
            setState(() => _totalError = true);
          },
        );
    _watchRecords();
  }

  void _watchRecords() {
    _loadingRecords = true;
    _recordError = null;
    final request = ++_recordRequest;
    final limit = _limit;
    unawaited(_recordSubscription?.cancel());
    _recordSubscription = ref
        .read(gcashRepositoryProvider)
        .watch(
          since: _since,
          until: _until,
          kind: _filter.kind,
          limit: limit + 1,
        )
        .listen(
          (records) {
            if (!mounted || request != _recordRequest) return;
            setState(() {
              _records = records.take(limit).toList();
              _hasMore = records.length > limit;
              _loadingRecords = false;
              _recordError = null;
            });
          },
          onError: (Object error) {
            if (!mounted || request != _recordRequest) return;
            setState(() {
              _recordError = error;
              _loadingRecords = false;
            });
          },
        );
  }

  void _loadMore() {
    if (_loadingRecords || !_hasMore || _recordError != null) return;
    setState(() {
      _limit += _pageSize;
      _watchRecords();
    });
  }

  Future<void> _chooseFilters(BuildContext context) async {
    final filter = await showDialog<_HistoryFilter>(
      context: context,
      builder: (_) => _HistoryFilterDialog(filter: _filter, today: _today),
    );
    if (!mounted || filter == null) return;
    setState(() {
      _filter = filter;
      _reloadFilter();
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _openRecord(BuildContext context, GcashRecord record) =>
      Navigator.of(context, rootNavigator: true).push<void>(
        MaterialPageRoute<void>(
          builder: (pageContext) => GcashTransactionScreen(
            record: record,
            actions: [
              GcashRecordActions(
                record: record,
                onDeleted: () => Navigator.of(pageContext).pop(),
              ),
            ],
          ),
        ),
      );

  Future<void> _createRecord(BuildContext context, GcashKind kind) async {
    final saved = await showGcashFormSheet(context, kind: kind);
    if (!mounted || !context.mounted || saved == null) return;
    final day = DateUtils.dateOnly(saved.date);
    // An imported receipt may be months old. Show its actual transaction day
    // instead of silently hiding the new record behind the Today/type filter.
    setState(() {
      _filter = _HistoryFilter(
        range: DateUtils.isSameDay(day, _today)
            ? null
            : DateTimeRange(start: day, end: day),
      );
      _reloadFilter();
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    final details = _openRecord(context, saved);
    showToast(context, 'GCash record saved.', type: AppToastType.success);
    await details;
  }

  @override
  void dispose() {
    unawaited(_recordSubscription?.cancel());
    unawaited(_totalSubscription?.cancel());
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GcashTheme(
    builder: (context) {
      final theme = Theme.of(context);
      return Scaffold(
        appBar: AppBar(
          title: const Text('GCash Services'),
          actions: [
            IconButton(
              tooltip: 'GCash settings',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const GcashSettingsScreen(),
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'History',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        OutlinedButton.icon(
                          key: const ValueKey('gcash-history-filter'),
                          onPressed: () => _chooseFilters(context),
                          icon: const Icon(Icons.tune_rounded, size: 18),
                          label: const Text('Filter'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_filter.periodLabel} · ${_filter.kind?.label ?? 'All transactions'}',
                      key: const ValueKey('gcash-history-filter-summary'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(child: _history(context)),
            ],
          ),
        ),
        bottomNavigationBar: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.cardTheme.color,
            border: Border(
              top: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: const ValueKey('gcash-history-cash-in'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(48, 52),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    onPressed: () => _createRecord(context, GcashKind.cashIn),
                    icon: const Icon(Icons.add_circle_outline_rounded),
                    label: const Text('Cash In'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey('gcash-history-cash-out'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(48, 52),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    onPressed: () => _createRecord(context, GcashKind.cashOut),
                    icon: const Icon(Icons.payments_outlined),
                    label: const Text('Cash Out'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _history(BuildContext context) {
    final records = _records;
    final itemCount = records == null || records.isEmpty
        ? 2
        : 1 + records.length + (_hasMore || _recordError != null ? 1 : 0);
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollUpdateNotification &&
            notification.metrics.extentAfter < 240) {
          _loadMore();
        }
        return false;
      },
      child: ListView.builder(
        key: const ValueKey('gcash-history-list'),
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        itemCount: itemCount,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _TotalsCard(
                totals: _totals,
                hasError: _totalError,
                onRetry: () => setState(_reloadFilter),
              ),
            );
          }
          if (records == null || records.isEmpty) {
            if (_recordError != null) return _retryRecords();
            if (_loadingRecords) {
              return const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            return _EmptyHistory(filter: _filter);
          }
          if (index > records.length) {
            if (_recordError != null) return _retryRecords();
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: _loadingRecords
                    ? const CircularProgressIndicator()
                    : TextButton(
                        onPressed: _loadMore,
                        child: const Text('Load more transactions'),
                      ),
              ),
            );
          }
          final record = records[index - 1];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _HistoryRow(
              record: record,
              onTap: () => _openRecord(context, record),
            ),
          );
        },
      ),
    );
  }

  Widget _retryRecords() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32),
    child: Center(
      child: TextButton.icon(
        onPressed: () => setState(_watchRecords),
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Could not load transactions. Retry'),
      ),
    ),
  );
}

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({
    required this.totals,
    required this.hasError,
    required this.onRetry,
  });

  final _GcashTotals? totals;
  final bool hasError;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.12),
        ),
      ),
      child: hasError
          ? TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Totals unavailable. Retry'),
            )
          : LayoutBuilder(
              builder: (context, constraints) => Wrap(
                spacing: 12,
                runSpacing: 16,
                children: [
                  for (final entry in [
                    (label: 'Cash in', amount: totals?.cashIn),
                    (label: 'Cash out', amount: totals?.cashOut),
                    (label: 'Service fees', amount: totals?.fees),
                  ])
                    SizedBox(
                      width:
                          constraints.maxWidth >= 300 &&
                              MediaQuery.textScalerOf(context).scale(14) <= 18
                          ? (constraints.maxWidth - 24) / 3
                          : (constraints.maxWidth - 12) / 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.label,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            entry.amount == null ? '…' : _money(entry.amount!),
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.record, required this.onTap});

  final GcashRecord record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final receiptPlaceholder = ColoredBox(
      color: theme.colorScheme.primary.withValues(alpha: 0.07),
      child: Icon(
        Icons.receipt_long_outlined,
        color: theme.colorScheme.primary,
      ),
    );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('gcash-history-record-${record.id}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 44,
                  height: 56,
                  child: record.receipt == null
                      ? receiptPlaceholder
                      : Image.memory(
                          record.receipt!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => receiptPlaceholder,
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      record.kind.label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${DateFormat('MMM d, h:mm a').format(record.date)}\n${record.number}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _money(record.amount),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory({required this.filter});

  final _HistoryFilter filter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final range = filter.range;
    final title = range != null
        ? (DateUtils.isSameDay(range.start, range.end)
              ? 'No transactions on ${DateFormat.MMMd().format(range.start)}'
              : 'No transactions in this date range')
        : switch (filter.days) {
            1 => 'No transactions today',
            0 => 'No transactions yet',
            _ => 'No transactions in the last ${filter.days} days',
          };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: Column(
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.receipt_long_rounded,
              size: 40,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            filter.kind == null && filter.days == 1 && range == null
                ? 'Your GCash activity will appear here.\nStart with Cash In or Cash Out below.'
                : 'Try another filter, or record a new\n${filter.kind?.label ?? 'GCash'} transaction below.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryFilter {
  const _HistoryFilter({this.days = 1, this.range, this.kind});

  final int days;
  final DateTimeRange? range;
  final GcashKind? kind;

  String get periodLabel {
    final selectedRange = range;
    if (selectedRange != null) {
      final start = DateFormat.yMMMd().format(selectedRange.start);
      return DateUtils.isSameDay(selectedRange.start, selectedRange.end)
          ? start
          : '$start – ${DateFormat.yMMMd().format(selectedRange.end)}';
    }
    return switch (days) {
      1 => 'Today',
      7 => 'Last 7 days',
      30 => 'Last 30 days',
      _ => 'All dates',
    };
  }
}

class _HistoryFilterDialog extends StatefulWidget {
  const _HistoryFilterDialog({required this.filter, required this.today});

  final _HistoryFilter filter;
  final DateTime today;

  @override
  State<_HistoryFilterDialog> createState() => _HistoryFilterDialogState();
}

class _HistoryFilterDialogState extends State<_HistoryFilterDialog> {
  late int _days = widget.filter.days;
  late DateTimeRange? _range = widget.filter.range;
  late GcashKind? _kind = widget.filter.kind;

  Future<void> _chooseRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2200),
      currentDate: widget.today,
      initialDateRange: _range,
      builder: (context, child) => DatePickerTheme(
        data: DatePickerTheme.of(context).copyWith(
          rangePickerHeaderHeadlineStyle: Theme.of(
            context,
          ).textTheme.titleMedium,
        ),
        child: child!,
      ),
    );
    if (range != null && mounted) {
      setState(() => _range = range);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Filter history'),
    content: SizedBox(
      width: 360,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Date', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final days in [1, 7, 30, 0])
                  ChoiceChip(
                    key: ValueKey('gcash-filter-days-$days'),
                    label: Text(switch (days) {
                      1 => 'Today',
                      7 => '7 days',
                      30 => '30 days',
                      _ => 'All dates',
                    }),
                    selected: _range == null && _days == days,
                    onSelected: (_) => setState(() {
                      _days = days;
                      _range = null;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const ValueKey('gcash-filter-custom-range'),
              onPressed: _chooseRange,
              icon: const Icon(Icons.date_range_outlined),
              label: Text(
                _range == null
                    ? 'Custom range'
                    : _HistoryFilter(range: _range).periodLabel,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Transaction type',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                ChoiceChip(
                  key: const ValueKey('gcash-filter-kind-all'),
                  label: const Text('All types'),
                  selected: _kind == null,
                  onSelected: (_) => setState(() => _kind = null),
                ),
                for (final kind in GcashKind.values)
                  ChoiceChip(
                    key: ValueKey('gcash-filter-kind-${kind.name}'),
                    label: Text(kind.label),
                    selected: _kind == kind,
                    onSelected: (_) => setState(() => _kind = kind),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(
          context,
        ).pop(_HistoryFilter(days: _days, range: _range, kind: _kind)),
        child: const Text('Apply'),
      ),
    ],
  );
}

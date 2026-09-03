import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/core/widgets/app_widgets.dart';
import 'package:raze_store/features/sales/application/sales_providers.dart';
import 'package:raze_store/features/sales/domain/completed_sale.dart';
import 'package:raze_store/features/sales/domain/sales_date_range.dart';
import 'package:raze_store/features/sales/presentation/widgets/sales_history_widgets.dart';

enum SalesPeriodPreset {
  today,
  sevenDays,
  thisMonth,
  threeMonths,
  thisYear,
  custom,
}

extension SalesPeriodPresetLabel on SalesPeriodPreset {
  String get label => switch (this) {
    SalesPeriodPreset.today => 'Today',
    SalesPeriodPreset.sevenDays => '7D',
    SalesPeriodPreset.thisMonth => 'This month',
    SalesPeriodPreset.threeMonths => '3 months',
    SalesPeriodPreset.thisYear => 'This year',
    SalesPeriodPreset.custom => 'Custom',
  };
}

/// Daily sales history with synchronized period totals and transaction rows.
class SalesScreen extends ConsumerStatefulWidget {
  const SalesScreen({
    super.key,
    this.now,
    this.initialPeriod = SalesPeriodPreset.today,
    this.onOpenSale,
  });

  /// Clock seam used by deterministic date-filter and heading tests.
  final DateTime? now;
  final SalesPeriodPreset initialPeriod;

  /// Optional navigation seam. The app route is used when this is omitted.
  final ValueChanged<CompletedSale>? onOpenSale;

  @override
  ConsumerState<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends ConsumerState<SalesScreen> {
  late SalesPeriodPreset _period;
  DateTimeRange? _customRange;
  final Set<String> _selectedSaleIds = <String>{};
  bool _selectionMode = false;
  bool _pickingCustomRange = false;
  bool _confirmingDelete = false;
  bool _deletingSelected = false;

  bool get _bulkActionLocked => _confirmingDelete || _deletingSelected;

  @override
  void initState() {
    super.initState();
    _period = widget.initialPeriod;
    if (_period == SalesPeriodPreset.custom) {
      final localNow = (widget.now ?? DateTime.now()).toLocal();
      final today = DateTime(localNow.year, localNow.month, localNow.day);
      _customRange = DateTimeRange(start: today, end: today);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.now ?? DateTime.now();
    final range = _dateRange(now);
    final history = ref.watch(salesHistoryForRangeProvider(range));
    final oldestSaleDate = ref.watch(oldestSaleDateProvider);
    final hasLoadedSales = switch (history) {
      AsyncData(:final value) => value.isNotEmpty,
      _ => false,
    };
    final width = MediaQuery.sizeOf(context).width;
    final pageInsets = AppSpacing.pageInsetsFor(width);
    final sideInset = ((width - AppBreakpoints.readingMaxWidth) / 2).clamp(
      pageInsets.left,
      double.infinity,
    );

    return AppPageScaffold(
      title: 'Sales',
      actions: [
        if (_selectionMode)
          TextButton(
            key: const ValueKey('sales-cancel-selection'),
            onPressed: _bulkActionLocked ? null : _cancelSelection,
            child: const Text('Cancel'),
          )
        else if (hasLoadedSales)
          TextButton(
            key: const ValueKey('sales-start-selection'),
            onPressed: _startSelection,
            child: const Text('Select'),
          ),
      ],
      padBody: false,
      body: CustomScrollView(
        key: const ValueKey('sales-scroll-view'),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              sideInset,
              pageInsets.top,
              sideInset,
              0,
            ),
            sliver: SliverList.list(
              children: [
                const AppSectionHeader(
                  title: 'Daily sales history',
                  subtitle:
                      'Review completed checkouts and totals by local sale date.',
                ),
                const SizedBox(height: AppSpacing.sm),
                _SalesPeriodSelector(
                  selected: _period,
                  customLabel: _customRange == null
                      ? null
                      : _formatPickerRange(_customRange!),
                  enabled:
                      !_selectionMode &&
                      !_pickingCustomRange &&
                      !_bulkActionLocked,
                  onSelected: (period) => _selectPeriod(
                    period,
                    now: now,
                    oldestSaleDate: oldestSaleDate.value,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
            ),
          ),
          ...history.when(
            loading: () => [
              const SliverFillRemaining(
                hasScrollBody: false,
                child: AppLoadingState(message: 'Loading sales…'),
              ),
            ],
            error: (error, stackTrace) => [
              SliverFillRemaining(
                hasScrollBody: false,
                child: AppErrorState(
                  message: 'Sales history could not be loaded.',
                  onRetry: () {
                    ref
                      ..invalidate(salesHistoryForRangeProvider(range))
                      ..invalidate(oldestSaleDateProvider);
                  },
                ),
              ),
            ],
            data: (sales) {
              if (sales.isEmpty) {
                final noSalesAnywhere =
                    oldestSaleDate is AsyncData<DateTime?> &&
                    oldestSaleDate.value == null;
                return [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: AppEmptyState(
                      icon: noSalesAnywhere
                          ? Icons.point_of_sale_outlined
                          : Icons.event_busy_outlined,
                      title: noSalesAnywhere
                          ? 'No sales yet'
                          : 'No sales in this period',
                      message: noSalesAnywhere
                          ? 'Completed checkouts will appear here automatically.'
                          : 'Choose another date range to review earlier sales.',
                    ),
                  ),
                ];
              }

              final visibleIds = sales.map((sale) => sale.id).toSet();
              final selectedCount = _selectedSaleIds
                  .where(visibleIds.contains)
                  .length;
              final allSelected = selectedCount == sales.length;

              return [
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: sideInset),
                  sliver: SliverToBoxAdapter(
                    child: SalesSummaryCard(
                      summary: SalesSummaryData.fromSales(sales),
                      periodLabel: _periodDescription(now),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    sideInset,
                    AppSpacing.lg,
                    sideInset,
                    AppSpacing.sm,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: AppSectionHeader(
                      title: 'Transactions',
                      subtitle: _selectionMode
                          ? '$selectedCount of ${sales.length} selected'
                          : '${sales.length} ${sales.length == 1 ? 'sale' : 'sales'} · newest first',
                    ),
                  ),
                ),
                if (_selectionMode)
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      sideInset,
                      0,
                      sideInset,
                      AppSpacing.sm,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: _SalesSelectionToolbar(
                        selectedCount: selectedCount,
                        allSelected: allSelected,
                        locked: _bulkActionLocked,
                        deleting: _deletingSelected,
                        onToggleAll: () => _toggleSelectAll(sales),
                        onDelete: selectedCount == 0
                            ? null
                            : () => _confirmDeleteSelected(sales, now: now),
                      ),
                    ),
                  ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    sideInset,
                    0,
                    sideInset,
                    pageInsets.bottom + AppSpacing.lg,
                  ),
                  sliver: SalesHistorySliver(
                    sales: sales,
                    now: now,
                    onOpenSale: _openSale,
                    selectionMode: _selectionMode,
                    selectedSaleIds: _selectedSaleIds,
                    onToggleSelection: _toggleSelection,
                    enabled: !_bulkActionLocked,
                  ),
                ),
              ];
            },
          ),
        ],
      ),
    );
  }

  SalesDateRange _dateRange(DateTime now) {
    return switch (_period) {
      SalesPeriodPreset.today => SalesDateRange.today(now),
      SalesPeriodPreset.sevenDays => SalesDateRange.lastDays(7, now: now),
      SalesPeriodPreset.thisMonth => SalesDateRange.thisMonth(now),
      SalesPeriodPreset.threeMonths => SalesDateRange.lastMonths(3, now: now),
      SalesPeriodPreset.thisYear => SalesDateRange.thisYear(now),
      SalesPeriodPreset.custom => SalesDateRange.custom(
        startDay: _customRange!.start,
        endDay: _customRange!.end,
      ),
    };
  }

  String _periodDescription(DateTime now) {
    final localNow = now.toLocal();
    return switch (_period) {
      SalesPeriodPreset.today =>
        'Today · ${DateFormat.yMMMd().format(localNow)}',
      SalesPeriodPreset.sevenDays => 'Last 7 days',
      SalesPeriodPreset.thisMonth => DateFormat.yMMMM().format(localNow),
      SalesPeriodPreset.threeMonths => 'Last 3 calendar months',
      SalesPeriodPreset.thisYear => DateFormat.y().format(localNow),
      SalesPeriodPreset.custom => _formatPickerRange(_customRange!),
    };
  }

  Future<void> _selectPeriod(
    SalesPeriodPreset period, {
    required DateTime now,
    required DateTime? oldestSaleDate,
  }) async {
    if (_bulkActionLocked || _pickingCustomRange) return;
    if (period != SalesPeriodPreset.custom) {
      if (_period != period) {
        setState(() {
          _period = period;
          _selectionMode = false;
          _selectedSaleIds.clear();
        });
      }
      return;
    }

    final localNow = now.toLocal();
    final today = DateTime(localNow.year, localNow.month, localNow.day);
    var firstDate = DateTime(today.year - 10, today.month, today.day);
    if (oldestSaleDate != null) {
      final completed = oldestSaleDate.toLocal();
      final day = DateTime(completed.year, completed.month, completed.day);
      if (day.isBefore(firstDate)) firstDate = day;
    }
    final initial = _customRange ?? DateTimeRange(start: today, end: today);
    setState(() => _pickingCustomRange = true);
    DateTimeRange? picked;
    try {
      picked = await showDateRangePicker(
        context: context,
        firstDate: firstDate,
        lastDate: today,
        currentDate: today,
        initialDateRange: DateTimeRange(
          start: initial.start.isBefore(firstDate) ? firstDate : initial.start,
          end: initial.end.isAfter(today) ? today : initial.end,
        ),
        helpText: 'Choose sales dates',
        saveText: 'Apply',
      );
    } finally {
      if (mounted) setState(() => _pickingCustomRange = false);
    }
    if (picked == null || !mounted) return;
    setState(() {
      _customRange = picked;
      _period = SalesPeriodPreset.custom;
      _selectionMode = false;
      _selectedSaleIds.clear();
    });
  }

  void _startSelection() {
    if (_bulkActionLocked || _pickingCustomRange || _selectionMode) return;
    setState(() => _selectionMode = true);
  }

  void _cancelSelection() {
    if (_bulkActionLocked || !_selectionMode) return;
    setState(() {
      _selectionMode = false;
      _selectedSaleIds.clear();
    });
  }

  void _toggleSelection(CompletedSale sale) {
    if (_bulkActionLocked) return;
    setState(() {
      _selectionMode = true;
      if (!_selectedSaleIds.add(sale.id)) {
        _selectedSaleIds.remove(sale.id);
      }
    });
  }

  void _toggleSelectAll(List<CompletedSale> sales) {
    if (_bulkActionLocked || sales.isEmpty) return;
    final visibleIds = sales.map((sale) => sale.id).toSet();
    final allSelected = visibleIds.every(_selectedSaleIds.contains);
    setState(() {
      if (allSelected) {
        _selectedSaleIds.removeAll(visibleIds);
      } else {
        _selectedSaleIds.addAll(visibleIds);
      }
    });
  }

  Future<void> _confirmDeleteSelected(
    List<CompletedSale> sales, {
    required DateTime now,
  }) async {
    if (_bulkActionLocked) return;
    final visibleIds = sales.map((sale) => sale.id).toSet();
    final ids = List<String>.unmodifiable(
      _selectedSaleIds.where(visibleIds.contains).toSet(),
    );
    if (ids.isEmpty) return;

    final count = ids.length;
    final saleWord = count == 1 ? 'sale' : 'sales';
    final periodLabel = _periodDescription(now);
    setState(() => _confirmingDelete = true);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete $count $saleWord?'),
        content: Text(
          'This permanently deletes $count $saleWord from "$periodLabel", '
          'including the saved receipt details. Products in your catalog will '
          'not be deleted. This cannot be undone.',
        ),
        actions: [
          TextButton(
            key: const ValueKey('sales-delete-cancel'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep sales'),
          ),
          FilledButton(
            key: const ValueKey('sales-delete-confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            child: Text('Delete $count $saleWord'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed != true) {
      setState(() => _confirmingDelete = false);
      return;
    }

    setState(() {
      _confirmingDelete = false;
      _deletingSelected = true;
    });
    try {
      await ref.read(salesRepositoryProvider).deleteSales(ids);
      if (!mounted) return;
      setState(() {
        _deletingSelected = false;
        _selectionMode = false;
        _selectedSaleIds.clear();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$count $saleWord deleted.')));
    } catch (_) {
      if (!mounted) return;
      setState(() => _deletingSelected = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not delete the selected sales. Please try again.',
          ),
        ),
      );
    }
  }

  void _openSale(CompletedSale sale) {
    final callback = widget.onOpenSale;
    if (callback != null) {
      callback(sale);
      return;
    }
    context.push('/sales/${Uri.encodeComponent(sale.id)}', extra: sale);
  }
}

class _SalesPeriodSelector extends StatelessWidget {
  const _SalesPeriodSelector({
    required this.selected,
    required this.customLabel,
    required this.enabled,
    required this.onSelected,
  });

  final SalesPeriodPreset selected;
  final String? customLabel;
  final bool enabled;
  final ValueChanged<SalesPeriodPreset> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label: 'Sales date range',
      child: Card(
        key: const ValueKey('sales-period-panel'),
        color: Theme.of(context).brightness == Brightness.dark
            ? scheme.surfaceContainerLow
            : scheme.surfaceContainerLowest,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final textScale = MediaQuery.textScalerOf(
                    context,
                  ).scale(1).clamp(1.0, 2.0);
                  final columns = constraints.maxWidth >= 620 && textScale < 1.3
                      ? 6
                      : constraints.maxWidth < 340 || textScale >= 1.5
                      ? 2
                      : 3;
                  const spacing = AppSpacing.xxs;
                  final width =
                      (constraints.maxWidth - spacing * (columns - 1)) /
                      columns;
                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: [
                      for (final period in SalesPeriodPreset.values)
                        SizedBox(
                          width: width,
                          child: _SalesPeriodButton(
                            period: period,
                            selected: selected == period,
                            onPressed: enabled
                                ? () => onSelected(period)
                                : null,
                          ),
                        ),
                    ],
                  );
                },
              ),
              if (selected == SalesPeriodPreset.custom &&
                  customLabel != null) ...[
                const SizedBox(height: AppSpacing.xxs),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: AppSpacing.xxs,
                  ),
                  child: Text(
                    customLabel!,
                    key: const ValueKey('sales-custom-period-label'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SalesPeriodButton extends StatelessWidget {
  const _SalesPeriodButton({
    required this.period,
    required this.selected,
    required this.onPressed,
  });

  final SalesPeriodPreset period;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      key: ValueKey('sales-period-${period.name}'),
      button: true,
      enabled: onPressed != null,
      selected: selected,
      label: '${period.label} sales period',
      excludeSemantics: true,
      child: Material(
        color: selected ? scheme.primaryContainer : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.control,
          side: BorderSide(
            color: selected
                ? scheme.primary.withValues(alpha: 0.35)
                : Colors.transparent,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppSize.minimumTouchTarget,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
              child: Center(
                child: Text(
                  period.label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: selected
                        ? scheme.onPrimaryContainer
                        : scheme.onSurface,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SalesSelectionToolbar extends StatelessWidget {
  const _SalesSelectionToolbar({
    required this.selectedCount,
    required this.allSelected,
    required this.locked,
    required this.deleting,
    required this.onToggleAll,
    required this.onDelete,
  });

  final int selectedCount;
  final bool allSelected;
  final bool locked;
  final bool deleting;
  final VoidCallback onToggleAll;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final actions = Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xxs,
      children: [
        TextButton.icon(
          key: const ValueKey('sales-select-all'),
          onPressed: locked ? null : onToggleAll,
          icon: Icon(
            allSelected ? Icons.deselect_rounded : Icons.select_all_rounded,
            size: 18,
          ),
          label: Text(allSelected ? 'Clear all' : 'Select all'),
        ),
        FilledButton.tonalIcon(
          key: const ValueKey('sales-delete-selected'),
          onPressed: locked ? null : onDelete,
          style: FilledButton.styleFrom(foregroundColor: scheme.error),
          icon: deleting
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.delete_outline_rounded, size: 18),
          label: Text(deleting ? 'Deleting…' : 'Delete selected'),
        ),
      ],
    );

    return Card(
      key: const ValueKey('sales-selection-toolbar'),
      color: scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final count = Text(
              '$selectedCount selected',
              key: const ValueKey('sales-selected-count'),
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
            );
            if (constraints.maxWidth < 420) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  count,
                  const SizedBox(height: AppSpacing.xxs),
                  actions,
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: count),
                actions,
              ],
            );
          },
        ),
      ),
    );
  }
}

String _formatPickerRange(DateTimeRange range) {
  final start = range.start.toLocal();
  final end = range.end.toLocal();
  if (start.year == end.year &&
      start.month == end.month &&
      start.day == end.day) {
    return DateFormat.yMMMd().format(start);
  }
  if (start.year == end.year) {
    return '${DateFormat.MMMd().format(start)} – ${DateFormat.yMMMd().format(end)}';
  }
  return '${DateFormat.yMMMd().format(start)} – ${DateFormat.yMMMd().format(end)}';
}

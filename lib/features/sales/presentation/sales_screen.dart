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

enum SalesPeriodPreset { today, sevenDays, thisMonth, custom }

extension SalesPeriodPresetLabel on SalesPeriodPreset {
  String get label => switch (this) {
    SalesPeriodPreset.today => 'Today',
    SalesPeriodPreset.sevenDays => '7D',
    SalesPeriodPreset.thisMonth => 'This month',
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
    final width = MediaQuery.sizeOf(context).width;
    final pageInsets = AppSpacing.pageInsetsFor(width);
    final sideInset = ((width - AppBreakpoints.readingMaxWidth) / 2).clamp(
      pageInsets.left,
      double.infinity,
    );

    return AppPageScaffold(
      title: 'Sales',
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
                      subtitle:
                          '${sales.length} ${sales.length == 1 ? 'sale' : 'sales'} · newest first',
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
      SalesPeriodPreset.custom => _formatPickerRange(_customRange!),
    };
  }

  Future<void> _selectPeriod(
    SalesPeriodPreset period, {
    required DateTime now,
    required DateTime? oldestSaleDate,
  }) async {
    if (period != SalesPeriodPreset.custom) {
      if (_period != period) setState(() => _period = period);
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
    final picked = await showDateRangePicker(
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
    if (picked == null || !mounted) return;
    setState(() {
      _customRange = picked;
      _period = SalesPeriodPreset.custom;
    });
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
    required this.onSelected,
  });

  final SalesPeriodPreset selected;
  final String? customLabel;
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
                  final columns = constraints.maxWidth < 340 || textScale >= 1.5
                      ? 2
                      : 4;
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
                            onPressed: () => onSelected(period),
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
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      key: ValueKey('sales-period-${period.name}'),
      button: true,
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

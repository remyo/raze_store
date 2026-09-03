import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/core/widgets/app_widgets.dart';
import 'package:raze_store/features/sales/domain/completed_sale.dart';

/// Totals shown above the history list for the currently selected period.
@immutable
final class SalesSummaryData {
  const SalesSummaryData({
    required this.revenueCentavos,
    required this.transactionCount,
    required this.itemQuantity,
  });

  factory SalesSummaryData.fromSales(Iterable<CompletedSale> sales) {
    var revenueCentavos = 0;
    var transactionCount = 0;
    var itemQuantity = 0;
    for (final sale in sales) {
      revenueCentavos += sale.totalCentavos;
      transactionCount += 1;
      itemQuantity += sale.totalQuantity;
    }
    return SalesSummaryData(
      revenueCentavos: revenueCentavos,
      transactionCount: transactionCount,
      itemQuantity: itemQuantity,
    );
  }

  final int revenueCentavos;
  final int transactionCount;
  final int itemQuantity;
}

/// A compact three-metric overview for a sales period.
class SalesSummaryCard extends StatelessWidget {
  const SalesSummaryCard({
    super.key,
    required this.summary,
    required this.periodLabel,
  });

  final SalesSummaryData summary;
  final String periodLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final metrics = <_SalesMetric>[
      _SalesMetric(
        key: const ValueKey('sales-summary-revenue'),
        icon: Icons.payments_rounded,
        label: 'Revenue',
        value: PriceText.format(summary.revenueCentavos),
        valueColor: context.storeColors.price,
      ),
      _SalesMetric(
        key: const ValueKey('sales-summary-transactions'),
        icon: Icons.receipt_long_rounded,
        label: 'Transactions',
        value: NumberFormat.decimalPattern().format(summary.transactionCount),
      ),
      _SalesMetric(
        key: const ValueKey('sales-summary-items'),
        icon: Icons.shopping_bag_rounded,
        label: 'Items sold',
        value: NumberFormat.decimalPattern().format(summary.itemQuantity),
      ),
    ];

    return Card(
      key: const ValueKey('sales-summary-card'),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              periodLabel,
              key: const ValueKey('sales-summary-period'),
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.sm),
            LayoutBuilder(
              builder: (context, constraints) {
                final textScale = MediaQuery.textScalerOf(
                  context,
                ).scale(1).clamp(1.0, 2.0);
                final singleRevenueRow =
                    constraints.maxWidth < 390 || textScale >= 1.5;
                if (singleRevenueRow) {
                  return Column(
                    children: [
                      _SalesMetricCell(metric: metrics.first),
                      Divider(height: 1, color: scheme.outlineVariant),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _SalesMetricCell(metric: metrics[1])),
                          SizedBox(
                            height: AppSize.comfortableRow,
                            child: VerticalDivider(
                              width: 1,
                              color: scheme.outlineVariant,
                            ),
                          ),
                          Expanded(child: _SalesMetricCell(metric: metrics[2])),
                        ],
                      ),
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var index = 0; index < metrics.length; index++) ...[
                      Expanded(child: _SalesMetricCell(metric: metrics[index])),
                      if (index != metrics.length - 1)
                        SizedBox(
                          height: AppSize.comfortableRow,
                          child: VerticalDivider(
                            width: 1,
                            color: scheme.outlineVariant,
                          ),
                        ),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

final class _SalesMetric {
  const _SalesMetric({
    required this.key,
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final Key key;
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
}

class _SalesMetricCell extends StatelessWidget {
  const _SalesMetricCell({required this.metric});

  final _SalesMetric metric;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      key: metric.key,
      container: true,
      label: '${metric.label}: ${metric.value}',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: AppRadius.control,
                ),
                alignment: Alignment.center,
                child: Icon(metric.icon, size: 18, color: scheme.primary),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      metric.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: metric.valueColor ?? scheme.onSurface,
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      metric.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lazily builds a reverse-chronological ledger grouped by local calendar day.
///
/// This is a sliver so the filter, summary, headings, and rows can share one
/// scroll view instead of nesting a list inside another scrollable.
class SalesHistorySliver extends StatelessWidget {
  const SalesHistorySliver({
    super.key,
    required this.sales,
    required this.now,
    required this.onOpenSale,
  });

  final List<CompletedSale> sales;
  final DateTime now;
  final ValueChanged<CompletedSale> onOpenSale;

  @override
  Widget build(BuildContext context) {
    final sorted = [...sales]
      ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
    final rows = _buildRows(sorted);
    return SliverList(
      key: const ValueKey('sales-history-list'),
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final row = rows[index];
          if (row.day case final day?) {
            return Padding(
              key: ValueKey('sales-day-${_localDateKey(day)}'),
              padding: EdgeInsets.only(
                top: index == 0 ? 0 : AppSpacing.md,
                bottom: AppSpacing.xs,
              ),
              child: Text(
                formatSalesDayHeading(day, now: now),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            );
          }

          final sale = row.sale!;
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: _SalesHistoryTile(
              key: ValueKey('sales-history-${sale.id}'),
              sale: sale,
              onTap: () => onOpenSale(sale),
            ),
          );
        },
        childCount: rows.length,
        addAutomaticKeepAlives: false,
      ),
    );
  }
}

class _SalesHistoryTile extends StatelessWidget {
  const _SalesHistoryTile({super.key, required this.sale, required this.onTap});

  final CompletedSale sale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final firstLine = sale.lines.first;
    final moreLines = sale.lines.length - 1;
    final title = moreLines == 0
        ? firstLine.nameSnapshot
        : '${firstLine.nameSnapshot} + $moreLines more';
    final quantityLabel =
        '${sale.totalQuantity} ${sale.totalQuantity == 1 ? 'item' : 'items'}';
    final timeLabel = DateFormat.jm().format(sale.completedAt.toLocal());

    return Semantics(
      button: true,
      label:
          '$title, $quantityLabel, ${PriceText.format(sale.totalCentavos)}, completed $timeLabel',
      child: Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.card,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppSize.comfortableRow,
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: scheme.secondaryContainer,
                      borderRadius: AppRadius.control,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.receipt_long_rounded,
                      color: scheme.onSecondaryContainer,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$timeLabel · $quantityLabel',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        PriceText.format(sale.totalCentavos),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: context.storeColors.price,
                              fontWeight: FontWeight.w800,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: scheme.onSurfaceVariant,
                        size: 20,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _SalesHistoryRow {
  const _SalesHistoryRow.day(this.day) : sale = null;
  const _SalesHistoryRow.sale(this.sale) : day = null;

  final DateTime? day;
  final CompletedSale? sale;
}

List<_SalesHistoryRow> _buildRows(List<CompletedSale> sortedSales) {
  final result = <_SalesHistoryRow>[];
  String? previousDay;
  for (final sale in sortedSales) {
    final local = sale.completedAt.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    final key = _localDateKey(day);
    if (key != previousDay) {
      result.add(_SalesHistoryRow.day(day));
      previousDay = key;
    }
    result.add(_SalesHistoryRow.sale(sale));
  }
  return result;
}

String formatSalesDayHeading(DateTime value, {required DateTime now}) {
  final local = value.toLocal();
  final localNow = now.toLocal();
  final day = DateTime(local.year, local.month, local.day);
  final today = DateTime(localNow.year, localNow.month, localNow.day);
  if (day == today) return 'Today';
  if (day == DateTime(today.year, today.month, today.day - 1)) {
    return 'Yesterday';
  }
  return DateFormat.yMMMd().format(day);
}

String _localDateKey(DateTime value) {
  final local = value.toLocal();
  return '${local.year}-${local.month}-${local.day}';
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/core/widgets/app_widgets.dart';
import 'package:raze_store/core/widgets/bounded_network_image.dart';
import 'package:raze_store/features/receipt/domain/receipt_draft.dart';
import 'package:raze_store/features/sales/application/sales_providers.dart';
import 'package:raze_store/features/sales/domain/completed_sale.dart';

/// A saved transaction with its immutable line and receipt snapshots.
class SaleDetailScreen extends ConsumerStatefulWidget {
  const SaleDetailScreen({
    super.key,
    required this.saleId,
    this.initialSale,
    this.onDeleted,
    this.onOpenReceipt,
  });

  final String saleId;

  /// Lets list-to-detail navigation paint immediately while the live stream
  /// resolves. Direct links still work through [saleId].
  final CompletedSale? initialSale;
  final VoidCallback? onDeleted;
  final ValueChanged<ReceiptDraft>? onOpenReceipt;

  @override
  ConsumerState<SaleDetailScreen> createState() => _SaleDetailScreenState();
}

class _SaleDetailScreenState extends ConsumerState<SaleDetailScreen> {
  bool _deleting = false;

  @override
  Widget build(BuildContext context) {
    final liveSale = ref.watch(completedSaleProvider(widget.saleId));
    final sale = switch (liveSale) {
      AsyncLoading() => widget.initialSale,
      AsyncData(:final value) => value,
      AsyncError() => null,
    };

    return AppPageScaffold(
      title: 'Sale details',
      actions: sale == null
          ? null
          : [
              IconButton(
                key: const ValueKey('sale-detail-receipt'),
                tooltip: 'View receipt',
                onPressed: _deleting ? null : () => _openReceipt(sale),
                icon: const Icon(Icons.receipt_long_outlined),
              ),
              IconButton(
                key: const ValueKey('sale-detail-delete'),
                tooltip: 'Delete sale',
                onPressed: _deleting ? null : () => _confirmDelete(sale),
                icon: _deleting
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_outline_rounded),
              ),
            ],
      body: switch ((sale, liveSale)) {
        (final CompletedSale sale, _) => _SaleDetailBody(
          sale: sale,
          deleting: _deleting,
          onOpenReceipt: () => _openReceipt(sale),
          onDelete: () => _confirmDelete(sale),
        ),
        (null, AsyncLoading()) => const AppLoadingState(
          message: 'Loading sale…',
        ),
        (null, AsyncError()) => AppErrorState(
          message: 'This sale could not be loaded.',
          onRetry: () => ref.invalidate(completedSaleProvider(widget.saleId)),
        ),
        _ => const AppEmptyState(
          icon: Icons.receipt_long_outlined,
          title: 'Sale not found',
          message: 'It may already have been deleted from this device.',
        ),
      },
    );
  }

  void _openReceipt(CompletedSale sale) {
    final draft = sale.toReceiptDraft();
    final callback = widget.onOpenReceipt;
    if (callback != null) {
      callback(draft);
      return;
    }
    context.push('/receipt', extra: draft);
  }

  Future<void> _confirmDelete(CompletedSale sale) async {
    if (_deleting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this sale?'),
        content: Text(
          'This permanently removes the ${DateFormat.yMMMd().add_jm().format(sale.completedAt.toLocal())} sale from history. Products in your catalog will not be deleted.',
        ),
        actions: [
          TextButton(
            key: const ValueKey('sale-delete-cancel'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep sale'),
          ),
          FilledButton(
            key: const ValueKey('sale-delete-confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            child: const Text('Delete sale'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      await ref.read(salesRepositoryProvider).deleteSale(sale.id);
      if (!mounted) return;
      final callback = widget.onDeleted;
      if (callback != null) {
        callback();
      } else {
        final router = GoRouter.of(context);
        if (router.canPop()) {
          router.pop(true);
        } else {
          router.go('/sales');
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not delete this sale. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }
}

class _SaleDetailBody extends StatelessWidget {
  const _SaleDetailBody({
    required this.sale,
    required this.deleting,
    required this.onOpenReceipt,
    required this.onDelete,
  });

  final CompletedSale sale;
  final bool deleting;
  final VoidCallback onOpenReceipt;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      key: const ValueKey('sale-detail-scroll-view'),
      children: [
        Card(
          key: const ValueKey('sale-detail-summary'),
          color: scheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              children: [
                Text(
                  'Sale total',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                PriceText(
                  centavos: sale.totalCentavos,
                  size: PriceTextSize.large,
                  color: scheme.onPrimaryContainer,
                  semanticLabel: 'Sale total',
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  DateFormat.yMMMMd().add_jm().format(
                    sale.completedAt.toLocal(),
                  ),
                  key: const ValueKey('sale-detail-date'),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  '${sale.totalQuantity} ${sale.totalQuantity == 1 ? 'item' : 'items'} · ${sale.lines.length} ${sale.lines.length == 1 ? 'product line' : 'product lines'}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppSectionHeader(
          title: 'Items sold',
          subtitle:
              '${sale.totalQuantity} ${sale.totalQuantity == 1 ? 'item' : 'items'} in this checkout',
        ),
        const SizedBox(height: AppSpacing.sm),
        Card(
          key: const ValueKey('sale-detail-lines'),
          child: Column(
            children: [
              for (var index = 0; index < sale.lines.length; index++) ...[
                _CompletedSaleLineTile(line: sale.lines[index]),
                if (index != sale.lines.length - 1)
                  Divider(height: 1, color: scheme.outlineVariant),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        const AppSectionHeader(title: 'Payment'),
        const SizedBox(height: AppSpacing.sm),
        _SalePaymentCard(sale: sale),
        const SizedBox(height: AppSpacing.lg),
        FilledButton.icon(
          key: const ValueKey('sale-detail-view-receipt'),
          onPressed: deleting ? null : onOpenReceipt,
          icon: const Icon(Icons.receipt_long_outlined),
          label: const Text('View receipt'),
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          key: const ValueKey('sale-detail-delete-bottom'),
          onPressed: deleting ? null : onDelete,
          style: OutlinedButton.styleFrom(
            foregroundColor: scheme.error,
            side: BorderSide(color: scheme.error.withValues(alpha: 0.65)),
          ),
          icon: deleting
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.delete_outline_rounded),
          label: Text(deleting ? 'Deleting…' : 'Delete sale'),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Deleting this record does not delete products from your catalog.',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.xl),
        SelectionArea(
          child: Text(
            'Transaction ID: ${sale.id}',
            key: const ValueKey('sale-detail-id'),
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }
}

class _CompletedSaleLineTile extends StatelessWidget {
  const _CompletedSaleLineTile({required this.line});

  final CompletedSaleLine line;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final details = <String>[
      if (line.brandSnapshot?.trim().isNotEmpty == true)
        line.brandSnapshot!.trim(),
      if (line.unitLabelSnapshot?.trim().isNotEmpty == true)
        'Sold as ${line.unitLabelSnapshot!.trim()}',
    ].join(' · ');

    return Padding(
      key: ValueKey('sale-detail-line-${line.position}'),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final textScale = MediaQuery.textScalerOf(
            context,
          ).scale(1).clamp(1.0, 2.0);
          final stackAmount = constraints.maxWidth < 320 || textScale >= 1.5;
          final product = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SaleLineImage(line: line),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      line.nameSnapshot,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (details.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        details,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${PriceText.format(line.unitPriceCentavos)} × ${line.quantity}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

          if (stackAmount) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                product,
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: Alignment.centerRight,
                  child: PriceText(
                    centavos: line.lineTotalCentavos,
                    size: PriceTextSize.small,
                    semanticLabel: 'Line total for ${line.nameSnapshot}',
                  ),
                ),
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: product),
              const SizedBox(width: AppSpacing.md),
              PriceText(
                centavos: line.lineTotalCentavos,
                size: PriceTextSize.small,
                semanticLabel: 'Line total for ${line.nameSnapshot}',
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SaleLineImage extends StatelessWidget {
  const _SaleLineImage({required this.line});

  final CompletedSaleLine line;

  @override
  Widget build(BuildContext context) {
    final path = line.imagePathSnapshot?.trim();
    final uri = path == null ? null : Uri.tryParse(path);
    final remote =
        uri != null &&
        (uri.scheme.toLowerCase() == 'http' ||
            uri.scheme.toLowerCase() == 'https');
    final fallback = ProductImagePlaceholder(
      width: AppSize.thumbnail,
      height: AppSize.thumbnail,
      semanticLabel: 'No saved photo for ${line.nameSnapshot}',
    );
    if (path == null || path.isEmpty) return fallback;

    return ClipRRect(
      borderRadius: AppRadius.control,
      child: remote
          ? BoundedNetworkImage(
              url: path,
              fallback: fallback,
              width: AppSize.thumbnail,
              height: AppSize.thumbnail,
              fit: BoxFit.cover,
              cacheWidth: 168,
              semanticLabel: line.nameSnapshot,
            )
          : Image.file(
              File(path),
              width: AppSize.thumbnail,
              height: AppSize.thumbnail,
              fit: BoxFit.cover,
              cacheWidth: 168,
              semanticLabel: line.nameSnapshot,
              errorBuilder: (_, _, _) => fallback,
            ),
    );
  }
}

class _SalePaymentCard extends StatelessWidget {
  const _SalePaymentCard({required this.sale});

  final CompletedSale sale;

  @override
  Widget build(BuildContext context) {
    final cash = sale.cashReceivedCentavos;
    final change = sale.changeCentavos;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      key: const ValueKey('sale-detail-payment'),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: cash == null
            ? Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: scheme.primary),
                  const SizedBox(width: AppSpacing.sm),
                  const Expanded(
                    child: Text(
                      'Cash received was not recorded for this sale.',
                    ),
                  ),
                ],
              )
            : Column(
                children: [
                  _PaymentRow(label: 'Total', centavos: sale.totalCentavos),
                  const SizedBox(height: AppSpacing.sm),
                  _PaymentRow(label: 'Cash received', centavos: cash),
                  Divider(height: AppSpacing.lg, color: scheme.outlineVariant),
                  _PaymentRow(
                    label: (change ?? 0) < 0 ? 'Balance due' : 'Change',
                    centavos: (change ?? 0).abs(),
                    emphasized: true,
                  ),
                ],
              ),
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({
    required this.label,
    required this.centavos,
    this.emphasized = false,
  });

  final String label;
  final int centavos;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: emphasized
                ? Theme.of(context).textTheme.titleMedium
                : Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        PriceText(
          centavos: centavos,
          size: PriceTextSize.small,
          semanticLabel: label,
        ),
      ],
    );
  }
}

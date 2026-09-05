import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'gcash_fee_settings.dart';
import 'gcash_theme.dart';

/// Shows the store's saved charges without opening the settings editor.
Future<void> showGcashPriceListSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (context) =>
        GcashTheme(builder: (context) => const _GcashPriceListSheet()),
  );
}

class _GcashPriceListSheet extends ConsumerWidget {
  const _GcashPriceListSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(gcashFeeSettingsProvider);
    return LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        height: math.min(constraints.maxHeight * 0.85, 680),
        child: Material(
          key: const ValueKey('gcash-price-list-sheet'),
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                ColoredBox(
                  color: GcashTheme.blue,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'GCash price list',
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          key: const ValueKey('gcash-price-list-close'),
                          tooltip: 'Close price list',
                          onPressed: () => Navigator.of(context).pop(),
                          color: Colors.white,
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: settings.when(
                    skipLoadingOnRefresh: false,
                    skipLoadingOnReload: false,
                    loading: () => const Center(
                      child: CircularProgressIndicator(
                        semanticsLabel: 'Loading saved GCash charges',
                      ),
                    ),
                    error: (_, _) => Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline_rounded, size: 32),
                            const SizedBox(height: 12),
                            const Text(
                              'Could not load your saved charges.',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              key: const ValueKey('gcash-price-list-retry'),
                              onPressed: () =>
                                  ref.invalidate(gcashFeeSettingsProvider),
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    data: (settings) => _PriceList(schedule: settings.shared),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PriceList extends StatelessWidget {
  const _PriceList({required this.schedule});

  final GcashFeeSchedule schedule;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tiers = schedule.tiers;
    return ListView.builder(
      key: const ValueKey('gcash-price-list-scroll'),
      padding: const EdgeInsets.only(bottom: 20),
      itemCount: tiers.length + 3,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Same charges for Cash In & Cash Out.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Your store’s charges, not official GCash rates.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (!schedule.autoFillEnabled) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Automatic charges are off. Use this list as a reference.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          );
        }
        if (index == 1) {
          return _TableRow(
            backgroundColor: theme.colorScheme.primaryContainer,
            amount: 'Amount',
            charge: 'Charge',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w700,
            ),
          );
        }
        if (index == tiers.length + 2) {
          return Padding(
            key: const ValueKey('gcash-price-list-manual-note'),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(
              'Above ${_money(tiers.last.upperLimitCentavos)}, '
              'enter the charge manually.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }
        final tierIndex = index - 2;
        final tier = tiers[tierIndex];
        final lower = tierIndex == 0
            ? 1
            : tiers[tierIndex - 1].upperLimitCentavos + 1;
        return _TableRow(
          key: ValueKey('gcash-price-list-tier-$tierIndex'),
          backgroundColor: tierIndex.isEven
              ? theme.cardTheme.color!
              : theme.colorScheme.primary.withValues(alpha: 0.035),
          amount: '${_money(lower)} – ${_money(tier.upperLimitCentavos)}',
          charge: _money(tier.feeCentavos),
          style: theme.textTheme.bodyMedium,
        );
      },
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({
    super.key,
    required this.backgroundColor,
    required this.amount,
    required this.charge,
    required this.style,
  });

  final Color backgroundColor;
  final String amount;
  final String charge;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Container(
    color: backgroundColor,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 3, child: Text(amount, style: style)),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: Text(
            charge,
            textAlign: TextAlign.end,
            style: style?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

final _wholeCurrency = NumberFormat.currency(
  locale: 'en_PH',
  symbol: '₱',
  decimalDigits: 0,
);
final _decimalCurrency = NumberFormat.currency(locale: 'en_PH', symbol: '₱');

String _money(int centavos) =>
    (centavos % 100 == 0 ? _wholeCurrency : _decimalCurrency).format(
      centavos / 100,
    );

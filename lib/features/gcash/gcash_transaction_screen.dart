import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'gcash_record.dart';
import 'gcash_theme.dart';

/// A local transaction summary, not confirmation from the GCash service.
class GcashTransactionScreen extends StatelessWidget {
  const GcashTransactionScreen({
    super.key,
    required this.record,
    this.actions = const [],
  });

  final GcashRecord record;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return GcashTheme(
      builder: (context) {
        final theme = Theme.of(context);
        return Scaffold(
          key: const ValueKey('gcash-transaction-screen'),
          appBar: AppBar(
            title: const Text(
              'GCash transaction',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: actions,
          ),
          body: SafeArea(
            top: false,
            child: SingleChildScrollView(
              key: const ValueKey('gcash-transaction-scroll'),
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 28),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: SelectionArea(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Semantics(
                            label: 'Transaction recorded in Raze Store',
                            child: Container(
                              key: const ValueKey('gcash-transaction-status'),
                              width: 76,
                              height: 76,
                              decoration: const BoxDecoration(
                                color: GcashTheme.blue,
                                shape: BoxShape.circle,
                              ),
                              child: const ExcludeSemantics(
                                child: Icon(
                                  Icons.check_rounded,
                                  size: 44,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          record.kind.label,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Price',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 2),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            _money(record.amount),
                            key: const ValueKey('gcash-transaction-price'),
                            maxLines: 1,
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontSize: 32,
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Recorded',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Saved in Raze Store',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Card(
                          key: const ValueKey('gcash-transaction-details'),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 4,
                            ),
                            child: Column(
                              children: [
                                _DetailRow(
                                  label: 'Name',
                                  value: record.name,
                                  valueKey: 'gcash-transaction-name',
                                ),
                                const Divider(),
                                _DetailRow(
                                  label: 'Number',
                                  value: record.number,
                                  valueKey: 'gcash-transaction-number',
                                ),
                                const Divider(),
                                _DetailRow(
                                  label: 'Profit',
                                  value: _money(record.fee),
                                  valueKey: 'gcash-transaction-profit',
                                ),
                                const Divider(),
                                _DetailRow(
                                  label: 'Transaction number',
                                  value: record.reference,
                                  valueKey: 'gcash-transaction-reference',
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    required this.valueKey,
  });

  final String label;
  final String value;
  final String valueKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelWidget = Text(
      label,
      style: theme.textTheme.bodyMedium?.copyWith(
        fontSize: 14,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
    final valueWidget = Text(
      value,
      key: ValueKey(valueKey),
      textAlign: TextAlign.right,
      style: theme.textTheme.bodyMedium?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Give long identifiers the full row on narrow or enlarged layouts.
          final stacked =
              constraints.maxWidth < 280 ||
              MediaQuery.textScalerOf(context).scale(14) > 20;
          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [labelWidget, const SizedBox(height: 6), valueWidget],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 2, child: labelWidget),
              const SizedBox(width: 16),
              Expanded(flex: 3, child: valueWidget),
            ],
          );
        },
      ),
    );
  }
}

String _money(int value) => NumberFormat.currency(
  locale: 'en_PH',
  symbol: '₱',
  decimalDigits: 2,
).format(value / 100);

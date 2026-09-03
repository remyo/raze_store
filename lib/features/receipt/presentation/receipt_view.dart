import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:raze_store/features/receipt/domain/receipt_draft.dart';

const double receiptPreferredWidth = 420;

final NumberFormat _receiptPesoFormat = NumberFormat.decimalPattern('en_PH');
final DateFormat _receiptDateFormat = DateFormat('MMM d, yyyy • h:mm a');

String formatReceiptMoney(int centavos) {
  final isNegative = centavos < 0;
  final absolute = centavos.abs();
  final pesos = absolute ~/ 100;
  final cents = (absolute % 100).toString().padLeft(2, '0');
  return '${isNegative ? '-' : ''}₱${_receiptPesoFormat.format(pesos)}.$cents';
}

/// A complete, screenshot-friendly customer copy of a cart.
///
/// This is a pure presentation widget. It never writes a sale, mutates the
/// cart, or clears cart contents.
class ReceiptView extends StatelessWidget {
  const ReceiptView({
    super.key,
    required this.draft,
    this.showDraftNotice = false,
  });

  final ReceiptDraft draft;

  /// Adds a small note explaining that the image is a cart snapshot.
  final bool showDraftNotice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final accent = colors.primary;
    const paper = Color(0xFFFFFDF8);
    const ink = Color(0xFF211F1B);
    const mutedInk = Color(0xFF6F6A61);

    return Semantics(
      label: 'Receipt from ${draft.storeName}',
      container: true,
      child: Container(
        width: receiptPreferredWidth,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: paper,
          border: Border.all(color: const Color(0xFFE7E0D5)),
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A000000),
              blurRadius: 24,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: DefaultTextStyle.merge(
          style: const TextStyle(color: ink),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ReceiptHeader(draft: draft, accent: accent),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 26),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'ITEM',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: mutedInk,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ),
                        Text(
                          'AMOUNT',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: mutedInk,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const _DashedDivider(),
                    for (
                      var index = 0;
                      index < draft.lines.length;
                      index++
                    ) ...[
                      _ReceiptLineRow(line: draft.lines[index]),
                      if (index != draft.lines.length - 1)
                        const Divider(height: 1, color: Color(0xFFEDE7DD)),
                    ],
                    const SizedBox(height: 4),
                    const _DashedDivider(),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${draft.totalQuantity} ${draft.totalQuantity == 1 ? 'item' : 'items'}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: mutedInk,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          'TOTAL',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: ink,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.6,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          formatReceiptMoney(draft.totalCentavos),
                          key: const ValueKey('receipt-total'),
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: accent,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ),
                    if (draft.cashReceivedCentavos case final cash?) ...[
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          children: [
                            _AmountRow(
                              label: 'Cash received',
                              value: formatReceiptMoney(cash),
                            ),
                            const SizedBox(height: 8),
                            _AmountRow(
                              label: (draft.changeCentavos ?? 0) < 0
                                  ? 'Balance due'
                                  : 'Change',
                              value: formatReceiptMoney(
                                (draft.changeCentavos ?? 0).abs(),
                              ),
                              emphasized: true,
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 26),
                    Icon(Icons.favorite_rounded, color: accent, size: 19),
                    const SizedBox(height: 8),
                    Text(
                      draft.footerMessage ?? 'Salamat po!',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (showDraftNotice) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Generated from the current cart',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: mutedInk,
                        ),
                      ),
                    ],
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

class _ReceiptHeader extends StatelessWidget {
  const _ReceiptHeader({required this.draft, required this.accent});

  final ReceiptDraft draft;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onAccent =
        ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
        ? Colors.white
        : const Color(0xFF171512);

    return ColoredBox(
      color: accent,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.storefront_rounded, color: onAccent, size: 32),
            const SizedBox(height: 10),
            Text(
              draft.storeName,
              key: const ValueKey('receipt-store-name'),
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: onAccent,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.4,
              ),
            ),
            if (draft.storeAddress case final address?) ...[
              const SizedBox(height: 5),
              Text(
                address,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: onAccent.withValues(alpha: 0.84),
                  height: 1.3,
                ),
              ),
            ],
            if (draft.storeContact case final contact?) ...[
              const SizedBox(height: 3),
              Text(
                contact,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: onAccent.withValues(alpha: 0.84),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: onAccent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.receipt_long_rounded, color: onAccent, size: 16),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      'CUSTOMER COPY  •  ${_receiptDateFormat.format(draft.createdAt.toLocal())}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: onAccent,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.35,
                      ),
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

class _ReceiptLineRow extends StatelessWidget {
  const _ReceiptLineRow({required this.line});

  final ReceiptLine line;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.productName,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: const Color(0xFF211F1B),
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
                if (line.unitLabel case final unit?) ...[
                  const SizedBox(height: 3),
                  Text(
                    'Sold as $unit',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF6F6A61),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  '${formatReceiptMoney(line.unitPriceCentavos)} × ${line.quantity}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF6F6A61),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (line.barcode case final barcode?) ...[
                  const SizedBox(height: 2),
                  Text(
                    barcode,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: const Color(0xFF8A847B),
                      letterSpacing: 0.45,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 18),
          Text(
            formatReceiptMoney(line.lineTotalCentavos),
            style: theme.textTheme.bodyLarge?.copyWith(
              color: const Color(0xFF211F1B),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: const Color(0xFF3E3A34),
      fontWeight: emphasized ? FontWeight.w800 : FontWeight.w600,
    );
    return Row(
      children: [
        Expanded(child: Text(label, style: style)),
        Text(value, style: style),
      ],
    );
  }
}

class _DashedDivider extends StatelessWidget {
  const _DashedDivider();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 1,
      width: double.infinity,
      child: CustomPaint(painter: _DashedLinePainter()),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  const _DashedLinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    const dashWidth = 5.0;
    const gapWidth = 4.0;
    final paint = Paint()
      ..color = const Color(0xFFCBC3B6)
      ..strokeWidth = 1;

    for (var start = 0.0; start < size.width; start += dashWidth + gapWidth) {
      canvas.drawLine(
        Offset(start, 0.5),
        Offset((start + dashWidth).clamp(0, size.width), 0.5),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) => false;
}

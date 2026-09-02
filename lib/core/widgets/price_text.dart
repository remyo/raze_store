import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:raze_store/app/theme/theme.dart';

enum PriceTextSize { small, regular, large }

/// Displays integer centavos as a consistently formatted Philippine peso
/// amount. Keeping the API integer-based avoids floating-point price errors.
class PriceText extends StatelessWidget {
  const PriceText({
    super.key,
    required this.centavos,
    this.size = PriceTextSize.regular,
    this.style,
    this.color,
    this.textAlign,
    this.semanticLabel,
  });

  final int centavos;
  final PriceTextSize size;
  final TextStyle? style;
  final Color? color;
  final TextAlign? textAlign;
  final String? semanticLabel;

  static final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'en_PH',
    symbol: '₱',
    decimalDigits: 2,
  );

  static String format(int centavos) => _currencyFormat.format(centavos / 100);

  String get _spokenAmount {
    final absoluteCentavos = centavos.abs();
    final pesos = absoluteCentavos ~/ 100;
    final remainder = absoluteCentavos % 100;
    final sign = centavos < 0 ? 'negative ' : '';
    final pesoLabel = pesos == 1 ? 'peso' : 'pesos';
    if (remainder == 0) return '$sign$pesos $pesoLabel';
    final centavoLabel = remainder == 1 ? 'centavo' : 'centavos';
    return '$sign$pesos $pesoLabel and $remainder $centavoLabel';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseStyle = switch (size) {
      PriceTextSize.small => theme.textTheme.titleMedium,
      PriceTextSize.regular => theme.textTheme.headlineSmall,
      PriceTextSize.large => theme.textTheme.headlineLarge,
    };

    return Semantics(
      label: semanticLabel ?? _spokenAmount,
      excludeSemantics: true,
      child: Text(
        format(centavos),
        textAlign: textAlign,
        maxLines: 1,
        overflow: TextOverflow.fade,
        softWrap: false,
        style: baseStyle
            ?.copyWith(
              color: color ?? context.storeColors.price,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            )
            .merge(style),
      ),
    );
  }
}

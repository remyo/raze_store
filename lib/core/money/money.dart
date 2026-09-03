import 'package:intl/intl.dart';

/// An exact Philippine-peso amount represented as integer centavos.
///
/// Integer storage avoids rounding errors from binary floating-point values.
final class Money implements Comparable<Money> {
  const Money.fromCentavos(this.centavos);

  const Money.zero() : centavos = 0;

  final int centavos;

  Money operator +(Money other) =>
      Money.fromCentavos(centavos + other.centavos);

  Money operator -(Money other) =>
      Money.fromCentavos(centavos - other.centavos);

  Money times(int quantity) {
    if (quantity < 0) {
      throw ArgumentError.value(quantity, 'quantity', 'Must not be negative.');
    }
    return Money.fromCentavos(centavos * quantity);
  }

  String format({bool showSymbol = true}) {
    final formatter = NumberFormat.currency(
      locale: 'en_PH',
      symbol: showSymbol ? '₱' : '',
      decimalDigits: 2,
    );
    return formatter.format(centavos / 100);
  }

  @override
  int compareTo(Money other) => centavos.compareTo(other.centavos);

  @override
  bool operator ==(Object other) =>
      other is Money && other.centavos == centavos;

  @override
  int get hashCode => centavos.hashCode;

  @override
  String toString() => format();
}

/// Parses a form value such as `12`, `12.5`, `12.50`, or `₱1,234.50`.
///
/// Returns `null` for a negative value, unsupported precision, or malformed
/// input. Prices in this app are non-negative.
int? tryParsePesoCentavos(String input) {
  final normalized = input.trim().replaceAll('₱', '').replaceAll(',', '');
  final match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(normalized);
  if (match == null) return null;

  final pesos = int.tryParse(match.group(1)!);
  if (pesos == null) return null;
  final fraction = match.group(2) ?? '';
  final centavos = switch (fraction.length) {
    0 => 0,
    1 => int.parse(fraction) * 10,
    _ => int.parse(fraction),
  };
  return pesos * 100 + centavos;
}

/// Formats non-negative centavos for an editable peso input field.
String formatPesoInput(int centavos) {
  if (centavos < 0) {
    throw ArgumentError.value(centavos, 'centavos', 'Must not be negative.');
  }
  final pesos = centavos ~/ 100;
  final remainder = (centavos % 100).toString().padLeft(2, '0');
  return '$pesos.$remainder';
}

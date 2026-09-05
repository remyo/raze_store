import 'package:intl/intl.dart';
import 'gcash_record.dart';

class GcashSuggestions {
  const GcashSuggestions({
    this.name,
    this.number,
    this.amount,
    this.reference,
    this.date,
  });
  final String? name;
  final String? number;
  final int? amount;
  final String? reference;
  final DateTime? date;
}

/// Conservative rules: ambiguous fields stay empty for review. Receipt samples
/// can extend these rules without training a model or uploading customer data.
GcashSuggestions parseGcashReceipt(String text, GcashKind kind) {
  final lines = text
      .split(RegExp(r'[\r\n]+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
  String? labeled(String labels) {
    final regex = RegExp(
      '^(?:$labels)(?:\\s*[:：-]\\s*|\\s+|\$)(.*)\$',
      caseSensitive: false,
    );
    for (var i = 0; i < lines.length; i++) {
      final match = regex.firstMatch(lines[i]);
      if (match != null) {
        if (match[1]!.isNotEmpty) return match[1];
        if (i + 1 < lines.length) return lines[i + 1];
      }
    }
    return null;
  }

  final rawRef = labeled(
    r'(?:reference|ref\.?|transaction)\s*(?:number|no\.?|id)',
  );
  final reference = rawRef == null ? null : normalizeGcashReference(rawRef);
  final phones = RegExp(
    r'(?<!\d)(?:\+63|0)9[\d *xX-]{8,16}(?!\d)',
  ).allMatches(text).map((e) => e[0]!.trim()).toSet();
  final phoneLabel = labeled(r'(?:mobile|phone|account)\s*(?:number|no\.?)');
  final name = labeled(
    kind == GcashKind.cashIn
        ? r'(?:recipient(?: name)?|sent to|to|customer name|name)'
        : r'(?:sender(?: name)?|received from|from|customer name|name)',
  );
  int? amount;
  final amountLabel = labeled(
    r'(?:amount sent|amount received|transfer amount|amount)',
  );
  if (amountLabel != null) {
    amount = gcashCentavos(
      amountLabel
          .replaceAll(RegExp(r'(?:PHP|₱)', caseSensitive: false), '')
          .trim(),
    );
  }
  if (amount == null) {
    final amounts =
        RegExp(r'(?:PHP|₱)\s*([\d,]+(?:\.\d{1,2})?)', caseSensitive: false)
            .allMatches(text)
            .map((m) => gcashCentavos(m[1]!))
            .whereType<int>()
            .where((a) => a > 0)
            .toSet();
    if (amounts.length == 1) amount = amounts.single;
  }
  DateTime? date;
  for (final raw in [
    ?labeled(r'(?:date(?: and time)?|transaction date)'),
    ...lines,
  ]) {
    for (final format in [
      'MMM d, yyyy h:mm a',
      'MMMM d, yyyy h:mm a',
      'MMM d yyyy h:mm a',
      'yyyy-MM-dd HH:mm:ss',
      'yyyy-MM-dd HH:mm',
      'MM/dd/yyyy h:mm a',
    ]) {
      try {
        date = DateFormat(format, 'en_US').parseStrict(raw);
        break;
      } on FormatException {
        /* Try the next explicit format. */
      }
    }
    if (date != null) break;
  }
  return GcashSuggestions(
    name: name,
    number: phoneLabel ?? (phones.length == 1 ? phones.single : null),
    amount: amount,
    reference:
        reference != null && RegExp(r'^[A-Z0-9]{4,80}$').hasMatch(reference)
        ? reference
        : null,
    date: date,
  );
}

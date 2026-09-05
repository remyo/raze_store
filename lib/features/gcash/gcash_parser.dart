import 'package:intl/intl.dart';
import 'gcash_record.dart';

class GcashSuggestions {
  const GcashSuggestions({
    this.name,
    this.number,
    this.amount,
    this.reference,
    this.date,
    this.isGcashReceipt = false,
    this.recipientOnly = false,
  });
  final String? name;
  final String? number;
  final int? amount;
  final String? reference;
  final DateTime? date;
  final bool isGcashReceipt;

  /// The receipt shows the transfer recipient, but Cash Out needs its sender.
  final bool recipientOnly;
}

final _phonePattern = RegExp(
  r'(?<![\d+])(?:\+63[ \u00a0-]*|0)9(?:[ \u00a0-]*[\d*xX•●·]){9}'
  r'(?![\d*xX•●·]|[ \u00a0-]+\d)',
);

final _datePattern = RegExp(
  r'(?<![A-Za-z])(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|'
  r'Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:tember)?|Sept|Oct(?:ober)?|'
  r'Nov(?:ember)?|Dec(?:ember)?)\s+\d{1,2}(?:\s*,\s*|\s+)\d{4}\s+'
  r'\d{1,2}:\d{2}\s*[AP]M\b|'
  r'(?<!\d)\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}(?::\d{2})?(?![\d:])|'
  r'(?<!\d)\d{2}/\d{2}/\d{4}\s+\d{1,2}:\d{2}\s*[AP]M\b',
  caseSensitive: false,
);

String _phoneKey(String value) {
  final compact = value.replaceAll(RegExp(r'[ \u00a0-]'), '');
  return (compact.startsWith('0') ? '+63${compact.substring(1)}' : compact)
      .toUpperCase();
}

String? _uniquePhone(Iterable<String> values) {
  final phones = <String, String>{};
  for (final value in values) {
    for (final match in _phonePattern.allMatches(value)) {
      final phone = match[0]!;
      phones.putIfAbsent(_phoneKey(phone), () => phone);
    }
  }
  return phones.length == 1 ? phones.values.single : null;
}

int? _amountValue(String raw) {
  final match = RegExp(
    r'^(?:PHP|₱)?\s*([\d,]+(?:\.\d+)?)(?=\s*(?:$|total\b|service fee\b))',
    caseSensitive: false,
  ).firstMatch(raw.trim());
  final amount = match == null ? null : gcashCentavos(match[1]!);
  return amount != null && amount > 0 ? amount : null;
}

DateTime? _dateValue(String raw) {
  final normalized = raw
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'\s*,\s*'), ', ')
      .replaceFirst(RegExp(r'\bSept\b', caseSensitive: false), 'Sep')
      .replaceFirstMapped(
        RegExp(r'\s*([AP]M)$', caseSensitive: false),
        (match) => ' ${match[1]!.toUpperCase()}',
      );
  for (final format in [
    'MMM d, yyyy h:mm a',
    'MMMM d, yyyy h:mm a',
    'MMM d yyyy h:mm a',
    'MMMM d yyyy h:mm a',
    'yyyy-MM-dd HH:mm:ss',
    'yyyy-MM-dd HH:mm',
    'MM/dd/yyyy h:mm a',
  ]) {
    try {
      return DateFormat(format, 'en_US').parseStrict(normalized);
    } on FormatException {
      // Try the next complete date format; a status-bar time is insufficient.
    }
  }
  return null;
}

/// Conservative rules: ambiguous fields stay empty for review. Receipt samples
/// can extend these rules without training a model or uploading customer data.
GcashSuggestions parseGcashReceipt(String text, GcashKind kind) {
  final lines = text
      .split(RegExp(r'[\r\n]+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
  List<String> labeledValues(String labels, {List<String>? source}) {
    final candidates = source ?? lines;
    final regex = RegExp(
      '^(?:$labels)(?:\\s*[:：-]\\s*|\\s+|\$)(.*)\$',
      caseSensitive: false,
    );
    final values = <String>[];
    for (var i = 0; i < candidates.length; i++) {
      final match = regex.firstMatch(candidates[i]);
      if (match != null) {
        if (match[1]!.isNotEmpty) {
          values.add(match[1]!.trim());
        } else if (i + 1 < candidates.length) {
          values.add(candidates[i + 1]);
        }
      }
    }
    return values;
  }

  String? labeled(String labels) {
    final values = labeledValues(labels).toSet();
    return values.length == 1 ? values.single : null;
  }

  final isGcashReceipt = RegExp(
    r'\bg\s*cash\b',
    caseSensitive: false,
  ).hasMatch(text);
  final sentVia = RegExp(r'\bsent\s+via\s+g\s*cash\b', caseSensitive: false);
  final isExpressSend = RegExp(
    r'\bexpress\s+send\b',
    caseSensitive: false,
  ).hasMatch(text);
  final uniquePhone = _uniquePhone(lines);
  final inferredRecipients = <String>{};
  if (isGcashReceipt && uniquePhone != null) {
    for (var i = 0; i < lines.length; i++) {
      final phone = _phonePattern.firstMatch(lines[i]);
      if (phone == null) continue;
      final following = lines.skip(i).take(3).join(' ');
      if (!sentVia.hasMatch(following)) continue;
      final prefix = lines[i].substring(0, phone.start).trim();
      final candidate = prefix.isNotEmpty
          ? prefix
          : (i > 0 ? lines[i - 1] : '');
      // The masked recipient sits directly above/beside the phone. Requiring
      // masks avoids treating headings or promotional copy as customer names.
      if (RegExp(r'[•●·*]|[xX]{2,}').hasMatch(candidate) &&
          RegExp(r'\p{L}', unicode: true).hasMatch(candidate) &&
          RegExp(
            r"^[\p{L}\p{M} •●·*.'’\-]{2,150}$",
            unicode: true,
          ).hasMatch(candidate)) {
        inferredRecipients.add(candidate);
      }
    }
  }
  final inferredRecipient = inferredRecipients.length == 1
      ? inferredRecipients.single
      : null;
  // The title still identifies the recipient layout when OCR misreads GCash.
  final hasRecipientLayout = isExpressSend || sentVia.hasMatch(text);
  final senderName = labeled(
    r'(?:sender(?!\s+(?:mobile|phone|account|number|no)\b)(?: name)?|'
    r'received from|from|customer name)',
  );
  final senderNumber = _uniquePhone(
    labeledValues(r'sender(?: mobile| phone| account)?\s*(?:number|no\.?)'),
  );
  final recipientOnly =
      kind == GcashKind.cashOut &&
      hasRecipientLayout &&
      senderName == null &&
      senderNumber == null;
  final recipientNames = labeledValues(
    r'(?:recipient(?!\s+(?:mobile|phone|account|number|no)\b)(?: name)?|'
    r'sent to|to|customer name|name)',
  ).toSet();
  final name = kind == GcashKind.cashIn
      ? (recipientNames.isEmpty
            ? inferredRecipient
            : (recipientNames.length == 1 ? recipientNames.single : null))
      : senderName ?? (hasRecipientLayout ? null : labeled(r'name'));
  final genericNumber = _uniquePhone(
    labeledValues(r'(?:mobile|phone|account)\s*(?:number|no\.?)'),
  );
  final number = kind == GcashKind.cashOut
      ? senderNumber ??
            (hasRecipientLayout ? null : genericNumber ?? uniquePhone)
      : _uniquePhone(
              labeledValues(
                r'recipient(?: mobile| phone| account)?\s*(?:number|no\.?)',
              ),
            ) ??
            genericNumber ??
            uniquePhone;

  final dates = _datePattern
      .allMatches(text)
      .map((match) => _dateValue(match[0]!))
      .whereType<DateTime>()
      .toSet();
  // OCR may join the reference and date on one line or emit the date column
  // before the reference value. Remove full dates before reading the label.
  final referenceLines = text
      .replaceAll(_datePattern, '')
      .split(RegExp(r'[\r\n]+'))
      .map((line) => line.trim().replaceAll(RegExp(r'^\|+|\|+$'), '').trim())
      .where((line) => line.isNotEmpty)
      .toList();
  final references = labeledValues(
    r'(?:reference|ref\.?|transaction)\s*(?:number|no\.?|id)',
    source: referenceLines,
  ).map(normalizeGcashReference).toSet();
  final reference = references.length == 1 ? references.single : null;
  // A missed footer value must not turn the following carbon-savings copy or
  // button label into a reference. Keep legacy alphanumeric IDs elsewhere.
  final referencePattern = hasRecipientLayout
      ? RegExp(r'^\d{8,80}$')
      : RegExp(r'^[A-Z0-9]{4,80}$');

  const amountLabels =
      r'(?:amount sent|amount received|transfer amount|amount)';
  final labeledAmounts = labeledValues(amountLabels);
  final amounts = labeledAmounts.map(_amountValue).whereType<int>().toSet();
  int? amount = amounts.length == 1 ? amounts.single : null;
  if (amount == null && labeledAmounts.isEmpty) {
    final excludedLabel = RegExp(
      r'^(?:total(?: amount sent)?|service\s*fee|fee)\b',
      caseSensitive: false,
    );
    final currency = RegExp(
      r'(?:PHP|₱)\s*([\d,]+(?:\.\d+)?)',
      caseSensitive: false,
    );
    final fallbackAmounts = <int>{};
    final allCurrencyAmounts = <int>{};
    for (var i = 0; i < lines.length; i++) {
      final excluded =
          excludedLabel.hasMatch(lines[i]) ||
          (i > 0 &&
              excludedLabel.hasMatch(lines[i - 1]) &&
              !currency.hasMatch(lines[i - 1]));
      for (final match in currency.allMatches(lines[i])) {
        final candidate = gcashCentavos(match[1]!);
        if (candidate != null && candidate > 0) {
          allCurrencyAmounts.add(candidate);
          if (!excluded) fallbackAmounts.add(candidate);
        }
      }
    }
    if (fallbackAmounts.length == 1 && allCurrencyAmounts.length == 1) {
      amount = fallbackAmounts.single;
    }
  }
  return GcashSuggestions(
    name: name,
    number: number,
    amount: amount,
    reference: reference != null && referencePattern.hasMatch(reference)
        ? reference
        : null,
    date: dates.length == 1 ? dates.single : null,
    isGcashReceipt: isGcashReceipt,
    recipientOnly: recipientOnly,
  );
}

import 'dart:typed_data';

enum GcashKind {
  cashIn('Cash In', 'Customer gives cash; store sends GCash.'),
  cashOut('Cash Out', 'Customer sends GCash; store gives cash.');

  const GcashKind(this.label, this.description);
  final String label;
  final String description;
}

String normalizeGcashReference(String value) =>
    value.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');

int? gcashCentavos(String value) {
  final cleaned = value.trim().replaceAll(',', '');
  if (!RegExp(r'^\d{1,9}(?:\.\d{1,2})?$').hasMatch(cleaned)) return null;
  final parts = cleaned.split('.');
  return int.parse(parts.first) * 100 +
      (parts.length == 1 ? 0 : int.parse(parts.last.padRight(2, '0')));
}

class GcashRecord {
  const GcashRecord({
    required this.id,
    required this.kind,
    required this.name,
    required this.number,
    required this.amount,
    required this.fee,
    required this.reference,
    required this.date,
    this.receipt,
  });

  final String id;
  final GcashKind kind;
  final String name;
  final String number;
  final int amount;
  final int fee;
  final String reference;
  // Wall-clock time printed on the receipt; no implicit timezone conversion.
  final DateTime date;
  final Uint8List? receipt;

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'name': name,
    'number': number,
    'amount': amount,
    'fee': fee,
    'reference': normalizeGcashReference(reference),
    'date': date.toIso8601String(),
  };

  factory GcashRecord.fromJson(
    Map<String, dynamic> json, {
    Uint8List? receipt,
  }) {
    final result = GcashRecord(
      id: json['id'] as String,
      kind: GcashKind.values.byName(json['kind'] as String),
      name: json['name'] as String,
      number: json['number'] as String,
      amount: json['amount'] as int,
      fee: json['fee'] as int,
      reference: normalizeGcashReference(json['reference'] as String),
      date: DateTime.parse(json['date'] as String),
      receipt: receipt,
    );
    result.validate();
    return result;
  }

  void validate() {
    final image = receipt;
    if (image != null &&
        (image.length < 8 ||
            !List.generate(
              8,
              (i) => image[i],
            ).join(',').startsWith('137,80,78,71,13,10,26,10'))) {
      throw const FormatException('Receipt must be a PNG image.');
    }
    if (id.isEmpty ||
        id.length > 100 ||
        name.trim().isEmpty ||
        name.length > 150 ||
        number.trim().isEmpty ||
        number.length > 40 ||
        amount <= 0 ||
        amount > 99999999999 ||
        fee < 0 ||
        fee > 99999999999 ||
        !RegExp(
          r'^[A-Z0-9]{4,80}$',
        ).hasMatch(normalizeGcashReference(reference)) ||
        date.year < 2000 ||
        date.year > 2200 ||
        (receipt?.length ?? 0) > 2000000) {
      throw const FormatException('Check the GCash details and receipt size.');
    }
  }
}

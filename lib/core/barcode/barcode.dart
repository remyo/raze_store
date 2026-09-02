/// Returns the stable value used to store and compare a scanned barcode.
///
/// UPC-A scanners may report the same product either as 12 digits or as an
/// EAN-13 value with a leading zero. Numeric UPC-A values are therefore stored
/// in their EAN-13 representation. Other formats (including Code 128) retain
/// their exact, case-sensitive payload after surrounding whitespace is
/// removed.
String canonicalizeBarcode(String rawValue) {
  final trimmed = rawValue.trim();
  if (trimmed.isEmpty) return '';

  final isNumeric = RegExp(r'^\d+$').hasMatch(trimmed);
  if (isNumeric && trimmed.length == 12) return '0$trimmed';
  return trimmed;
}

/// A validated, canonical barcode string.
final class Barcode {
  factory Barcode(String rawValue) {
    final value = canonicalizeBarcode(rawValue);
    if (value.isEmpty) {
      throw ArgumentError.value(rawValue, 'rawValue', 'Must not be blank.');
    }
    if (value.length > maximumLength) {
      throw ArgumentError.value(
        rawValue,
        'rawValue',
        'Must be at most $maximumLength characters.',
      );
    }
    return Barcode._(value);
  }

  const Barcode._(this.value);

  static const maximumLength = 160;

  final String value;

  static Barcode? tryParse(String rawValue) {
    try {
      return Barcode(rawValue);
    } on ArgumentError {
      return null;
    }
  }

  @override
  bool operator ==(Object other) => other is Barcode && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Editable product details suggested by text visible on a product label.
///
/// Every value is only a suggestion: packaging text can be incomplete or
/// ambiguous and should still be reviewed before it is saved. In particular,
/// this model intentionally has no barcode field. Barcodes must come from the
/// barcode scanner, not from OCR digits.
final class ProductTextSuggestions {
  const ProductTextSuggestions({
    this.productName,
    this.brand,
    this.sizeOrUnit,
    this.priceCentavos,
  });

  final String? productName;
  final String? brand;
  final String? sizeOrUnit;

  /// A price is present only when the label explicitly used `₱`, `PHP`, or a
  /// standalone `P` currency marker.
  final int? priceCentavos;

  /// Alias matching the catalog form's field name.
  String? get unitLabel => sizeOrUnit;

  /// Alias matching catalog metadata's suggested-price field name.
  int? get suggestedPriceCentavos => priceCentavos;

  @override
  bool operator ==(Object other) =>
      other is ProductTextSuggestions &&
      other.productName == productName &&
      other.brand == brand &&
      other.sizeOrUnit == sizeOrUnit &&
      other.priceCentavos == priceCentavos;

  @override
  int get hashCode =>
      Object.hash(productName, brand, sizeOrUnit, priceCentavos);
}

/// The lossless line-level OCR output alongside conservative form suggestions.
final class ProductTextRecognitionResult {
  ProductTextRecognitionResult({
    required Iterable<String> rawLines,
    required this.suggestions,
  }) : rawLines = List<String>.unmodifiable(rawLines);

  /// Non-empty lines in the order supplied by the on-device recognizer.
  final List<String> rawLines;
  final ProductTextSuggestions suggestions;

  String get rawText => rawLines.join('\n');
}

/// Test seam for product-label OCR.
abstract interface class ProductTextRecognizer {
  Future<ProductTextRecognitionResult> recognizeImagePath(String imagePath);
}

/// Uses ML Kit's bundled Latin recognizer and never sends the image off-device.
final class OnDeviceProductTextRecognizer implements ProductTextRecognizer {
  OnDeviceProductTextRecognizer({
    TextRecognizer? textRecognizer,
    this.parser = const ProductTextRecognitionParser(),
  }) : _textRecognizer =
           textRecognizer ??
           TextRecognizer(script: TextRecognitionScript.latin);

  final TextRecognizer _textRecognizer;
  final ProductTextRecognitionParser parser;

  @override
  Future<ProductTextRecognitionResult> recognizeImagePath(
    String imagePath,
  ) async {
    if (imagePath.trim().isEmpty) {
      throw ArgumentError.value(imagePath, 'imagePath', 'Must not be empty.');
    }

    final recognized = await _textRecognizer.processImage(
      InputImage.fromFilePath(imagePath),
    );
    final structuredLines = <String>[
      for (final block in recognized.blocks)
        for (final line in block.lines) line.text,
    ];
    return parser.parse(
      structuredLines.isEmpty
          ? recognized.text.split(RegExp(r'[\r\n]+'))
          : structuredLines,
    );
  }

  Future<void> close() => _textRecognizer.close();
}

final productTextRecognizerProvider = Provider<ProductTextRecognizer>((ref) {
  final recognizer = OnDeviceProductTextRecognizer();
  ref.onDispose(() => unawaited(recognizer.close()));
  return recognizer;
});

/// Deterministically turns recognized label lines into editable suggestions.
///
/// The rules intentionally favor an empty field over an unsafe guess. They do
/// not inspect or infer barcodes, and a bare number is never treated as a price.
final class ProductTextRecognitionParser {
  const ProductTextRecognitionParser();

  ProductTextRecognitionResult parse(Iterable<String> recognizedLines) {
    final rawLines = <String>[
      for (final input in recognizedLines)
        for (final line in input.split(RegExp(r'[\r\n]+')))
          if (line.trim().isNotEmpty) line.trim(),
    ];
    final lines = [for (final line in rawLines) _LabelLine(line)];

    final explicitName = _firstLabeledValue(lines, _nameLabelPattern);
    final explicitBrand = _firstLabeledValue(lines, _brandLabelPattern);
    final sizeOrUnit = _findSizeOrUnit(lines);
    final priceCentavos = _findUnambiguousExplicitPrice(lines);

    final nameCandidates = <String>[];
    for (final line in lines) {
      if (_isLabeledLine(line.normalized) ||
          _isPackagingNoise(line.normalized) ||
          _containsExplicitPrice(line.normalized) ||
          _looksLikeSizeOnly(line.normalized) ||
          !_looksLikeNameText(line.normalized)) {
        continue;
      }
      nameCandidates.add(_cleanSuggestion(line.raw));
    }

    String? inferredBrand;
    if (explicitBrand == null && nameCandidates.length >= 2) {
      final first = nameCandidates[0];
      final second = nameCandidates[1];
      if (_looksLikeBrand(first, nextLine: second)) inferredBrand = first;
    }

    final brand = explicitBrand ?? inferredBrand;
    final productName =
        explicitName ??
        _firstProductNameCandidate(
          nameCandidates,
          inferredBrand: inferredBrand,
        );

    return ProductTextRecognitionResult(
      rawLines: rawLines,
      suggestions: ProductTextSuggestions(
        productName: productName,
        brand: brand,
        sizeOrUnit: sizeOrUnit,
        priceCentavos: priceCentavos,
      ),
    );
  }
}

ProductTextRecognitionResult parseProductText(
  Iterable<String> recognizedLines,
) => const ProductTextRecognitionParser().parse(recognizedLines);

final RegExp _nameLabelPattern = RegExp(
  r'^(?:product\s*name|item\s*name|product|name)\s*(?:[:\-]\s*|\s+)(.+)$',
  caseSensitive: false,
);
final RegExp _brandLabelPattern = RegExp(
  r'^(?:brand\s*name|brand)\s*(?:[:\-]\s*|\s+)(.+)$',
  caseSensitive: false,
);
final RegExp _sizeLabelPattern = RegExp(
  r'^(?:net\s*(?:wt\.?|weight|contents?)|size|volume|vol\.?)\s*(?:[:\-]\s*|\s+)(.+)$',
  caseSensitive: false,
);
final RegExp _anyKnownLabelPattern = RegExp(
  r'^(?:product\s*name|item\s*name|product|name|brand\s*name|brand|net\s*(?:wt\.?|weight|contents?)|size|volume|vol\.?|price|srp|retail\s*price)\s*(?:[:\-]|\s)',
  caseSensitive: false,
);
final RegExp _prefixPricePattern = RegExp(
  r'(?:₱|\bPHP\s*[:.]?|\bP\s*[:.]?)\s*((?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d{1,2})?)(?![\d,.])',
  caseSensitive: false,
);
final RegExp _suffixPricePattern = RegExp(
  r'(?<![\d,.])((?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d{1,2})?)\s*(?:PHP|₱|P\b)',
  caseSensitive: false,
);
final RegExp _explicitPriceMarkerPattern = RegExp(
  r'(?:₱|\bPHP\b)',
  caseSensitive: false,
);
final RegExp _standalonePesoMarkerPattern = RegExp(
  r'(?:^|\b(?:price|srp|retail|promo|only|sale)\b[\s:=-]{0,8})P\s*[:.]?\s*\d',
  caseSensitive: false,
);
final RegExp _measurePattern = RegExp(
  r'\b(\d+(?:[.,]\d+)?)\s*(fl\s*oz|milligrams?|millilit(?:er|re)s?|kilograms?|grams?|lit(?:er|re)s?|ounces?|pounds?|mg|kg|g|ml|cl|l|oz|lbs?|pcs?|pieces?|packs?|sachets?|sticks?|bottles?|cans?|pouches?|boxes?|trays?|jars?|tubes?)\b',
  caseSensitive: false,
);
final RegExp _multipackMeasurePattern = RegExp(
  r'\b(\d+)\s*[x×]\s*(\d+(?:[.,]\d+)?)\s*(fl\s*oz|milligrams?|millilit(?:er|re)s?|kilograms?|grams?|lit(?:er|re)s?|ounces?|pounds?|mg|kg|g|ml|cl|l|oz|lbs?)\b',
  caseSensitive: false,
);
final RegExp _unitOnlyPattern = RegExp(
  r'^(?:single\s+)?(?:pack|packet|sachet|stick|bottle|can|pouch|box|tray|piece|pc|jar|tube)s?$',
  caseSensitive: false,
);
final RegExp _barcodeLikePattern = RegExp(r'^\D*\d(?:[\s\-]?\d){7,13}\D*$');
final RegExp _nameLettersPattern = RegExp(r'[A-Za-z]{2}');
final RegExp _noisePattern = RegExp(
  r'^(?:nutrition(?:al)?\s*facts?|ingredients?|manufactured|distributed|imported|marketed|expiry|expiration|exp\.?\b|mfg\.?\b|best\s*before|batch\b|lot\b|servings?|calories?|energy\b|protein\b|carbohydrates?|sugars?|sodium\b|total\s*fat|keep\b|store\b|storage\b|warning\b|directions?|instructions?|customer|consumer|hotline|telephone|tel\.?\b|www\.|https?://|made\s+in|product\s+of|fda\b|lto\b|vat\b|allergen)',
  caseSensitive: false,
);
final RegExp _genericProductWordsPattern = RegExp(
  r'\b(?:instant|noodles?|corned|beef|sardines?|tuna|coffee|milk|water|juice|soap|shampoo|detergent|biscuits?|crackers?|chips?|candy|rice|sugar|salt|flour|oil|sauce|seasoning|snacks?|flakes|powder|drink|tea)\b',
  caseSensitive: false,
);

String? _firstLabeledValue(List<_LabelLine> lines, RegExp pattern) {
  for (final line in lines) {
    final match = pattern.firstMatch(line.normalized);
    if (match == null) continue;
    final value = _cleanSuggestion(match.group(1)!);
    if (_looksLikeNameText(value) && !_barcodeLikePattern.hasMatch(value)) {
      return value;
    }
  }
  return null;
}

String? _findSizeOrUnit(List<_LabelLine> lines) {
  for (final line in lines) {
    final labeled = _sizeLabelPattern.firstMatch(line.normalized);
    if (labeled == null) continue;
    final value = _cleanSuggestion(labeled.group(1)!);
    final measure = _extractMeasure(value);
    if (measure != null) return measure;
    if (_unitOnlyPattern.hasMatch(value)) return _canonicalUnitOnly(value);
  }

  for (final line in lines) {
    // A long digit run with a stray OCR letter (for example a trailing `G`)
    // must not become a package-size suggestion.
    if (_barcodeLikePattern.hasMatch(line.normalized)) continue;
    final measure = _extractMeasure(line.normalized);
    if (measure != null) return measure;
    if (_unitOnlyPattern.hasMatch(line.normalized)) {
      return _canonicalUnitOnly(line.normalized);
    }
  }
  return null;
}

String? _extractMeasure(String input) {
  final multipack = _multipackMeasurePattern.firstMatch(input);
  if (multipack != null) {
    return '${multipack.group(1)} x ${_canonicalNumber(multipack.group(2)!)} '
        '${_canonicalMeasureUnit(multipack.group(3)!)}';
  }
  final measure = _measurePattern.firstMatch(input);
  if (measure == null) return null;
  return '${_canonicalNumber(measure.group(1)!)} '
      '${_canonicalMeasureUnit(measure.group(2)!)}';
}

String _canonicalNumber(String input) => input.replaceAll(',', '.');

String _canonicalMeasureUnit(String input) {
  final unit = input.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  return switch (unit) {
    'milligram' || 'milligrams' => 'mg',
    'gram' || 'grams' => 'g',
    'kilogram' || 'kilograms' => 'kg',
    'milliliter' || 'milliliters' || 'millilitre' || 'millilitres' => 'mL',
    'ml' => 'mL',
    'liter' || 'liters' || 'litre' || 'litres' => 'L',
    'l' => 'L',
    'ounce' || 'ounces' => 'oz',
    'pound' || 'pounds' || 'lb' || 'lbs' => 'lb',
    'pc' || 'piece' => 'pc',
    'pcs' || 'pieces' => 'pcs',
    _ => unit,
  };
}

String _canonicalUnitOnly(String input) {
  final normalized = input.trim().toLowerCase();
  final words = normalized.split(RegExp(r'\s+'));
  return [
    for (final word in words) '${word[0].toUpperCase()}${word.substring(1)}',
  ].join(' ');
}

int? _findUnambiguousExplicitPrice(List<_LabelLine> lines) {
  final amounts = <int>{};
  for (final line in lines) {
    if (!_containsExplicitPrice(line.normalized)) continue;
    for (final pattern in [_prefixPricePattern, _suffixPricePattern]) {
      for (final match in pattern.allMatches(line.normalized)) {
        final centavos = _parseExplicitAmount(match.group(1)!);
        if (centavos != null) amounts.add(centavos);
      }
    }
  }
  return amounts.length == 1 ? amounts.single : null;
}

int? _parseExplicitAmount(String input) {
  final normalized = input.replaceAll(',', '');
  final parts = normalized.split('.');
  final pesos = int.tryParse(parts[0]);
  if (pesos == null || pesos < 0 || pesos > 999999) return null;
  final fraction = parts.length == 1 ? '' : parts[1];
  final centavos = switch (fraction.length) {
    0 => 0,
    1 => int.parse(fraction) * 10,
    2 => int.parse(fraction),
    _ => -1,
  };
  final total = pesos * 100 + centavos;
  return total > 0 ? total : null;
}

bool _containsExplicitPrice(String input) =>
    _explicitPriceMarkerPattern.hasMatch(input) ||
    _standalonePesoMarkerPattern.hasMatch(input);

bool _isLabeledLine(String input) => _anyKnownLabelPattern.hasMatch(input);

bool _isPackagingNoise(String input) => _noisePattern.hasMatch(input);

bool _looksLikeSizeOnly(String input) {
  final withoutPrefixes = input.replaceFirst(
    RegExp(
      r'^(?:net\s*(?:wt\.?|weight|contents?)|size|volume|vol\.?)\s*(?:[:\-]\s*|\s+)',
      caseSensitive: false,
    ),
    '',
  );
  final measure = _extractMeasure(withoutPrefixes);
  if (measure == null) return _unitOnlyPattern.hasMatch(withoutPrefixes);
  return withoutPrefixes
      .replaceFirst(_multipackMeasurePattern, '')
      .replaceFirst(_measurePattern, '')
      .trim()
      .isEmpty;
}

bool _looksLikeNameText(String input) {
  final value = input.trim();
  return value.length >= 2 &&
      value.length <= 80 &&
      _nameLettersPattern.hasMatch(value) &&
      !_barcodeLikePattern.hasMatch(value);
}

bool _looksLikeBrand(String input, {required String nextLine}) {
  final value = input.trim();
  final wordCount = value.split(RegExp(r'\s+')).length;
  if (wordCount > 3 || value.length > 30) return false;
  if (_genericProductWordsPattern.hasMatch(value)) return false;

  final letters = value.replaceAll(RegExp('[^A-Za-z]'), '');
  final allUppercase = letters.isNotEmpty && letters == letters.toUpperCase();
  final hasBrandStyling = value.contains(RegExp(r'[!\-®™]'));
  final visiblyLeadsDescription = value.length < nextLine.length;
  return hasBrandStyling ||
      (allUppercase && visiblyLeadsDescription) ||
      (wordCount <= 2 && visiblyLeadsDescription);
}

String? _firstProductNameCandidate(
  List<String> candidates, {
  required String? inferredBrand,
}) {
  for (final candidate in candidates) {
    if (candidate != inferredBrand) return candidate;
  }
  return null;
}

String _cleanSuggestion(String input) => input
    .trim()
    .replaceAll(RegExp(r'\s+'), ' ')
    .replaceAll(RegExp(r'^[\s:;\-]+|[\s:;\-]+$'), '');

final class _LabelLine {
  _LabelLine(this.raw) : normalized = raw.replaceAll(RegExp(r'\s+'), ' ');

  final String raw;
  final String normalized;
}

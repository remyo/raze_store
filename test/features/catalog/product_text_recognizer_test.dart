import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:raze_store/features/catalog/application/product_text_recognizer.dart';

void main() {
  group('ProductTextRecognitionParser', () {
    const parser = ProductTextRecognitionParser();

    test('suggests common label details while retaining recognized lines', () {
      final result = parser.parse([
        'LUCKY ME!',
        'PANCIT CANTON',
        'CHILIMANSI',
        'NET WT. 60 g',
        'SRP ₱ 16.00',
        '4 801234 567890',
        'Nutrition Facts',
      ]);

      expect(result.rawLines, [
        'LUCKY ME!',
        'PANCIT CANTON',
        'CHILIMANSI',
        'NET WT. 60 g',
        'SRP ₱ 16.00',
        '4 801234 567890',
        'Nutrition Facts',
      ]);
      expect(
        result.suggestions,
        const ProductTextSuggestions(
          productName: 'PANCIT CANTON',
          brand: 'LUCKY ME!',
          sizeOrUnit: '60 g',
          priceCentavos: 1600,
        ),
      );
      expect(result.suggestions.unitLabel, '60 g');
      expect(result.suggestions.suggestedPriceCentavos, 1600);
    });

    test('prefers explicit labels and normalizes units and peso amounts', () {
      final result = parser.parse([
        'Brand: Mega',
        'Product Name - Sardines in Tomato Sauce',
        'Size: 155ML',
        'Retail price PHP: 27.5',
      ]);

      expect(result.suggestions.productName, 'Sardines in Tomato Sauce');
      expect(result.suggestions.brand, 'Mega');
      expect(result.suggestions.sizeOrUnit, '155 mL');
      expect(result.suggestions.priceCentavos, 2750);
    });

    test('never treats bare prices or barcode-like digits as suggestions', () {
      final result = parser.parse([
        'Argentina Corned Beef',
        '4801234567890',
        '35.00',
      ]);

      expect(result.suggestions.productName, 'Argentina Corned Beef');
      expect(result.suggestions.brand, isNull);
      expect(result.suggestions.priceCentavos, isNull);
      expect(result.rawLines, contains('4801234567890'));
    });

    test('does not mistake a barcode with an OCR suffix for a size', () {
      final result = parser.parse(['Chocolate Biscuits', '4801234567890G']);

      expect(result.suggestions.sizeOrUnit, isNull);
      expect(result.rawLines, contains('4801234567890G'));
    });

    test('declines an ambiguous label containing different peso prices', () {
      final result = parser.parse([
        'Chocolate Biscuits',
        'SRP ₱25.00',
        'Promo PHP 20.00',
      ]);

      expect(result.suggestions.priceCentavos, isNull);
    });

    test('accepts duplicate mentions only when their peso amount agrees', () {
      final result = parser.parse(['Chocolate Biscuits', '₱25', 'PHP 25.00']);

      expect(result.suggestions.priceCentavos, 2500);
    });

    test('accepts a standalone P only when it clearly marks a price', () {
      expect(
        parser
            .parse(['Suggested Retail Price P 10.00'])
            .suggestions
            .priceCentavos,
        1000,
      );
      expect(parser.parse(['Vitamin P 10']).suggestions.priceCentavos, isNull);
    });

    test('normalizes multipack measurements and standalone selling units', () {
      expect(
        parser.parse(['SOAP', '3 x 90 GRAMS']).suggestions.sizeOrUnit,
        '3 x 90 g',
      );
      expect(parser.parse(['SOAP', 'Bottle']).suggestions.sizeOrUnit, 'Bottle');
    });

    test('splits embedded newlines, removes blanks, and freezes raw lines', () {
      final result = parseProductText(['  ACME\n\nChocolate Cookies  ', '80g']);

      expect(result.rawLines, ['ACME', 'Chocolate Cookies', '80g']);
      expect(result.rawText, 'ACME\nChocolate Cookies\n80g');
      expect(() => result.rawLines.add('changed'), throwsUnsupportedError);
    });
  });

  group('OnDeviceProductTextRecognizer', () {
    test('adapts ML Kit text into the pure parser result', () async {
      final mlKit = _FakeTextRecognizer(
        RecognizedText(
          text: 'ACME\nChocolate Cookies\n80g\nPHP 25',
          blocks: const [],
        ),
      );
      final recognizer = OnDeviceProductTextRecognizer(textRecognizer: mlKit);

      final result = await recognizer.recognizeImagePath('/tmp/label.jpg');

      expect(mlKit.processedPath, '/tmp/label.jpg');
      expect(result.suggestions.productName, 'Chocolate Cookies');
      expect(result.suggestions.brand, 'ACME');
      expect(result.suggestions.sizeOrUnit, '80 g');
      expect(result.suggestions.priceCentavos, 2500);

      await recognizer.close();
      expect(mlKit.didClose, isTrue);
    });

    test('rejects an empty image path before invoking ML Kit', () async {
      final mlKit = _FakeTextRecognizer(
        RecognizedText(text: '', blocks: const []),
      );
      final recognizer = OnDeviceProductTextRecognizer(textRecognizer: mlKit);

      await expectLater(
        recognizer.recognizeImagePath('  '),
        throwsArgumentError,
      );
      expect(mlKit.processedPath, isNull);
    });
  });
}

final class _FakeTextRecognizer extends TextRecognizer {
  _FakeTextRecognizer(this.output) : super(script: TextRecognitionScript.latin);

  final RecognizedText output;
  String? processedPath;
  bool didClose = false;

  @override
  Future<RecognizedText> processImage(InputImage inputImage) async {
    processedPath = inputImage.filePath;
    return output;
  }

  @override
  Future<void> close() async {
    didClose = true;
  }
}

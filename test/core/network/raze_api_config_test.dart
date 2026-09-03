import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/core/network/raze_api_config.dart';

void main() {
  group('RazeApiConfig', () {
    test('normalizes a server root to the versioned API base', () {
      final config = RazeApiConfig.fromValue('https://catalog.example.com');

      expect(config.isConfigured, isTrue);
      expect(config.baseUri, Uri.parse('https://catalog.example.com/api/v1/'));
    });

    test('keeps a configured API path and safely encodes query values', () {
      final config = RazeApiConfig.fromValue(
        'https://catalog.example.com/api/v1',
      );

      final endpoint = config.endpoint(
        'products/by-barcode/',
        queryParameters: {'barcode': 'CASE.12+BLUE/?#'},
      );

      expect(endpoint.path, '/api/v1/products/by-barcode/');
      expect(endpoint.queryParameters['barcode'], 'CASE.12+BLUE/?#');
    });

    test('rejects insecure release endpoints', () {
      final config = RazeApiConfig.fromValue(
        'http://catalog.example.com/api/v1/',
      );

      expect(config.isConfigured, isFalse);
      expect(config.error, contains('HTTPS'));
    });

    test('allows local HTTP only when explicitly enabled', () {
      final config = RazeApiConfig.fromValue(
        'http://127.0.0.1:8000/api/v1/',
        allowInsecureHttp: true,
      );

      expect(config.isConfigured, isTrue);
    });

    test('rejects credentials and query parameters in the base URL', () {
      final credentials = RazeApiConfig.fromValue(
        'https://admin:secret@catalog.example.com/api/v1/',
      );
      final query = RazeApiConfig.fromValue(
        'https://catalog.example.com/api/v1/?token=secret',
      );

      expect(credentials.isConfigured, isFalse);
      expect(query.isConfigured, isFalse);
    });
  });
}

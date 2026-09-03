import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:raze_store/core/network/raze_api_config.dart';
import 'package:raze_store/features/catalog/data/raze_store_api_client.dart';
import 'package:raze_store/features/catalog/domain/remote_catalog_repository.dart';

void main() {
  group('RazeStoreApiClient', () {
    test(
      'looks up punctuation barcodes with query encoding and maps metadata',
      () async {
        late Uri requestedUri;
        final client = _apiClient(
          MockClient((request) async {
            requestedUri = request.url;
            return http.Response(
              jsonEncode(_product(barcode: 'CASE.12+BLUE/?#')),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        );

        final product = await client.findByBarcode('CASE.12+BLUE/?#');

        expect(requestedUri.path, '/api/v1/products/by-barcode/');
        expect(requestedUri.queryParameters['barcode'], 'CASE.12+BLUE/?#');
        expect(product?.name, 'Lucky Me Pancit Canton');
        expect(product?.brand, 'Lucky Me!');
        expect(product?.unitLabel, '60 g');
        expect(product?.category, 'Instant noodles');
        expect(product?.metadata.source, 'raze_store_api');
        expect(product?.metadata.sourceProductId, _productId);
        expect(product?.metadata.suggestedPriceCentavos, 1650);
      },
    );

    test('maps 404 to an absent product', () async {
      final client = _apiClient(
        MockClient((_) async => http.Response('{}', 404)),
      );

      expect(await client.findByBarcode('4800012345678'), isNull);
    });

    test('parses DRF pagination without accepting a store price', () async {
      final client = _apiClient(
        MockClient((request) async {
          expect(request.url.queryParameters, {'q': 'coffee', 'page': '2'});
          final product = _product()..['priceCentavos'] = 1;
          return http.Response(
            jsonEncode({
              'count': 51,
              'next': null,
              'previous': 'https://catalog.example.com/api/v1/products/?page=1',
              'results': [product],
            }),
            200,
          );
        }),
      );

      final page = await client.searchProducts(query: ' coffee ', page: 2);

      expect(page.totalCount, 51);
      expect(page.page, 2);
      expect(page.hasNextPage, isFalse);
      expect(page.products, hasLength(1));
      expect(page.products.single.metadata, isNotNull);
    });

    test('loads, trims, sorts, and deduplicates API categories', () async {
      final client = _apiClient(
        MockClient((request) async {
          expect(request.url.path, '/api/v1/categories/');
          return http.Response(
            jsonEncode({
              'schemaVersion': 1,
              'categories': [' Snacks ', 'coffee', 'COFFEE'],
            }),
            200,
          );
        }),
      );

      expect(await client.fetchCategories(), ['coffee', 'Snacks']);
    });

    test('rejects an invalid API category list', () async {
      final client = _apiClient(
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              'schemaVersion': 1,
              'categories': ['Valid', 42],
            }),
            200,
          ),
        ),
      );

      await expectLater(
        client.fetchCategories(),
        throwsA(
          isA<CatalogApiException>().having(
            (error) => error.kind,
            'kind',
            CatalogApiFailureKind.invalidResponse,
          ),
        ),
      );
    });

    test('rejects an unsupported schema version', () async {
      final client = _apiClient(
        MockClient((_) async {
          final body = _product()..['schemaVersion'] = 2;
          return http.Response(jsonEncode(body), 200);
        }),
      );

      await expectLater(
        client.findByBarcode('4800012345678'),
        throwsA(
          isA<CatalogApiException>().having(
            (error) => error.kind,
            'kind',
            CatalogApiFailureKind.invalidResponse,
          ),
        ),
      );
    });

    test('rejects non-HTTP product image URLs', () async {
      final client = _apiClient(
        MockClient((_) async {
          final body = _product()..['remoteImageUrl'] = 'file:///secret.jpg';
          return http.Response(jsonEncode(body), 200);
        }),
      );

      await expectLater(
        client.findByBarcode('4800012345678'),
        throwsA(
          isA<CatalogApiException>().having(
            (error) => error.kind,
            'kind',
            CatalogApiFailureKind.invalidResponse,
          ),
        ),
      );
    });

    test('rejects an HTTP image delivered by an HTTPS API', () async {
      final client = _apiClient(
        MockClient((_) async {
          final body = _product()
            ..['remoteImageUrl'] = 'http://192.168.1.10/private.jpg';
          return http.Response(jsonEncode(body), 200);
        }),
      );

      await expectLater(
        client.findByBarcode('4800012345678'),
        throwsA(
          isA<CatalogApiException>().having(
            (error) => error.kind,
            'kind',
            CatalogApiFailureKind.invalidResponse,
          ),
        ),
      );
    });

    test('enforces the response size limit', () async {
      final client = RazeStoreApiClient(
        config: _config,
        client: MockClient((_) async => http.Response('x' * 65, 200)),
        maximumResponseBytes: 64,
      );

      await expectLater(
        client.checkHealth(),
        throwsA(
          isA<CatalogApiException>().having(
            (error) => error.kind,
            'kind',
            CatalogApiFailureKind.invalidResponse,
          ),
        ),
      );
    });

    test('reports request timeouts separately', () async {
      final client = RazeStoreApiClient(
        config: _config,
        client: _NeverRespondingClient(),
        timeout: const Duration(milliseconds: 10),
      );

      await expectLater(
        client.checkHealth(),
        throwsA(
          isA<CatalogApiException>().having(
            (error) => error.kind,
            'kind',
            CatalogApiFailureKind.timeout,
          ),
        ),
      );
    });

    test('validates the health service identity', () async {
      final client = _apiClient(
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              'status': 'ok',
              'service': 'raze_store_api',
              'time': '2026-09-03T00:00:00Z',
            }),
            200,
          ),
        ),
      );

      final health = await client.checkHealth();

      expect(health.service, 'raze_store_api');
      expect(health.checkedAt, DateTime.utc(2026, 9, 3));
    });
  });
}

final _config = RazeApiConfig.fromValue('https://catalog.example.com/api/v1/');

RazeStoreApiClient _apiClient(http.Client client) =>
    RazeStoreApiClient(config: _config, client: client);

Map<String, Object?> _product({String barcode = '4800012345678'}) => {
  'schemaVersion': 1,
  'catalogProductId': _productId,
  'barcode': barcode,
  'name': 'Lucky Me Pancit Canton',
  'brand': 'Lucky Me!',
  'unitLabel': '60 g',
  'category': 'Instant noodles',
  'remoteImageUrl': 'https://catalog.example.com/images/product.jpg',
  'source': 'raze_store_api',
  'sourceProductId': _productId,
  'suggestedPriceCentavos': 1650,
  'updatedAt': '2026-09-03T00:00:00Z',
};

const String _productId = 'f71ea24a-41f2-422f-9aeb-24efa48e7a5d';

final class _NeverRespondingClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      Completer<http.StreamedResponse>().future;
}

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../core/network/raze_api_config.dart';
import '../domain/catalog_product.dart';
import '../domain/remote_catalog_product.dart';
import '../domain/remote_catalog_repository.dart';

final class RazeStoreApiClient implements RemoteCatalogRepository {
  RazeStoreApiClient({
    required RazeApiConfig config,
    required http.Client client,
    Duration timeout = const Duration(seconds: 8),
    int maximumResponseBytes = 2 * 1024 * 1024,
  }) : _config = config,
       _client = client,
       _timeout = timeout,
       _maximumResponseBytes = maximumResponseBytes;

  final RazeApiConfig _config;
  final http.Client _client;
  final Duration _timeout;
  final int _maximumResponseBytes;

  @override
  bool get isConfigured => _config.isConfigured;

  @override
  Uri? get baseUri => _config.baseUri;

  @override
  String? get configurationError => _config.error;

  @override
  Future<RemoteCatalogProduct?> findByBarcode(String barcode) async {
    if (barcode.trim().isEmpty || barcode.length > 160) {
      throw const CatalogApiException(
        CatalogApiFailureKind.invalidRequest,
        'The barcode is missing or too long.',
      );
    }
    final response = await _get(
      _endpoint('products/by-barcode/', queryParameters: {'barcode': barcode}),
    );
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw _statusException(response);
    }
    return _parseProduct(_decodeObject(response.body));
  }

  @override
  Future<RemoteCatalogPage> searchProducts({
    String query = '',
    int page = 1,
  }) async {
    if (page < 1) {
      throw const CatalogApiException(
        CatalogApiFailureKind.invalidRequest,
        'The catalog page must be at least 1.',
      );
    }
    final normalizedQuery = query.trim();
    if (normalizedQuery.length > 240) {
      throw const CatalogApiException(
        CatalogApiFailureKind.invalidRequest,
        'The catalog search is too long.',
      );
    }
    final response = await _get(
      _endpoint(
        'products/',
        queryParameters: {
          if (normalizedQuery.isNotEmpty) 'q': normalizedQuery,
          'page': '$page',
        },
      ),
    );
    if (response.statusCode != 200) throw _statusException(response);

    final payload = _decodeObject(response.body);
    final rawCount = payload['count'];
    final rawResults = payload['results'];
    final rawNext = payload['next'];
    if (rawCount is! int ||
        rawCount < 0 ||
        rawResults is! List<Object?> ||
        (rawNext != null && rawNext is! String)) {
      throw _invalidResponse('The catalog page has an invalid shape.');
    }
    if (rawResults.length > 100) {
      throw _invalidResponse('The catalog page contains too many products.');
    }
    final products = <RemoteCatalogProduct>[];
    for (final value in rawResults) {
      if (value is! Map<String, Object?>) {
        throw _invalidResponse('A catalog product is not a JSON object.');
      }
      products.add(_parseProduct(value));
    }
    return RemoteCatalogPage(
      products: List.unmodifiable(products),
      totalCount: rawCount,
      page: page,
      hasNextPage: rawNext != null,
    );
  }

  @override
  Future<List<String>> fetchCategories() async {
    final response = await _get(_endpoint('categories/'));
    if (response.statusCode != 200) throw _statusException(response);

    final payload = _decodeObject(response.body);
    final rawCategories = payload['categories'];
    if (payload['schemaVersion'] != 1 || rawCategories is! List<Object?>) {
      throw _invalidResponse('The category list has an invalid shape.');
    }
    if (rawCategories.length > 1000) {
      throw _invalidResponse('The category list contains too many values.');
    }

    final categoriesByKey = <String, String>{};
    for (final value in rawCategories) {
      if (value is! String) {
        throw _invalidResponse('A catalog category is not text.');
      }
      final category = value.trim();
      if (category.isEmpty || category.length > 240) {
        throw _invalidResponse('A catalog category is invalid.');
      }
      categoriesByKey.putIfAbsent(category.toLowerCase(), () => category);
    }
    final categories = categoriesByKey.values.toList(
      growable: false,
    )..sort((left, right) => left.toLowerCase().compareTo(right.toLowerCase()));
    return List<String>.unmodifiable(categories);
  }

  @override
  Future<CatalogApiHealth> checkHealth() async {
    final response = await _get(_endpoint('health/'));
    if (response.statusCode != 200) throw _statusException(response);
    final payload = _decodeObject(response.body);
    if (payload['status'] != 'ok' || payload['service'] != 'raze_store_api') {
      throw _invalidResponse('The server is not a Raze Store catalog API.');
    }
    final checkedAt = DateTime.tryParse(
      _requiredString(payload, 'time', maximumLength: 64),
    );
    if (checkedAt == null) {
      throw _invalidResponse('The API health timestamp is invalid.');
    }
    return CatalogApiHealth(
      service: 'raze_store_api',
      checkedAt: checkedAt.toUtc(),
    );
  }

  Uri _endpoint(String relativePath, {Map<String, String>? queryParameters}) {
    try {
      return _config.endpoint(relativePath, queryParameters: queryParameters);
    } on StateError catch (error) {
      throw CatalogApiException(
        CatalogApiFailureKind.notConfigured,
        error.message.toString(),
      );
    }
  }

  Future<_ApiResponse> _get(Uri uri) async {
    final abortRequest = Completer<void>();
    final abortTimer = Timer(_timeout, abortRequest.complete);
    try {
      // AbortableRequest lets IOClient/BrowserClient release the socket and
      // response stream when the whole-operation deadline is reached. The
      // Future timeout is also kept as a fallback for custom test clients.
      return await _performGet(
        uri,
        abortTrigger: abortRequest.future,
      ).timeout(_timeout);
    } on CatalogApiException {
      if (!abortRequest.isCompleted) abortRequest.complete();
      rethrow;
    } on http.RequestAbortedException {
      throw _timeoutException();
    } on TimeoutException {
      if (!abortRequest.isCompleted) abortRequest.complete();
      throw _timeoutException();
    } on http.ClientException catch (error) {
      throw CatalogApiException(
        CatalogApiFailureKind.network,
        'The shared catalog could not be reached: ${error.message}',
      );
    } on Object {
      throw const CatalogApiException(
        CatalogApiFailureKind.network,
        'The shared catalog could not be reached.',
      );
    } finally {
      abortTimer.cancel();
    }
  }

  Future<_ApiResponse> _performGet(
    Uri uri, {
    required Future<void> abortTrigger,
  }) async {
    final request =
        http.AbortableRequest('GET', uri, abortTrigger: abortTrigger)
          ..headers['Accept'] = 'application/json'
          ..followRedirects = false;
    final streamed = await _client.send(request);

    final bytes = BytesBuilder(copy: false);
    await for (final chunk in streamed.stream) {
      if (bytes.length + chunk.length > _maximumResponseBytes) {
        throw _invalidResponse('The catalog response is too large.');
      }
      bytes.add(chunk);
    }
    String body;
    try {
      body = utf8.decode(bytes.takeBytes());
    } on FormatException {
      throw _invalidResponse('The catalog response is not valid UTF-8.');
    }
    return _ApiResponse(statusCode: streamed.statusCode, body: body);
  }

  CatalogApiException _timeoutException() => const CatalogApiException(
    CatalogApiFailureKind.timeout,
    'The shared catalog took too long to respond.',
  );

  RemoteCatalogProduct _parseProduct(Map<String, Object?> payload) {
    if (payload['schemaVersion'] != 1) {
      throw _invalidResponse('The product uses an unsupported schema version.');
    }
    final catalogProductId = _requiredString(
      payload,
      'catalogProductId',
      maximumLength: 64,
    );
    final source = _requiredString(payload, 'source', maximumLength: 64);
    final sourceProductId = _requiredString(
      payload,
      'sourceProductId',
      maximumLength: 160,
    );
    if (!_uuidPattern.hasMatch(catalogProductId) ||
        source != 'raze_store_api' ||
        sourceProductId != catalogProductId) {
      throw _invalidResponse('The product identity is inconsistent.');
    }
    final remoteImageUrl = _optionalString(
      payload,
      'remoteImageUrl',
      maximumLength: 2048,
    );
    if (remoteImageUrl != null) {
      final imageUri = Uri.tryParse(remoteImageUrl);
      if (imageUri == null ||
          !imageUri.hasAuthority ||
          imageUri.userInfo.isNotEmpty ||
          (imageUri.scheme != 'https' && imageUri.scheme != 'http') ||
          (_config.baseUri?.scheme == 'https' && imageUri.scheme != 'https')) {
        throw _invalidResponse('The product image URL is invalid.');
      }
    }
    final updatedAt = DateTime.tryParse(
      _requiredString(payload, 'updatedAt', maximumLength: 64),
    );
    if (updatedAt == null) {
      throw _invalidResponse('The product update timestamp is invalid.');
    }
    final suggestedPriceCentavos = _optionalPositiveInt(
      payload,
      'suggestedPriceCentavos',
    );
    try {
      final metadata = CatalogMetadata(
        barcode: _requiredString(payload, 'barcode', maximumLength: 160),
        name: _requiredString(payload, 'name', maximumLength: 240),
        brand: _optionalString(payload, 'brand', maximumLength: 240),
        unitLabel: _optionalString(payload, 'unitLabel', maximumLength: 120),
        category: _optionalString(payload, 'category', maximumLength: 240),
        remoteImageUrl: remoteImageUrl,
        source: source,
        sourceProductId: sourceProductId,
        suggestedPriceCentavos: suggestedPriceCentavos,
      );
      return RemoteCatalogProduct(
        catalogProductId: catalogProductId,
        metadata: metadata,
        updatedAt: updatedAt.toUtc(),
      );
    } on ArgumentError {
      throw _invalidResponse('The product contains invalid catalog fields.');
    }
  }

  Map<String, Object?> _decodeObject(String body) {
    try {
      final value = jsonDecode(body);
      if (value is Map<String, Object?>) return value;
    } on FormatException {
      // Report the same stable error for invalid JSON and non-object JSON.
    }
    throw _invalidResponse('The catalog returned invalid JSON.');
  }

  String _requiredString(
    Map<String, Object?> payload,
    String key, {
    required int maximumLength,
  }) {
    final value = payload[key];
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty && trimmed.length <= maximumLength) return trimmed;
    }
    throw _invalidResponse('The catalog field "$key" is missing or invalid.');
  }

  String? _optionalString(
    Map<String, Object?> payload,
    String key, {
    required int maximumLength,
  }) {
    final value = payload[key];
    if (value == null) return null;
    if (value is! String) {
      throw _invalidResponse('The catalog field "$key" is invalid.');
    }
    final trimmed = value.trim();
    if (trimmed.length > maximumLength) {
      throw _invalidResponse('The catalog field "$key" is too long.');
    }
    return trimmed.isEmpty ? null : trimmed;
  }

  int? _optionalPositiveInt(Map<String, Object?> payload, String key) {
    final value = payload[key];
    if (value == null) return null;
    if (value is int && value > 0) return value;
    throw _invalidResponse('The catalog field "$key" is invalid.');
  }

  CatalogApiException _statusException(_ApiResponse response) {
    final message = _serverMessage(response.body);
    final status = response.statusCode;
    if (status == 400) {
      return CatalogApiException(
        CatalogApiFailureKind.invalidRequest,
        message ?? 'The catalog rejected this request.',
        statusCode: status,
      );
    }
    if (status == 409) {
      return CatalogApiException(
        CatalogApiFailureKind.conflict,
        message ?? 'The barcode matches more than one catalog product.',
        statusCode: status,
      );
    }
    return CatalogApiException(
      CatalogApiFailureKind.server,
      status >= 500
          ? 'The shared catalog is temporarily unavailable.'
          : message ?? 'The catalog request failed.',
      statusCode: status,
    );
  }

  String? _serverMessage(String body) {
    if (body.length > 4096) return null;
    try {
      final value = jsonDecode(body);
      if (value is Map<String, Object?>) {
        final message = value['error'] ?? value['detail'];
        if (message is String && message.trim().isNotEmpty) {
          return message.trim();
        }
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  CatalogApiException _invalidResponse(String message) =>
      CatalogApiException(CatalogApiFailureKind.invalidResponse, message);
}

final RegExp _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
);

final class _ApiResponse {
  const _ApiResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}

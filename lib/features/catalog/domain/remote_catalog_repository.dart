import 'remote_catalog_product.dart';

enum CatalogApiFailureKind {
  notConfigured,
  timeout,
  network,
  invalidRequest,
  conflict,
  server,
  invalidResponse,
}

final class CatalogApiException implements Exception {
  const CatalogApiException(this.kind, this.message, {this.statusCode});

  final CatalogApiFailureKind kind;
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

abstract interface class RemoteCatalogRepository {
  bool get isConfigured;

  Uri? get baseUri;

  String? get configurationError;

  Future<RemoteCatalogProduct?> findByBarcode(String barcode);

  Future<RemoteCatalogPage> searchProducts({String query = '', int page = 1});

  Future<List<String>> fetchCategories();

  Future<CatalogApiHealth> checkHealth();
}

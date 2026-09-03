import 'package:flutter/foundation.dart';

const String razeStoreApiBaseUrlDefine = 'RAZE_STORE_API_BASE_URL';

/// Validated connection settings for the shared Raze product catalog.
///
/// Debug builds default to the API running on the development computer. A
/// release build stays offline unless an HTTPS endpoint is supplied with
/// `--dart-define=RAZE_STORE_API_BASE_URL=https://…/api/v1/`.
final class RazeApiConfig {
  const RazeApiConfig._({this.baseUri, this.error});

  factory RazeApiConfig.fromEnvironment() {
    const configured = String.fromEnvironment(razeStoreApiBaseUrlDefine);
    if (configured.trim().isNotEmpty) {
      return RazeApiConfig.fromValue(configured, allowInsecureHttp: kDebugMode);
    }
    if (!kDebugMode) return const RazeApiConfig._();

    final host = defaultTargetPlatform == TargetPlatform.android
        ? '10.0.2.2'
        : '127.0.0.1';
    return RazeApiConfig.fromValue(
      'http://$host:8000/api/v1/',
      allowInsecureHttp: true,
    );
  }

  factory RazeApiConfig.fromValue(
    String rawValue, {
    bool allowInsecureHttp = false,
  }) {
    final value = rawValue.trim();
    if (value.isEmpty) return const RazeApiConfig._();

    final parsed = Uri.tryParse(value);
    if (parsed == null ||
        !parsed.hasScheme ||
        !parsed.hasAuthority ||
        parsed.host.isEmpty ||
        (parsed.scheme != 'https' && parsed.scheme != 'http')) {
      return const RazeApiConfig._(
        error: 'The catalog API URL must be a complete HTTP or HTTPS URL.',
      );
    }
    if (parsed.userInfo.isNotEmpty || parsed.hasQuery || parsed.hasFragment) {
      return const RazeApiConfig._(
        error:
            'The catalog API URL cannot contain credentials, a query, or a fragment.',
      );
    }
    if (parsed.scheme == 'http' && !allowInsecureHttp) {
      return const RazeApiConfig._(
        error: 'Release builds require an HTTPS catalog API URL.',
      );
    }

    var path = parsed.path;
    if (path.isEmpty || path == '/') {
      path = '/api/v1/';
    } else if (!path.endsWith('/')) {
      path = '$path/';
    }
    return RazeApiConfig._(
      baseUri: parsed.replace(path: path, query: null, fragment: null),
    );
  }

  final Uri? baseUri;
  final String? error;

  bool get isConfigured => baseUri != null;

  Uri endpoint(String relativePath, {Map<String, String>? queryParameters}) {
    final base = baseUri;
    if (base == null) {
      throw StateError(error ?? 'The shared catalog API is not configured.');
    }
    final resolved = base.resolve(relativePath);
    return queryParameters == null
        ? resolved
        : resolved.replace(queryParameters: queryParameters);
  }
}

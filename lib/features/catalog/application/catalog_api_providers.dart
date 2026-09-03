import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/network/raze_api_config.dart';
import '../data/raze_store_api_client.dart';
import '../domain/remote_catalog_repository.dart';

final razeApiConfigProvider = Provider<RazeApiConfig>((ref) {
  return RazeApiConfig.fromEnvironment();
});

final catalogHttpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final remoteCatalogRepositoryProvider = Provider<RemoteCatalogRepository>((
  ref,
) {
  return RazeStoreApiClient(
    config: ref.watch(razeApiConfigProvider),
    client: ref.watch(catalogHttpClientProvider),
  );
});

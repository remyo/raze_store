import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../../../core/storage/product_photo_services.dart';
import '../data/local_cart_repository.dart';
import '../domain/cart.dart';
import '../domain/cart_repository.dart';

final cartRepositoryProvider = Provider<CartRepository>((ref) {
  return LocalCartRepository(
    ref.watch(appDatabaseProvider),
    imageStore: ref.watch(localProductImageStoreProvider),
  );
});

final cartDraftProvider = StreamProvider<CartDraft>((ref) {
  return ref.watch(cartRepositoryProvider).watchDraft();
});

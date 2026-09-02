import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../data/local_cart_repository.dart';
import '../domain/cart.dart';
import '../domain/cart_repository.dart';

final cartRepositoryProvider = Provider<CartRepository>((ref) {
  return LocalCartRepository(ref.watch(appDatabaseProvider));
});

final cartDraftProvider = StreamProvider<CartDraft>((ref) {
  return ref.watch(cartRepositoryProvider).watchDraft();
});

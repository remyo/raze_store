import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../data/local_settings_repository.dart';
import '../domain/settings_repository.dart';
import '../domain/store_profile.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return LocalSettingsRepository(ref.watch(appDatabaseProvider));
});

final storeProfileProvider = StreamProvider<StoreProfile>((ref) {
  return ref.watch(settingsRepositoryProvider).watchStoreProfile();
});

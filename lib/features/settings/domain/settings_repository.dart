import 'store_profile.dart';

abstract interface class SettingsRepository {
  Stream<StoreProfile> watchStoreProfile();

  Future<StoreProfile> getStoreProfile();

  Future<void> saveStoreProfile(StoreProfile profile);

  Future<void> resetStoreProfile();
}

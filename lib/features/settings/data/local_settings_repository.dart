import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart' as database;
import '../domain/settings_repository.dart';
import '../domain/store_profile.dart';

final class LocalSettingsRepository implements SettingsRepository {
  LocalSettingsRepository(this._database, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  static const _profileId = 1;

  final database.AppDatabase _database;
  final DateTime Function() _now;

  @override
  Stream<StoreProfile> watchStoreProfile() {
    final statement = _database.select(_database.storeProfiles)
      ..where((table) => table.id.equals(_profileId));
    return statement.watchSingleOrNull().map(_mapRow);
  }

  @override
  Future<StoreProfile> getStoreProfile() async {
    final row = await (_database.select(
      _database.storeProfiles,
    )..where((table) => table.id.equals(_profileId))).getSingleOrNull();
    return _mapRow(row);
  }

  @override
  Future<void> saveStoreProfile(StoreProfile profile) async {
    final storeName = profile.storeName.trim();
    if (storeName.isEmpty) {
      throw ArgumentError.value(
        profile.storeName,
        'profile.storeName',
        'Must not be blank.',
      );
    }
    await _database
        .into(_database.storeProfiles)
        .insertOnConflictUpdate(
          database.StoreProfilesCompanion.insert(
            id: const Value(_profileId),
            storeName: Value(storeName),
            address: Value(profile.address.trim()),
            contact: Value(profile.contact.trim()),
            receiptFooter: Value(profile.receiptFooter.trim()),
            updatedAt: Value(_now().toUtc()),
          ),
        );
  }

  @override
  Future<void> resetStoreProfile() => saveStoreProfile(StoreProfile.defaults);

  StoreProfile _mapRow(database.StoreProfile? row) {
    if (row == null) return StoreProfile.defaults;
    return StoreProfile(
      storeName: row.storeName,
      address: row.address,
      contact: row.contact,
      receiptFooter: row.receiptFooter,
    );
  }
}

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/core/database/app_database.dart' show AppDatabase;
import 'package:raze_store/features/settings/data/local_settings_repository.dart';
import 'package:raze_store/features/settings/domain/store_profile.dart';

void main() {
  late AppDatabase database;
  late LocalSettingsRepository repository;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = LocalSettingsRepository(
      database,
      now: () => DateTime.utc(2026, 9, 2),
    );
  });

  tearDown(() => database.close());

  test('provides receipt-ready defaults', () async {
    final profile = await repository.getStoreProfile();

    expect(profile.storeName, 'Raze Store');
    expect(profile.receiptFooter, 'Salamat po!');
  });

  test('saves and watches the store receipt profile', () async {
    await repository.saveStoreProfile(
      const StoreProfile(
        storeName: '  Aling Nena Store  ',
        address: '  Quezon City  ',
        contact: '  0917 000 0000  ',
        receiptFooter: '  Maraming salamat!  ',
      ),
    );

    final profile = await repository.watchStoreProfile().first;
    expect(profile.storeName, 'Aling Nena Store');
    expect(profile.address, 'Quezon City');
    expect(profile.contact, '0917 000 0000');
    expect(profile.receiptFooter, 'Maraming salamat!');
  });
}

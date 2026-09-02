import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [StoreProducts, DraftCartItems, StoreProfiles])
class AppDatabase extends _$AppDatabase {
  AppDatabase({String name = 'raze_store'}) : super(driftDatabase(name: name));

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
      await into(storeProfiles).insert(
        StoreProfilesCompanion.insert(),
        mode: InsertMode.insertOrIgnore,
      );
    },
  );
}

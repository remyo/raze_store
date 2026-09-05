import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:raze_store/core/database/app_database.dart';
import 'package:raze_store/core/database/database_provider.dart';
import 'gcash_record.dart';

final gcashRepositoryProvider = Provider(
  (ref) => GcashRepository(ref.watch(appDatabaseProvider)),
);

class DuplicateGcashReference implements Exception {}

class GcashRepository {
  GcashRepository(this.database);
  final AppDatabase database;

  Stream<({int cashIn, int cashOut, int fees})> totals({
    DateTime? since,
    DateTime? until,
    GcashKind? kind,
  }) {
    final conditions = <String>[];
    final variables = <Variable>[];
    if (since != null) {
      conditions.add('occurred_at >= ?');
      variables.add(Variable(since.millisecondsSinceEpoch ~/ 1000));
    }
    if (until != null) {
      conditions.add('occurred_at < ?');
      variables.add(Variable(until.millisecondsSinceEpoch ~/ 1000));
    }
    if (kind != null) {
      conditions.add("json_extract(payload, '\$.kind') = ?");
      variables.add(Variable(kind.name));
    }
    return database
        .customSelect(
          '''
      SELECT COALESCE(SUM(CASE WHEN json_extract(payload, '\$.kind') = 'cashIn' THEN json_extract(payload, '\$.amount') ELSE 0 END), 0) AS cash_in,
        COALESCE(SUM(CASE WHEN json_extract(payload, '\$.kind') = 'cashOut' THEN json_extract(payload, '\$.amount') ELSE 0 END), 0) AS cash_out,
        COALESCE(SUM(json_extract(payload, '\$.fee')), 0) AS fees
      FROM gcash_entries ${conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}'}
    ''',
          variables: variables,
          readsFrom: {database.gcashEntries},
        )
        .watchSingle()
        .map(
          (row) => (
            cashIn: row.read<int>('cash_in'),
            cashOut: row.read<int>('cash_out'),
            fees: row.read<int>('fees'),
          ),
        );
  }

  Stream<List<GcashRecord>> watch({
    DateTime? since,
    DateTime? until,
    GcashKind? kind,
    int limit = 40,
  }) {
    final query = database.select(database.gcashEntries);
    if (since != null) {
      query.where((row) => row.occurredAt.isBiggerOrEqualValue(since));
    }
    if (until != null) {
      query.where((row) => row.occurredAt.isSmallerThanValue(until));
    }
    if (kind != null) {
      query.where((row) => row.payload.like('%"kind":"${kind.name}"%'));
    }
    query.orderBy([
      (row) => OrderingTerm.desc(row.occurredAt),
      (row) => OrderingTerm.asc(row.id),
    ]);
    query.limit(limit);
    return query.watch().map(
      (rows) => rows
          .map(
            (row) => GcashRecord.fromJson(
              jsonDecode(row.payload) as Map<String, dynamic>,
              receipt: row.receipt,
            ),
          )
          .toList(),
    );
  }

  Future<void> save(GcashRecord record) async {
    record.validate();
    await database.transaction(() async {
      final reference = normalizeGcashReference(record.reference);
      final duplicate =
          await (database.select(database.gcashEntries)..where(
                (row) =>
                    row.reference.equals(reference) &
                    row.id.equals(record.id).not(),
              ))
              .getSingleOrNull();
      if (duplicate != null) throw DuplicateGcashReference();
      await database
          .into(database.gcashEntries)
          .insertOnConflictUpdate(
            GcashEntriesCompanion.insert(
              id: record.id,
              reference: reference,
              payload: jsonEncode(record.toJson()),
              occurredAt: record.date,
              receipt: Value(record.receipt),
            ),
          );
    });
  }

  Future<void> delete(String id) => (database.delete(
    database.gcashEntries,
  )..where((row) => row.id.equals(id))).go();
}

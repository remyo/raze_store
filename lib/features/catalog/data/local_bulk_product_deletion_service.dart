import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart' as database;
import '../../../core/storage/local_product_image_store.dart';
import '../domain/bulk_product_deletion.dart';

/// Removes selected products and their unfinished-cart references atomically.
///
/// SQLite builds commonly cap one statement at 999 bound variables, so large
/// selections are split into conservative chunks while staying inside one
/// database transaction.
final class LocalBulkProductDeletionService
    implements BulkProductDeletionService {
  LocalBulkProductDeletionService(this._database, this._imageStore);

  static const _queryChunkSize = 400;

  final database.AppDatabase _database;
  final LocalProductImageStore _imageStore;

  @override
  Future<BulkProductDeletionResult> deleteProducts(
    Iterable<String> productIds,
  ) async {
    final requestedIds = productIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (requestedIds.isEmpty) {
      return const BulkProductDeletionResult.empty();
    }

    late List<database.StoreProduct> productsToDelete;
    late int removedCartRows;
    late Set<String> unreferencedImagePaths;

    await _database.transaction(() async {
      productsToDelete = <database.StoreProduct>[];
      for (final ids in _chunks(requestedIds)) {
        productsToDelete.addAll(
          await (_database.select(
            _database.storeProducts,
          )..where((table) => table.id.isIn(ids))).get(),
        );
      }

      final existingIds = productsToDelete
          .map((product) => product.id)
          .toList(growable: false);
      if (existingIds.isEmpty) {
        removedCartRows = 0;
        unreferencedImagePaths = <String>{};
        return;
      }

      removedCartRows = 0;
      for (final ids in _chunks(existingIds)) {
        removedCartRows += await (_database.delete(
          _database.draftCartItems,
        )..where((table) => table.productId.isIn(ids))).go();
        await (_database.delete(
          _database.productSellingUnits,
        )..where((table) => table.productId.isIn(ids))).go();
        await (_database.delete(
          _database.storeProducts,
        )..where((table) => table.id.isIn(ids))).go();
      }

      final undoImagePaths = <String>{};
      final undoEntries = await _database
          .select(_database.catalogImportUndoProducts)
          .get();
      for (final entry in undoEntries) {
        for (final encoded in [entry.beforeJson, entry.afterJson]) {
          if (encoded == null) continue;
          try {
            final decoded = jsonDecode(encoded);
            if (decoded is! Map) continue;
            for (final key in ['localImagePath', 'catalogImagePath']) {
              final value = decoded[key];
              if (value is! String) continue;
              final path = _usablePath(value);
              if (path != null) undoImagePaths.add(path);
            }
          } catch (_) {
            // A malformed internal checkpoint is cleared below and must not
            // block the explicitly confirmed product deletion.
          }
        }
      }

      // A catalog mutation outside the importer makes its one-level before/
      // after checkpoint unsafe to replay. Clear it in this same transaction
      // so a later undo can never resurrect deliberately deleted products.
      await _database.delete(_database.catalogImportUndoProducts).go();
      await _database.delete(_database.catalogImportUndoBatches).go();

      final imagePaths = <String>{
        for (final product in productsToDelete)
          ?_usablePath(product.localImagePath),
        for (final product in productsToDelete)
          ?_usablePath(product.catalogImagePath),
        ...undoImagePaths,
      };
      final stillReferenced = await _findReferencedImages(imagePaths);
      unreferencedImagePaths = imagePaths.difference(stillReferenced);
    });

    var cleanedImages = 0;
    var imageCleanupFailures = 0;
    for (final path in unreferencedImagePaths) {
      try {
        final managedPath = await _imageStore.resolveManagedPath(path);
        if (managedPath == null) continue;
        await _imageStore.deleteIfManaged(managedPath);
        cleanedImages += 1;
      } catch (_) {
        // Catalog deletion is already complete. A leftover managed image is
        // safer than rolling back valid data changes or deleting another row.
        imageCleanupFailures += 1;
      }
    }

    return BulkProductDeletionResult(
      deletedProductCount: productsToDelete.length,
      removedCartRowCount: removedCartRows,
      cleanedImageCount: cleanedImages,
      imageCleanupFailureCount: imageCleanupFailures,
    );
  }

  Future<Set<String>> _findReferencedImages(Set<String> candidatePaths) async {
    if (candidatePaths.isEmpty) return <String>{};

    final referenced = <String>{};
    final paths = candidatePaths.toList(growable: false);
    for (final chunk in _chunks(paths)) {
      final products =
          await (_database.select(_database.storeProducts)..where(
                (table) =>
                    table.localImagePath.isIn(chunk) |
                    table.catalogImagePath.isIn(chunk),
              ))
              .get();
      for (final product in products) {
        _addCandidate(referenced, candidatePaths, product.localImagePath);
        _addCandidate(referenced, candidatePaths, product.catalogImagePath);
      }

      final cartRows = await (_database.select(
        _database.draftCartItems,
      )..where((table) => table.imagePathSnapshot.isIn(chunk))).get();
      for (final row in cartRows) {
        _addCandidate(referenced, candidatePaths, row.imagePathSnapshot);
      }

      // Sale lines are immutable receipt snapshots and have no catalog foreign
      // key. Keeping their referenced image prevents an old receipt from losing
      // its photo when the original product is removed.
      final saleLines = await (_database.select(
        _database.saleLines,
      )..where((table) => table.imagePathSnapshot.isIn(chunk))).get();
      for (final line in saleLines) {
        _addCandidate(referenced, candidatePaths, line.imagePathSnapshot);
      }
    }
    return referenced;
  }

  static void _addCandidate(
    Set<String> output,
    Set<String> candidates,
    String? rawPath,
  ) {
    final path = _usablePath(rawPath);
    if (path != null && candidates.contains(path)) output.add(path);
  }

  static String? _usablePath(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static Iterable<List<T>> _chunks<T>(List<T> values) sync* {
    for (var start = 0; start < values.length; start += _queryChunkSize) {
      final end = (start + _queryChunkSize).clamp(0, values.length);
      yield values.sublist(start, end);
    }
  }
}

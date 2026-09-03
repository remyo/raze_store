import 'package:drift/drift.dart';

@TableIndex(
  name: 'store_products_barcode_unique_idx',
  columns: {#barcode},
  unique: true,
)
@TableIndex(name: 'store_products_name_idx', columns: {#name})
@TableIndex(
  name: 'store_products_source_identity_unique_idx',
  columns: {#source, #sourceProductId},
  unique: true,
)
class StoreProducts extends Table {
  TextColumn get id => text()();

  /// Canonical barcode used for local lookup. UPC-A values are stored as
  /// zero-prefixed EAN-13 values so either scanner representation will match.
  TextColumn get barcode => text().withLength(min: 1, max: 160).nullable()();

  /// Future API-owned catalog identity. Store price remains local regardless
  /// of whether this metadata came from an API or was entered manually.
  TextColumn get source => text().nullable()();
  TextColumn get sourceProductId => text().nullable()();

  TextColumn get name => text().withLength(min: 1, max: 240)();
  TextColumn get brand => text().nullable()();
  TextColumn get unitLabel => text().nullable()();
  TextColumn get category => text().nullable()();
  TextColumn get remoteImageUrl => text().nullable()();

  /// App-managed image supplied by an offline shared-catalog pack. A store's
  /// own [localImagePath] remains the visual override and is never replaced by
  /// a later catalog pack.
  TextColumn get catalogImagePath => text().nullable()();

  /// Revision timestamp for the shared metadata currently applied to this
  /// row. This prevents an older offline pack from rolling metadata backward.
  DateTimeColumn get sourceUpdatedAt => dateTime().nullable()();

  /// A device-local photo selected by this store. This intentionally remains
  /// separate from the future catalog API image URL.
  TextColumn get localImagePath => text().nullable()();

  /// This store's authoritative selling price, stored as integer centavos.
  IntColumn get priceCentavos =>
      integer().check(const CustomExpression<bool>('price_centavos >= 0'))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Additional ways a store can sell a product whose package owns the barcode.
///
/// For example, a scanned cigarette pack can keep its package price on
/// [StoreProducts], while this table stores a `Stick` price. Sub-units do not
/// have their own barcode because scanning always resolves the parent product.
@TableIndex(
  name: 'product_selling_units_product_position_idx',
  columns: {#productId, #position},
)
class ProductSellingUnits extends Table {
  TextColumn get id => text()();
  TextColumn get productId =>
      text().references(StoreProducts, #id, onDelete: KeyAction.cascade)();
  TextColumn get label => text().withLength(min: 1, max: 80)();
  IntColumn get priceCentavos =>
      integer().check(const CustomExpression<bool>('price_centavos >= 0'))();
  IntColumn get position =>
      integer().check(const CustomExpression<bool>('position >= 0'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// The single unfinished cart draft. A catalog item can be deleted without
/// altering the draft because every receipt-relevant value is snapshotted.
class DraftCartItems extends Table {
  /// Stable identity for a particular product + selling-unit selection.
  /// Existing version-1 rows migrate with a `main:`-prefixed product ID.
  TextColumn get lineId => text()();
  TextColumn get productId => text()();
  TextColumn get sellingUnitId => text().nullable()();
  TextColumn get barcode => text().nullable()();
  TextColumn get nameSnapshot => text()();
  TextColumn get brandSnapshot => text().nullable()();
  TextColumn get unitLabelSnapshot => text().nullable()();
  TextColumn get imagePathSnapshot => text().nullable()();
  IntColumn get unitPriceCentavos => integer().check(
    const CustomExpression<bool>('unit_price_centavos >= 0'),
  )();
  IntColumn get quantity =>
      integer().check(const CustomExpression<bool>('quantity > 0'))();
  DateTimeColumn get addedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {lineId};
}

/// Receipt identity for this device/store. There is exactly one row (id = 1).
class StoreProfiles extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();
  TextColumn get storeName =>
      text().withDefault(const Constant('Raze Store'))();
  TextColumn get address => text().withDefault(const Constant(''))();
  TextColumn get contact => text().withDefault(const Constant(''))();
  TextColumn get receiptFooter =>
      text().withDefault(const Constant('Salamat po!'))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

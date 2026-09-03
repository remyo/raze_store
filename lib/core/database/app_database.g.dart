// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $StoreProductsTable extends StoreProducts
    with TableInfo<$StoreProductsTable, StoreProduct> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StoreProductsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _barcodeMeta = const VerificationMeta(
    'barcode',
  );
  @override
  late final GeneratedColumn<String> barcode = GeneratedColumn<String>(
    'barcode',
    aliasedName,
    true,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 160,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceProductIdMeta = const VerificationMeta(
    'sourceProductId',
  );
  @override
  late final GeneratedColumn<String> sourceProductId = GeneratedColumn<String>(
    'source_product_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 240,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _brandMeta = const VerificationMeta('brand');
  @override
  late final GeneratedColumn<String> brand = GeneratedColumn<String>(
    'brand',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _unitLabelMeta = const VerificationMeta(
    'unitLabel',
  );
  @override
  late final GeneratedColumn<String> unitLabel = GeneratedColumn<String>(
    'unit_label',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _categoryMeta = const VerificationMeta(
    'category',
  );
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
    'category',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _remoteImageUrlMeta = const VerificationMeta(
    'remoteImageUrl',
  );
  @override
  late final GeneratedColumn<String> remoteImageUrl = GeneratedColumn<String>(
    'remote_image_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _catalogImagePathMeta = const VerificationMeta(
    'catalogImagePath',
  );
  @override
  late final GeneratedColumn<String> catalogImagePath = GeneratedColumn<String>(
    'catalog_image_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceUpdatedAtMeta = const VerificationMeta(
    'sourceUpdatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> sourceUpdatedAt =
      GeneratedColumn<DateTime>(
        'source_updated_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _localImagePathMeta = const VerificationMeta(
    'localImagePath',
  );
  @override
  late final GeneratedColumn<String> localImagePath = GeneratedColumn<String>(
    'local_image_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _priceCentavosMeta = const VerificationMeta(
    'priceCentavos',
  );
  @override
  late final GeneratedColumn<int> priceCentavos = GeneratedColumn<int>(
    'price_centavos',
    aliasedName,
    false,
    check: () => const CustomExpression<bool>('price_centavos >= 0'),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    barcode,
    source,
    sourceProductId,
    name,
    brand,
    unitLabel,
    category,
    remoteImageUrl,
    catalogImagePath,
    sourceUpdatedAt,
    localImagePath,
    priceCentavos,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'store_products';
  @override
  VerificationContext validateIntegrity(
    Insertable<StoreProduct> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('barcode')) {
      context.handle(
        _barcodeMeta,
        barcode.isAcceptableOrUnknown(data['barcode']!, _barcodeMeta),
      );
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    }
    if (data.containsKey('source_product_id')) {
      context.handle(
        _sourceProductIdMeta,
        sourceProductId.isAcceptableOrUnknown(
          data['source_product_id']!,
          _sourceProductIdMeta,
        ),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('brand')) {
      context.handle(
        _brandMeta,
        brand.isAcceptableOrUnknown(data['brand']!, _brandMeta),
      );
    }
    if (data.containsKey('unit_label')) {
      context.handle(
        _unitLabelMeta,
        unitLabel.isAcceptableOrUnknown(data['unit_label']!, _unitLabelMeta),
      );
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    }
    if (data.containsKey('remote_image_url')) {
      context.handle(
        _remoteImageUrlMeta,
        remoteImageUrl.isAcceptableOrUnknown(
          data['remote_image_url']!,
          _remoteImageUrlMeta,
        ),
      );
    }
    if (data.containsKey('catalog_image_path')) {
      context.handle(
        _catalogImagePathMeta,
        catalogImagePath.isAcceptableOrUnknown(
          data['catalog_image_path']!,
          _catalogImagePathMeta,
        ),
      );
    }
    if (data.containsKey('source_updated_at')) {
      context.handle(
        _sourceUpdatedAtMeta,
        sourceUpdatedAt.isAcceptableOrUnknown(
          data['source_updated_at']!,
          _sourceUpdatedAtMeta,
        ),
      );
    }
    if (data.containsKey('local_image_path')) {
      context.handle(
        _localImagePathMeta,
        localImagePath.isAcceptableOrUnknown(
          data['local_image_path']!,
          _localImagePathMeta,
        ),
      );
    }
    if (data.containsKey('price_centavos')) {
      context.handle(
        _priceCentavosMeta,
        priceCentavos.isAcceptableOrUnknown(
          data['price_centavos']!,
          _priceCentavosMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_priceCentavosMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  StoreProduct map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoreProduct(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      barcode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}barcode'],
      ),
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      ),
      sourceProductId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_product_id'],
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      brand: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}brand'],
      ),
      unitLabel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}unit_label'],
      ),
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      ),
      remoteImageUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}remote_image_url'],
      ),
      catalogImagePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}catalog_image_path'],
      ),
      sourceUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}source_updated_at'],
      ),
      localImagePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_image_path'],
      ),
      priceCentavos: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}price_centavos'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $StoreProductsTable createAlias(String alias) {
    return $StoreProductsTable(attachedDatabase, alias);
  }
}

class StoreProduct extends DataClass implements Insertable<StoreProduct> {
  final String id;

  /// Canonical barcode used for local lookup. UPC-A values are stored as
  /// zero-prefixed EAN-13 values so either scanner representation will match.
  final String? barcode;

  /// Future API-owned catalog identity. Store price remains local regardless
  /// of whether this metadata came from an API or was entered manually.
  final String? source;
  final String? sourceProductId;
  final String name;
  final String? brand;
  final String? unitLabel;
  final String? category;
  final String? remoteImageUrl;

  /// App-managed image supplied by an offline shared-catalog pack. A store's
  /// own [localImagePath] remains the visual override and is never replaced by
  /// a later catalog pack.
  final String? catalogImagePath;

  /// Revision timestamp for the shared metadata currently applied to this
  /// row. This prevents an older offline pack from rolling metadata backward.
  final DateTime? sourceUpdatedAt;

  /// A device-local photo selected by this store. This intentionally remains
  /// separate from the future catalog API image URL.
  final String? localImagePath;

  /// This store's authoritative selling price, stored as integer centavos.
  final int priceCentavos;
  final DateTime createdAt;
  final DateTime updatedAt;
  const StoreProduct({
    required this.id,
    this.barcode,
    this.source,
    this.sourceProductId,
    required this.name,
    this.brand,
    this.unitLabel,
    this.category,
    this.remoteImageUrl,
    this.catalogImagePath,
    this.sourceUpdatedAt,
    this.localImagePath,
    required this.priceCentavos,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || barcode != null) {
      map['barcode'] = Variable<String>(barcode);
    }
    if (!nullToAbsent || source != null) {
      map['source'] = Variable<String>(source);
    }
    if (!nullToAbsent || sourceProductId != null) {
      map['source_product_id'] = Variable<String>(sourceProductId);
    }
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || brand != null) {
      map['brand'] = Variable<String>(brand);
    }
    if (!nullToAbsent || unitLabel != null) {
      map['unit_label'] = Variable<String>(unitLabel);
    }
    if (!nullToAbsent || category != null) {
      map['category'] = Variable<String>(category);
    }
    if (!nullToAbsent || remoteImageUrl != null) {
      map['remote_image_url'] = Variable<String>(remoteImageUrl);
    }
    if (!nullToAbsent || catalogImagePath != null) {
      map['catalog_image_path'] = Variable<String>(catalogImagePath);
    }
    if (!nullToAbsent || sourceUpdatedAt != null) {
      map['source_updated_at'] = Variable<DateTime>(sourceUpdatedAt);
    }
    if (!nullToAbsent || localImagePath != null) {
      map['local_image_path'] = Variable<String>(localImagePath);
    }
    map['price_centavos'] = Variable<int>(priceCentavos);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  StoreProductsCompanion toCompanion(bool nullToAbsent) {
    return StoreProductsCompanion(
      id: Value(id),
      barcode: barcode == null && nullToAbsent
          ? const Value.absent()
          : Value(barcode),
      source: source == null && nullToAbsent
          ? const Value.absent()
          : Value(source),
      sourceProductId: sourceProductId == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceProductId),
      name: Value(name),
      brand: brand == null && nullToAbsent
          ? const Value.absent()
          : Value(brand),
      unitLabel: unitLabel == null && nullToAbsent
          ? const Value.absent()
          : Value(unitLabel),
      category: category == null && nullToAbsent
          ? const Value.absent()
          : Value(category),
      remoteImageUrl: remoteImageUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(remoteImageUrl),
      catalogImagePath: catalogImagePath == null && nullToAbsent
          ? const Value.absent()
          : Value(catalogImagePath),
      sourceUpdatedAt: sourceUpdatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceUpdatedAt),
      localImagePath: localImagePath == null && nullToAbsent
          ? const Value.absent()
          : Value(localImagePath),
      priceCentavos: Value(priceCentavos),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory StoreProduct.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoreProduct(
      id: serializer.fromJson<String>(json['id']),
      barcode: serializer.fromJson<String?>(json['barcode']),
      source: serializer.fromJson<String?>(json['source']),
      sourceProductId: serializer.fromJson<String?>(json['sourceProductId']),
      name: serializer.fromJson<String>(json['name']),
      brand: serializer.fromJson<String?>(json['brand']),
      unitLabel: serializer.fromJson<String?>(json['unitLabel']),
      category: serializer.fromJson<String?>(json['category']),
      remoteImageUrl: serializer.fromJson<String?>(json['remoteImageUrl']),
      catalogImagePath: serializer.fromJson<String?>(json['catalogImagePath']),
      sourceUpdatedAt: serializer.fromJson<DateTime?>(json['sourceUpdatedAt']),
      localImagePath: serializer.fromJson<String?>(json['localImagePath']),
      priceCentavos: serializer.fromJson<int>(json['priceCentavos']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'barcode': serializer.toJson<String?>(barcode),
      'source': serializer.toJson<String?>(source),
      'sourceProductId': serializer.toJson<String?>(sourceProductId),
      'name': serializer.toJson<String>(name),
      'brand': serializer.toJson<String?>(brand),
      'unitLabel': serializer.toJson<String?>(unitLabel),
      'category': serializer.toJson<String?>(category),
      'remoteImageUrl': serializer.toJson<String?>(remoteImageUrl),
      'catalogImagePath': serializer.toJson<String?>(catalogImagePath),
      'sourceUpdatedAt': serializer.toJson<DateTime?>(sourceUpdatedAt),
      'localImagePath': serializer.toJson<String?>(localImagePath),
      'priceCentavos': serializer.toJson<int>(priceCentavos),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  StoreProduct copyWith({
    String? id,
    Value<String?> barcode = const Value.absent(),
    Value<String?> source = const Value.absent(),
    Value<String?> sourceProductId = const Value.absent(),
    String? name,
    Value<String?> brand = const Value.absent(),
    Value<String?> unitLabel = const Value.absent(),
    Value<String?> category = const Value.absent(),
    Value<String?> remoteImageUrl = const Value.absent(),
    Value<String?> catalogImagePath = const Value.absent(),
    Value<DateTime?> sourceUpdatedAt = const Value.absent(),
    Value<String?> localImagePath = const Value.absent(),
    int? priceCentavos,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => StoreProduct(
    id: id ?? this.id,
    barcode: barcode.present ? barcode.value : this.barcode,
    source: source.present ? source.value : this.source,
    sourceProductId: sourceProductId.present
        ? sourceProductId.value
        : this.sourceProductId,
    name: name ?? this.name,
    brand: brand.present ? brand.value : this.brand,
    unitLabel: unitLabel.present ? unitLabel.value : this.unitLabel,
    category: category.present ? category.value : this.category,
    remoteImageUrl: remoteImageUrl.present
        ? remoteImageUrl.value
        : this.remoteImageUrl,
    catalogImagePath: catalogImagePath.present
        ? catalogImagePath.value
        : this.catalogImagePath,
    sourceUpdatedAt: sourceUpdatedAt.present
        ? sourceUpdatedAt.value
        : this.sourceUpdatedAt,
    localImagePath: localImagePath.present
        ? localImagePath.value
        : this.localImagePath,
    priceCentavos: priceCentavos ?? this.priceCentavos,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  StoreProduct copyWithCompanion(StoreProductsCompanion data) {
    return StoreProduct(
      id: data.id.present ? data.id.value : this.id,
      barcode: data.barcode.present ? data.barcode.value : this.barcode,
      source: data.source.present ? data.source.value : this.source,
      sourceProductId: data.sourceProductId.present
          ? data.sourceProductId.value
          : this.sourceProductId,
      name: data.name.present ? data.name.value : this.name,
      brand: data.brand.present ? data.brand.value : this.brand,
      unitLabel: data.unitLabel.present ? data.unitLabel.value : this.unitLabel,
      category: data.category.present ? data.category.value : this.category,
      remoteImageUrl: data.remoteImageUrl.present
          ? data.remoteImageUrl.value
          : this.remoteImageUrl,
      catalogImagePath: data.catalogImagePath.present
          ? data.catalogImagePath.value
          : this.catalogImagePath,
      sourceUpdatedAt: data.sourceUpdatedAt.present
          ? data.sourceUpdatedAt.value
          : this.sourceUpdatedAt,
      localImagePath: data.localImagePath.present
          ? data.localImagePath.value
          : this.localImagePath,
      priceCentavos: data.priceCentavos.present
          ? data.priceCentavos.value
          : this.priceCentavos,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoreProduct(')
          ..write('id: $id, ')
          ..write('barcode: $barcode, ')
          ..write('source: $source, ')
          ..write('sourceProductId: $sourceProductId, ')
          ..write('name: $name, ')
          ..write('brand: $brand, ')
          ..write('unitLabel: $unitLabel, ')
          ..write('category: $category, ')
          ..write('remoteImageUrl: $remoteImageUrl, ')
          ..write('catalogImagePath: $catalogImagePath, ')
          ..write('sourceUpdatedAt: $sourceUpdatedAt, ')
          ..write('localImagePath: $localImagePath, ')
          ..write('priceCentavos: $priceCentavos, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    barcode,
    source,
    sourceProductId,
    name,
    brand,
    unitLabel,
    category,
    remoteImageUrl,
    catalogImagePath,
    sourceUpdatedAt,
    localImagePath,
    priceCentavos,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoreProduct &&
          other.id == this.id &&
          other.barcode == this.barcode &&
          other.source == this.source &&
          other.sourceProductId == this.sourceProductId &&
          other.name == this.name &&
          other.brand == this.brand &&
          other.unitLabel == this.unitLabel &&
          other.category == this.category &&
          other.remoteImageUrl == this.remoteImageUrl &&
          other.catalogImagePath == this.catalogImagePath &&
          other.sourceUpdatedAt == this.sourceUpdatedAt &&
          other.localImagePath == this.localImagePath &&
          other.priceCentavos == this.priceCentavos &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class StoreProductsCompanion extends UpdateCompanion<StoreProduct> {
  final Value<String> id;
  final Value<String?> barcode;
  final Value<String?> source;
  final Value<String?> sourceProductId;
  final Value<String> name;
  final Value<String?> brand;
  final Value<String?> unitLabel;
  final Value<String?> category;
  final Value<String?> remoteImageUrl;
  final Value<String?> catalogImagePath;
  final Value<DateTime?> sourceUpdatedAt;
  final Value<String?> localImagePath;
  final Value<int> priceCentavos;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const StoreProductsCompanion({
    this.id = const Value.absent(),
    this.barcode = const Value.absent(),
    this.source = const Value.absent(),
    this.sourceProductId = const Value.absent(),
    this.name = const Value.absent(),
    this.brand = const Value.absent(),
    this.unitLabel = const Value.absent(),
    this.category = const Value.absent(),
    this.remoteImageUrl = const Value.absent(),
    this.catalogImagePath = const Value.absent(),
    this.sourceUpdatedAt = const Value.absent(),
    this.localImagePath = const Value.absent(),
    this.priceCentavos = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StoreProductsCompanion.insert({
    required String id,
    this.barcode = const Value.absent(),
    this.source = const Value.absent(),
    this.sourceProductId = const Value.absent(),
    required String name,
    this.brand = const Value.absent(),
    this.unitLabel = const Value.absent(),
    this.category = const Value.absent(),
    this.remoteImageUrl = const Value.absent(),
    this.catalogImagePath = const Value.absent(),
    this.sourceUpdatedAt = const Value.absent(),
    this.localImagePath = const Value.absent(),
    required int priceCentavos,
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       priceCentavos = Value(priceCentavos);
  static Insertable<StoreProduct> custom({
    Expression<String>? id,
    Expression<String>? barcode,
    Expression<String>? source,
    Expression<String>? sourceProductId,
    Expression<String>? name,
    Expression<String>? brand,
    Expression<String>? unitLabel,
    Expression<String>? category,
    Expression<String>? remoteImageUrl,
    Expression<String>? catalogImagePath,
    Expression<DateTime>? sourceUpdatedAt,
    Expression<String>? localImagePath,
    Expression<int>? priceCentavos,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (barcode != null) 'barcode': barcode,
      if (source != null) 'source': source,
      if (sourceProductId != null) 'source_product_id': sourceProductId,
      if (name != null) 'name': name,
      if (brand != null) 'brand': brand,
      if (unitLabel != null) 'unit_label': unitLabel,
      if (category != null) 'category': category,
      if (remoteImageUrl != null) 'remote_image_url': remoteImageUrl,
      if (catalogImagePath != null) 'catalog_image_path': catalogImagePath,
      if (sourceUpdatedAt != null) 'source_updated_at': sourceUpdatedAt,
      if (localImagePath != null) 'local_image_path': localImagePath,
      if (priceCentavos != null) 'price_centavos': priceCentavos,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StoreProductsCompanion copyWith({
    Value<String>? id,
    Value<String?>? barcode,
    Value<String?>? source,
    Value<String?>? sourceProductId,
    Value<String>? name,
    Value<String?>? brand,
    Value<String?>? unitLabel,
    Value<String?>? category,
    Value<String?>? remoteImageUrl,
    Value<String?>? catalogImagePath,
    Value<DateTime?>? sourceUpdatedAt,
    Value<String?>? localImagePath,
    Value<int>? priceCentavos,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return StoreProductsCompanion(
      id: id ?? this.id,
      barcode: barcode ?? this.barcode,
      source: source ?? this.source,
      sourceProductId: sourceProductId ?? this.sourceProductId,
      name: name ?? this.name,
      brand: brand ?? this.brand,
      unitLabel: unitLabel ?? this.unitLabel,
      category: category ?? this.category,
      remoteImageUrl: remoteImageUrl ?? this.remoteImageUrl,
      catalogImagePath: catalogImagePath ?? this.catalogImagePath,
      sourceUpdatedAt: sourceUpdatedAt ?? this.sourceUpdatedAt,
      localImagePath: localImagePath ?? this.localImagePath,
      priceCentavos: priceCentavos ?? this.priceCentavos,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (barcode.present) {
      map['barcode'] = Variable<String>(barcode.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (sourceProductId.present) {
      map['source_product_id'] = Variable<String>(sourceProductId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (brand.present) {
      map['brand'] = Variable<String>(brand.value);
    }
    if (unitLabel.present) {
      map['unit_label'] = Variable<String>(unitLabel.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (remoteImageUrl.present) {
      map['remote_image_url'] = Variable<String>(remoteImageUrl.value);
    }
    if (catalogImagePath.present) {
      map['catalog_image_path'] = Variable<String>(catalogImagePath.value);
    }
    if (sourceUpdatedAt.present) {
      map['source_updated_at'] = Variable<DateTime>(sourceUpdatedAt.value);
    }
    if (localImagePath.present) {
      map['local_image_path'] = Variable<String>(localImagePath.value);
    }
    if (priceCentavos.present) {
      map['price_centavos'] = Variable<int>(priceCentavos.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StoreProductsCompanion(')
          ..write('id: $id, ')
          ..write('barcode: $barcode, ')
          ..write('source: $source, ')
          ..write('sourceProductId: $sourceProductId, ')
          ..write('name: $name, ')
          ..write('brand: $brand, ')
          ..write('unitLabel: $unitLabel, ')
          ..write('category: $category, ')
          ..write('remoteImageUrl: $remoteImageUrl, ')
          ..write('catalogImagePath: $catalogImagePath, ')
          ..write('sourceUpdatedAt: $sourceUpdatedAt, ')
          ..write('localImagePath: $localImagePath, ')
          ..write('priceCentavos: $priceCentavos, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProductSellingUnitsTable extends ProductSellingUnits
    with TableInfo<$ProductSellingUnitsTable, ProductSellingUnit> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProductSellingUnitsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _productIdMeta = const VerificationMeta(
    'productId',
  );
  @override
  late final GeneratedColumn<String> productId = GeneratedColumn<String>(
    'product_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES store_products (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 80,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _priceCentavosMeta = const VerificationMeta(
    'priceCentavos',
  );
  @override
  late final GeneratedColumn<int> priceCentavos = GeneratedColumn<int>(
    'price_centavos',
    aliasedName,
    false,
    check: () => const CustomExpression<bool>('price_centavos >= 0'),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    check: () => const CustomExpression<bool>('position >= 0'),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    productId,
    label,
    priceCentavos,
    position,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'product_selling_units';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProductSellingUnit> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('product_id')) {
      context.handle(
        _productIdMeta,
        productId.isAcceptableOrUnknown(data['product_id']!, _productIdMeta),
      );
    } else if (isInserting) {
      context.missing(_productIdMeta);
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    } else if (isInserting) {
      context.missing(_labelMeta);
    }
    if (data.containsKey('price_centavos')) {
      context.handle(
        _priceCentavosMeta,
        priceCentavos.isAcceptableOrUnknown(
          data['price_centavos']!,
          _priceCentavosMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_priceCentavosMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProductSellingUnit map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProductSellingUnit(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      productId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}product_id'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      )!,
      priceCentavos: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}price_centavos'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ProductSellingUnitsTable createAlias(String alias) {
    return $ProductSellingUnitsTable(attachedDatabase, alias);
  }
}

class ProductSellingUnit extends DataClass
    implements Insertable<ProductSellingUnit> {
  final String id;
  final String productId;
  final String label;
  final int priceCentavos;
  final int position;
  final DateTime createdAt;
  final DateTime updatedAt;
  const ProductSellingUnit({
    required this.id,
    required this.productId,
    required this.label,
    required this.priceCentavos,
    required this.position,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['product_id'] = Variable<String>(productId);
    map['label'] = Variable<String>(label);
    map['price_centavos'] = Variable<int>(priceCentavos);
    map['position'] = Variable<int>(position);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ProductSellingUnitsCompanion toCompanion(bool nullToAbsent) {
    return ProductSellingUnitsCompanion(
      id: Value(id),
      productId: Value(productId),
      label: Value(label),
      priceCentavos: Value(priceCentavos),
      position: Value(position),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory ProductSellingUnit.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProductSellingUnit(
      id: serializer.fromJson<String>(json['id']),
      productId: serializer.fromJson<String>(json['productId']),
      label: serializer.fromJson<String>(json['label']),
      priceCentavos: serializer.fromJson<int>(json['priceCentavos']),
      position: serializer.fromJson<int>(json['position']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'productId': serializer.toJson<String>(productId),
      'label': serializer.toJson<String>(label),
      'priceCentavos': serializer.toJson<int>(priceCentavos),
      'position': serializer.toJson<int>(position),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ProductSellingUnit copyWith({
    String? id,
    String? productId,
    String? label,
    int? priceCentavos,
    int? position,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => ProductSellingUnit(
    id: id ?? this.id,
    productId: productId ?? this.productId,
    label: label ?? this.label,
    priceCentavos: priceCentavos ?? this.priceCentavos,
    position: position ?? this.position,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ProductSellingUnit copyWithCompanion(ProductSellingUnitsCompanion data) {
    return ProductSellingUnit(
      id: data.id.present ? data.id.value : this.id,
      productId: data.productId.present ? data.productId.value : this.productId,
      label: data.label.present ? data.label.value : this.label,
      priceCentavos: data.priceCentavos.present
          ? data.priceCentavos.value
          : this.priceCentavos,
      position: data.position.present ? data.position.value : this.position,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProductSellingUnit(')
          ..write('id: $id, ')
          ..write('productId: $productId, ')
          ..write('label: $label, ')
          ..write('priceCentavos: $priceCentavos, ')
          ..write('position: $position, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    productId,
    label,
    priceCentavos,
    position,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProductSellingUnit &&
          other.id == this.id &&
          other.productId == this.productId &&
          other.label == this.label &&
          other.priceCentavos == this.priceCentavos &&
          other.position == this.position &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ProductSellingUnitsCompanion extends UpdateCompanion<ProductSellingUnit> {
  final Value<String> id;
  final Value<String> productId;
  final Value<String> label;
  final Value<int> priceCentavos;
  final Value<int> position;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ProductSellingUnitsCompanion({
    this.id = const Value.absent(),
    this.productId = const Value.absent(),
    this.label = const Value.absent(),
    this.priceCentavos = const Value.absent(),
    this.position = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProductSellingUnitsCompanion.insert({
    required String id,
    required String productId,
    required String label,
    required int priceCentavos,
    required int position,
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       productId = Value(productId),
       label = Value(label),
       priceCentavos = Value(priceCentavos),
       position = Value(position);
  static Insertable<ProductSellingUnit> custom({
    Expression<String>? id,
    Expression<String>? productId,
    Expression<String>? label,
    Expression<int>? priceCentavos,
    Expression<int>? position,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (productId != null) 'product_id': productId,
      if (label != null) 'label': label,
      if (priceCentavos != null) 'price_centavos': priceCentavos,
      if (position != null) 'position': position,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProductSellingUnitsCompanion copyWith({
    Value<String>? id,
    Value<String>? productId,
    Value<String>? label,
    Value<int>? priceCentavos,
    Value<int>? position,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ProductSellingUnitsCompanion(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      label: label ?? this.label,
      priceCentavos: priceCentavos ?? this.priceCentavos,
      position: position ?? this.position,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (productId.present) {
      map['product_id'] = Variable<String>(productId.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (priceCentavos.present) {
      map['price_centavos'] = Variable<int>(priceCentavos.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProductSellingUnitsCompanion(')
          ..write('id: $id, ')
          ..write('productId: $productId, ')
          ..write('label: $label, ')
          ..write('priceCentavos: $priceCentavos, ')
          ..write('position: $position, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DraftCartItemsTable extends DraftCartItems
    with TableInfo<$DraftCartItemsTable, DraftCartItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DraftCartItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _lineIdMeta = const VerificationMeta('lineId');
  @override
  late final GeneratedColumn<String> lineId = GeneratedColumn<String>(
    'line_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _productIdMeta = const VerificationMeta(
    'productId',
  );
  @override
  late final GeneratedColumn<String> productId = GeneratedColumn<String>(
    'product_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sellingUnitIdMeta = const VerificationMeta(
    'sellingUnitId',
  );
  @override
  late final GeneratedColumn<String> sellingUnitId = GeneratedColumn<String>(
    'selling_unit_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _barcodeMeta = const VerificationMeta(
    'barcode',
  );
  @override
  late final GeneratedColumn<String> barcode = GeneratedColumn<String>(
    'barcode',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nameSnapshotMeta = const VerificationMeta(
    'nameSnapshot',
  );
  @override
  late final GeneratedColumn<String> nameSnapshot = GeneratedColumn<String>(
    'name_snapshot',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _brandSnapshotMeta = const VerificationMeta(
    'brandSnapshot',
  );
  @override
  late final GeneratedColumn<String> brandSnapshot = GeneratedColumn<String>(
    'brand_snapshot',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _unitLabelSnapshotMeta = const VerificationMeta(
    'unitLabelSnapshot',
  );
  @override
  late final GeneratedColumn<String> unitLabelSnapshot =
      GeneratedColumn<String>(
        'unit_label_snapshot',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _imagePathSnapshotMeta = const VerificationMeta(
    'imagePathSnapshot',
  );
  @override
  late final GeneratedColumn<String> imagePathSnapshot =
      GeneratedColumn<String>(
        'image_path_snapshot',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _unitPriceCentavosMeta = const VerificationMeta(
    'unitPriceCentavos',
  );
  @override
  late final GeneratedColumn<int> unitPriceCentavos = GeneratedColumn<int>(
    'unit_price_centavos',
    aliasedName,
    false,
    check: () => const CustomExpression<bool>('unit_price_centavos >= 0'),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _quantityMeta = const VerificationMeta(
    'quantity',
  );
  @override
  late final GeneratedColumn<int> quantity = GeneratedColumn<int>(
    'quantity',
    aliasedName,
    false,
    check: () => const CustomExpression<bool>('quantity > 0'),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<DateTime> addedAt = GeneratedColumn<DateTime>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    lineId,
    productId,
    sellingUnitId,
    barcode,
    nameSnapshot,
    brandSnapshot,
    unitLabelSnapshot,
    imagePathSnapshot,
    unitPriceCentavos,
    quantity,
    addedAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'draft_cart_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<DraftCartItem> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('line_id')) {
      context.handle(
        _lineIdMeta,
        lineId.isAcceptableOrUnknown(data['line_id']!, _lineIdMeta),
      );
    } else if (isInserting) {
      context.missing(_lineIdMeta);
    }
    if (data.containsKey('product_id')) {
      context.handle(
        _productIdMeta,
        productId.isAcceptableOrUnknown(data['product_id']!, _productIdMeta),
      );
    } else if (isInserting) {
      context.missing(_productIdMeta);
    }
    if (data.containsKey('selling_unit_id')) {
      context.handle(
        _sellingUnitIdMeta,
        sellingUnitId.isAcceptableOrUnknown(
          data['selling_unit_id']!,
          _sellingUnitIdMeta,
        ),
      );
    }
    if (data.containsKey('barcode')) {
      context.handle(
        _barcodeMeta,
        barcode.isAcceptableOrUnknown(data['barcode']!, _barcodeMeta),
      );
    }
    if (data.containsKey('name_snapshot')) {
      context.handle(
        _nameSnapshotMeta,
        nameSnapshot.isAcceptableOrUnknown(
          data['name_snapshot']!,
          _nameSnapshotMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_nameSnapshotMeta);
    }
    if (data.containsKey('brand_snapshot')) {
      context.handle(
        _brandSnapshotMeta,
        brandSnapshot.isAcceptableOrUnknown(
          data['brand_snapshot']!,
          _brandSnapshotMeta,
        ),
      );
    }
    if (data.containsKey('unit_label_snapshot')) {
      context.handle(
        _unitLabelSnapshotMeta,
        unitLabelSnapshot.isAcceptableOrUnknown(
          data['unit_label_snapshot']!,
          _unitLabelSnapshotMeta,
        ),
      );
    }
    if (data.containsKey('image_path_snapshot')) {
      context.handle(
        _imagePathSnapshotMeta,
        imagePathSnapshot.isAcceptableOrUnknown(
          data['image_path_snapshot']!,
          _imagePathSnapshotMeta,
        ),
      );
    }
    if (data.containsKey('unit_price_centavos')) {
      context.handle(
        _unitPriceCentavosMeta,
        unitPriceCentavos.isAcceptableOrUnknown(
          data['unit_price_centavos']!,
          _unitPriceCentavosMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_unitPriceCentavosMeta);
    }
    if (data.containsKey('quantity')) {
      context.handle(
        _quantityMeta,
        quantity.isAcceptableOrUnknown(data['quantity']!, _quantityMeta),
      );
    } else if (isInserting) {
      context.missing(_quantityMeta);
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {lineId};
  @override
  DraftCartItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DraftCartItem(
      lineId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}line_id'],
      )!,
      productId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}product_id'],
      )!,
      sellingUnitId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}selling_unit_id'],
      ),
      barcode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}barcode'],
      ),
      nameSnapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name_snapshot'],
      )!,
      brandSnapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}brand_snapshot'],
      ),
      unitLabelSnapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}unit_label_snapshot'],
      ),
      imagePathSnapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}image_path_snapshot'],
      ),
      unitPriceCentavos: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}unit_price_centavos'],
      )!,
      quantity: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}quantity'],
      )!,
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}added_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $DraftCartItemsTable createAlias(String alias) {
    return $DraftCartItemsTable(attachedDatabase, alias);
  }
}

class DraftCartItem extends DataClass implements Insertable<DraftCartItem> {
  /// Stable identity for a particular product + selling-unit selection.
  /// Existing version-1 rows migrate with a `main:`-prefixed product ID.
  final String lineId;
  final String productId;
  final String? sellingUnitId;
  final String? barcode;
  final String nameSnapshot;
  final String? brandSnapshot;
  final String? unitLabelSnapshot;
  final String? imagePathSnapshot;
  final int unitPriceCentavos;
  final int quantity;
  final DateTime addedAt;
  final DateTime updatedAt;
  const DraftCartItem({
    required this.lineId,
    required this.productId,
    this.sellingUnitId,
    this.barcode,
    required this.nameSnapshot,
    this.brandSnapshot,
    this.unitLabelSnapshot,
    this.imagePathSnapshot,
    required this.unitPriceCentavos,
    required this.quantity,
    required this.addedAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['line_id'] = Variable<String>(lineId);
    map['product_id'] = Variable<String>(productId);
    if (!nullToAbsent || sellingUnitId != null) {
      map['selling_unit_id'] = Variable<String>(sellingUnitId);
    }
    if (!nullToAbsent || barcode != null) {
      map['barcode'] = Variable<String>(barcode);
    }
    map['name_snapshot'] = Variable<String>(nameSnapshot);
    if (!nullToAbsent || brandSnapshot != null) {
      map['brand_snapshot'] = Variable<String>(brandSnapshot);
    }
    if (!nullToAbsent || unitLabelSnapshot != null) {
      map['unit_label_snapshot'] = Variable<String>(unitLabelSnapshot);
    }
    if (!nullToAbsent || imagePathSnapshot != null) {
      map['image_path_snapshot'] = Variable<String>(imagePathSnapshot);
    }
    map['unit_price_centavos'] = Variable<int>(unitPriceCentavos);
    map['quantity'] = Variable<int>(quantity);
    map['added_at'] = Variable<DateTime>(addedAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  DraftCartItemsCompanion toCompanion(bool nullToAbsent) {
    return DraftCartItemsCompanion(
      lineId: Value(lineId),
      productId: Value(productId),
      sellingUnitId: sellingUnitId == null && nullToAbsent
          ? const Value.absent()
          : Value(sellingUnitId),
      barcode: barcode == null && nullToAbsent
          ? const Value.absent()
          : Value(barcode),
      nameSnapshot: Value(nameSnapshot),
      brandSnapshot: brandSnapshot == null && nullToAbsent
          ? const Value.absent()
          : Value(brandSnapshot),
      unitLabelSnapshot: unitLabelSnapshot == null && nullToAbsent
          ? const Value.absent()
          : Value(unitLabelSnapshot),
      imagePathSnapshot: imagePathSnapshot == null && nullToAbsent
          ? const Value.absent()
          : Value(imagePathSnapshot),
      unitPriceCentavos: Value(unitPriceCentavos),
      quantity: Value(quantity),
      addedAt: Value(addedAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory DraftCartItem.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DraftCartItem(
      lineId: serializer.fromJson<String>(json['lineId']),
      productId: serializer.fromJson<String>(json['productId']),
      sellingUnitId: serializer.fromJson<String?>(json['sellingUnitId']),
      barcode: serializer.fromJson<String?>(json['barcode']),
      nameSnapshot: serializer.fromJson<String>(json['nameSnapshot']),
      brandSnapshot: serializer.fromJson<String?>(json['brandSnapshot']),
      unitLabelSnapshot: serializer.fromJson<String?>(
        json['unitLabelSnapshot'],
      ),
      imagePathSnapshot: serializer.fromJson<String?>(
        json['imagePathSnapshot'],
      ),
      unitPriceCentavos: serializer.fromJson<int>(json['unitPriceCentavos']),
      quantity: serializer.fromJson<int>(json['quantity']),
      addedAt: serializer.fromJson<DateTime>(json['addedAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'lineId': serializer.toJson<String>(lineId),
      'productId': serializer.toJson<String>(productId),
      'sellingUnitId': serializer.toJson<String?>(sellingUnitId),
      'barcode': serializer.toJson<String?>(barcode),
      'nameSnapshot': serializer.toJson<String>(nameSnapshot),
      'brandSnapshot': serializer.toJson<String?>(brandSnapshot),
      'unitLabelSnapshot': serializer.toJson<String?>(unitLabelSnapshot),
      'imagePathSnapshot': serializer.toJson<String?>(imagePathSnapshot),
      'unitPriceCentavos': serializer.toJson<int>(unitPriceCentavos),
      'quantity': serializer.toJson<int>(quantity),
      'addedAt': serializer.toJson<DateTime>(addedAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  DraftCartItem copyWith({
    String? lineId,
    String? productId,
    Value<String?> sellingUnitId = const Value.absent(),
    Value<String?> barcode = const Value.absent(),
    String? nameSnapshot,
    Value<String?> brandSnapshot = const Value.absent(),
    Value<String?> unitLabelSnapshot = const Value.absent(),
    Value<String?> imagePathSnapshot = const Value.absent(),
    int? unitPriceCentavos,
    int? quantity,
    DateTime? addedAt,
    DateTime? updatedAt,
  }) => DraftCartItem(
    lineId: lineId ?? this.lineId,
    productId: productId ?? this.productId,
    sellingUnitId: sellingUnitId.present
        ? sellingUnitId.value
        : this.sellingUnitId,
    barcode: barcode.present ? barcode.value : this.barcode,
    nameSnapshot: nameSnapshot ?? this.nameSnapshot,
    brandSnapshot: brandSnapshot.present
        ? brandSnapshot.value
        : this.brandSnapshot,
    unitLabelSnapshot: unitLabelSnapshot.present
        ? unitLabelSnapshot.value
        : this.unitLabelSnapshot,
    imagePathSnapshot: imagePathSnapshot.present
        ? imagePathSnapshot.value
        : this.imagePathSnapshot,
    unitPriceCentavos: unitPriceCentavos ?? this.unitPriceCentavos,
    quantity: quantity ?? this.quantity,
    addedAt: addedAt ?? this.addedAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  DraftCartItem copyWithCompanion(DraftCartItemsCompanion data) {
    return DraftCartItem(
      lineId: data.lineId.present ? data.lineId.value : this.lineId,
      productId: data.productId.present ? data.productId.value : this.productId,
      sellingUnitId: data.sellingUnitId.present
          ? data.sellingUnitId.value
          : this.sellingUnitId,
      barcode: data.barcode.present ? data.barcode.value : this.barcode,
      nameSnapshot: data.nameSnapshot.present
          ? data.nameSnapshot.value
          : this.nameSnapshot,
      brandSnapshot: data.brandSnapshot.present
          ? data.brandSnapshot.value
          : this.brandSnapshot,
      unitLabelSnapshot: data.unitLabelSnapshot.present
          ? data.unitLabelSnapshot.value
          : this.unitLabelSnapshot,
      imagePathSnapshot: data.imagePathSnapshot.present
          ? data.imagePathSnapshot.value
          : this.imagePathSnapshot,
      unitPriceCentavos: data.unitPriceCentavos.present
          ? data.unitPriceCentavos.value
          : this.unitPriceCentavos,
      quantity: data.quantity.present ? data.quantity.value : this.quantity,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DraftCartItem(')
          ..write('lineId: $lineId, ')
          ..write('productId: $productId, ')
          ..write('sellingUnitId: $sellingUnitId, ')
          ..write('barcode: $barcode, ')
          ..write('nameSnapshot: $nameSnapshot, ')
          ..write('brandSnapshot: $brandSnapshot, ')
          ..write('unitLabelSnapshot: $unitLabelSnapshot, ')
          ..write('imagePathSnapshot: $imagePathSnapshot, ')
          ..write('unitPriceCentavos: $unitPriceCentavos, ')
          ..write('quantity: $quantity, ')
          ..write('addedAt: $addedAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    lineId,
    productId,
    sellingUnitId,
    barcode,
    nameSnapshot,
    brandSnapshot,
    unitLabelSnapshot,
    imagePathSnapshot,
    unitPriceCentavos,
    quantity,
    addedAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DraftCartItem &&
          other.lineId == this.lineId &&
          other.productId == this.productId &&
          other.sellingUnitId == this.sellingUnitId &&
          other.barcode == this.barcode &&
          other.nameSnapshot == this.nameSnapshot &&
          other.brandSnapshot == this.brandSnapshot &&
          other.unitLabelSnapshot == this.unitLabelSnapshot &&
          other.imagePathSnapshot == this.imagePathSnapshot &&
          other.unitPriceCentavos == this.unitPriceCentavos &&
          other.quantity == this.quantity &&
          other.addedAt == this.addedAt &&
          other.updatedAt == this.updatedAt);
}

class DraftCartItemsCompanion extends UpdateCompanion<DraftCartItem> {
  final Value<String> lineId;
  final Value<String> productId;
  final Value<String?> sellingUnitId;
  final Value<String?> barcode;
  final Value<String> nameSnapshot;
  final Value<String?> brandSnapshot;
  final Value<String?> unitLabelSnapshot;
  final Value<String?> imagePathSnapshot;
  final Value<int> unitPriceCentavos;
  final Value<int> quantity;
  final Value<DateTime> addedAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const DraftCartItemsCompanion({
    this.lineId = const Value.absent(),
    this.productId = const Value.absent(),
    this.sellingUnitId = const Value.absent(),
    this.barcode = const Value.absent(),
    this.nameSnapshot = const Value.absent(),
    this.brandSnapshot = const Value.absent(),
    this.unitLabelSnapshot = const Value.absent(),
    this.imagePathSnapshot = const Value.absent(),
    this.unitPriceCentavos = const Value.absent(),
    this.quantity = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DraftCartItemsCompanion.insert({
    required String lineId,
    required String productId,
    this.sellingUnitId = const Value.absent(),
    this.barcode = const Value.absent(),
    required String nameSnapshot,
    this.brandSnapshot = const Value.absent(),
    this.unitLabelSnapshot = const Value.absent(),
    this.imagePathSnapshot = const Value.absent(),
    required int unitPriceCentavos,
    required int quantity,
    this.addedAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : lineId = Value(lineId),
       productId = Value(productId),
       nameSnapshot = Value(nameSnapshot),
       unitPriceCentavos = Value(unitPriceCentavos),
       quantity = Value(quantity);
  static Insertable<DraftCartItem> custom({
    Expression<String>? lineId,
    Expression<String>? productId,
    Expression<String>? sellingUnitId,
    Expression<String>? barcode,
    Expression<String>? nameSnapshot,
    Expression<String>? brandSnapshot,
    Expression<String>? unitLabelSnapshot,
    Expression<String>? imagePathSnapshot,
    Expression<int>? unitPriceCentavos,
    Expression<int>? quantity,
    Expression<DateTime>? addedAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (lineId != null) 'line_id': lineId,
      if (productId != null) 'product_id': productId,
      if (sellingUnitId != null) 'selling_unit_id': sellingUnitId,
      if (barcode != null) 'barcode': barcode,
      if (nameSnapshot != null) 'name_snapshot': nameSnapshot,
      if (brandSnapshot != null) 'brand_snapshot': brandSnapshot,
      if (unitLabelSnapshot != null) 'unit_label_snapshot': unitLabelSnapshot,
      if (imagePathSnapshot != null) 'image_path_snapshot': imagePathSnapshot,
      if (unitPriceCentavos != null) 'unit_price_centavos': unitPriceCentavos,
      if (quantity != null) 'quantity': quantity,
      if (addedAt != null) 'added_at': addedAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DraftCartItemsCompanion copyWith({
    Value<String>? lineId,
    Value<String>? productId,
    Value<String?>? sellingUnitId,
    Value<String?>? barcode,
    Value<String>? nameSnapshot,
    Value<String?>? brandSnapshot,
    Value<String?>? unitLabelSnapshot,
    Value<String?>? imagePathSnapshot,
    Value<int>? unitPriceCentavos,
    Value<int>? quantity,
    Value<DateTime>? addedAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return DraftCartItemsCompanion(
      lineId: lineId ?? this.lineId,
      productId: productId ?? this.productId,
      sellingUnitId: sellingUnitId ?? this.sellingUnitId,
      barcode: barcode ?? this.barcode,
      nameSnapshot: nameSnapshot ?? this.nameSnapshot,
      brandSnapshot: brandSnapshot ?? this.brandSnapshot,
      unitLabelSnapshot: unitLabelSnapshot ?? this.unitLabelSnapshot,
      imagePathSnapshot: imagePathSnapshot ?? this.imagePathSnapshot,
      unitPriceCentavos: unitPriceCentavos ?? this.unitPriceCentavos,
      quantity: quantity ?? this.quantity,
      addedAt: addedAt ?? this.addedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (lineId.present) {
      map['line_id'] = Variable<String>(lineId.value);
    }
    if (productId.present) {
      map['product_id'] = Variable<String>(productId.value);
    }
    if (sellingUnitId.present) {
      map['selling_unit_id'] = Variable<String>(sellingUnitId.value);
    }
    if (barcode.present) {
      map['barcode'] = Variable<String>(barcode.value);
    }
    if (nameSnapshot.present) {
      map['name_snapshot'] = Variable<String>(nameSnapshot.value);
    }
    if (brandSnapshot.present) {
      map['brand_snapshot'] = Variable<String>(brandSnapshot.value);
    }
    if (unitLabelSnapshot.present) {
      map['unit_label_snapshot'] = Variable<String>(unitLabelSnapshot.value);
    }
    if (imagePathSnapshot.present) {
      map['image_path_snapshot'] = Variable<String>(imagePathSnapshot.value);
    }
    if (unitPriceCentavos.present) {
      map['unit_price_centavos'] = Variable<int>(unitPriceCentavos.value);
    }
    if (quantity.present) {
      map['quantity'] = Variable<int>(quantity.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<DateTime>(addedAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DraftCartItemsCompanion(')
          ..write('lineId: $lineId, ')
          ..write('productId: $productId, ')
          ..write('sellingUnitId: $sellingUnitId, ')
          ..write('barcode: $barcode, ')
          ..write('nameSnapshot: $nameSnapshot, ')
          ..write('brandSnapshot: $brandSnapshot, ')
          ..write('unitLabelSnapshot: $unitLabelSnapshot, ')
          ..write('imagePathSnapshot: $imagePathSnapshot, ')
          ..write('unitPriceCentavos: $unitPriceCentavos, ')
          ..write('quantity: $quantity, ')
          ..write('addedAt: $addedAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StoreProfilesTable extends StoreProfiles
    with TableInfo<$StoreProfilesTable, StoreProfile> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StoreProfilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _storeNameMeta = const VerificationMeta(
    'storeName',
  );
  @override
  late final GeneratedColumn<String> storeName = GeneratedColumn<String>(
    'store_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('Raze Store'),
  );
  static const VerificationMeta _addressMeta = const VerificationMeta(
    'address',
  );
  @override
  late final GeneratedColumn<String> address = GeneratedColumn<String>(
    'address',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _contactMeta = const VerificationMeta(
    'contact',
  );
  @override
  late final GeneratedColumn<String> contact = GeneratedColumn<String>(
    'contact',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _receiptFooterMeta = const VerificationMeta(
    'receiptFooter',
  );
  @override
  late final GeneratedColumn<String> receiptFooter = GeneratedColumn<String>(
    'receipt_footer',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('Salamat po!'),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    storeName,
    address,
    contact,
    receiptFooter,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'store_profiles';
  @override
  VerificationContext validateIntegrity(
    Insertable<StoreProfile> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('store_name')) {
      context.handle(
        _storeNameMeta,
        storeName.isAcceptableOrUnknown(data['store_name']!, _storeNameMeta),
      );
    }
    if (data.containsKey('address')) {
      context.handle(
        _addressMeta,
        address.isAcceptableOrUnknown(data['address']!, _addressMeta),
      );
    }
    if (data.containsKey('contact')) {
      context.handle(
        _contactMeta,
        contact.isAcceptableOrUnknown(data['contact']!, _contactMeta),
      );
    }
    if (data.containsKey('receipt_footer')) {
      context.handle(
        _receiptFooterMeta,
        receiptFooter.isAcceptableOrUnknown(
          data['receipt_footer']!,
          _receiptFooterMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  StoreProfile map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoreProfile(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      storeName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}store_name'],
      )!,
      address: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}address'],
      )!,
      contact: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}contact'],
      )!,
      receiptFooter: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}receipt_footer'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $StoreProfilesTable createAlias(String alias) {
    return $StoreProfilesTable(attachedDatabase, alias);
  }
}

class StoreProfile extends DataClass implements Insertable<StoreProfile> {
  final int id;
  final String storeName;
  final String address;
  final String contact;
  final String receiptFooter;
  final DateTime updatedAt;
  const StoreProfile({
    required this.id,
    required this.storeName,
    required this.address,
    required this.contact,
    required this.receiptFooter,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['store_name'] = Variable<String>(storeName);
    map['address'] = Variable<String>(address);
    map['contact'] = Variable<String>(contact);
    map['receipt_footer'] = Variable<String>(receiptFooter);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  StoreProfilesCompanion toCompanion(bool nullToAbsent) {
    return StoreProfilesCompanion(
      id: Value(id),
      storeName: Value(storeName),
      address: Value(address),
      contact: Value(contact),
      receiptFooter: Value(receiptFooter),
      updatedAt: Value(updatedAt),
    );
  }

  factory StoreProfile.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoreProfile(
      id: serializer.fromJson<int>(json['id']),
      storeName: serializer.fromJson<String>(json['storeName']),
      address: serializer.fromJson<String>(json['address']),
      contact: serializer.fromJson<String>(json['contact']),
      receiptFooter: serializer.fromJson<String>(json['receiptFooter']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'storeName': serializer.toJson<String>(storeName),
      'address': serializer.toJson<String>(address),
      'contact': serializer.toJson<String>(contact),
      'receiptFooter': serializer.toJson<String>(receiptFooter),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  StoreProfile copyWith({
    int? id,
    String? storeName,
    String? address,
    String? contact,
    String? receiptFooter,
    DateTime? updatedAt,
  }) => StoreProfile(
    id: id ?? this.id,
    storeName: storeName ?? this.storeName,
    address: address ?? this.address,
    contact: contact ?? this.contact,
    receiptFooter: receiptFooter ?? this.receiptFooter,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  StoreProfile copyWithCompanion(StoreProfilesCompanion data) {
    return StoreProfile(
      id: data.id.present ? data.id.value : this.id,
      storeName: data.storeName.present ? data.storeName.value : this.storeName,
      address: data.address.present ? data.address.value : this.address,
      contact: data.contact.present ? data.contact.value : this.contact,
      receiptFooter: data.receiptFooter.present
          ? data.receiptFooter.value
          : this.receiptFooter,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoreProfile(')
          ..write('id: $id, ')
          ..write('storeName: $storeName, ')
          ..write('address: $address, ')
          ..write('contact: $contact, ')
          ..write('receiptFooter: $receiptFooter, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, storeName, address, contact, receiptFooter, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoreProfile &&
          other.id == this.id &&
          other.storeName == this.storeName &&
          other.address == this.address &&
          other.contact == this.contact &&
          other.receiptFooter == this.receiptFooter &&
          other.updatedAt == this.updatedAt);
}

class StoreProfilesCompanion extends UpdateCompanion<StoreProfile> {
  final Value<int> id;
  final Value<String> storeName;
  final Value<String> address;
  final Value<String> contact;
  final Value<String> receiptFooter;
  final Value<DateTime> updatedAt;
  const StoreProfilesCompanion({
    this.id = const Value.absent(),
    this.storeName = const Value.absent(),
    this.address = const Value.absent(),
    this.contact = const Value.absent(),
    this.receiptFooter = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  StoreProfilesCompanion.insert({
    this.id = const Value.absent(),
    this.storeName = const Value.absent(),
    this.address = const Value.absent(),
    this.contact = const Value.absent(),
    this.receiptFooter = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  static Insertable<StoreProfile> custom({
    Expression<int>? id,
    Expression<String>? storeName,
    Expression<String>? address,
    Expression<String>? contact,
    Expression<String>? receiptFooter,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (storeName != null) 'store_name': storeName,
      if (address != null) 'address': address,
      if (contact != null) 'contact': contact,
      if (receiptFooter != null) 'receipt_footer': receiptFooter,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  StoreProfilesCompanion copyWith({
    Value<int>? id,
    Value<String>? storeName,
    Value<String>? address,
    Value<String>? contact,
    Value<String>? receiptFooter,
    Value<DateTime>? updatedAt,
  }) {
    return StoreProfilesCompanion(
      id: id ?? this.id,
      storeName: storeName ?? this.storeName,
      address: address ?? this.address,
      contact: contact ?? this.contact,
      receiptFooter: receiptFooter ?? this.receiptFooter,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (storeName.present) {
      map['store_name'] = Variable<String>(storeName.value);
    }
    if (address.present) {
      map['address'] = Variable<String>(address.value);
    }
    if (contact.present) {
      map['contact'] = Variable<String>(contact.value);
    }
    if (receiptFooter.present) {
      map['receipt_footer'] = Variable<String>(receiptFooter.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StoreProfilesCompanion(')
          ..write('id: $id, ')
          ..write('storeName: $storeName, ')
          ..write('address: $address, ')
          ..write('contact: $contact, ')
          ..write('receiptFooter: $receiptFooter, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $StoreProductsTable storeProducts = $StoreProductsTable(this);
  late final $ProductSellingUnitsTable productSellingUnits =
      $ProductSellingUnitsTable(this);
  late final $DraftCartItemsTable draftCartItems = $DraftCartItemsTable(this);
  late final $StoreProfilesTable storeProfiles = $StoreProfilesTable(this);
  late final Index storeProductsBarcodeUniqueIdx = Index(
    'store_products_barcode_unique_idx',
    'CREATE UNIQUE INDEX store_products_barcode_unique_idx ON store_products (barcode)',
  );
  late final Index storeProductsNameIdx = Index(
    'store_products_name_idx',
    'CREATE INDEX store_products_name_idx ON store_products (name)',
  );
  late final Index storeProductsSourceIdentityUniqueIdx = Index(
    'store_products_source_identity_unique_idx',
    'CREATE UNIQUE INDEX store_products_source_identity_unique_idx ON store_products (source, source_product_id)',
  );
  late final Index productSellingUnitsProductPositionIdx = Index(
    'product_selling_units_product_position_idx',
    'CREATE INDEX product_selling_units_product_position_idx ON product_selling_units (product_id, position)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    storeProducts,
    productSellingUnits,
    draftCartItems,
    storeProfiles,
    storeProductsBarcodeUniqueIdx,
    storeProductsNameIdx,
    storeProductsSourceIdentityUniqueIdx,
    productSellingUnitsProductPositionIdx,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'store_products',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('product_selling_units', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$StoreProductsTableCreateCompanionBuilder =
    StoreProductsCompanion Function({
      required String id,
      Value<String?> barcode,
      Value<String?> source,
      Value<String?> sourceProductId,
      required String name,
      Value<String?> brand,
      Value<String?> unitLabel,
      Value<String?> category,
      Value<String?> remoteImageUrl,
      Value<String?> catalogImagePath,
      Value<DateTime?> sourceUpdatedAt,
      Value<String?> localImagePath,
      required int priceCentavos,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$StoreProductsTableUpdateCompanionBuilder =
    StoreProductsCompanion Function({
      Value<String> id,
      Value<String?> barcode,
      Value<String?> source,
      Value<String?> sourceProductId,
      Value<String> name,
      Value<String?> brand,
      Value<String?> unitLabel,
      Value<String?> category,
      Value<String?> remoteImageUrl,
      Value<String?> catalogImagePath,
      Value<DateTime?> sourceUpdatedAt,
      Value<String?> localImagePath,
      Value<int> priceCentavos,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$StoreProductsTableReferences
    extends BaseReferences<_$AppDatabase, $StoreProductsTable, StoreProduct> {
  $$StoreProductsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<
    $ProductSellingUnitsTable,
    List<ProductSellingUnit>
  >
  _productSellingUnitsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.productSellingUnits,
        aliasName: $_aliasNameGenerator(
          db.storeProducts.id,
          db.productSellingUnits.productId,
        ),
      );

  $$ProductSellingUnitsTableProcessedTableManager get productSellingUnitsRefs {
    final manager = $$ProductSellingUnitsTableTableManager(
      $_db,
      $_db.productSellingUnits,
    ).filter((f) => f.productId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _productSellingUnitsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$StoreProductsTableFilterComposer
    extends Composer<_$AppDatabase, $StoreProductsTable> {
  $$StoreProductsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get barcode => $composableBuilder(
    column: $table.barcode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceProductId => $composableBuilder(
    column: $table.sourceProductId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get brand => $composableBuilder(
    column: $table.brand,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get unitLabel => $composableBuilder(
    column: $table.unitLabel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get remoteImageUrl => $composableBuilder(
    column: $table.remoteImageUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get catalogImagePath => $composableBuilder(
    column: $table.catalogImagePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get sourceUpdatedAt => $composableBuilder(
    column: $table.sourceUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localImagePath => $composableBuilder(
    column: $table.localImagePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get priceCentavos => $composableBuilder(
    column: $table.priceCentavos,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> productSellingUnitsRefs(
    Expression<bool> Function($$ProductSellingUnitsTableFilterComposer f) f,
  ) {
    final $$ProductSellingUnitsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.productSellingUnits,
      getReferencedColumn: (t) => t.productId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProductSellingUnitsTableFilterComposer(
            $db: $db,
            $table: $db.productSellingUnits,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$StoreProductsTableOrderingComposer
    extends Composer<_$AppDatabase, $StoreProductsTable> {
  $$StoreProductsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get barcode => $composableBuilder(
    column: $table.barcode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceProductId => $composableBuilder(
    column: $table.sourceProductId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get brand => $composableBuilder(
    column: $table.brand,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get unitLabel => $composableBuilder(
    column: $table.unitLabel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get remoteImageUrl => $composableBuilder(
    column: $table.remoteImageUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get catalogImagePath => $composableBuilder(
    column: $table.catalogImagePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get sourceUpdatedAt => $composableBuilder(
    column: $table.sourceUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localImagePath => $composableBuilder(
    column: $table.localImagePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get priceCentavos => $composableBuilder(
    column: $table.priceCentavos,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StoreProductsTableAnnotationComposer
    extends Composer<_$AppDatabase, $StoreProductsTable> {
  $$StoreProductsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get barcode =>
      $composableBuilder(column: $table.barcode, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get sourceProductId => $composableBuilder(
    column: $table.sourceProductId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get brand =>
      $composableBuilder(column: $table.brand, builder: (column) => column);

  GeneratedColumn<String> get unitLabel =>
      $composableBuilder(column: $table.unitLabel, builder: (column) => column);

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<String> get remoteImageUrl => $composableBuilder(
    column: $table.remoteImageUrl,
    builder: (column) => column,
  );

  GeneratedColumn<String> get catalogImagePath => $composableBuilder(
    column: $table.catalogImagePath,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get sourceUpdatedAt => $composableBuilder(
    column: $table.sourceUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get localImagePath => $composableBuilder(
    column: $table.localImagePath,
    builder: (column) => column,
  );

  GeneratedColumn<int> get priceCentavos => $composableBuilder(
    column: $table.priceCentavos,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> productSellingUnitsRefs<T extends Object>(
    Expression<T> Function($$ProductSellingUnitsTableAnnotationComposer a) f,
  ) {
    final $$ProductSellingUnitsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.productSellingUnits,
          getReferencedColumn: (t) => t.productId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ProductSellingUnitsTableAnnotationComposer(
                $db: $db,
                $table: $db.productSellingUnits,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$StoreProductsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $StoreProductsTable,
          StoreProduct,
          $$StoreProductsTableFilterComposer,
          $$StoreProductsTableOrderingComposer,
          $$StoreProductsTableAnnotationComposer,
          $$StoreProductsTableCreateCompanionBuilder,
          $$StoreProductsTableUpdateCompanionBuilder,
          (StoreProduct, $$StoreProductsTableReferences),
          StoreProduct,
          PrefetchHooks Function({bool productSellingUnitsRefs})
        > {
  $$StoreProductsTableTableManager(_$AppDatabase db, $StoreProductsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StoreProductsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StoreProductsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StoreProductsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> barcode = const Value.absent(),
                Value<String?> source = const Value.absent(),
                Value<String?> sourceProductId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> brand = const Value.absent(),
                Value<String?> unitLabel = const Value.absent(),
                Value<String?> category = const Value.absent(),
                Value<String?> remoteImageUrl = const Value.absent(),
                Value<String?> catalogImagePath = const Value.absent(),
                Value<DateTime?> sourceUpdatedAt = const Value.absent(),
                Value<String?> localImagePath = const Value.absent(),
                Value<int> priceCentavos = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StoreProductsCompanion(
                id: id,
                barcode: barcode,
                source: source,
                sourceProductId: sourceProductId,
                name: name,
                brand: brand,
                unitLabel: unitLabel,
                category: category,
                remoteImageUrl: remoteImageUrl,
                catalogImagePath: catalogImagePath,
                sourceUpdatedAt: sourceUpdatedAt,
                localImagePath: localImagePath,
                priceCentavos: priceCentavos,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> barcode = const Value.absent(),
                Value<String?> source = const Value.absent(),
                Value<String?> sourceProductId = const Value.absent(),
                required String name,
                Value<String?> brand = const Value.absent(),
                Value<String?> unitLabel = const Value.absent(),
                Value<String?> category = const Value.absent(),
                Value<String?> remoteImageUrl = const Value.absent(),
                Value<String?> catalogImagePath = const Value.absent(),
                Value<DateTime?> sourceUpdatedAt = const Value.absent(),
                Value<String?> localImagePath = const Value.absent(),
                required int priceCentavos,
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StoreProductsCompanion.insert(
                id: id,
                barcode: barcode,
                source: source,
                sourceProductId: sourceProductId,
                name: name,
                brand: brand,
                unitLabel: unitLabel,
                category: category,
                remoteImageUrl: remoteImageUrl,
                catalogImagePath: catalogImagePath,
                sourceUpdatedAt: sourceUpdatedAt,
                localImagePath: localImagePath,
                priceCentavos: priceCentavos,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$StoreProductsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({productSellingUnitsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (productSellingUnitsRefs) db.productSellingUnits,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (productSellingUnitsRefs)
                    await $_getPrefetchedData<
                      StoreProduct,
                      $StoreProductsTable,
                      ProductSellingUnit
                    >(
                      currentTable: table,
                      referencedTable: $$StoreProductsTableReferences
                          ._productSellingUnitsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$StoreProductsTableReferences(
                            db,
                            table,
                            p0,
                          ).productSellingUnitsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.productId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$StoreProductsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $StoreProductsTable,
      StoreProduct,
      $$StoreProductsTableFilterComposer,
      $$StoreProductsTableOrderingComposer,
      $$StoreProductsTableAnnotationComposer,
      $$StoreProductsTableCreateCompanionBuilder,
      $$StoreProductsTableUpdateCompanionBuilder,
      (StoreProduct, $$StoreProductsTableReferences),
      StoreProduct,
      PrefetchHooks Function({bool productSellingUnitsRefs})
    >;
typedef $$ProductSellingUnitsTableCreateCompanionBuilder =
    ProductSellingUnitsCompanion Function({
      required String id,
      required String productId,
      required String label,
      required int priceCentavos,
      required int position,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$ProductSellingUnitsTableUpdateCompanionBuilder =
    ProductSellingUnitsCompanion Function({
      Value<String> id,
      Value<String> productId,
      Value<String> label,
      Value<int> priceCentavos,
      Value<int> position,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$ProductSellingUnitsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $ProductSellingUnitsTable,
          ProductSellingUnit
        > {
  $$ProductSellingUnitsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $StoreProductsTable _productIdTable(_$AppDatabase db) =>
      db.storeProducts.createAlias(
        $_aliasNameGenerator(
          db.productSellingUnits.productId,
          db.storeProducts.id,
        ),
      );

  $$StoreProductsTableProcessedTableManager get productId {
    final $_column = $_itemColumn<String>('product_id')!;

    final manager = $$StoreProductsTableTableManager(
      $_db,
      $_db.storeProducts,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_productIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ProductSellingUnitsTableFilterComposer
    extends Composer<_$AppDatabase, $ProductSellingUnitsTable> {
  $$ProductSellingUnitsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get priceCentavos => $composableBuilder(
    column: $table.priceCentavos,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$StoreProductsTableFilterComposer get productId {
    final $$StoreProductsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.productId,
      referencedTable: $db.storeProducts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$StoreProductsTableFilterComposer(
            $db: $db,
            $table: $db.storeProducts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProductSellingUnitsTableOrderingComposer
    extends Composer<_$AppDatabase, $ProductSellingUnitsTable> {
  $$ProductSellingUnitsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get priceCentavos => $composableBuilder(
    column: $table.priceCentavos,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$StoreProductsTableOrderingComposer get productId {
    final $$StoreProductsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.productId,
      referencedTable: $db.storeProducts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$StoreProductsTableOrderingComposer(
            $db: $db,
            $table: $db.storeProducts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProductSellingUnitsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProductSellingUnitsTable> {
  $$ProductSellingUnitsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<int> get priceCentavos => $composableBuilder(
    column: $table.priceCentavos,
    builder: (column) => column,
  );

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$StoreProductsTableAnnotationComposer get productId {
    final $$StoreProductsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.productId,
      referencedTable: $db.storeProducts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$StoreProductsTableAnnotationComposer(
            $db: $db,
            $table: $db.storeProducts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProductSellingUnitsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ProductSellingUnitsTable,
          ProductSellingUnit,
          $$ProductSellingUnitsTableFilterComposer,
          $$ProductSellingUnitsTableOrderingComposer,
          $$ProductSellingUnitsTableAnnotationComposer,
          $$ProductSellingUnitsTableCreateCompanionBuilder,
          $$ProductSellingUnitsTableUpdateCompanionBuilder,
          (ProductSellingUnit, $$ProductSellingUnitsTableReferences),
          ProductSellingUnit,
          PrefetchHooks Function({bool productId})
        > {
  $$ProductSellingUnitsTableTableManager(
    _$AppDatabase db,
    $ProductSellingUnitsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProductSellingUnitsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProductSellingUnitsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ProductSellingUnitsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> productId = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<int> priceCentavos = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProductSellingUnitsCompanion(
                id: id,
                productId: productId,
                label: label,
                priceCentavos: priceCentavos,
                position: position,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String productId,
                required String label,
                required int priceCentavos,
                required int position,
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProductSellingUnitsCompanion.insert(
                id: id,
                productId: productId,
                label: label,
                priceCentavos: priceCentavos,
                position: position,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ProductSellingUnitsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({productId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (productId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.productId,
                                referencedTable:
                                    $$ProductSellingUnitsTableReferences
                                        ._productIdTable(db),
                                referencedColumn:
                                    $$ProductSellingUnitsTableReferences
                                        ._productIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ProductSellingUnitsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ProductSellingUnitsTable,
      ProductSellingUnit,
      $$ProductSellingUnitsTableFilterComposer,
      $$ProductSellingUnitsTableOrderingComposer,
      $$ProductSellingUnitsTableAnnotationComposer,
      $$ProductSellingUnitsTableCreateCompanionBuilder,
      $$ProductSellingUnitsTableUpdateCompanionBuilder,
      (ProductSellingUnit, $$ProductSellingUnitsTableReferences),
      ProductSellingUnit,
      PrefetchHooks Function({bool productId})
    >;
typedef $$DraftCartItemsTableCreateCompanionBuilder =
    DraftCartItemsCompanion Function({
      required String lineId,
      required String productId,
      Value<String?> sellingUnitId,
      Value<String?> barcode,
      required String nameSnapshot,
      Value<String?> brandSnapshot,
      Value<String?> unitLabelSnapshot,
      Value<String?> imagePathSnapshot,
      required int unitPriceCentavos,
      required int quantity,
      Value<DateTime> addedAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$DraftCartItemsTableUpdateCompanionBuilder =
    DraftCartItemsCompanion Function({
      Value<String> lineId,
      Value<String> productId,
      Value<String?> sellingUnitId,
      Value<String?> barcode,
      Value<String> nameSnapshot,
      Value<String?> brandSnapshot,
      Value<String?> unitLabelSnapshot,
      Value<String?> imagePathSnapshot,
      Value<int> unitPriceCentavos,
      Value<int> quantity,
      Value<DateTime> addedAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$DraftCartItemsTableFilterComposer
    extends Composer<_$AppDatabase, $DraftCartItemsTable> {
  $$DraftCartItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get lineId => $composableBuilder(
    column: $table.lineId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get productId => $composableBuilder(
    column: $table.productId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sellingUnitId => $composableBuilder(
    column: $table.sellingUnitId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get barcode => $composableBuilder(
    column: $table.barcode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nameSnapshot => $composableBuilder(
    column: $table.nameSnapshot,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get brandSnapshot => $composableBuilder(
    column: $table.brandSnapshot,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get unitLabelSnapshot => $composableBuilder(
    column: $table.unitLabelSnapshot,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get imagePathSnapshot => $composableBuilder(
    column: $table.imagePathSnapshot,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get unitPriceCentavos => $composableBuilder(
    column: $table.unitPriceCentavos,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get quantity => $composableBuilder(
    column: $table.quantity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DraftCartItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $DraftCartItemsTable> {
  $$DraftCartItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get lineId => $composableBuilder(
    column: $table.lineId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get productId => $composableBuilder(
    column: $table.productId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sellingUnitId => $composableBuilder(
    column: $table.sellingUnitId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get barcode => $composableBuilder(
    column: $table.barcode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nameSnapshot => $composableBuilder(
    column: $table.nameSnapshot,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get brandSnapshot => $composableBuilder(
    column: $table.brandSnapshot,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get unitLabelSnapshot => $composableBuilder(
    column: $table.unitLabelSnapshot,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get imagePathSnapshot => $composableBuilder(
    column: $table.imagePathSnapshot,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get unitPriceCentavos => $composableBuilder(
    column: $table.unitPriceCentavos,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get quantity => $composableBuilder(
    column: $table.quantity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DraftCartItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DraftCartItemsTable> {
  $$DraftCartItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get lineId =>
      $composableBuilder(column: $table.lineId, builder: (column) => column);

  GeneratedColumn<String> get productId =>
      $composableBuilder(column: $table.productId, builder: (column) => column);

  GeneratedColumn<String> get sellingUnitId => $composableBuilder(
    column: $table.sellingUnitId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get barcode =>
      $composableBuilder(column: $table.barcode, builder: (column) => column);

  GeneratedColumn<String> get nameSnapshot => $composableBuilder(
    column: $table.nameSnapshot,
    builder: (column) => column,
  );

  GeneratedColumn<String> get brandSnapshot => $composableBuilder(
    column: $table.brandSnapshot,
    builder: (column) => column,
  );

  GeneratedColumn<String> get unitLabelSnapshot => $composableBuilder(
    column: $table.unitLabelSnapshot,
    builder: (column) => column,
  );

  GeneratedColumn<String> get imagePathSnapshot => $composableBuilder(
    column: $table.imagePathSnapshot,
    builder: (column) => column,
  );

  GeneratedColumn<int> get unitPriceCentavos => $composableBuilder(
    column: $table.unitPriceCentavos,
    builder: (column) => column,
  );

  GeneratedColumn<int> get quantity =>
      $composableBuilder(column: $table.quantity, builder: (column) => column);

  GeneratedColumn<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$DraftCartItemsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DraftCartItemsTable,
          DraftCartItem,
          $$DraftCartItemsTableFilterComposer,
          $$DraftCartItemsTableOrderingComposer,
          $$DraftCartItemsTableAnnotationComposer,
          $$DraftCartItemsTableCreateCompanionBuilder,
          $$DraftCartItemsTableUpdateCompanionBuilder,
          (
            DraftCartItem,
            BaseReferences<_$AppDatabase, $DraftCartItemsTable, DraftCartItem>,
          ),
          DraftCartItem,
          PrefetchHooks Function()
        > {
  $$DraftCartItemsTableTableManager(
    _$AppDatabase db,
    $DraftCartItemsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DraftCartItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DraftCartItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DraftCartItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> lineId = const Value.absent(),
                Value<String> productId = const Value.absent(),
                Value<String?> sellingUnitId = const Value.absent(),
                Value<String?> barcode = const Value.absent(),
                Value<String> nameSnapshot = const Value.absent(),
                Value<String?> brandSnapshot = const Value.absent(),
                Value<String?> unitLabelSnapshot = const Value.absent(),
                Value<String?> imagePathSnapshot = const Value.absent(),
                Value<int> unitPriceCentavos = const Value.absent(),
                Value<int> quantity = const Value.absent(),
                Value<DateTime> addedAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DraftCartItemsCompanion(
                lineId: lineId,
                productId: productId,
                sellingUnitId: sellingUnitId,
                barcode: barcode,
                nameSnapshot: nameSnapshot,
                brandSnapshot: brandSnapshot,
                unitLabelSnapshot: unitLabelSnapshot,
                imagePathSnapshot: imagePathSnapshot,
                unitPriceCentavos: unitPriceCentavos,
                quantity: quantity,
                addedAt: addedAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String lineId,
                required String productId,
                Value<String?> sellingUnitId = const Value.absent(),
                Value<String?> barcode = const Value.absent(),
                required String nameSnapshot,
                Value<String?> brandSnapshot = const Value.absent(),
                Value<String?> unitLabelSnapshot = const Value.absent(),
                Value<String?> imagePathSnapshot = const Value.absent(),
                required int unitPriceCentavos,
                required int quantity,
                Value<DateTime> addedAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DraftCartItemsCompanion.insert(
                lineId: lineId,
                productId: productId,
                sellingUnitId: sellingUnitId,
                barcode: barcode,
                nameSnapshot: nameSnapshot,
                brandSnapshot: brandSnapshot,
                unitLabelSnapshot: unitLabelSnapshot,
                imagePathSnapshot: imagePathSnapshot,
                unitPriceCentavos: unitPriceCentavos,
                quantity: quantity,
                addedAt: addedAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DraftCartItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DraftCartItemsTable,
      DraftCartItem,
      $$DraftCartItemsTableFilterComposer,
      $$DraftCartItemsTableOrderingComposer,
      $$DraftCartItemsTableAnnotationComposer,
      $$DraftCartItemsTableCreateCompanionBuilder,
      $$DraftCartItemsTableUpdateCompanionBuilder,
      (
        DraftCartItem,
        BaseReferences<_$AppDatabase, $DraftCartItemsTable, DraftCartItem>,
      ),
      DraftCartItem,
      PrefetchHooks Function()
    >;
typedef $$StoreProfilesTableCreateCompanionBuilder =
    StoreProfilesCompanion Function({
      Value<int> id,
      Value<String> storeName,
      Value<String> address,
      Value<String> contact,
      Value<String> receiptFooter,
      Value<DateTime> updatedAt,
    });
typedef $$StoreProfilesTableUpdateCompanionBuilder =
    StoreProfilesCompanion Function({
      Value<int> id,
      Value<String> storeName,
      Value<String> address,
      Value<String> contact,
      Value<String> receiptFooter,
      Value<DateTime> updatedAt,
    });

class $$StoreProfilesTableFilterComposer
    extends Composer<_$AppDatabase, $StoreProfilesTable> {
  $$StoreProfilesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get storeName => $composableBuilder(
    column: $table.storeName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get address => $composableBuilder(
    column: $table.address,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contact => $composableBuilder(
    column: $table.contact,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get receiptFooter => $composableBuilder(
    column: $table.receiptFooter,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$StoreProfilesTableOrderingComposer
    extends Composer<_$AppDatabase, $StoreProfilesTable> {
  $$StoreProfilesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get storeName => $composableBuilder(
    column: $table.storeName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get address => $composableBuilder(
    column: $table.address,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contact => $composableBuilder(
    column: $table.contact,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get receiptFooter => $composableBuilder(
    column: $table.receiptFooter,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StoreProfilesTableAnnotationComposer
    extends Composer<_$AppDatabase, $StoreProfilesTable> {
  $$StoreProfilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get storeName =>
      $composableBuilder(column: $table.storeName, builder: (column) => column);

  GeneratedColumn<String> get address =>
      $composableBuilder(column: $table.address, builder: (column) => column);

  GeneratedColumn<String> get contact =>
      $composableBuilder(column: $table.contact, builder: (column) => column);

  GeneratedColumn<String> get receiptFooter => $composableBuilder(
    column: $table.receiptFooter,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$StoreProfilesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $StoreProfilesTable,
          StoreProfile,
          $$StoreProfilesTableFilterComposer,
          $$StoreProfilesTableOrderingComposer,
          $$StoreProfilesTableAnnotationComposer,
          $$StoreProfilesTableCreateCompanionBuilder,
          $$StoreProfilesTableUpdateCompanionBuilder,
          (
            StoreProfile,
            BaseReferences<_$AppDatabase, $StoreProfilesTable, StoreProfile>,
          ),
          StoreProfile,
          PrefetchHooks Function()
        > {
  $$StoreProfilesTableTableManager(_$AppDatabase db, $StoreProfilesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StoreProfilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StoreProfilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StoreProfilesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> storeName = const Value.absent(),
                Value<String> address = const Value.absent(),
                Value<String> contact = const Value.absent(),
                Value<String> receiptFooter = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => StoreProfilesCompanion(
                id: id,
                storeName: storeName,
                address: address,
                contact: contact,
                receiptFooter: receiptFooter,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> storeName = const Value.absent(),
                Value<String> address = const Value.absent(),
                Value<String> contact = const Value.absent(),
                Value<String> receiptFooter = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => StoreProfilesCompanion.insert(
                id: id,
                storeName: storeName,
                address: address,
                contact: contact,
                receiptFooter: receiptFooter,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$StoreProfilesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $StoreProfilesTable,
      StoreProfile,
      $$StoreProfilesTableFilterComposer,
      $$StoreProfilesTableOrderingComposer,
      $$StoreProfilesTableAnnotationComposer,
      $$StoreProfilesTableCreateCompanionBuilder,
      $$StoreProfilesTableUpdateCompanionBuilder,
      (
        StoreProfile,
        BaseReferences<_$AppDatabase, $StoreProfilesTable, StoreProfile>,
      ),
      StoreProfile,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$StoreProductsTableTableManager get storeProducts =>
      $$StoreProductsTableTableManager(_db, _db.storeProducts);
  $$ProductSellingUnitsTableTableManager get productSellingUnits =>
      $$ProductSellingUnitsTableTableManager(_db, _db.productSellingUnits);
  $$DraftCartItemsTableTableManager get draftCartItems =>
      $$DraftCartItemsTableTableManager(_db, _db.draftCartItems);
  $$StoreProfilesTableTableManager get storeProfiles =>
      $$StoreProfilesTableTableManager(_db, _db.storeProfiles);
}

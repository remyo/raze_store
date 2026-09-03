import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/core/money/money.dart';
import 'package:raze_store/features/catalog/domain/catalog_product.dart';
import 'package:raze_store/features/catalog/presentation/product_image.dart';

void main() {
  testWidgets('owner photo takes precedence over the catalog pack image', (
    tester,
  ) async {
    late final Directory root;
    late final File local;
    late final File catalog;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('product_image_test_');
      local = File('${root.path}/local.png');
      catalog = File('${root.path}/catalog.png');
      await local.writeAsBytes(_onePixelPng);
      await catalog.writeAsBytes(_onePixelPng);
    });
    addTearDown(() => root.delete(recursive: true));

    await tester.pumpWidget(
      MaterialApp(
        home: ProductImage(
          product: _product(
            localImagePath: local.path,
            catalogImagePath: catalog.path,
          ),
        ),
      ),
    );

    final rendered = tester.widget<Image>(find.byType(Image));
    expect(rendered.image, isA<ResizeImage>());
    final resized = rendered.image as ResizeImage;
    expect(resized.width, 1024);
    expect(resized.height, 1024);
    expect(resized.imageProvider, isA<FileImage>());
    expect((resized.imageProvider as FileImage).file.path, local.path);
  });

  testWidgets('catalog pack image is used when there is no owner photo', (
    tester,
  ) async {
    late final Directory root;
    late final File catalog;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('catalog_image_test_');
      catalog = File('${root.path}/catalog.png');
      await catalog.writeAsBytes(_onePixelPng);
    });
    addTearDown(() => root.delete(recursive: true));

    await tester.pumpWidget(
      MaterialApp(
        home: ProductImage(product: _product(catalogImagePath: catalog.path)),
      ),
    );

    final rendered = tester.widget<Image>(find.byType(Image));
    expect(rendered.image, isA<ResizeImage>());
    final resized = rendered.image as ResizeImage;
    expect(resized.width, 1024);
    expect(resized.height, 1024);
    expect(resized.imageProvider, isA<FileImage>());
    expect((resized.imageProvider as FileImage).file.path, catalog.path);
  });
}

StoreProduct _product({String? localImagePath, String? catalogImagePath}) =>
    StoreProduct(
      id: 'product',
      metadata: CatalogMetadata(name: 'Product'),
      price: Money.fromCentavos(100),
      localImagePath: localImagePath,
      catalogImagePath: catalogImagePath,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

final _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

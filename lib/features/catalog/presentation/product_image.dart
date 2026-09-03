import 'dart:io';

import 'package:flutter/material.dart';
import 'package:raze_store/core/widgets/app_widgets.dart';
import 'package:raze_store/core/widgets/bounded_network_image.dart';
import 'package:raze_store/features/catalog/domain/catalog_product.dart';

class ProductImage extends StatelessWidget {
  const ProductImage({
    super.key,
    required this.product,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius = BorderRadius.zero,
  });

  final StoreProduct product;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadiusGeometry borderRadius;

  @override
  Widget build(BuildContext context) {
    final localPath = product.localImagePath?.trim();
    final catalogPath = product.catalogImagePath?.trim();
    final remoteUrl = product.remoteImageUrl?.trim();
    final logicalCacheSize = width ?? height;
    final cacheSize =
        logicalCacheSize == null ||
            !logicalCacheSize.isFinite ||
            logicalCacheSize <= 0
        ? 1024
        : (logicalCacheSize * MediaQuery.devicePixelRatioOf(context))
              .ceil()
              .clamp(1, 1024);
    final fallback = ProductImagePlaceholder(
      width: width,
      height: height,
      semanticLabel: 'No photo for ${product.name}',
      borderRadius: borderRadius,
    );

    Widget remoteOrPlaceholder() {
      if (remoteUrl == null || remoteUrl.isEmpty) return fallback;
      return BoundedNetworkImage(
        url: remoteUrl,
        fallback: fallback,
        width: width,
        height: height,
        fit: fit,
        cacheWidth: cacheSize,
        cacheHeight: cacheSize,
        semanticLabel: product.name,
      );
    }

    Widget catalogOrRemote() {
      if (catalogPath == null || catalogPath.isEmpty) {
        return remoteOrPlaceholder();
      }
      return Image.file(
        File(catalogPath),
        width: width,
        height: height,
        fit: fit,
        cacheWidth: cacheSize,
        cacheHeight: cacheSize,
        errorBuilder: (_, _, _) => remoteOrPlaceholder(),
        semanticLabel: product.name,
      );
    }

    if (localPath != null && localPath.isNotEmpty) {
      return ClipRRect(
        borderRadius: borderRadius,
        child: Image.file(
          File(localPath),
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (_, _, _) => catalogOrRemote(),
          semanticLabel: product.name,
        ),
      );
    }
    return ClipRRect(borderRadius: borderRadius, child: catalogOrRemote());
  }
}

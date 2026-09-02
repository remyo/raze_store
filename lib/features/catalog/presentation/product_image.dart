import 'dart:io';

import 'package:flutter/material.dart';
import 'package:raze_store/core/widgets/app_widgets.dart';
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
    final remoteUrl = product.remoteImageUrl?.trim();
    final fallback = ProductImagePlaceholder(
      width: width,
      height: height,
      semanticLabel: 'No photo for ${product.name}',
      borderRadius: borderRadius,
    );

    if (localPath != null && localPath.isNotEmpty) {
      return ClipRRect(
        borderRadius: borderRadius,
        child: Image.file(
          File(localPath),
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (_, _, _) => fallback,
          semanticLabel: product.name,
        ),
      );
    }
    if (remoteUrl != null && remoteUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: borderRadius,
        child: Image.network(
          remoteUrl,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (_, _, _) => fallback,
          loadingBuilder: (context, child, progress) =>
              progress == null ? child : fallback,
          semanticLabel: product.name,
        ),
      );
    }
    return fallback;
  }
}

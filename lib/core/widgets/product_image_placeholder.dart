import 'package:flutter/material.dart';
import 'package:raze_store/app/theme/theme.dart';

/// Warm, recognizable fallback for products that do not have a photo yet.
class ProductImagePlaceholder extends StatelessWidget {
  const ProductImagePlaceholder({
    super.key,
    this.width = AppSize.thumbnail,
    this.height = AppSize.thumbnail,
    this.icon = Icons.inventory_2_outlined,
    this.semanticLabel = 'No product photo',
    this.borderRadius = AppRadius.control,
  });

  final double? width;
  final double? height;
  final IconData icon;
  final String semanticLabel;
  final BorderRadiusGeometry borderRadius;

  @override
  Widget build(BuildContext context) {
    final colors = context.storeColors;

    return Semantics(
      image: true,
      label: semanticLabel,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: colors.productImageBackground,
          borderRadius: borderRadius,
        ),
        alignment: Alignment.center,
        child: Icon(
          icon,
          color: colors.productImageForeground,
          size: AppSize.icon,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'app_tokens.dart';

/// Compact button dimensions shared by dense catalog and cart workflows.
///
/// The visual controls match Raze Tag's 36/42dp hierarchy. Material's padded
/// tap target keeps the interactive region at least 48dp for accessibility.
abstract final class AppButtonStyles {
  static const double compactHeight = AppSize.compactControl;
  static const double primaryHeight = AppSize.primaryControl;
  static const double compactFontSize = 13;
  static const double primaryFontSize = 14;
  static const double compactLineHeight = 1.2;
  static const double primaryLineHeight = 1.2;
  static const FontWeight compactFontWeight = FontWeight.w600;
  static const FontWeight primaryFontWeight = FontWeight.w600;

  static TextStyle? _compactLabel(BuildContext context) {
    return Theme.of(context).textTheme.labelMedium?.copyWith(
      fontSize: compactFontSize,
      fontWeight: compactFontWeight,
      height: compactLineHeight,
      letterSpacing: 0,
    );
  }

  static ButtonStyle compact(BuildContext context) => compactFilled(context);

  static ButtonStyle compactFilled(BuildContext context) {
    return FilledButton.styleFrom(
      minimumSize: const Size(compactHeight, compactHeight),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      tapTargetSize: MaterialTapTargetSize.padded,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.control),
      textStyle: _compactLabel(context),
    );
  }

  static ButtonStyle compactOutlined(BuildContext context) {
    return OutlinedButton.styleFrom(
      minimumSize: const Size(compactHeight, compactHeight),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      tapTargetSize: MaterialTapTargetSize.padded,
      textStyle: _compactLabel(context),
    );
  }

  static ButtonStyle compactText(BuildContext context) {
    return TextButton.styleFrom(
      minimumSize: const Size(compactHeight, compactHeight),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      tapTargetSize: MaterialTapTargetSize.padded,
      textStyle: _compactLabel(context),
    );
  }

  static ButtonStyle compactIcon(BuildContext context) {
    return IconButton.styleFrom(
      minimumSize: const Size.square(AppSize.minimumTouchTarget),
      maximumSize: const Size.square(AppSize.minimumTouchTarget),
      padding: const EdgeInsets.all(AppSpacing.xs),
      tapTargetSize: MaterialTapTargetSize.padded,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.control),
      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
    );
  }
}

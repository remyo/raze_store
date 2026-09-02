import 'package:flutter/material.dart';

/// Color roles not represented by Material's [ColorScheme].
///
/// Every status has a foreground/background pair and should also be paired
/// with text or an icon so meaning never depends on color alone.
@immutable
class StoreColors extends ThemeExtension<StoreColors> {
  const StoreColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.price,
    required this.priceContainer,
    required this.onPriceContainer,
    required this.productImageBackground,
    required this.productImageForeground,
  });

  const StoreColors.light()
    : success = const Color(0xFF136B4D),
      onSuccess = Colors.white,
      successContainer = const Color(0xFFD8F4E7),
      onSuccessContainer = const Color(0xFF064630),
      warning = const Color(0xFF8B5900),
      onWarning = Colors.white,
      warningContainer = const Color(0xFFFFE2AD),
      onWarningContainer = const Color(0xFF3D2500),
      price = const Color(0xFF075E52),
      priceContainer = const Color(0xFFD8F4EC),
      onPriceContainer = const Color(0xFF003D35),
      productImageBackground = const Color(0xFFFFE7B8),
      productImageForeground = const Color(0xFF765000);

  const StoreColors.dark()
    : success = const Color(0xFF75DCB2),
      onSuccess = const Color(0xFF003824),
      successContainer = const Color(0xFF124B38),
      onSuccessContainer = const Color(0xFFA8F3D3),
      warning = const Color(0xFFFFC567),
      onWarning = const Color(0xFF452C00),
      warningContainer = const Color(0xFF533800),
      onWarningContainer = const Color(0xFFFFDFA5),
      price = const Color(0xFF7DD8C3),
      priceContainer = const Color(0xFF164C43),
      onPriceContainer = const Color(0xFFA8F2E1),
      productImageBackground = const Color(0xFF4D3912),
      productImageForeground = const Color(0xFFFFD68C);

  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;
  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color onWarningContainer;
  final Color price;
  final Color priceContainer;
  final Color onPriceContainer;
  final Color productImageBackground;
  final Color productImageForeground;

  @override
  StoreColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? price,
    Color? priceContainer,
    Color? onPriceContainer,
    Color? productImageBackground,
    Color? productImageForeground,
  }) {
    return StoreColors(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      price: price ?? this.price,
      priceContainer: priceContainer ?? this.priceContainer,
      onPriceContainer: onPriceContainer ?? this.onPriceContainer,
      productImageBackground:
          productImageBackground ?? this.productImageBackground,
      productImageForeground:
          productImageForeground ?? this.productImageForeground,
    );
  }

  @override
  StoreColors lerp(covariant StoreColors? other, double t) {
    if (other == null) return this;
    return StoreColors(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      successContainer: Color.lerp(
        successContainer,
        other.successContainer,
        t,
      )!,
      onSuccessContainer: Color.lerp(
        onSuccessContainer,
        other.onSuccessContainer,
        t,
      )!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      warningContainer: Color.lerp(
        warningContainer,
        other.warningContainer,
        t,
      )!,
      onWarningContainer: Color.lerp(
        onWarningContainer,
        other.onWarningContainer,
        t,
      )!,
      price: Color.lerp(price, other.price, t)!,
      priceContainer: Color.lerp(priceContainer, other.priceContainer, t)!,
      onPriceContainer: Color.lerp(
        onPriceContainer,
        other.onPriceContainer,
        t,
      )!,
      productImageBackground: Color.lerp(
        productImageBackground,
        other.productImageBackground,
        t,
      )!,
      productImageForeground: Color.lerp(
        productImageForeground,
        other.productImageForeground,
        t,
      )!,
    );
  }
}

extension StoreThemeContext on BuildContext {
  StoreColors get storeColors =>
      Theme.of(this).extension<StoreColors>() ?? const StoreColors.light();
}

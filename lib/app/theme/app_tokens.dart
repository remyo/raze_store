import 'package:flutter/widgets.dart';

/// Spacing values shared by Raze Store screens and components.
abstract final class AppSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
  static const double xxxl = 64;

  /// Responsive page gutters that remain comfortable on phones and tablets.
  static EdgeInsets pageInsetsFor(double width) {
    final horizontal = switch (width) {
      < AppBreakpoints.compact => md,
      < AppBreakpoints.medium => lg,
      _ => xl,
    };

    return EdgeInsets.symmetric(
      horizontal: horizontal,
      vertical: width < AppBreakpoints.compact ? md : lg,
    );
  }
}

/// Standard component dimensions, with touch targets kept at least 48dp.
abstract final class AppSize {
  static const double minimumTouchTarget = 48;
  static const double field = 56;
  static const double primaryButton = 56;
  static const double appBar = 64;
  static const double icon = 24;
  static const double smallThumbnail = 56;
  static const double thumbnail = 72;
  static const double largeThumbnail = 96;
}

/// A soft corner hierarchy inspired by familiar neighborhood-store packaging.
abstract final class AppRadius {
  static const double small = 8;
  static const double medium = 12;
  static const double large = 18;
  static const double extraLarge = 24;
  static const double pill = 999;

  static const BorderRadius control = BorderRadius.all(Radius.circular(medium));
  static const BorderRadius card = BorderRadius.all(Radius.circular(large));
  static const BorderRadius panel = BorderRadius.all(
    Radius.circular(extraLarge),
  );
}

/// Widths used to adapt page gutters and content density.
abstract final class AppBreakpoints {
  static const double compact = 600;
  static const double medium = 900;
  static const double expanded = 1200;
  static const double contentMaxWidth = 1280;
  static const double readingMaxWidth = 720;
}

abstract final class AppDurations {
  static const Duration quick = Duration(milliseconds: 150);
  static const Duration standard = Duration(milliseconds: 250);
}

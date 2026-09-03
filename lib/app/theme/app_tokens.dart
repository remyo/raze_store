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
  /// Dense visual controls still receive a padded 48dp Material hit target.
  static const double compactControl = 36;
  static const double compactChip = 34;
  static const double minimumTouchTarget = 48;
  static const double appBar = 44;
  static const double field = 48;
  static const double primaryControl = 42;

  /// Backwards-compatible name used by existing feature screens.
  static const double primaryButton = primaryControl;
  static const double compactRow = 48;
  static const double regularRow = 52;
  static const double comfortableRow = 64;
  static const double iconBadge = 40;
  static const double iconBadgeLarge = 44;
  static const double icon = 20;
  static const double iconLarge = 24;
  static const double smallThumbnail = 48;
  static const double thumbnail = 56;
  static const double largeThumbnail = 72;
}

/// A soft corner hierarchy inspired by familiar neighborhood-store packaging.
abstract final class AppRadius {
  static const double small = 8;
  static const double medium = 10;
  static const double large = 12;
  static const double extraLarge = 12;
  static const double pill = 999;

  static const BorderRadius control = BorderRadius.all(Radius.circular(medium));
  static const BorderRadius card = BorderRadius.all(Radius.circular(large));
  static const BorderRadius panel = BorderRadius.all(
    Radius.circular(extraLarge),
  );
  static const BorderRadius tile = BorderRadius.all(Radius.circular(large));
  static const BorderRadius dialog = BorderRadius.all(
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

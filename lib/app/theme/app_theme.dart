import 'package:flutter/material.dart';

import 'app_palette.dart';
import 'app_button_styles.dart';
import 'app_tokens.dart';
import 'store_colors.dart';

/// Material 3 themes for the warm, browse-first Raze Store experience.
abstract final class AppTheme {
  static final ThemeData light = _build(Brightness.light);
  static final ThemeData dark = _build(Brightness.dark);

  static ThemeData get lightTheme => light;
  static ThemeData get darkTheme => dark;

  static ColorScheme _scheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final generated = ColorScheme.fromSeed(
      seedColor: isDark ? AppPalette.mint : AppPalette.deepTeal,
      brightness: brightness,
      contrastLevel: 0.1,
    );

    return generated.copyWith(
      primary: isDark ? AppPalette.mint : AppPalette.deepTeal,
      onPrimary: isDark ? AppPalette.darkTeal : Colors.white,
      primaryContainer: isDark
          ? const Color(0xFF164C43)
          : const Color(0xFFD8F4EC),
      onPrimaryContainer: isDark
          ? const Color(0xFFA8F2E1)
          : AppPalette.darkTeal,
      secondary: isDark ? const Color(0xFFFFC567) : AppPalette.darkAmber,
      onSecondary: isDark ? const Color(0xFF452C00) : Colors.white,
      secondaryContainer: isDark
          ? const Color(0xFF533800)
          : const Color(0xFFFFE2AD),
      onSecondaryContainer: isDark
          ? const Color(0xFFFFDFA5)
          : const Color(0xFF3D2500),
      tertiary: isDark ? const Color(0xFFFFB4A9) : AppPalette.coral,
      onTertiary: isDark ? const Color(0xFF5F150D) : Colors.white,
      tertiaryContainer: isDark
          ? const Color(0xFF76261D)
          : const Color(0xFFFFDAD4),
      onTertiaryContainer: isDark
          ? const Color(0xFFFFDAD4)
          : const Color(0xFF6C1B13),
      error: isDark ? const Color(0xFFFFB4AB) : const Color(0xFFBA1A1A),
      onError: isDark ? const Color(0xFF690005) : Colors.white,
      errorContainer: isDark
          ? const Color(0xFF93000A)
          : const Color(0xFFFFDAD6),
      onErrorContainer: isDark
          ? const Color(0xFFFFDAD6)
          : const Color(0xFF410002),
      surface: isDark ? const Color(0xFF0C1513) : AppPalette.warmPaper,
      surfaceContainerLowest: isDark ? const Color(0xFF07100E) : Colors.white,
      surfaceContainerLow: isDark
          ? const Color(0xFF121D1A)
          : const Color(0xFFF7F4EA),
      surfaceContainer: isDark
          ? const Color(0xFF17231F)
          : const Color(0xFFF0EEE5),
      surfaceContainerHigh: isDark
          ? const Color(0xFF202C28)
          : const Color(0xFFEAE7DC),
      surfaceContainerHighest: isDark
          ? const Color(0xFF2B3733)
          : const Color(0xFFE3E1D7),
      onSurface: isDark ? const Color(0xFFE6F0EC) : AppPalette.ink,
      onSurfaceVariant: isDark
          ? const Color(0xFFB9C7C1)
          : const Color(0xFF56615D),
      outline: isDark ? const Color(0xFF83918C) : const Color(0xFF747E79),
      outlineVariant: isDark
          ? const Color(0xFF394641)
          : const Color(0xFFD1D8D3),
    );
  }

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = _scheme(brightness);
    final baseTextTheme = ThemeData(
      useMaterial3: true,
      brightness: brightness,
    ).textTheme;
    final textTheme = baseTextTheme.copyWith(
      displayLarge: baseTextTheme.displayLarge?.copyWith(
        fontSize: 44,
        fontWeight: FontWeight.w700,
        height: 1.1,
        letterSpacing: -1,
      ),
      displayMedium: baseTextTheme.displayMedium?.copyWith(
        fontSize: 36,
        fontWeight: FontWeight.w700,
        height: 1.12,
        letterSpacing: -0.8,
      ),
      displaySmall: baseTextTheme.displaySmall?.copyWith(
        fontSize: 30,
        fontWeight: FontWeight.w700,
        height: 1.15,
        letterSpacing: -0.6,
      ),
      headlineLarge: baseTextTheme.headlineLarge?.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        height: 1.18,
        letterSpacing: -0.45,
      ),
      headlineMedium: baseTextTheme.headlineMedium?.copyWith(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        height: 1.2,
        letterSpacing: -0.35,
      ),
      headlineSmall: baseTextTheme.headlineSmall?.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        height: 1.22,
        letterSpacing: -0.25,
      ),
      titleLarge: baseTextTheme.titleLarge?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        height: 1.25,
        letterSpacing: -0.1,
      ),
      titleMedium: baseTextTheme.titleMedium?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        height: 1.3,
        letterSpacing: 0,
      ),
      titleSmall: baseTextTheme.titleSmall?.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        height: 1.3,
        letterSpacing: 0,
      ),
      bodyLarge: baseTextTheme.bodyLarge?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: 1.45,
        letterSpacing: 0,
      ),
      bodyMedium: baseTextTheme.bodyMedium?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.45,
        letterSpacing: 0,
      ),
      bodySmall: baseTextTheme.bodySmall?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.4,
        letterSpacing: 0.1,
      ),
      labelLarge: baseTextTheme.labelLarge?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 1.25,
        letterSpacing: 0,
      ),
      labelMedium: baseTextTheme.labelMedium?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        height: 1.25,
        letterSpacing: 0,
      ),
      labelSmall: baseTextTheme.labelSmall?.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        height: 1.25,
        letterSpacing: 0.1,
      ),
    );
    final controlShape = RoundedRectangleBorder(
      borderRadius: AppRadius.control,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      textTheme: textTheme,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      iconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 22),
      primaryIconTheme: IconThemeData(color: scheme.onPrimary, size: 22),
      extensions: <ThemeExtension<dynamic>>[
        if (isDark) const StoreColors.dark() else const StoreColors.light(),
      ],
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: AppSize.appBar,
        centerTitle: true,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        titleSpacing: AppSpacing.md,
        titleTextStyle: textTheme.titleMedium?.copyWith(
          color: scheme.onSurface,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          height: 1.3,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.card,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        isDense: true,
        fillColor: isDark
            ? scheme.surfaceContainer
            : scheme.surfaceContainerLow,
        constraints: const BoxConstraints(minHeight: AppSize.field),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        floatingLabelStyle: textTheme.bodySmall?.copyWith(
          color: scheme.primary,
          fontWeight: FontWeight.w600,
        ),
        border: OutlineInputBorder(
          borderRadius: AppRadius.control,
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.control,
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.control,
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.control,
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadius.control,
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(
            AppButtonStyles.primaryHeight,
            AppButtonStyles.primaryHeight,
          ),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          tapTargetSize: MaterialTapTargetSize.padded,
          textStyle: textTheme.labelLarge?.copyWith(
            fontSize: AppButtonStyles.primaryFontSize,
            fontWeight: AppButtonStyles.primaryFontWeight,
            height: AppButtonStyles.primaryLineHeight,
            letterSpacing: 0,
          ),
          shape: controlShape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(
            AppButtonStyles.compactHeight,
            AppButtonStyles.compactHeight,
          ),
          foregroundColor: scheme.onSurface,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          tapTargetSize: MaterialTapTargetSize.padded,
          side: BorderSide(color: scheme.outlineVariant),
          textStyle: textTheme.labelMedium?.copyWith(
            fontSize: AppButtonStyles.compactFontSize,
            fontWeight: AppButtonStyles.compactFontWeight,
            height: AppButtonStyles.compactLineHeight,
            letterSpacing: 0,
          ),
          shape: controlShape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(
            AppButtonStyles.compactHeight,
            AppButtonStyles.compactHeight,
          ),
          foregroundColor: scheme.primary,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          tapTargetSize: MaterialTapTargetSize.padded,
          textStyle: textTheme.labelMedium?.copyWith(
            fontSize: AppButtonStyles.compactFontSize,
            fontWeight: AppButtonStyles.compactFontWeight,
            height: AppButtonStyles.compactLineHeight,
            letterSpacing: 0,
          ),
          shape: controlShape,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size.square(AppSize.minimumTouchTarget),
          iconSize: AppSize.icon,
          tapTargetSize: MaterialTapTargetSize.padded,
          shape: controlShape,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 2,
        focusElevation: 3,
        highlightElevation: 4,
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.card),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        elevation: 0,
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        indicatorShape: RoundedRectangleBorder(borderRadius: AppRadius.control),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
            size: states.contains(WidgetState.selected) ? 23 : 21,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return textTheme.labelMedium?.copyWith(
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        elevation: 0,
        backgroundColor: scheme.surfaceContainerLowest,
        indicatorColor: scheme.primaryContainer,
        indicatorShape: RoundedRectangleBorder(borderRadius: AppRadius.control),
        selectedIconTheme: IconThemeData(color: scheme.primary, size: 22),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        selectedLabelTextStyle: textTheme.labelMedium?.copyWith(
          color: scheme.primary,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: textTheme.labelMedium?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w500,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainer,
        selectedColor: scheme.primaryContainer,
        disabledColor: scheme.surfaceContainerHigh,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.control),
        labelStyle: textTheme.labelMedium?.copyWith(
          color: scheme.onSurface,
          fontSize: AppButtonStyles.compactFontSize,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xxs,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(
            Size(AppButtonStyles.compactHeight, AppButtonStyles.compactHeight),
          ),
          textStyle: WidgetStatePropertyAll(
            textTheme.labelMedium?.copyWith(
              fontSize: AppButtonStyles.compactFontSize,
              fontWeight: AppButtonStyles.compactFontWeight,
              height: AppButtonStyles.compactLineHeight,
              letterSpacing: 0,
            ),
          ),
          tapTargetSize: MaterialTapTargetSize.padded,
          shape: WidgetStatePropertyAll(controlShape),
        ),
      ),
      listTileTheme: ListTileThemeData(
        minTileHeight: AppSize.compactRow,
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xxs,
        ),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.tile),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      dialogTheme: DialogThemeData(
        elevation: 3,
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.dialog),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: scheme.surfaceContainerLowest,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.extraLarge),
          ),
        ),
        showDragHandle: true,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.control),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.primaryContainer,
        circularTrackColor: scheme.primaryContainer,
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 500),
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: const BorderRadius.all(
            Radius.circular(AppRadius.small),
          ),
        ),
        textStyle: textTheme.bodySmall?.copyWith(
          color: scheme.onInverseSurface,
        ),
      ),
    );
  }
}

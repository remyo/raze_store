import 'package:flutter/material.dart';

/// Blue-and-white styling scoped to GCash routes. Uses the app's typography
/// and follows its light/dark preference without changing the grocery theme.
class GcashTheme extends StatelessWidget {
  const GcashTheme({super.key, required this.builder});

  final WidgetBuilder builder;
  static const blue = Color(0xFF005CE5);
  static const deepBlue = Color(0xFF003CA7);

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final dark = base.brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: blue,
      brightness: base.brightness,
      primary: dark ? const Color(0xFFA9C7FF) : blue,
      secondary: dark ? const Color(0xFF9FCDFF) : const Color(0xFF0071DC),
      surface: dark ? const Color(0xFF101B2E) : const Color(0xFFF5F8FF),
    );
    final outline = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: scheme.outlineVariant),
    );
    final theme = ThemeData(
      useMaterial3: true,
      brightness: base.brightness,
      colorScheme: scheme,
      textTheme: base.textTheme,
      visualDensity: base.visualDensity,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarThemeData(
        backgroundColor: dark ? const Color(0xFF12356B) : blue,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: dark ? const Color(0xFF17263E) : Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        isDense: true,
        filled: true,
        fillColor: dark ? const Color(0xFF17263E) : Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 14,
        ),
        border: outline,
        enabledBorder: outline,
        focusedBorder: outline.copyWith(
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: outline.copyWith(
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: outline.copyWith(
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 44),
          side: BorderSide(color: scheme.primary.withValues(alpha: 0.4)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
    );
    return Theme(
      data: theme,
      child: Builder(builder: builder),
    );
  }
}

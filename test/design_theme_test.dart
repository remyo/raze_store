import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/app/theme/theme.dart';

void main() {
  group('AppTheme', () {
    test('provides distinct accessible Material 3 themes', () {
      expect(AppTheme.light.useMaterial3, isTrue);
      expect(AppTheme.dark.useMaterial3, isTrue);
      expect(AppTheme.light.brightness, Brightness.light);
      expect(AppTheme.dark.brightness, Brightness.dark);
      expect(AppTheme.light.colorScheme.primary, AppPalette.deepTeal);
      expect(AppTheme.dark.colorScheme.primary, AppPalette.mint);
      expect(AppTheme.light.extension<StoreColors>(), isNotNull);
      expect(AppTheme.dark.extension<StoreColors>(), isNotNull);
    });

    test('compact controls preserve padded Material touch targets', () {
      final theme = AppTheme.light;
      final filledStyle = theme.filledButtonTheme.style!;
      final outlinedStyle = theme.outlinedButtonTheme.style!;
      final iconStyle = theme.iconButtonTheme.style!;

      expect(
        filledStyle.minimumSize?.resolve({}),
        const Size.square(AppButtonStyles.primaryHeight),
      );
      expect(
        outlinedStyle.minimumSize?.resolve({}),
        const Size.square(AppButtonStyles.compactHeight),
      );
      expect(
        iconStyle.minimumSize?.resolve({}),
        const Size.square(AppSize.minimumTouchTarget),
      );
      expect(theme.materialTapTargetSize, MaterialTapTargetSize.padded);
      expect(filledStyle.tapTargetSize, MaterialTapTargetSize.padded);
      expect(outlinedStyle.tapTargetSize, MaterialTapTargetSize.padded);
    });

    test('uses the compact Raze Tag component hierarchy', () {
      final theme = AppTheme.light;

      expect(AppSize.appBar, 44);
      expect(AppSize.field, 48);
      expect(AppSize.primaryControl, 42);
      expect(AppSize.compactControl, 36);
      expect(AppSize.thumbnail, 56);
      expect(AppSize.largeThumbnail, 72);
      expect(AppRadius.medium, 10);
      expect(AppRadius.large, 12);
      expect(AppRadius.extraLarge, 12);
      expect(theme.appBarTheme.toolbarHeight, AppSize.appBar);
      expect(theme.appBarTheme.centerTitle, isTrue);
      expect(theme.navigationBarTheme.height, 64);
      expect(theme.listTileTheme.minTileHeight, AppSize.compactRow);
      expect(theme.inputDecorationTheme.constraints?.minHeight, AppSize.field);
    });

    test('uses the compact Raze Tag type scale', () {
      for (final theme in [AppTheme.light, AppTheme.dark]) {
        final text = theme.textTheme;

        _expectType(text.displayLarge, 44, FontWeight.w700);
        _expectType(text.displayMedium, 36, FontWeight.w700);
        _expectType(text.displaySmall, 30, FontWeight.w700);
        _expectType(text.headlineLarge, 28, FontWeight.w700);
        _expectType(text.headlineMedium, 24, FontWeight.w700);
        _expectType(text.headlineSmall, 22, FontWeight.w600);
        _expectType(text.titleLarge, 20, FontWeight.w600);
        _expectType(text.titleMedium, 15, FontWeight.w600);
        _expectType(text.titleSmall, 13, FontWeight.w600);
        _expectType(text.bodyLarge, 15, FontWeight.w400);
        _expectType(text.bodyMedium, 14, FontWeight.w400);
        _expectType(text.bodySmall, 12, FontWeight.w400);
        _expectType(text.labelLarge, 14, FontWeight.w600);
        _expectType(text.labelMedium, 12, FontWeight.w600);
        _expectType(text.labelSmall, 11, FontWeight.w500);
      }
    });

    testWidgets('dense visual buttons keep 48dp interactive layout', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FilledButton(
                  key: const ValueKey('filled'),
                  onPressed: () {},
                  child: const Text('Save'),
                ),
                OutlinedButton(
                  key: const ValueKey('outlined'),
                  onPressed: () {},
                  child: const Text('Import'),
                ),
              ],
            ),
          ),
        ),
      );

      expect(
        tester.getSize(find.byKey(const ValueKey('filled'))).height,
        greaterThanOrEqualTo(AppSize.minimumTouchTarget),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('outlined'))).height,
        greaterThanOrEqualTo(AppSize.minimumTouchTarget),
      );
    });

    test('core foreground pairs meet WCAG AA contrast', () {
      final light = AppTheme.light.colorScheme;
      final dark = AppTheme.dark.colorScheme;

      expect(
        _contrast(light.primary, light.onPrimary),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(light.secondaryContainer, light.onSecondaryContainer),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(dark.primary, dark.onPrimary),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(dark.surface, dark.onSurface),
        greaterThanOrEqualTo(4.5),
      );
    });
  });

  test('page gutters increase with available width', () {
    expect(AppSpacing.pageInsetsFor(375).horizontal, 32);
    expect(AppSpacing.pageInsetsFor(700).horizontal, 48);
    expect(AppSpacing.pageInsetsFor(1200).horizontal, 64);
  });
}

void _expectType(TextStyle? style, double size, FontWeight weight) {
  expect(style?.fontSize, size);
  expect(style?.fontWeight, weight);
}

double _contrast(Color first, Color second) {
  final lighter = first.computeLuminance() > second.computeLuminance()
      ? first
      : second;
  final darker = identical(lighter, first) ? second : first;
  return (lighter.computeLuminance() + 0.05) /
      (darker.computeLuminance() + 0.05);
}

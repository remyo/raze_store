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

    test('primary actions meet the minimum touch target', () {
      final buttonStyle = AppTheme.light.filledButtonTheme.style;
      final minimumSize = buttonStyle?.minimumSize?.resolve({});

      expect(minimumSize, isNotNull);
      expect(minimumSize!.width, greaterThanOrEqualTo(48));
      expect(minimumSize.height, greaterThanOrEqualTo(48));
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

double _contrast(Color first, Color second) {
  final lighter = first.computeLuminance() > second.computeLuminance()
      ? first
      : second;
  final darker = identical(lighter, first) ? second : first;
  return (lighter.computeLuminance() + 0.05) /
      (darker.computeLuminance() + 0.05);
}

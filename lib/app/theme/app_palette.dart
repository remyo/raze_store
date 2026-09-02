import 'package:flutter/material.dart';

/// Fixed brand colors. Prefer [Theme.of] color roles inside widgets so dark
/// mode and accessibility overrides continue to work.
abstract final class AppPalette {
  static const Color deepTeal = Color(0xFF075E52);
  static const Color darkTeal = Color(0xFF003D35);
  static const Color mint = Color(0xFF7DD8C3);
  static const Color warmAmber = Color(0xFFF4A624);
  static const Color darkAmber = Color(0xFF8B5900);
  static const Color coral = Color(0xFFC84C3D);
  static const Color warmPaper = Color(0xFFFAF8F2);
  static const Color ink = Color(0xFF17201D);
}

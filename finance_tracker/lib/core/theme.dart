/// Demo-1 emerald dark theme tokens (see docs/Design.md §1).
library;

import 'package:flutter/material.dart';

class AppColors {
  static const bg = Color(0xFF0B0F0E);
  static const surface = Color(0xFF111715);
  static const surface2 = Color(0xFF1A221F);
  static const text = Color(0xFFEDF2EF);
  static const text2 = Color(0xFFB9C6BF);
  static const text3 = Color(0xFF7D8B84);
  static const primary = Color(0xFF10B981);
  static const gold = Color(0xFFF5C044);
  static const danger = Color(0xFFF87171);
  static const line = Color(0x1AEDF2EF);
  static const inkOnPrimary = Color(0xFF06110C);
}

class AppText {
  /// 11px uppercase eyebrow label.
  static const eyebrow = TextStyle(
    fontSize: 11,
    letterSpacing: 1.4,
    fontWeight: FontWeight.w600,
    color: AppColors.text3,
  );

  /// Tabular numbers (mono-style without bundling a font file).
  static TextStyle mono(
    double size, {
    Color color = AppColors.text,
    FontWeight weight = FontWeight.w700,
  }) =>
      TextStyle(
        fontSize: size,
        fontWeight: weight,
        color: color,
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      );
}

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.primary,
      onPrimary: AppColors.inkOnPrimary,
      surface: AppColors.surface,
      error: AppColors.danger,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      elevation: 0,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: AppColors.text,
      ),
      iconTheme: IconThemeData(color: AppColors.text2),
    ),
    cardColor: AppColors.surface,
    dividerColor: AppColors.line,
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
  );
}

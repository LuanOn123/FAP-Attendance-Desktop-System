import 'package:flutter/material.dart';
import 'theme/app_palette.dart';

ThemeData buildTheme() {
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: AppPalette.line),
  );
  return ThemeData(
    useMaterial3: true,
    fontFamily: 'Segoe UI',
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppPalette.orange,
      primary: AppPalette.orange,
      onPrimary: Colors.white,
      primaryContainer: AppPalette.orangeSoft,
      onPrimaryContainer: AppPalette.orangeDark,
      surface: Colors.white,
      onSurface: AppPalette.ink,
      outlineVariant: AppPalette.line,
    ),
    scaffoldBackgroundColor: AppPalette.canvas,
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 36,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.2,
      ),
      headlineMedium: TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
      ),
      titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      bodyMedium: TextStyle(fontSize: 14, height: 1.5),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: AppPalette.ink,
      surfaceTintColor: Colors.transparent,
      toolbarHeight: 80,
      centerTitle: false,
      titleSpacing: 28,
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: Colors.white,
      indicatorColor: AppPalette.orangeSoft,
      selectedIconTheme: IconThemeData(color: AppPalette.orangeDark),
      unselectedIconTheme: IconThemeData(color: AppPalette.muted),
      selectedLabelTextStyle: TextStyle(
        fontFamily: 'Segoe UI',
        color: AppPalette.orangeDark,
        fontWeight: FontWeight.w700,
      ),
      unselectedLabelTextStyle: TextStyle(
        fontFamily: 'Segoe UI',
        color: AppPalette.muted,
        fontSize: 12,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: AppPalette.orange, width: 2),
      ),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: Colors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppPalette.line),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(
          fontFamily: 'Segoe UI',
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        side: const BorderSide(color: AppPalette.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    dividerTheme: const DividerThemeData(color: AppPalette.line, thickness: 1),
    chipTheme: ChipThemeData(
      backgroundColor: AppPalette.orangeSoft,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

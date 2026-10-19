import 'package:flutter/material.dart';

/// ZYVPAY palette — the familiar UPI-app look: a deep indigo/purple brand colour,
/// a teal accent for money-in, soft greys for surfaces.
class ZColors {
  static const brand = Color(0xFF4A2FBD);
  static const brandDark = Color(0xFF3B1E9E);
  static const accent = Color(0xFF00BFA6);
  static const success = Color(0xFF1AA260);
  static const danger = Color(0xFFE23B43);
  static const pending = Color(0xFFEC9A1E);
  static const ink = Color(0xFF17123B);
  static const mutedLight = Color(0xFF6B6A86);
}

ThemeData zyvTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: ZColors.brand,
    brightness: b,
    primary: ZColors.brand,
    secondary: ZColors.accent,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? const Color(0xFF12101F) : const Color(0xFFF5F4FA),
    fontFamily: 'Roboto',
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? const Color(0xFF12101F) : Colors.white,
      foregroundColor: dark ? Colors.white : ZColors.ink,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: dark ? const Color(0xFF1C1930) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF1C1930) : Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

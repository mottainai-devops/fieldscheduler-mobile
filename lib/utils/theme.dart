import 'package:flutter/material.dart';

class AppTheme {
  // ─── Primary palette ────────────────────────────────────────────────────────
  static const Color primaryColor   = Color(0xFF1565C0);
  static const Color accentColor    = Color(0xFF42A5F5);
  static const Color successColor   = Color(0xFF4CAF50);
  static const Color warningColor   = Color(0xFFFF9800);
  static const Color errorColor     = Color(0xFFF44336);
  static const Color dangerColor    = Color(0xFFF44336);

  // ─── Background colours ─────────────────────────────────────────────────────
  static const Color bgDark         = Color(0xFF0D1B2A);
  static const Color bgCard         = Color(0xFF1A2A3A);
  static const Color bgCardLight    = Color(0xFF243447);

  // ─── Text colours ───────────────────────────────────────────────────────────
  static const Color textPrimary    = Color(0xFFE8EDF2);
  static const Color textSecondary  = Color(0xFF8FA8C0);

  // ─── Misc ───────────────────────────────────────────────────────────────────
  static const Color borderColor    = Color(0xFF2C3E50);

  static ThemeData get lightTheme {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        brightness: Brightness.light,
      ),
      useMaterial3: true,
      appBarTheme: const AppBarTheme(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      cardTheme: CardTheme(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

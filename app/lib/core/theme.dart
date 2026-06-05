import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class TimoColors {
  static const Color background = Color(0xFF0F0F0F); // Deep black
  static const Color surface = Color(0xFF1A1A1A); // Card background
  static const Color border = Color(0xFF2A2A2A); // Divider
  static const Color primary = Color(0xFFFF6B35); // xboom orange
  static const Color success = Color(0xFF4ADE80); // Green
  static const Color error = Color(0xFFEF4444); // Red
  static const Color warning = Color(0xFFFBBF24); // Amber
  static const Color textPrimary = Color(0xFFFFFFFF); // White
  static const Color textSecondary = Color(0xFF9CA3AF); // Grey
}

class TimoTheme {
  static ThemeData get dark {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: TimoColors.background,
      canvasColor: TimoColors.surface,
      colorScheme: ColorScheme.dark(
        primary: TimoColors.primary,
        surface: TimoColors.surface,
        error: TimoColors.error,
        onPrimary: Colors.black,
        onSurface: TimoColors.textPrimary,
      ),
      textTheme: GoogleFonts.interTextTheme(
        ThemeData(brightness: Brightness.dark).textTheme.copyWith(
          headlineLarge: GoogleFonts.inter(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: TimoColors.textPrimary,
          ),
          titleLarge: GoogleFonts.inter(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: TimoColors.textPrimary,
          ),
          bodyMedium: GoogleFonts.inter(
            fontSize: 14,
            color: TimoColors.textPrimary,
          ),
          labelSmall: GoogleFonts.inter(
            fontSize: 12,
            color: TimoColors.textSecondary,
          ),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: TimoColors.surface,
        elevation: 1,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: TimoColors.textPrimary,
        ),
      ),
      cardTheme: CardTheme(
        color: TimoColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: TimoColors.border, width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: TimoColors.primary,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: TimoColors.surface,
          foregroundColor: TimoColors.textPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: TimoColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: TimoColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: TimoColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: TimoColors.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        hintStyle: const TextStyle(color: TimoColors.textSecondary),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: TimoColors.surface,
        labelStyle: GoogleFonts.inter(color: TimoColors.textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: TimoColors.border),
        ),
      ),
    );
  }
}

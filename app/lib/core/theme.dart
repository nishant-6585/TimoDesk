import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class MikeeColors {
  // Layout & backgrounds
  static const Color background = Color(0xFF0F0F0F); // App bg
  static const Color surface = Color(0xFF121212); // Header, sidebar
  static const Color cardTop = Color(0xFF1A1A1A);
  static const Color cardBottom = Color(0xFF161616);
  static const Color inset = Color(0xFF141414); // Action buttons

  // Borders & dividers
  static const Color border = Color(0xFF2A2A2A);
  static const Color borderFaint = Color(0xFF222222);

  // Brand colors
  static const Color primary = Color(0xFFFF6B35); // xboom orange
  static const Color primaryDark = Color(0xFFE14B1E); // Logo gradient

  // Status colors
  static const Color success = Color(0xFF4ADE80); // Green / online
  static const Color error = Color(0xFFEF4444); // Red / stop
  static const Color errorPressed = Color(0xFF7F1D1D); // Dark red pressed
  static const Color info = Color(0xFF3B82F6); // Blue / commands
  static const Color warning = Color(0xFFF59E0B); // Amber / battery

  // Text colors
  static const Color textPrimary = Color(0xFFFFFFFF); // White
  static const Color textSecondary = Color(0xFF9CA3AF); // Grey
  static const Color textMuted = Color(0xFF6B7280); // Darker grey
}

class MikeeTheme {
  static ThemeData get dark {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: MikeeColors.background,
      canvasColor: MikeeColors.surface,
      colorScheme: ColorScheme.dark(
        primary: MikeeColors.primary,
        surface: MikeeColors.surface,
        error: MikeeColors.error,
        onPrimary: Colors.black,
        onSurface: MikeeColors.textPrimary,
      ),
      textTheme: GoogleFonts.interTextTheme(
        ThemeData(brightness: Brightness.dark).textTheme.copyWith(
          headlineLarge: GoogleFonts.inter(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: MikeeColors.textPrimary,
          ),
          titleLarge: GoogleFonts.inter(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: MikeeColors.textPrimary,
          ),
          bodyMedium: GoogleFonts.inter(
            fontSize: 14,
            color: MikeeColors.textPrimary,
          ),
          labelSmall: GoogleFonts.inter(
            fontSize: 12,
            color: MikeeColors.textSecondary,
          ),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: MikeeColors.surface,
        elevation: 1,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: MikeeColors.textPrimary,
        ),
      ),
      cardTheme: CardThemeData(
        color: MikeeColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: MikeeColors.border, width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: MikeeColors.primary,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: MikeeColors.surface,
          foregroundColor: MikeeColors.textPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: MikeeColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: MikeeColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: MikeeColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: MikeeColors.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        hintStyle: const TextStyle(color: MikeeColors.textSecondary),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: MikeeColors.surface,
        labelStyle: GoogleFonts.inter(color: MikeeColors.textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: MikeeColors.border),
        ),
      ),
    );
  }
}

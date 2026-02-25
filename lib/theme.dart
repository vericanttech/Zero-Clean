// ─────────────────────────────────────────────
//  ZERO-CLEAN  ·  Theme
// ─────────────────────────────────────────────

import 'package:flutter/material.dart';

class ZCTheme {
  // ── Palette (light mode — preferred in Senegal) ─────
  static const bg = Color(0xFFF5F6F8);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceAlt = Color(0xFFEEF0F3);
  static const border = Color(0xFFD8DCE4);

  static const accent = Color(0xFF00B89A);       // teal — primary action
  static const accentDim = Color(0xFF008F77);
  static const gold = Color(0xFFE5A020);         // shutter locked / building
  static const critical = Color(0xFFD32F2F);     // <30%
  static const building = Color(0xFFE5A020);    // 30–80%
  static const saturated = Color(0xFF00B89A);    // >100%

  static const textPrimary = Color(0xFF1A1D24);
  static const textSecondary = Color(0xFF4A5165);
  static const textMuted = Color(0xFF6B7280);

  // ── Typography ────────────────────────────
  // Using system fonts — in real project add "Space Mono" + "DM Sans" via google_fonts
  static const fontMono = 'monospace';

  static ThemeData get theme => ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: bg,
        colorScheme: const ColorScheme.light(
          surface: surface,
          primary: accent,
          secondary: gold,
          error: critical,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: bg,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
          iconTheme: IconThemeData(color: textPrimary),
        ),
        cardTheme: CardThemeData(
          color: surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: border),
          ),
          margin: const EdgeInsets.symmetric(vertical: 6),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: surface,
          selectedItemColor: accent,
          unselectedItemColor: textMuted,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: surfaceAlt,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: accent, width: 1.5),
          ),
          labelStyle: const TextStyle(color: textSecondary),
          hintStyle: const TextStyle(color: textMuted),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            textStyle: const TextStyle(
                fontWeight: FontWeight.w700, letterSpacing: 0.5),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: accent),
        ),
        dividerTheme: const DividerThemeData(color: border, thickness: 1),
      );

  // ── Progress ring color ───────────────────
  static Color progressColor(double pct) {
    if (pct < 0.30) return critical;
    if (pct < 1.00) return building;
    return saturated;
  }

  // ── Progress status label ─────────────────
  static String progressEmoji(double pct) {
    if (pct < 0.30) return '🔴';
    if (pct < 1.00) return '🟡';
    return '🟢';
  }
}

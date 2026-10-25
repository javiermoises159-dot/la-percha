import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Estilo de títulos de La Percha.
TextStyle display(double size, {Color? color, double height = 1.1}) {
  return GoogleFonts.outfit(
    fontSize: size,
    fontWeight: FontWeight.w700,
    height: height,
    color: color,
    letterSpacing: -size * 0.015,
  );
}

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final bg = dark ? const Color(0xFF0F1512) : const Color(0xFFF2F4F0);
  final surface = dark ? const Color(0xFF18211D) : Colors.white;
  final ink = dark ? const Color(0xFFEEF3EF) : const Color(0xFF14201B);
  final accent = dark ? const Color(0xFFFF7C9F) : const Color(0xFFC92A58);
  final onAccent = dark ? const Color(0xFF2B0713) : Colors.white;
  final leaf = dark ? const Color(0xFF5ED0A0) : const Color(0xFF17694A);

  final scheme = ColorScheme(
    brightness: b,
    primary: accent,
    onPrimary: onAccent,
    secondary: leaf,
    onSecondary: bg,
    error: accent,
    onError: onAccent,
    surface: surface,
    onSurface: ink,
  );

  final base = ThemeData(brightness: b);
  final text = GoogleFonts.figtreeTextTheme(base.textTheme)
      .apply(bodyColor: ink, displayColor: ink);
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));

  return ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: scheme,
    scaffoldBackgroundColor: bg,
    textTheme: text,
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      foregroundColor: ink,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      indicatorColor: accent.withAlpha(40),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: shape,
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: shape,
        side: BorderSide(color: ink.withAlpha(50)),
        foregroundColor: ink,
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: ink.withAlpha(40)),
      ),
    ),
  );
}

extension PaletteX on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  Color get muted => isDark ? const Color(0xFF9FB0A7) : const Color(0xFF56655E);
  Color get leaf => isDark ? const Color(0xFF5ED0A0) : const Color(0xFF17694A);
  Color get leafSoft =>
      isDark ? const Color(0xFF173A2B) : const Color(0xFFD9EFE3);
  Color get chip => isDark ? const Color(0xFF222D27) : const Color(0xFFE6EBE5);
}

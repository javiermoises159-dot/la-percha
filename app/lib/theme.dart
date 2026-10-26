import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Identidad de La Percha: blanco, tinta cálida y un solo acento rojo arcilla.
/// La foto del artículo es la protagonista; el color se usa solo para actuar.
class LP {
  static const ink = Color(0xFF161412);
  static const muted = Color(0xFF77716B);
  static const line = Color(0xFFECE8E3);
  static const soft = Color(0xFFF6F3EF);
  static const clay = Color(0xFFE0452C); // acento de marca
  static const ok = Color(0xFF1F7A4D); // compra protegida, bajadas de precio
  static const okSoft = Color(0xFFE3F1E9);

  // Versión oscura
  static const inkD = Color(0xFFF3EFEA);
  static const mutedD = Color(0xFFA49D96);
  static const lineD = Color(0xFF2C2825);
  static const softD = Color(0xFF221F1C);
  static const bgD = Color(0xFF141210);
  static const clayD = Color(0xFFFF6A50);
  static const okD = Color(0xFF5CC68E);
  static const okSoftD = Color(0xFF173528);
}

/// Estilo de títulos (Onest, apretado).
TextStyle display(double size, {Color? color, double height = 1.1}) {
  return GoogleFonts.onest(
    fontSize: size,
    fontWeight: FontWeight.w800,
    height: height,
    color: color,
    letterSpacing: -size * 0.035,
  );
}

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final bg = dark ? LP.bgD : Colors.white;
  final soft = dark ? LP.softD : LP.soft;
  final line = dark ? LP.lineD : LP.line;
  final ink = dark ? LP.inkD : LP.ink;
  final accent = dark ? LP.clayD : LP.clay;
  final ok = dark ? LP.okD : LP.ok;

  final scheme = ColorScheme(
    brightness: b,
    primary: accent,
    onPrimary: Colors.white,
    secondary: ink,
    onSecondary: bg,
    error: const Color(0xFFB3261E),
    onError: Colors.white,
    surface: bg,
    onSurface: ink,
    surfaceContainerHighest: soft,
    outline: line,
    outlineVariant: line,
    tertiary: ok,
  );

  final base = ThemeData(brightness: b);
  final text = GoogleFonts.onestTextTheme(base.textTheme)
      .apply(bodyColor: ink, displayColor: ink);
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
  const btnText =
      TextStyle(fontWeight: FontWeight.w700, fontSize: 16, letterSpacing: -0.2);

  return ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: scheme,
    scaffoldBackgroundColor: bg,
    textTheme: text,
    dividerColor: line,
    dividerTheme: DividerThemeData(color: line, space: 1, thickness: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      foregroundColor: ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: display(20, color: ink),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: bg,
      elevation: 0,
      height: 66,
      indicatorColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontSize: 11,
            fontWeight: s.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: s.contains(WidgetState.selected)
                ? ink
                : (dark ? LP.mutedD : LP.muted),
          )),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
            color: s.contains(WidgetState.selected)
                ? ink
                : (dark ? LP.mutedD : LP.muted),
          )),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: bg,
      indicatorColor: soft,
      selectedIconTheme: IconThemeData(color: ink),
      unselectedIconTheme: IconThemeData(color: dark ? LP.mutedD : LP.muted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(50),
        shape: shape,
        elevation: 0,
        textStyle: btnText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(50),
        shape: shape,
        side: BorderSide(color: ink, width: 1.5),
        foregroundColor: ink,
        textStyle: btnText,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
          foregroundColor: ink,
          textStyle: const TextStyle(fontWeight: FontWeight.w600)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: soft,
      selectedColor: ink,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      labelStyle: TextStyle(color: ink, fontWeight: FontWeight.w600),
      secondaryLabelStyle: TextStyle(color: bg, fontWeight: FontWeight.w600),
      checkmarkColor: bg,
    ),
    cardTheme: CardThemeData(
      color: bg,
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: line)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: ink,
      contentTextStyle: TextStyle(color: bg, fontWeight: FontWeight.w500),
      behavior: SnackBarBehavior.floating,
      shape: shape,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: bg,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: soft,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: ink, width: 1.5)),
      labelStyle: TextStyle(color: dark ? LP.mutedD : LP.muted),
      hintStyle: TextStyle(color: dark ? LP.mutedD : LP.muted),
    ),
  );
}

extension PaletteX on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  Color get ink => isDark ? LP.inkD : LP.ink;
  Color get muted => isDark ? LP.mutedD : LP.muted;
  Color get line => isDark ? LP.lineD : LP.line;
  Color get soft => isDark ? LP.softD : LP.soft;
  // Nombres antiguos, ahora con la paleta nueva.
  Color get leaf => isDark ? LP.okD : LP.ok;
  Color get leafSoft => isDark ? LP.okSoftD : LP.okSoft;
  Color get chip => soft;
}

/// Logotipo de texto: "la percha." con el punto en rojo arcilla.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.size = 24});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(children: [
        const TextSpan(text: 'la percha'),
        TextSpan(
            text: '.',
            style: TextStyle(color: Theme.of(context).colorScheme.primary)),
      ]),
      style: display(size, color: context.ink),
    );
  }
}

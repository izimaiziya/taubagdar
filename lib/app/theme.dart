import 'package:flutter/material.dart';

/// Палитра взята из рисунков Алана и логотипа:
/// тёмно-синяя обводка, ледяной мех, сине-сиреневые пятна, синий и зелёный логотипа.
/// Красный логотипа — только для риска и SOS.
class Tb {
  static const sky = Color(0xFF1182AE); // основной: синий из «Тау» в логотипе
  static const skyDeep = Color(0xFF0B5E8A); // нажатие, ссылки
  static const night = Color(0xFF0B347C); // обводка Алана: заголовки, контуры
  static const ink = Color(0xFF1E3560); // основной текст
  static const slate = Color(0xFF5B6F92); // вторичный текст
  static const ice = Color(0xFFEEF6FA); // фон экранов
  static const air = Color(0xFFD9EEF4); // небо в шапках, фон головы Алана
  static const mist = Color(0xFFCFE3EC); // границы, подложки
  static const haze = Color(0xFFA4D3DF); // мех Алана, дальние хребты
  static const dusk = Color(0xFF6680C2); // пятна Алана, средние хребты
  static const leaf = Color(0xFF4AAB57); // зелёный «Бағдар»
  static const snow = Colors.white;

  static const safe = Color(0xFF3A9A4C); // зелёный логотипа, чуть темнее для текста
  static const caution = Color(0xFFE39B00);
  static const danger = Color(0xFFE8334B); // красная стрелка логотипа

  static const display = 'MontserratAlternates';
  static const body = 'Onest';
}

ThemeData buildTheme() {
  const scheme = ColorScheme.light(
    primary: Tb.sky,
    onPrimary: Colors.white,
    secondary: Tb.skyDeep,
    surface: Tb.snow,
    onSurface: Tb.ink,
    error: Tb.danger,
  );

  TextStyle d(double size, FontWeight w, {double h = 1.12, double ls = -0.4}) => TextStyle(
      fontFamily: Tb.display, fontSize: size, fontWeight: w, height: h, letterSpacing: ls, color: Tb.night);
  TextStyle b(double size, FontWeight w, {double h = 1.45, Color c = Tb.ink}) =>
      TextStyle(fontFamily: Tb.body, fontSize: size, fontWeight: w, height: h, color: c);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Tb.ice,
    fontFamily: Tb.body,
    textTheme: TextTheme(
      displayLarge: d(40, FontWeight.w800, h: 1.05, ls: -1.0),
      displayMedium: d(32, FontWeight.w800, ls: -0.8),
      displaySmall: d(26, FontWeight.w800, ls: -0.5),
      headlineSmall: d(21, FontWeight.w700, ls: -0.3),
      titleLarge: b(18, FontWeight.w700, h: 1.3, c: Tb.night),
      titleMedium: b(16, FontWeight.w600, h: 1.3, c: Tb.night),
      bodyLarge: b(17, FontWeight.w400),
      bodyMedium: b(15.5, FontWeight.w400),
      bodySmall: b(13.5, FontWeight.w400, c: Tb.slate),
      labelLarge: b(16, FontWeight.w600, h: 1.2),
      labelMedium: b(13, FontWeight.w600, h: 1.2, c: Tb.slate),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      foregroundColor: Tb.night,
      centerTitle: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Tb.snow,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      hintStyle: b(17, FontWeight.w400, c: Tb.slate.withValues(alpha: .7)),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: Tb.mist, width: 1.5)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: Tb.mist, width: 1.5)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: Tb.sky, width: 2)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Tb.night,
      contentTextStyle: b(15, FontWeight.w500, c: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}

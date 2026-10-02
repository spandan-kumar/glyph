import 'package:flutter/material.dart';

abstract final class GlyphColors {
  static const background = Color(0xFF09090E);
  static const surface = Color(0xFF13131B);
  static const surfaceHigh = Color(0xFF1C1C27);
  static const outline = Color(0xFF2A2A38);
  static const primary = Color(0xFF8B7CFF);
  static const accent = Color(0xFF3DDCFF);
  static const text = Color(0xFFEDEDF5);
  static const textMuted = Color(0xFF8C8CA3);
  static const warning = Color(0xFFFFB547);
  static const danger = Color(0xFFFF5C7A);
  static const success = Color(0xFF4BE3A0);

  static const brandGradient = LinearGradient(
    colors: [primary, accent],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: GlyphColors.primary,
    brightness: Brightness.dark,
  ).copyWith(
    primary: GlyphColors.primary,
    secondary: GlyphColors.accent,
    surface: GlyphColors.surface,
    surfaceContainerHighest: GlyphColors.surfaceHigh,
    outline: GlyphColors.outline,
    onSurface: GlyphColors.text,
    error: GlyphColors.danger,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: GlyphColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: GlyphColors.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: GlyphColors.surface,
      indicatorColor: GlyphColors.primary.withValues(alpha: 0.18),
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      ),
    ),
    cardTheme: CardThemeData(
      color: GlyphColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: GlyphColors.outline),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: GlyphColors.surface,
      selectedColor: GlyphColors.primary.withValues(alpha: 0.22),
      side: const BorderSide(color: GlyphColors.outline),
      shape: const StadiumBorder(),
      labelStyle: const TextStyle(fontWeight: FontWeight.w500),
    ),
    sliderTheme: const SliderThemeData(
      trackHeight: 4,
      activeTrackColor: GlyphColors.primary,
      inactiveTrackColor: GlyphColors.outline,
      thumbColor: Colors.white,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: GlyphColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: GlyphColors.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
  );
}

import 'package:flutter/material.dart';

import 'design/tokens.dart';
import 'design/type.dart';

/// Legacy names still used by feature screens; mapped onto Lightbox tokens so
/// everything shares one palette. New code should use [Lb] directly.
abstract final class GlyphColors {
  static const background = Lb.ink;
  static const surface = Lb.panel;
  static const surfaceHigh = Lb.raised;
  static const outline = Lb.line;
  static const primary = Lb.phosphor;
  static const accent = Lb.phosphor;
  static const text = Lb.text;
  static const textMuted = Lb.text2;
  static const warning = Lb.phosphor;
  static const danger = Lb.danger;
  static const success = Lb.ok;

  static const brandGradient = LinearGradient(colors: [Lb.text, Lb.text]);
}

ThemeData buildTheme() {
  final scheme = const ColorScheme.dark(
    primary: Lb.text,
    onPrimary: Lb.ink,
    secondary: Lb.phosphor,
    onSecondary: Lb.ink,
    surface: Lb.panel,
    onSurface: Lb.text,
    surfaceContainerHighest: Lb.raised,
    surfaceContainerHigh: Lb.raised,
    surfaceContainer: Lb.panel,
    surfaceContainerLow: Lb.panel,
    outline: Lb.line,
    outlineVariant: Lb.line,
    error: Lb.danger,
    onSurfaceVariant: Lb.text2,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Lb.ink,
    fontFamily: 'Bricolage',
    splashFactory: InkSparkle.splashFactory,
  );

  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      displaySmall: LbType.display,
      headlineSmall: LbType.title,
      titleLarge: LbType.title,
      titleMedium: LbType.heading,
      titleSmall: LbType.bodyStrong,
      bodyLarge: LbType.body,
      bodyMedium: LbType.body,
      bodySmall: LbType.small,
      labelLarge: LbType.bodyStrong,
      labelMedium: LbType.label,
      labelSmall: LbType.label,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: LbType.heading,
      foregroundColor: Lb.text,
    ),
    cardTheme: const CardThemeData(
      color: Lb.panel,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(Lb.rPanel)),
        side: Lb.hairline,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Lb.text,
        foregroundColor: Lb.ink,
        disabledBackgroundColor: Lb.raised,
        disabledForegroundColor: Lb.text3,
        textStyle: LbType.bodyStrong,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(Lb.rPanel))),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Lb.text,
        side: Lb.hairline,
        textStyle: LbType.bodyStrong,
        minimumSize: const Size(48, 44),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(Lb.rPanel))),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Lb.text,
        textStyle: LbType.bodyStrong,
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
    ),
    chipTheme: ChipThemeData(
      color: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Lb.text : Colors.transparent),
      side: Lb.hairline,
      shape: const StadiumBorder(),
      labelStyle: LbType.small.copyWith(
        color: WidgetStateColor.resolveWith((s) => s.contains(WidgetState.selected) ? Lb.ink : Lb.text),
      ),
      showCheckmark: false,
    ),
    sliderTheme: SliderThemeData(
      trackHeight: 2,
      activeTrackColor: Lb.text,
      inactiveTrackColor: Lb.line,
      thumbColor: Lb.text,
      overlayColor: Lb.text.withValues(alpha: 0.08),
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Lb.ink : Lb.text2),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Lb.text : Lb.raised),
      trackOutlineColor: const WidgetStatePropertyAll(Lb.line),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Lb.panel,
      hintStyle: LbType.body.copyWith(color: Lb.text3),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Lb.rPanel),
        borderSide: Lb.hairline,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Lb.rPanel),
        borderSide: Lb.hairline,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Lb.rPanel),
        borderSide: const BorderSide(color: Lb.text2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Lb.panel,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: Lb.line,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Lb.rSheet)),
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: Lb.panel,
      insetPadding: EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      actionsPadding: EdgeInsets.fromLTRB(16, 0, 16, 16),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(Lb.rSheet)),
        side: Lb.hairline,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Lb.raised,
      contentTextStyle: LbType.body,
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(Lb.rPanel)),
        side: Lb.hairline,
      ),
    ),
    dividerTheme: const DividerThemeData(color: Lb.line, thickness: 1, space: 1),
    listTileTheme: ListTileThemeData(
      titleTextStyle: LbType.bodyStrong,
      subtitleTextStyle: LbType.small,
      iconColor: Lb.text2,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: Lb.text,
      linearTrackColor: Lb.line,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        side: Lb.hairline,
        selectedBackgroundColor: Lb.text,
        selectedForegroundColor: Lb.ink,
        foregroundColor: Lb.text2,
      ),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: Lb.panel,
      indicatorColor: Lb.raised,
    ),
  );
}

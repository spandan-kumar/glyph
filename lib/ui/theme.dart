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
}

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
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
    surfaceContainerLowest: Lb.ink,
    outline: Lb.line,
    outlineVariant: Lb.line,
    error: Lb.danger,
    onError: Lb.ink,
    onSurfaceVariant: Lb.text2,
    inverseSurface: Lb.text,
    onInverseSurface: Lb.ink,
    surfaceTint: Colors.transparent,
  );

  // Every Material text role maps onto an LbType style, so a Text without a
  // style still lands in Bricolage / DM Mono, never Roboto.
  final text = TextTheme(
    displayLarge: LbType.display,
    displayMedium: LbType.display,
    displaySmall: LbType.display,
    headlineLarge: LbType.title,
    headlineMedium: LbType.title,
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
  );

  const control = RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(Lb.rControl)));
  const panel = RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(Lb.rPanel)));
  const panelLined = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(Lb.rPanel)),
    side: Lb.hairline,
  );
  const sheet = RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(Lb.rSheet)), side: Lb.hairline);
  OutlineInputBorder field(Color c) => OutlineInputBorder(
    borderRadius: const BorderRadius.all(Radius.circular(Lb.rPanel)),
    borderSide: BorderSide(color: c),
  );
  final menuStyle = MenuStyle(
    backgroundColor: const WidgetStatePropertyAll(Lb.raised),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    elevation: const WidgetStatePropertyAll(0),
    shape: const WidgetStatePropertyAll(panelLined),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Lb.ink,
    canvasColor: Lb.ink,
    fontFamily: 'Bricolage',
    textTheme: text,
    primaryTextTheme: text.apply(bodyColor: Lb.ink, displayColor: Lb.ink),
    // A plain ripple clipped to each control's rectangle; the M3 sparkle reads
    // as stock Android.
    splashFactory: InkRipple.splashFactory,
    iconTheme: const IconThemeData(color: Lb.text),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: Lb.phosphor,
      selectionColor: Lb.phosphor.withValues(alpha: 0.3),
      selectionHandleColor: Lb.phosphor,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: LbType.heading,
      toolbarTextStyle: LbType.body,
      foregroundColor: Lb.text,
    ),
    cardTheme: const CardThemeData(
      color: Lb.panel,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: panelLined,
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
        shape: panel,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: Lb.raised,
        foregroundColor: Lb.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        side: Lb.hairline,
        textStyle: LbType.bodyStrong,
        minimumSize: const Size(48, 44),
        shape: panel,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Lb.text,
        side: Lb.hairline,
        textStyle: LbType.bodyStrong,
        minimumSize: const Size(48, 44),
        shape: panel,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Lb.text,
        textStyle: LbType.bodyStrong,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        shape: control,
      ),
    ),
    // Shape only: forcing a colour here once hid icons on filled buttons.
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(shape: control)),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: Lb.text,
      foregroundColor: Lb.ink,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      shape: panel,
      extendedTextStyle: LbType.bodyStrong,
    ),
    menuButtonTheme: MenuButtonThemeData(
      style: MenuItemButton.styleFrom(textStyle: LbType.body, shape: control),
    ),
    toggleButtonsTheme: ToggleButtonsThemeData(
      borderRadius: const BorderRadius.all(Radius.circular(Lb.rControl)),
      borderColor: Lb.line,
      selectedBorderColor: Lb.line,
      selectedColor: Lb.ink,
      fillColor: Lb.text,
      color: Lb.text2,
      textStyle: LbType.bodyStrong,
    ),
    chipTheme: ChipThemeData(
      color: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Lb.text : Colors.transparent),
      side: Lb.hairline,
      shape: control,
      labelStyle: LbType.small.copyWith(
        color: WidgetStateColor.resolveWith((s) => s.contains(WidgetState.selected) ? Lb.ink : Lb.text),
      ),
      secondaryLabelStyle: LbType.small.copyWith(color: Lb.ink),
      showCheckmark: false,
    ),
    sliderTheme: SliderThemeData(
      trackHeight: 2,
      activeTrackColor: Lb.text,
      inactiveTrackColor: Lb.line,
      thumbColor: Lb.text,
      disabledThumbColor: Lb.text3,
      overlayColor: Lb.text.withValues(alpha: 0.08),
      valueIndicatorColor: Lb.text,
      valueIndicatorTextStyle: LbType.label.copyWith(color: Lb.ink),
      thumbShape: const _SquareThumb(),
      overlayShape: const _SquareOverlay(),
      trackShape: const RectangularSliderTrackShape(),
      valueIndicatorShape: const _BlockValueIndicator(),
      rangeThumbShape: const _SquareRangeThumb(),
      rangeTrackShape: const RectangularRangeSliderTrackShape(),
      // The range variant has no theme-free override short of a full
      // reimplementation; its 4 px corners are the one near-miss left.
      rangeValueIndicatorShape: const RectangularRangeSliderValueIndicatorShape(),
    ),
    // Material switches should not appear (use LbToggle); colours only, in
    // case a stray one does.
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Lb.ink : Lb.text2),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Lb.text : Lb.raised),
      trackOutlineColor: const WidgetStatePropertyAll(Lb.line),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(Lb.rTile))),
      side: const BorderSide(color: Lb.text2, width: 1.5),
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Lb.text : null),
      checkColor: const WidgetStatePropertyAll(Lb.ink),
    ),
    // Radio can't be reshaped through the theme; its ring-and-dot reads as an
    // LED, which the language allows to be round.
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Lb.phosphor : Lb.text2),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: Lb.panel,
      hintStyle: LbType.body.copyWith(color: Lb.text3),
      labelStyle: LbType.body.copyWith(color: Lb.text2),
      floatingLabelStyle: LbType.small.copyWith(color: Lb.text2),
      helperStyle: LbType.small,
      errorStyle: LbType.small.copyWith(color: Lb.danger),
      prefixStyle: LbType.body,
      suffixStyle: LbType.body,
      counterStyle: LbType.label,
      border: field(Lb.line),
      enabledBorder: field(Lb.line),
      disabledBorder: field(Lb.line),
      focusedBorder: field(Lb.text2),
      errorBorder: field(Lb.danger),
      focusedErrorBorder: field(Lb.danger),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      textStyle: LbType.body,
      menuStyle: menuStyle,
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: Lb.panel,
        border: field(Lb.line),
        enabledBorder: field(Lb.line),
        focusedBorder: field(Lb.text2),
      ),
    ),
    menuTheme: MenuThemeData(style: menuStyle),
    menuBarTheme: MenuBarThemeData(style: menuStyle),
    popupMenuTheme: PopupMenuThemeData(
      color: Lb.raised,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: panelLined,
      textStyle: LbType.body,
      labelTextStyle: WidgetStatePropertyAll(LbType.body),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Lb.panel,
      modalBackgroundColor: Lb.panel,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: Lb.line,
      // A thin bar (radius = half its 3 px height) rather than the M3 pill.
      dragHandleSize: Size(28, 3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Lb.rSheet))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Lb.panel,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      surfaceTintColor: Colors.transparent,
      shape: sheet,
      titleTextStyle: LbType.title,
      contentTextStyle: LbType.body.copyWith(color: Lb.text2),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Lb.raised,
      contentTextStyle: LbType.body,
      actionTextColor: Lb.phosphor,
      closeIconColor: Lb.text2,
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: panelLined,
    ),
    bannerTheme: MaterialBannerThemeData(backgroundColor: Lb.raised, contentTextStyle: LbType.body),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: Lb.raised,
        borderRadius: const BorderRadius.all(Radius.circular(Lb.rControl)),
        border: Border.fromBorderSide(Lb.hairline),
      ),
      textStyle: LbType.label.copyWith(color: Lb.text),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    ),
    // Badges are stadiums with no shape hook; keep the small form, which is
    // an LED dot.
    badgeTheme: BadgeThemeData(backgroundColor: Lb.phosphor, textColor: Lb.ink, textStyle: LbType.label, smallSize: 6),
    dividerTheme: const DividerThemeData(color: Lb.line, thickness: 1, space: 1),
    listTileTheme: ListTileThemeData(
      titleTextStyle: LbType.bodyStrong,
      subtitleTextStyle: LbType.small,
      leadingAndTrailingTextStyle: LbType.label,
      iconColor: Lb.text2,
      shape: control,
    ),
    expansionTileTheme: const ExpansionTileThemeData(
      shape: Border(),
      collapsedShape: Border(),
      iconColor: Lb.text,
      collapsedIconColor: Lb.text2,
      textColor: Lb.text,
      collapsedTextColor: Lb.text,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: Lb.text,
      linearTrackColor: Lb.line,
      circularTrackColor: Colors.transparent,
      linearMinHeight: 2,
      borderRadius: BorderRadius.zero,
      // Square stroke ends; LedSpinner (design/parts.dart) is the preferred
      // busy indicator where a spinner is wanted.
      strokeCap: StrokeCap.butt,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        side: Lb.hairline,
        selectedBackgroundColor: Lb.text,
        selectedForegroundColor: Lb.ink,
        foregroundColor: Lb.text2,
        textStyle: LbType.small.copyWith(fontWeight: FontWeight.w600),
        shape: control,
      ),
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: Lb.panel,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: sheet,
      headerHeadlineStyle: LbType.title,
      headerHelpStyle: LbType.label,
      weekdayStyle: LbType.label,
      dayStyle: LbType.body,
      yearStyle: LbType.body,
      dividerColor: Lb.line,
      dayShape: const WidgetStatePropertyAll(control),
      yearShape: const WidgetStatePropertyAll(control),
      todayBorder: const BorderSide(color: Lb.text2),
      rangePickerShape: sheet,
      rangePickerHeaderHeadlineStyle: LbType.title,
      rangePickerHeaderHelpStyle: LbType.label,
      cancelButtonStyle: TextButton.styleFrom(shape: control, textStyle: LbType.bodyStrong),
      confirmButtonStyle: TextButton.styleFrom(shape: control, textStyle: LbType.bodyStrong),
      inputDecorationTheme: InputDecorationThemeData(border: field(Lb.line), focusedBorder: field(Lb.text2)),
    ),
    // The clock dial stays round: it is a rotary dial, like a Knob.
    timePickerTheme: TimePickerThemeData(
      backgroundColor: Lb.panel,
      elevation: 0,
      shape: sheet,
      hourMinuteShape: control,
      dayPeriodShape: control,
      dayPeriodBorderSide: Lb.hairline,
      dialBackgroundColor: Lb.raised,
      dialHandColor: Lb.text,
      dialTextStyle: LbType.body,
      helpTextStyle: LbType.label,
      hourMinuteTextStyle: LbType.display,
      dayPeriodTextStyle: LbType.bodyStrong,
      timeSelectorSeparatorTextStyle: WidgetStatePropertyAll(LbType.display),
      cancelButtonStyle: TextButton.styleFrom(shape: control, textStyle: LbType.bodyStrong),
      confirmButtonStyle: TextButton.styleFrom(shape: control, textStyle: LbType.bodyStrong),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: Lb.raised,
        border: field(Lb.line),
        enabledBorder: field(Lb.line),
        focusedBorder: field(Lb.text2),
      ),
    ),
    scrollbarTheme: const ScrollbarThemeData(
      radius: Radius.circular(Lb.rTile),
      thickness: WidgetStatePropertyAll(3),
      thumbColor: WidgetStatePropertyAll(Lb.line),
    ),
    searchBarTheme: SearchBarThemeData(
      elevation: const WidgetStatePropertyAll(0),
      backgroundColor: const WidgetStatePropertyAll(Lb.panel),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      side: const WidgetStatePropertyAll(Lb.hairline),
      shape: const WidgetStatePropertyAll(panel),
      textStyle: WidgetStatePropertyAll(LbType.body),
      hintStyle: WidgetStatePropertyAll(LbType.body.copyWith(color: Lb.text3)),
    ),
    searchViewTheme: SearchViewThemeData(
      backgroundColor: Lb.panel,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: panel,
      headerTextStyle: LbType.body,
      headerHintStyle: LbType.body.copyWith(color: Lb.text3),
      dividerColor: Lb.line,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Lb.panel,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Lb.raised,
      indicatorShape: control,
      labelTextStyle: const WidgetStatePropertyAll(LbType.label),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: Lb.panel,
      indicatorColor: Lb.raised,
      indicatorShape: control,
      selectedLabelTextStyle: LbType.label.copyWith(color: Lb.text),
      unselectedLabelTextStyle: LbType.label,
    ),
    navigationDrawerTheme: NavigationDrawerThemeData(
      backgroundColor: Lb.panel,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Lb.raised,
      indicatorShape: control,
      labelTextStyle: WidgetStatePropertyAll(LbType.body),
    ),
    drawerTheme: const DrawerThemeData(
      backgroundColor: Lb.panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(),
      endShape: RoundedRectangleBorder(),
    ),
    tabBarTheme: TabBarThemeData(
      // A flat underline with square ends; M3 rounds the indicator's top.
      indicator: const UnderlineTabIndicator(borderSide: BorderSide(color: Lb.text, width: 2)),
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: Lb.line,
      labelColor: Lb.text,
      unselectedLabelColor: Lb.text2,
      labelStyle: LbType.bodyStrong,
      unselectedLabelStyle: LbType.body,
    ),
    bottomAppBarTheme: const BottomAppBarThemeData(color: Lb.panel, surfaceTintColor: Colors.transparent, elevation: 0),
  );
}

/// A small square slider thumb, matching the pixel geometry of the app.
class _SquareThumb extends SliderComponentShape {
  const _SquareThumb();

  static const side = 12.0;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size.square(side);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    _paintBlock(context.canvas, center, enableAnimation, sliderTheme);
  }
}

class _SquareRangeThumb extends RangeSliderThumbShape {
  const _SquareRangeThumb();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size.square(_SquareThumb.side);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    bool isDiscrete = false,
    bool isEnabled = false,
    bool? isOnTop,
    required SliderThemeData sliderTheme,
    TextDirection? textDirection,
    Thumb? thumb,
    bool? isPressed,
  }) {
    // Overlapping thumbs get an ink outline so both stay readable.
    if (isOnTop ?? false) {
      context.canvas.drawRect(
        Rect.fromCenter(center: center, width: _SquareThumb.side + 2, height: _SquareThumb.side + 2),
        Paint()..color = Lb.ink,
      );
    }
    _paintBlock(context.canvas, center, enableAnimation, sliderTheme);
  }
}

void _paintBlock(Canvas canvas, Offset center, Animation<double> enable, SliderThemeData theme) {
  final color = Color.lerp(theme.disabledThumbColor ?? Lb.text3, theme.thumbColor ?? Lb.text, enable.value)!;
  canvas.drawRect(
    Rect.fromCenter(center: center, width: _SquareThumb.side, height: _SquareThumb.side),
    Paint()..color = color,
  );
}

/// Press feedback: a faint square that grows around the thumb, instead of
/// the round M3 halo. Keeps the default 48 px footprint so track insets match.
class _SquareOverlay extends SliderComponentShape {
  const _SquareOverlay();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size.square(48);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final t = activationAnimation.value;
    if (t == 0) return;
    final side = _SquareThumb.side + 16 * t;
    context.canvas.drawRect(
      Rect.fromCenter(center: center, width: side, height: side),
      Paint()..color = sliderTheme.overlayColor ?? Lb.text.withValues(alpha: 0.08),
    );
  }
}

/// The value bubble as a flat block above the thumb, kept inside the slider.
class _BlockValueIndicator extends SliderComponentShape {
  const _BlockValueIndicator();

  static const _pad = EdgeInsets.symmetric(horizontal: 8, vertical: 5);
  static const _gap = 14.0;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete, {TextPainter? labelPainter, double? textScaleFactor}) {
    final label = labelPainter?.size ?? Size.zero;
    return Size(label.width + _pad.horizontal, label.height + _pad.vertical);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final t = activationAnimation.value;
    if (t == 0) return;
    final size = getPreferredSize(true, isDiscrete, labelPainter: labelPainter);
    final bounds = parentBox.localToGlobal(Offset.zero) & parentBox.size;
    final left = (center.dx - size.width / 2).clamp(
      bounds.left,
      (bounds.right - size.width).clamp(bounds.left, double.infinity),
    );
    final rect = Rect.fromLTWH(left, center.dy - _gap - size.height, size.width, size.height);
    final canvas = context.canvas
      ..save()
      ..translate(center.dx, center.dy - _gap)
      ..scale(t)
      ..translate(-center.dx, -(center.dy - _gap));
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(Lb.rControl)),
      Paint()..color = sliderTheme.valueIndicatorColor ?? Lb.text,
    );
    labelPainter.paint(canvas, rect.topLeft + Offset(_pad.left, _pad.top));
    canvas.restore();
  }
}

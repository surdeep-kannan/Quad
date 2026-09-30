import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'app_colors.dart';

abstract final class AppFonts {
  /// Figtree: body copy and UI.
  static const body = 'Figtree';

  /// Bricolage Grotesque: headlines and numbers with character.
  static const display = 'Bricolage';
}

/// Spacing scale (4pt grid).
abstract final class Space {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;

  /// Horizontal page gutter.
  static const double gutter = 16;
}

abstract final class Radii {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 22;
  static const double sheet = 28;
}

abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light, AppColors.light);
  static ThemeData dark() => _build(Brightness.dark, AppColors.dark);

  static TextTheme _textTheme(AppColors c) {
    TextStyle display(double size, double height, FontWeight weight, double tracking) => TextStyle(
          fontFamily: AppFonts.display,
          fontSize: size,
          height: height,
          fontWeight: weight,
          letterSpacing: tracking,
          color: c.ink,
        );
    TextStyle body(double size, double height, FontWeight weight, {Color? color, double tracking = 0}) => TextStyle(
          fontFamily: AppFonts.body,
          fontSize: size,
          height: height,
          fontWeight: weight,
          letterSpacing: tracking,
          color: color ?? c.ink,
        );

    return TextTheme(
      displayLarge: display(40, 1.04, FontWeight.w800, -1.4),
      displayMedium: display(34, 1.06, FontWeight.w800, -1.0),
      displaySmall: display(28, 1.1, FontWeight.w800, -0.7),
      headlineLarge: display(25, 1.14, FontWeight.w700, -0.5),
      headlineMedium: display(22, 1.18, FontWeight.w700, -0.35),
      headlineSmall: display(19, 1.22, FontWeight.w700, -0.2),
      titleLarge: body(18, 1.3, FontWeight.w700, tracking: -0.2),
      titleMedium: body(16, 1.35, FontWeight.w600, tracking: -0.1),
      titleSmall: body(14, 1.35, FontWeight.w600),
      bodyLarge: body(16, 1.5, FontWeight.w400),
      bodyMedium: body(15, 1.47, FontWeight.w400),
      bodySmall: body(13, 1.4, FontWeight.w400, color: c.inkMuted),
      labelLarge: body(15, 1.2, FontWeight.w600),
      labelMedium: body(13, 1.2, FontWeight.w600),
      labelSmall: body(11.5, 1.2, FontWeight.w600, tracking: 0.2),
    );
  }

  static ThemeData _build(Brightness brightness, AppColors c) {
    final text = _textTheme(c);
    final isLight = brightness == Brightness.light;

    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.ink,
      onPrimary: c.inkInverse,
      primaryContainer: c.accentSoft,
      onPrimaryContainer: c.accentInk,
      secondary: c.accent,
      onSecondary: c.onAccent,
      secondaryContainer: c.accentSoft,
      onSecondaryContainer: c.accentInk,
      tertiary: c.success,
      onTertiary: Colors.white,
      error: c.danger,
      onError: Colors.white,
      surface: c.surface,
      onSurface: c.ink,
      onSurfaceVariant: c.inkMuted,
      surfaceContainerLowest: c.background,
      surfaceContainerLow: c.surface,
      surfaceContainer: c.surfaceMuted,
      surfaceContainerHigh: c.surfaceMuted,
      surfaceContainerHighest: c.surfaceSunken,
      outline: c.lineStrong,
      outlineVariant: c.line,
      inverseSurface: c.ink,
      onInverseSurface: c.inkInverse,
      shadow: Colors.black,
      scrim: c.scrim,
      surfaceTint: Colors.transparent,
    );

    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(Radii.md + 2),
      borderSide: BorderSide.none,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: AppFonts.body,
      textTheme: text,
      extensions: [c],
      scaffoldBackgroundColor: c.background,
      canvasColor: c.background,
      dividerColor: c.line,
      splashFactory: InkRipple.splashFactory,
      splashColor: c.ink.withValues(alpha: 0.06),
      highlightColor: c.ink.withValues(alpha: 0.035),
      hoverColor: c.ink.withValues(alpha: 0.03),
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: c.background,
        foregroundColor: c.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleSpacing: Space.lg,
        titleTextStyle: text.titleLarge,
        systemOverlayStyle: isLight ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
      ),
      iconTheme: IconThemeData(color: c.ink, size: 24),
      dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surfaceMuted,
        hintStyle: text.bodyMedium!.copyWith(color: c.inkSubtle),
        labelStyle: text.bodyMedium!.copyWith(color: c.inkMuted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(borderSide: BorderSide(color: c.ink, width: 1.4)),
        errorBorder: inputBorder.copyWith(borderSide: BorderSide(color: c.danger, width: 1.2)),
        focusedErrorBorder: inputBorder.copyWith(borderSide: BorderSide(color: c.danger, width: 1.4)),
        errorStyle: text.bodySmall!.copyWith(color: c.danger),
        prefixIconColor: c.inkMuted,
        suffixIconColor: c.inkMuted,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: c.accent,
        selectionColor: c.accent.withValues(alpha: 0.25),
        selectionHandleColor: c.accent,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.ink,
          foregroundColor: c.inkInverse,
          minimumSize: const Size(64, 48),
          shape: const StadiumBorder(),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.ink,
          textStyle: text.labelLarge,
          shape: const StadiumBorder(),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.ink,
          side: BorderSide(color: c.lineStrong),
          shape: const StadiumBorder(),
          textStyle: text.labelLarge,
          minimumSize: const Size(64, 44),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: c.ink, highlightColor: c.ink.withValues(alpha: 0.06)),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: c.ink,
        unselectedLabelColor: c.inkSubtle,
        labelStyle: text.titleSmall!.copyWith(fontSize: 15, fontWeight: FontWeight.w700),
        unselectedLabelStyle: text.titleSmall!.copyWith(fontSize: 15),
        indicatorSize: TabBarIndicatorSize.label,
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: c.ink, width: 2.5),
          borderRadius: BorderRadius.circular(2),
        ),
        dividerColor: c.line,
        dividerHeight: 1,
        overlayColor: WidgetStatePropertyAll(c.ink.withValues(alpha: 0.04)),
        tabAlignment: TabAlignment.start,
        labelPadding: const EdgeInsets.symmetric(horizontal: 14),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        modalBackgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: c.lineStrong,
        dragHandleSize: const Size(36, 4),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.sheet))),
        clipBehavior: Clip.antiAlias,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.xl)),
        titleTextStyle: text.headlineSmall,
        contentTextStyle: text.bodyMedium!.copyWith(color: c.inkMuted),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isLight ? c.ink : c.surfaceSunken,
        contentTextStyle: text.bodyMedium!.copyWith(color: isLight ? c.inkInverse : c.ink),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md + 2)),
        elevation: 0,
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: c.ink, linearTrackColor: c.surfaceMuted),
      popupMenuTheme: PopupMenuThemeData(
        color: c.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg), side: BorderSide(color: c.line)),
        textStyle: text.bodyMedium,
        elevation: 6,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: c.ink,
        textColor: c.ink,
        contentPadding: const EdgeInsets.symmetric(horizontal: Space.lg),
        titleTextStyle: text.titleSmall!.copyWith(fontSize: 15),
        subtitleTextStyle: text.bodySmall,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.inkInverse : c.inkSubtle),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.ink : c.surfaceSunken),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.ink : Colors.transparent),
        checkColor: WidgetStatePropertyAll(c.inkInverse),
        side: BorderSide(color: c.lineStrong, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.ink : c.lineStrong),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: c.surface,
        headerForegroundColor: c.ink,
        dayForegroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.inkInverse : c.ink,
        ),
        dayBackgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.ink : Colors.transparent,
        ),
        todayForegroundColor: WidgetStatePropertyAll(c.accentInk),
        todayBorder: BorderSide(color: c.accent),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.xl)),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: c.surface,
        dialBackgroundColor: c.surfaceMuted,
        hourMinuteColor: c.surfaceMuted,
        dayPeriodColor: c.surfaceMuted,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.xl)),
      ),
      badgeTheme: BadgeThemeData(backgroundColor: c.accent, textColor: c.onAccent),
    );
  }
}

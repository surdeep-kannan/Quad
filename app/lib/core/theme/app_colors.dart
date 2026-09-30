import 'package:material_ui/material_ui.dart';

/// Semantic colour tokens. Read them with `context.colors`.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.surfaceSunken,
    required this.line,
    required this.lineStrong,
    required this.ink,
    required this.inkMuted,
    required this.inkSubtle,
    required this.inkInverse,
    required this.accent,
    required this.accentInk,
    required this.accentSoft,
    required this.onAccent,
    required this.success,
    required this.successSoft,
    required this.warning,
    required this.warningSoft,
    required this.danger,
    required this.dangerSoft,
    required this.online,
    required this.scrim,
  });

  /// App background behind lists and screens.
  final Color background;

  /// Cards, sheets and bars.
  final Color surface;

  /// Inputs, chips and quiet fills.
  final Color surfaceMuted;

  /// Pressed and selected fills, a step darker than [surfaceMuted].
  final Color surfaceSunken;

  final Color line;
  final Color lineStrong;

  final Color ink;
  final Color inkMuted;
  final Color inkSubtle;

  /// Text on [ink] fills.
  final Color inkInverse;

  /// Brand colour for icons, badges, likes and highlights.
  final Color accent;

  /// Accent for text on the background (meets 4.5:1 contrast).
  final Color accentInk;
  final Color accentSoft;
  final Color onAccent;

  final Color success;
  final Color successSoft;
  final Color warning;
  final Color warningSoft;
  final Color danger;
  final Color dangerSoft;
  final Color online;
  final Color scrim;

  static const light = AppColors(
    background: Color(0xFFFAF9F6),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFF1EFEA),
    surfaceSunken: Color(0xFFE7E4DD),
    line: Color(0xFFE9E6DF),
    lineStrong: Color(0xFFD5D1C7),
    ink: Color(0xFF16151B),
    inkMuted: Color(0xFF5E5B67),
    inkSubtle: Color(0xFF8A8793),
    inkInverse: Color(0xFFFFFFFF),
    accent: Color(0xFFFF4F2B),
    accentInk: Color(0xFFD23A17),
    accentSoft: Color(0xFFFFE8E0),
    onAccent: Color(0xFFFFFFFF),
    success: Color(0xFF12925A),
    successSoft: Color(0xFFE0F4EA),
    warning: Color(0xFFB7791F),
    warningSoft: Color(0xFFFFF1D6),
    danger: Color(0xFFD9363E),
    dangerSoft: Color(0xFFFCE6E7),
    online: Color(0xFF22B45E),
    scrim: Color(0x8A0E0D12),
  );

  static const dark = AppColors(
    background: Color(0xFF0E0E11),
    surface: Color(0xFF16161A),
    surfaceMuted: Color(0xFF202026),
    surfaceSunken: Color(0xFF2A2A31),
    line: Color(0xFF26262D),
    lineStrong: Color(0xFF383841),
    ink: Color(0xFFF3F2F6),
    inkMuted: Color(0xFFA6A4AF),
    inkSubtle: Color(0xFF706E7A),
    inkInverse: Color(0xFF16151B),
    accent: Color(0xFFFF6344),
    accentInk: Color(0xFFFF8166),
    accentSoft: Color(0xFF3B1E17),
    onAccent: Color(0xFFFFFFFF),
    success: Color(0xFF34C77B),
    successSoft: Color(0xFF12291D),
    warning: Color(0xFFE7A93B),
    warningSoft: Color(0xFF2E2413),
    danger: Color(0xFFFF5A62),
    dangerSoft: Color(0xFF331719),
    online: Color(0xFF34D06F),
    scrim: Color(0xB3000000),
  );

  @override
  AppColors copyWith({Color? background, Color? surface, Color? ink, Color? accent}) {
    return AppColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceMuted: surfaceMuted,
      surfaceSunken: surfaceSunken,
      line: line,
      lineStrong: lineStrong,
      ink: ink ?? this.ink,
      inkMuted: inkMuted,
      inkSubtle: inkSubtle,
      inkInverse: inkInverse,
      accent: accent ?? this.accent,
      accentInk: accentInk,
      accentSoft: accentSoft,
      onAccent: onAccent,
      success: success,
      successSoft: successSoft,
      warning: warning,
      warningSoft: warningSoft,
      danger: danger,
      dangerSoft: dangerSoft,
      online: online,
      scrim: scrim,
    );
  }

  @override
  AppColors lerp(covariant AppColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      background: l(background, other.background),
      surface: l(surface, other.surface),
      surfaceMuted: l(surfaceMuted, other.surfaceMuted),
      surfaceSunken: l(surfaceSunken, other.surfaceSunken),
      line: l(line, other.line),
      lineStrong: l(lineStrong, other.lineStrong),
      ink: l(ink, other.ink),
      inkMuted: l(inkMuted, other.inkMuted),
      inkSubtle: l(inkSubtle, other.inkSubtle),
      inkInverse: l(inkInverse, other.inkInverse),
      accent: l(accent, other.accent),
      accentInk: l(accentInk, other.accentInk),
      accentSoft: l(accentSoft, other.accentSoft),
      onAccent: l(onAccent, other.onAccent),
      success: l(success, other.success),
      successSoft: l(successSoft, other.successSoft),
      warning: l(warning, other.warning),
      warningSoft: l(warningSoft, other.warningSoft),
      danger: l(danger, other.danger),
      dangerSoft: l(dangerSoft, other.dangerSoft),
      online: l(online, other.online),
      scrim: l(scrim, other.scrim),
    );
  }
}

/// Identity colours for communities, colleges and avatars without a photo.
abstract final class Palette {
  static const colors = <Color>[
    Color(0xFFFF6B4A), // tomato
    Color(0xFFFF9F1C), // tangerine
    Color(0xFFF2B705), // sunflower
    Color(0xFF6DB33F), // lime
    Color(0xFF17A673), // emerald
    Color(0xFF0FA3B1), // teal
    Color(0xFF2E8BFF), // sky
    Color(0xFF3D5AFE), // cobalt
    Color(0xFF7B5CFF), // violet
    Color(0xFFC04FDB), // orchid
    Color(0xFFEC4F8B), // rose
    Color(0xFF475467), // graphite
  ];

  static Color at(int index) => colors[index.abs() % colors.length];

  /// A stable colour for any string, such as a name or id.
  static Color forText(String value) {
    var hash = 0;
    for (final unit in value.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return at(hash);
  }

  /// Readable text colour on top of [background].
  static Color foregroundOn(Color background) {
    return background.computeLuminance() > 0.55 ? const Color(0xFF16151B) : const Color(0xFFFFFFFF);
  }
}

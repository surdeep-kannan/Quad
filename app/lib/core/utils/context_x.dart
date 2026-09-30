import 'package:material_ui/material_ui.dart';

import '../theme/app_colors.dart';

extension ContextX on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
  TextTheme get text => Theme.of(this).textTheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  EdgeInsets get safePadding => MediaQuery.paddingOf(this);
  Size get screenSize => MediaQuery.sizeOf(this);
}

extension StringX on String {
  /// Up to two initials for avatars ("Diya Nair" -> "DN").
  String get initials {
    // Only letters and digits count, so emoji in names ("Squad 🚀") are skipped.
    final letter = RegExp(r'[\p{L}\p{N}]', unicode: true);
    final parts = trim()
        .split(RegExp(r'\s+'))
        .map((p) => String.fromCharCodes(p.runes.where((r) => letter.hasMatch(String.fromCharCode(r)))))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final runes = parts.first.runes.toList();
      return String.fromCharCodes(runes.take(2)).toUpperCase();
    }
    return (String.fromCharCode(parts.first.runes.first) + String.fromCharCode(parts.last.runes.first)).toUpperCase();
  }

  String get capitalized => isEmpty ? this : this[0].toUpperCase() + substring(1);

  /// "web-dev" -> "Web dev".
  String get humanized => replaceAll(RegExp(r'[-_]'), ' ').capitalized;
}

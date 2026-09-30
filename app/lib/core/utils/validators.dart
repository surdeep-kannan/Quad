abstract final class Validators {
  static final _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');
  static final _username = RegExp(r'^[a-z0-9_.]{3,24}$');

  static String? email(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Enter your email';
    if (!_email.hasMatch(v)) return 'That email doesn\'t look right';
    return null;
  }

  static String? password(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Enter a password';
    if (v.length < 8) return 'Use at least 8 characters';
    return null;
  }

  static String? name(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Enter your name';
    if (v.length > 80) return 'Keep it under 80 characters';
    return null;
  }

  static String? username(String? value) {
    final v = value?.trim() ?? '';
    if (v.length < 3) return 'At least 3 characters';
    if (v.length > 24) return 'Up to 24 characters';
    if (!_username.hasMatch(v)) return 'Lowercase letters, numbers, dots and underscores only';
    return null;
  }

  static String? required(String? value, [String message = 'Required']) {
    return (value?.trim().isEmpty ?? true) ? message : null;
  }

  static String? url(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    final uri = Uri.tryParse(v);
    if (uri == null || !uri.hasScheme || !(uri.scheme == 'http' || uri.scheme == 'https') || uri.host.isEmpty) {
      return 'Enter a full link starting with https://';
    }
    return null;
  }
}

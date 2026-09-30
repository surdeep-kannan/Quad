/// Build-time configuration, passed with `--dart-define-from-file=env/dev.json`.
///
/// Only client-safe values belong here: the project URL and the publishable
/// key. Never put the Supabase secret key or database password in the app.
abstract final class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  /// Optional TURN server for calls on restrictive networks.
  static const turnUrl = String.fromEnvironment('TURN_URL');
  static const turnUsername = String.fromEnvironment('TURN_USERNAME');
  static const turnCredential = String.fromEnvironment('TURN_CREDENTIAL');

  /// Builds the accessibility tree on start-up (used by automated UI checks).
  static const enableSemantics = bool.fromEnvironment('ENABLE_SEMANTICS');

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
}

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/data/supabase_providers.dart';
import '../../legal/legal_screen.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) => AuthRepository(ref.watch(supabaseProvider)));

class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  /// Where email links (confirmation, password reset) send people back to.
  String? get _redirect => kIsWeb ? Uri.base.origin : null;

  Future<void> signIn({required String email, required String password}) async {
    await _client.auth.signInWithPassword(email: email.trim(), password: password);
  }

  /// Returns true when the account is ready to use, false when the project
  /// requires email confirmation first.
  Future<bool> signUp({required String name, required String email, required String password}) async {
    final response = await _client.auth.signUp(
      email: email.trim(),
      password: password,
      // Records which Terms and Privacy Policy the person agreed to.
      data: {
        'full_name': name.trim(),
        'terms_version': legalVersion,
        'terms_accepted_at': DateTime.now().toUtc().toIso8601String(),
      },
      emailRedirectTo: _redirect,
    );
    return response.session != null;
  }

  Future<void> resendConfirmation(String email) async {
    await _client.auth.resend(type: OtpType.signup, email: email.trim(), emailRedirectTo: _redirect);
  }

  Future<void> sendPasswordReset(String email) async {
    await _client.auth.resetPasswordForEmail(email.trim(), redirectTo: _redirect);
  }

  Future<void> signOut() => _client.auth.signOut();
}

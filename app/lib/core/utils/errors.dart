import 'package:supabase_flutter/supabase_flutter.dart';

/// Turns backend and network errors into something a student can act on.
String friendlyError(Object error) {
  if (error is AuthException) {
    final message = error.message.toLowerCase();
    if (message.contains('invalid login')) return 'Wrong email or password.';
    if (message.contains('email not confirmed')) return 'Confirm your email first. Check your inbox for the link.';
    if (message.contains('already registered') || message.contains('already been registered')) {
      return 'An account with this email already exists. Try signing in.';
    }
    if (message.contains('rate limit')) return 'Too many attempts. Wait a minute and try again.';
    if (message.contains('password')) return error.message;
    return error.message;
  }
  if (error is PostgrestException) {
    // Our database functions raise messages written for students.
    final code = error.code ?? '';
    if (code == 'P0001' || code == 'P0002' || code == '22023' || code == '42501' || code == '28000') {
      if (code == '42501' && error.message.contains('row-level security')) {
        return 'You don\'t have permission to do that.';
      }
      return error.message;
    }
    if (code == '23505') return 'That already exists.';
    if (code == 'PGRST301' || code == '401') return 'Your session expired. Sign in again.';
    return 'Something went wrong. Please try again.';
  }
  if (error is StorageException) {
    final message = error.message.toLowerCase();
    if (message.contains('size') || message.contains('too large')) return 'That file is too large.';
    if (message.contains('mime') || message.contains('type')) return 'That file type isn\'t supported.';
    return 'Upload failed. Please try again.';
  }
  final text = error.toString();
  if (text.contains('SocketException') || text.contains('Failed host lookup') || text.contains('XMLHttpRequest')) {
    return 'You\'re offline. Check your connection.';
  }
  if (text.contains('TimeoutException')) return 'That took too long. Please try again.';
  return 'Something went wrong. Please try again.';
}

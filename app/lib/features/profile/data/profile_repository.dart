import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/data/json.dart';
import '../../../core/data/supabase_providers.dart';
import 'profile.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) => ProfileRepository(ref.watch(supabaseProvider)));

class ProfileRepository {
  ProfileRepository(this._client);

  final SupabaseClient _client;

  Future<Profile?> byId(String id) async {
    final row = await _client.from('profile_summaries').select().eq('id', id).maybeSingle();
    return row == null ? null : Profile.fromJson(row);
  }

  Future<Profile?> byUsername(String username) async {
    final row = await _client.from('profile_summaries').select().eq('username', username.toLowerCase()).maybeSingle();
    return row == null ? null : Profile.fromJson(row);
  }

  Future<List<Profile>> byIds(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final rows = await _client.from('profile_summaries').select().inFilter('id', ids);
    final byId = {for (final row in rows) row['id'] as String: Profile.fromJson(row)};
    return [for (final id in ids) ?byId[id]];
  }

  Future<void> update(Json fields) async {
    await _client.from('profiles').update(fields).eq('id', _client.uid);
  }

  Future<bool> isUsernameAvailable(String username) async {
    final result = await _client.rpc<bool>('is_username_available', params: {'p_username': username});
    return result;
  }

  Future<void> follow(String userId) async {
    await _client.from('follows').insert({'follower_id': _client.uid, 'following_id': userId});
  }

  Future<void> unfollow(String userId) async {
    await _client.from('follows').delete().eq('follower_id', _client.uid).eq('following_id', userId);
  }

  Future<List<Profile>> followers(String userId, {int offset = 0, int limit = 30}) async {
    final rows = await _client
        .from('follows')
        .select('follower_id')
        .eq('following_id', userId)
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return byIds([for (final row in rows) row['follower_id'] as String]);
  }

  Future<List<Profile>> following(String userId, {int offset = 0, int limit = 30}) async {
    final rows = await _client
        .from('follows')
        .select('following_id')
        .eq('follower_id', userId)
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return byIds([for (final row in rows) row['following_id'] as String]);
  }

  Future<List<Profile>> suggested({int limit = 10}) async {
    final rows = await _client.rpc<List<dynamic>>('suggested_people', params: {'p_limit': limit});
    return jsonListOf(rows).map(Profile.fromJson).toList();
  }

  Future<List<Achievement>> achievements(String userId) async {
    final rows = await _client
        .from('achievements')
        .select()
        .eq('user_id', userId)
        .order('achieved_on', ascending: false, nullsFirst: false)
        .order('created_at', ascending: false);
    return rows.map(Achievement.fromJson).toList();
  }

  Future<void> addAchievement({
    required String title,
    required String category,
    String? description,
    String? issuer,
    DateTime? achievedOn,
    String? url,
  }) async {
    await _client.from('achievements').insert({
      'user_id': _client.uid,
      'title': title,
      'category': category,
      'description': ?description,
      'issuer': ?issuer,
      if (achievedOn != null) 'achieved_on': achievedOn.toIso8601String().substring(0, 10),
      'url': ?url,
    });
  }

  Future<void> deleteAchievement(String id) async {
    await _client.from('achievements').delete().eq('id', id);
  }

  Future<void> touchLastSeen() async {
    await _client
        .from('profiles')
        .update({'last_seen_at': DateTime.now().toUtc().toIso8601String()}).eq('id', _client.uid);
  }

  Future<void> block(String userId) async {
    await _client.from('blocks').insert({'blocker_id': _client.uid, 'blocked_id': userId});
  }

  Future<void> unblock(String userId) async {
    await _client.from('blocks').delete().eq('blocker_id', _client.uid).eq('blocked_id', userId);
  }

  Future<List<Profile>> blocked() async {
    final rows = await _client.from('blocks').select('blocked_id').order('created_at', ascending: false);
    return byIds([for (final row in rows) row['blocked_id'] as String]);
  }
}
